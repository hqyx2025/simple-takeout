"""离线验证性能验收器；模拟HTTP服务的结果不能作为真实系统验收成绩。"""
import importlib.util
import contextlib
import io
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import threading
import time
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("performance", Path(__file__).with_name("acceptance-performance.py"))
performance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(performance)


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/timeout":
            time.sleep(0.15)
        self.send_response(401 if self.path == "/api/unauthorized" else 200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        body = {"code": 409 if self.path == "/api/business-error" else 200,
                "data": None if self.path == "/api/missing-detail" else []}
        try:
            self.wfile.write(json.dumps(body).encode())
        except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
            pass

    def log_message(self, *args):
        pass


class PerformanceAcceptanceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.base_url = f"http://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def test_measures_thirty_actual_responses_and_counts_business_failures(self):
        passed = performance.measure(self.base_url, "/api/valid", "test-token", 30, 2, 2)
        self.assertEqual(30, passed["requests"])
        self.assertTrue(passed["passed"])
        failed = performance.measure(self.base_url, "/api/business-error", "test-token", 30, 2, 2)
        self.assertEqual(30, failed["failures"])
        self.assertFalse(failed["passed"])
        self.assertEqual(0, failed["successfulWithin2SecondsRatio"])
        self.assertNotIn("test-token", json.dumps(failed))

    def test_rejects_null_details_unauthorized_responses_and_timeouts(self):
        for path, timeout in [("/api/missing-detail", 2), ("/api/unauthorized", 2), ("/api/timeout", 0.02)]:
            with self.subTest(path=path):
                sample, _ = performance.probe(self.base_url, path, "test-token", timeout)
                self.assertFalse(sample["success"])
                self.assertIn("error", sample)

    def test_exact_p95_boundary_and_minimum_sample_size(self):
        samples = [{"elapsedMs": 100, "success": True} for _ in range(38)]
        samples.extend([{"elapsedMs": 2100, "success": True}] * 2)
        result = performance.summarize("/api/valid", samples)
        self.assertEqual(100, result["p95Ms"])
        self.assertTrue(result["passed"])
        samples[0] = {"elapsedMs": 2200, "success": True}
        self.assertFalse(performance.summarize("/api/valid", samples)["passed"])
        self.assertFalse(performance.summarize("/api/valid", samples[:29])["passed"])
        samples = [{"elapsedMs": 100, "success": True} for _ in range(30)]
        samples[0]["success"] = False
        self.assertFalse(performance.summarize("/api/valid", samples)["passed"])

    def test_command_writes_environment_and_failure_report_without_secrets(self):
        cache = Path(__file__).resolve().parents[1] / "TemporaryCacheStorage"
        cache.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=cache) as directory:
            with patch.object(performance, "__file__", str(Path(directory) / "scripts" / "probe.py")), \
                    patch.dict("os.environ", {"TAKEOUT_PERF_TOKEN": "private-test-token"}), \
                    contextlib.redirect_stdout(io.StringIO()):
                status = performance.main(["--base-url", self.base_url, "--path", "/api/business-error",
                                           "--device", "离线测试服务", "--network", "loopback",
                                           "--data-scale", "stub only", "--concurrency", "2"])
            self.assertEqual(1, status)
            destination = next(Path(directory).rglob("api-*.json"))
            content = destination.read_text(encoding="utf-8")
            report = json.loads(content)
            self.assertEqual("离线测试服务", report["environment"]["device"])
            self.assertEqual(30, report["results"][0]["failures"])
            self.assertEqual(2, report["conditions"]["concurrencyPerEndpoint"])
            self.assertNotIn("private-test-token", content)


if __name__ == "__main__":
    unittest.main()
