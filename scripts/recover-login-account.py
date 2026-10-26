"""Run over the existing root SSH channel; never exposes a public recovery endpoint.

Without --apply, only checks the account and describes the exact recovery scope.
The apply mode clears one account's Redis login budgets and restarts every app replica to
clear their local lock mirrors. Source-IP failure blocks are left in Redis.
"""
import argparse
import json
import os
import re
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("admin_id", type=int)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    if args.admin_id <= 0 or os.name != "posix" or os.geteuid() != 0:
        raise SystemExit("A positive administrator ID and the existing root SSH channel are required")

    def run(command, data=None):
        result = subprocess.run(command, input=data, capture_output=True, timeout=120)
        if result.returncode:
            # Docker/config errors may include credentials; retain no subprocess text here.
            raise RuntimeError("Recovery command failed; inspect service health through the private operations channel")
        return result.stdout.decode("utf-8")

    app_ids = run(["docker", "ps", "-q", "--filter", "label=com.docker.compose.project=simple-takeout-demo",
                   "--filter", "label=com.docker.compose.service=app"]).split()
    if not app_ids:
        raise SystemExit("No running app replicas; this procedure requires a running deployment")
    apps = json.loads(run(["docker", "inspect", *app_ids]))
    if any(a["State"]["Status"] != "running" for a in apps):
        raise SystemExit("App state changed; inspect the deployment before recovery")
    env = dict(item.split("=", 1) for item in apps[0]["Config"]["Env"] if "=" in item)
    role = run(["docker", "exec", "-i", "takeout-mysql", "sh", "-c",
                'MYSQL_PWD="$MYSQL_ROOT_PASSWORD" mysql -uroot --batch --raw --skip-column-names'],
               f"SELECT CONCAT(role,':',status) FROM takeout.users WHERE id={args.admin_id};".encode()).strip()
    if role != "2:1":
        raise SystemExit("Target is not an enabled administrator; no recovery actions performed")
    # Include the previous release's namespace so the same operator command works before migration.
    keys = [f"takeout:rl:{action}:u{args.admin_id}{suffix}"
            for action in ("login-account", "login-account-fail", "login-account-total") for suffix in ("", ":blocked")]
    print(json.dumps({"operator_uid": os.geteuid(), "mode": "apply" if args.apply else "read-only",
                      "target_enabled_admin": True, "keys": keys, "app_replicas": len(app_ids),
                      "source_failure_keys_preserved": True}), flush=True)
    if not args.apply:
        return

    def resp(parts):
        encoded = [part.encode("utf-8") for part in parts]
        return f"*{len(encoded)}\r\n".encode() + b"".join(
            f"${len(part)}\r\n".encode() + part + b"\r\n" for part in encoded)

    password = env.get("TAKEOUT_REDIS_PASSWORD", "")
    username = env.get("TAKEOUT_REDIS_USERNAME", "")
    if not password:
        raise SystemExit("Missing Redis authentication configuration; nothing was cleared")
    auth = ["AUTH", username, password] if username else ["AUTH", password]
    # Credentials travel over stdin, not command arguments; all keys belong to one verified admin.
    response = run(["docker", "exec", "-i", "takeout-redis-compose", "redis-cli", "--pipe", "--pipe-timeout", "10"],
                   resp(auth) + resp(["DEL", *keys]))
    if not re.search(r"errors:\s*0\s*,", response):
        raise RuntimeError("Redis did not confirm recovery; app replicas were not restarted")
    run(["docker", "restart", "--time", "15", *app_ids])
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        states = json.loads(run(["docker", "inspect", *app_ids]))
        if all(a["State"].get("Health", {}).get("Status") == "healthy" for a in states):
            print("ACCOUNT_KEYS_CLEARED app_replicas_restarted=true healthy=true source_failure_keys_preserved=true")
            return
        time.sleep(1)
    raise RuntimeError("Readiness was not confirmed within 90 seconds; root operator must inspect the deployment")


if __name__ == "__main__":
    main()
