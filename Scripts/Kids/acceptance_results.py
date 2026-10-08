#!/usr/bin/env python3
"""Verify frozen-build acceptance evidence without launching an app or test.

Reads xcresulttool test-results summary schema 0.4.0. A successful Xcode
process exit alone does not establish that all selected tests executed.
"""
import argparse
import json
from pathlib import Path
import subprocess
import sys

SUMMARY_SCHEMA_VERSION = "0.4.0"
COUNT_FIELDS = ("totalTestCount", "passedTests", "failedTests", "skippedTests", "expectedFailures")


class AcceptanceResultError(ValueError):
    """The result bundle does not establish complete acceptance."""


def validate_summary(summary, expected_count):
    """Require an exact, complete pass and return a concise evidence summary."""
    if type(expected_count) is not int or expected_count < 1:
        raise AcceptanceResultError("Expected test count must be a positive integer")
    if not isinstance(summary, dict):
        raise AcceptanceResultError("Test summary must be a JSON object")
    for field in COUNT_FIELDS:
        value = summary.get(field)
        if type(value) is not int or value < 0:
            raise AcceptanceResultError(f"Missing or invalid test count: {field}")
    total = summary["totalTestCount"]
    passed = summary["passedTests"]
    failed = summary["failedTests"]
    skipped = summary["skippedTests"]
    expected_failures = summary["expectedFailures"]
    executed = passed + failed + expected_failures
    if executed == 0:
        raise AcceptanceResultError("No tests executed")
    if failed or skipped or expected_failures:
        raise AcceptanceResultError(
            f"Incomplete acceptance: {failed} failed, {skipped} skipped, "
            f"{expected_failures} expected failures"
        )
    if summary.get("result") != "Passed":
        raise AcceptanceResultError("Test summary result is not Passed")
    if total != executed + skipped:
        raise AcceptanceResultError("Test summary counts are inconsistent")
    if executed != expected_count:
        raise AcceptanceResultError(f"Expected {expected_count} executed tests, found {executed}")
    return f"{executed} executed, {passed} passed, 0 failed, 0 skipped"


def verify_result_bundle(path, expected_count, *, command_runner=None):
    """Read a retained bundle; an injectable sender keeps unit tests offline."""
    bundle = Path(path)
    if not bundle.is_dir():
        raise AcceptanceResultError(f"Missing result bundle: {bundle}")
    runner = subprocess.run if command_runner is None else command_runner
    command = [
        "xcrun", "xcresulttool", "get", "test-results", "summary",
        "--schema-version", SUMMARY_SCHEMA_VERSION,
        "--path", str(bundle), "--compact",
    ]
    try:
        result = runner(command, check=True, capture_output=True, text=True)
    except subprocess.CalledProcessError as error:
        raise AcceptanceResultError(f"Unable to read test summary: exit {error.returncode}") from error
    except OSError as error:
        raise AcceptanceResultError("Unable to run xcresulttool") from error
    try:
        summary = json.loads(result.stdout)
    except (json.JSONDecodeError, TypeError) as error:
        raise AcceptanceResultError("xcresulttool returned an invalid JSON summary") from error
    return f"{bundle.name}: {validate_summary(summary, expected_count)}"


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--path", type=Path, required=True)
    parser.add_argument("--expected-count", type=int, required=True)
    args = parser.parse_args(argv)
    try:
        print(verify_result_bundle(args.path, args.expected_count))
    except AcceptanceResultError as error:
        print(f"Acceptance evidence rejected: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
