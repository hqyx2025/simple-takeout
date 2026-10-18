"""毕设修改2接口验收（Python标准库，无需安装依赖）。

先在环境变量 TAKEOUT_PERF_TOKEN 设置测试账号令牌，再执行：
python scripts/acceptance-performance.py --device "本机 Windows" --network "本机回环" \
    --data-scale "实际测试库：店铺20、商品200、订单1000"
可重复 --path /api/... 指定任意角色的只读接口；默认测店铺列表/详情/商品、订单列表/详情。
令牌仅从环境变量读取，不写入报告；不会创建订单、充值或修改业务数据。
"""

import argparse
import concurrent.futures
import datetime
import http.client
import json
import math
import os
from pathlib import Path
import platform
import time
import urllib.error
import urllib.parse
import urllib.request


def probe(base_url, path, token, timeout):
    started = time.perf_counter()
    sample = {"httpStatus": None, "code": None, "success": False}
    data = None
    try:
        request = urllib.request.Request(base_url + path, headers={"Authorization": "Bearer " + token})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            sample["httpStatus"] = response.status
            payload = json.load(response)
        sample["code"] = payload.get("code")
        data = payload.get("data")
        sample["success"] = sample["httpStatus"] == 200 and sample["code"] == 200 and data is not None
        if not sample["success"]:
            sample["error"] = "business-error-or-empty-data"
    except urllib.error.HTTPError as error:
        sample["httpStatus"] = error.code
        sample["error"] = "http-error"
    except (urllib.error.URLError, TimeoutError, OSError, http.client.HTTPException):
        sample["error"] = "connection-error-or-timeout"
    except (ValueError, AttributeError):
        sample["error"] = "invalid-json-response"
    sample["elapsedMs"] = (time.perf_counter() - started) * 1000
    return sample, data


def summarize(path, samples):
    times = sorted(sample["elapsedMs"] for sample in samples)
    failures = sum(not sample["success"] for sample in samples)
    fast = sum(sample["success"] and sample["elapsedMs"] <= 2000 for sample in samples)
    p95 = times[math.ceil(len(times) * 0.95) - 1]
    return {
        "path": path, "requests": len(times), "failures": failures,
        "averageMs": sum(times) / len(times), "p95Ms": p95,
        "successfulWithin2SecondsRatio": fast / len(times),
        "passed": len(times) >= 30 and failures == 0 and fast / len(times) >= 0.95,
        "samples": samples,
    }


def measure(base_url, path, token, samples, concurrency, timeout):
    # Each endpoint is measured separately; concurrency is the maximum in-flight requests for that endpoint.
    with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
        results = list(pool.map(lambda _: probe(base_url, path, token, timeout)[0], range(samples)))
    return summarize(path, results)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default="http://127.0.0.1:8087")
    parser.add_argument("--samples", type=int, default=30)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--timeout", type=float, default=10)
    parser.add_argument("--device", required=True, help="实际测量设备及服务端部署信息")
    parser.add_argument("--network", required=True, help="实际网络条件，如本机回环/校园Wi-Fi")
    parser.add_argument("--data-scale", required=True, help="实际数据库数据规模，不确定时明确填写未核实")
    parser.add_argument("--path", action="append", help="重复指定只读API路径；需使用对应角色令牌")
    args = parser.parse_args(argv)
    if args.samples < 30 or not 1 <= args.concurrency <= args.samples or not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("samples必须>=30，concurrency必须在1到samples之间，timeout必须>0")
    token = os.environ.get("TAKEOUT_PERF_TOKEN", "").strip()
    if not token:
        parser.error("请在环境变量 TAKEOUT_PERF_TOKEN 设置测试账号令牌")
    base_url = args.base_url.rstrip("/")
    parsed = urllib.parse.urlsplit(base_url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc or parsed.username or parsed.password or parsed.query or parsed.fragment:
        parser.error("base-url必须是无凭据、查询参数和片段的HTTP(S)服务地址")
    paths = args.path
    skipped = []
    if paths is None:
        paths = ["/api/categories", "/api/stores", "/api/orders/page?page=1&pageSize=30"]
        for path, key, templates in [
            ("/api/stores", None, ["/api/stores/{id}", "/api/stores/{id}/goods"]),
            ("/api/orders/page?page=1&pageSize=30", "list", ["/api/orders/{id}"]),
        ]:
            status, data = probe(base_url, path, token, args.timeout)
            rows = data.get(key, []) if key and isinstance(data, dict) else data
            if status["success"] and isinstance(rows, list) and rows and isinstance(rows[0], dict) and isinstance(rows[0].get("id"), int):
                paths.extend(template.format(id=rows[0]["id"]) for template in templates)
            else:
                skipped.extend(templates)
    if any(not path.startswith("/api/") or "#" in path for path in paths):
        parser.error("path必须以/api/开头，且不能包含片段")
    paths = list(dict.fromkeys(paths))
    results = []
    for path in paths:
        result = measure(base_url, path, token, args.samples, args.concurrency, args.timeout)
        results.append(result)
        print(f'{path}: mean={result["averageMs"]:.2f}ms P95={result["p95Ms"]:.2f}ms '
              f'failures={result["failures"]}/{result["requests"]} '
              f'{"PASS" if result["passed"] else "FAIL"}')
    report = {
        "measuredAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "baseUrl": base_url,
        "environment": {"device": args.device, "network": args.network, "dataScale": args.data_scale,
                        "client": platform.platform(), "python": platform.python_version()},
        "conditions": {"requestsPerEndpoint": args.samples, "concurrencyPerEndpoint": args.concurrency,
                       "timeoutSeconds": args.timeout, "thresholdMs": 2000,
                       "p95Method": "nearest-rank; includes failed requests",
                       "discoveryRequestsExcluded": args.path is None,
                       "connectionReuse": False, "automaticRetries": 0},
        "skippedEndpoints": skipped, "results": results,
        "passed": not skipped and all(result["passed"] for result in results),
    }
    directory = Path(__file__).resolve().parents[1] / "TemporaryCacheStorage" / "performance"
    directory.mkdir(parents=True, exist_ok=True)
    destination = directory / ("api-" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f") + ".json")
    destination.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("报告：" + str(destination))
    if skipped:
        print("未覆盖详情接口（需有效账号和已有业务数据）：" + ", ".join(skipped))
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
