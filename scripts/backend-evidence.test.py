"""The evidence gate must reject skipped, failed, missing and stale executions."""
import importlib.util
from pathlib import Path
import tempfile
import time
import unittest

spec = importlib.util.spec_from_file_location("evidence", Path(__file__).with_name("backend-evidence.py"))
evidence = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evidence)


class EvidenceTest(unittest.TestCase):
    def test_coverage_requires_this_runs_aggregate_report(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            self.assertIsNone(evidence.read_coverage(root))
            report = root / "server/takeout-coverage/target/site/jacoco-aggregate/jacoco.xml"
            report.parent.mkdir(parents=True)
            report.write_text('<report><counter type="LINE" covered="75" missed="25"/></report>', encoding="utf-8")
            self.assertEqual(0.75, evidence.read_coverage(root)["ratio"])
            self.assertIsNone(evidence.read_coverage(root, time.time() + 60))
            report.write_text('<report/>', encoding="utf-8")
            self.assertIsNone(evidence.read_coverage(root))

    def test_reports_are_required_for_every_runtime_module(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("takeout-common", "takeout-app", "takeout-gateway", "takeout-erp"):
                report = root / "server" / name / "target/surefire-reports/TEST-example.xml"
                report.parent.mkdir(parents=True)
                report.write_text('<testsuite tests="3" failures="0" errors="0" skipped="0"/>', encoding="utf-8")
            self.assertEqual((True, dict(tests=12, failures=0, errors=0, skipped=0, passed=12)), evidence.evaluate(evidence.collect(root)))
            self.assertFalse(evidence.evaluate(evidence.collect(root, time.time() + 60))[0])
            report.unlink()
            self.assertFalse(evidence.evaluate(evidence.collect(root))[0])

    def test_failures_errors_and_skips_cannot_become_passed_tests(self):
        clean = dict(module="test", reports=1, tests=3, failures=0, errors=0, skipped=0)
        for field in ("failures", "errors", "skipped"):
            valid, totals = evidence.evaluate([dict(clean, **{field: 1})])
            self.assertFalse(valid)
            self.assertEqual(2, totals["passed"])
        self.assertTrue(evidence.evaluate([dict(clean, skipped=1)], allow_skipped=True)[0])
        self.assertFalse(evidence.evaluate([dict(clean, errors=1)], allow_skipped=True)[0])


if __name__ == "__main__":
    unittest.main()
