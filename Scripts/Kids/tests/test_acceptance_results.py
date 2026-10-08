import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "acceptance_results", Path(__file__).parents[1] / "acceptance_results.py"
)
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def passing_summary(count=81):
    return {
        "result": "Passed", "totalTestCount": count, "passedTests": count,
        "failedTests": 0, "skippedTests": 0, "expectedFailures": 0,
    }


class AcceptanceResultsTests(unittest.TestCase):
    def test_exact_current_acceptance_and_single_natural_cap_pass(self):
        for count in (81, 1):
            with self.subTest(count=count):
                self.assertEqual(
                    MODULE.validate_summary(passing_summary(count), count),
                    f"{count} executed, {count} passed, 0 failed, 0 skipped",
                )

    def test_zero_executed_tests_are_rejected_even_with_passed_result(self):
        with self.assertRaisesRegex(MODULE.AcceptanceResultError, "No tests executed"):
            MODULE.validate_summary(passing_summary(0), 81)

    def test_missing_counts_never_default_to_zero(self):
        for field in MODULE.COUNT_FIELDS:
            summary = passing_summary()
            del summary[field]
            with self.subTest(field=field), self.assertRaisesRegex(MODULE.AcceptanceResultError, field):
                MODULE.validate_summary(summary, 81)

    def test_skipped_selected_test_cannot_replace_an_executed_test(self):
        summary = passing_summary(80)
        summary.update(totalTestCount=81, skippedTests=1)
        with self.assertRaisesRegex(MODULE.AcceptanceResultError, "1 skipped"):
            MODULE.validate_summary(summary, 81)

    def test_actual_or_expected_failure_is_rejected(self):
        for field in ("failedTests", "expectedFailures"):
            summary = passing_summary(80)
            summary.update(totalTestCount=81)
            summary[field] = 1
            with self.subTest(field=field), self.assertRaises(MODULE.AcceptanceResultError):
                MODULE.validate_summary(summary, 81)

    def test_historical_pass_with_different_inventory_is_rejected(self):
        with self.assertRaisesRegex(MODULE.AcceptanceResultError, "Expected 81 executed tests, found 70"):
            MODULE.validate_summary(passing_summary(70), 81)

    def test_inconsistent_summary_or_nonpassed_result_is_rejected(self):
        for changed in ({"totalTestCount": 82}, {"result": "Failed"}, {"result": "unknown"}):
            summary = passing_summary()
            summary.update(changed)
            with self.subTest(changed=changed), self.assertRaises(MODULE.AcceptanceResultError):
                MODULE.validate_summary(summary, 81)

    def test_counts_require_nonnegative_integers_excluding_booleans(self):
        for invalid in (-1, True, 81.0, "81", None):
            summary = passing_summary()
            summary["passedTests"] = invalid
            with self.subTest(invalid=invalid), self.assertRaises(MODULE.AcceptanceResultError):
                MODULE.validate_summary(summary, 81)
        for invalid in (0, -1, True, "81"):
            with self.subTest(expected=invalid), self.assertRaises(MODULE.AcceptanceResultError):
                MODULE.validate_summary(passing_summary(), invalid)

    def test_nonobject_summary_is_rejected(self):
        for summary in (None, [], "Passed"):
            with self.subTest(summary=summary), self.assertRaises(MODULE.AcceptanceResultError):
                MODULE.validate_summary(summary, 81)

    def test_fixture_sender_uses_only_retained_bundle_summary_command(self):
        calls = []

        def fixture_sender(command, **kwargs):
            calls.append((command, kwargs))
            return subprocess.CompletedProcess(command, 0, json.dumps(passing_summary()))

        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / "Acceptance.xcresult"
            bundle.mkdir()
            result = MODULE.verify_result_bundle(bundle, 81, command_runner=fixture_sender)
        self.assertEqual(result, "Acceptance.xcresult: 81 executed, 81 passed, 0 failed, 0 skipped")
        self.assertEqual(calls, [([
            "xcrun", "xcresulttool", "get", "test-results", "summary",
            "--schema-version", "0.4.0", "--path", str(bundle), "--compact",
        ], {"check": True, "capture_output": True, "text": True})])

    def test_missing_bundle_is_rejected_before_calling_sender(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(MODULE.subprocess, "run") as sender:
                with self.assertRaisesRegex(MODULE.AcceptanceResultError, "Missing result bundle"):
                    MODULE.verify_result_bundle(Path(directory) / "missing.xcresult", 81)
                sender.assert_not_called()

    def test_invalid_json_and_failed_summary_command_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            def invalid_json(command, **kwargs):
                return subprocess.CompletedProcess(command, 0, "not JSON")

            with self.assertRaisesRegex(MODULE.AcceptanceResultError, "invalid JSON"):
                MODULE.verify_result_bundle(directory, 81, command_runner=invalid_json)

            def failed_command(command, **kwargs):
                raise subprocess.CalledProcessError(1, command)

            with self.assertRaisesRegex(MODULE.AcceptanceResultError, "exit 1"):
                MODULE.verify_result_bundle(directory, 81, command_runner=failed_command)

    def test_import_has_no_command_execution(self):
        imported = importlib.util.module_from_spec(SPEC)
        with patch("subprocess.run") as sender:
            SPEC.loader.exec_module(imported)
            sender.assert_not_called()


if __name__ == "__main__":
    unittest.main()
