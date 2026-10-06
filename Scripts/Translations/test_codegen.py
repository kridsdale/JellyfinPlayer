#!/usr/bin/env python3
"""Exercise the actual build-tool executable, including invalid printf input."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
BINARY = ROOT / "Packages/SwiftfinLocalization/.build/debug/LocalizationCodegen"

class CodegenTests(unittest.TestCase):
    def generate(self, source, *, encoding="utf-8", existing="old output"):
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "Localizable.strings"
            output = Path(directory) / "Strings.swift"
            input_path.write_text(source, encoding=encoding)
            original = input_path.read_bytes()
            output.write_text(existing)
            run = subprocess.run([str(BINARY), str(input_path), str(output)], capture_output=True, text=True)
            self.assertEqual(input_path.read_bytes(), original, "Build generation must never edit source resources")
            return run.returncode, run.stdout, output.read_text()

    def test_utf16_and_swift_keywords(self):
        code, _, output = self.generate('"repeat" = "Next";\n', encoding="utf-16")
        self.assertEqual(code, 0)
        self.assertIn("public enum L10n", output)
        self.assertIn("public static let `repeat`", output)
        self.assertIn("LocalizationResources.bundle", output)

    def test_dynamic_positional_format(self):
        code, _, output = self.generate('"amount" = "%2$*1$.3f / %2$.3f %%";\n')
        self.assertEqual(code, 0)
        self.assertIn("_ p1: Int, _ p2: Double", output)

    def test_conflicting_argument_types_leave_output_intact(self):
        code, error, output = self.generate('"invalid" = "%1$@ %1$d";\n')
        self.assertNotEqual(code, 0)
        self.assertIn("Conflicting types", error)
        self.assertEqual(output, "old output")

    def test_argument_gap_is_rejected(self):
        code, error, _ = self.generate('"invalid" = "%2$@";\n')
        self.assertNotEqual(code, 0)
        self.assertIn("Missing format argument position 1", error)

    def test_duplicate_key_is_rejected(self):
        code, error, _ = self.generate('"next" = "Next";\n"next" = "Next again";\n')
        self.assertNotEqual(code, 0)
        self.assertIn("Duplicate key", error)

    def test_escaped_content_is_decoded_without_changing_source(self):
        code, _, output = self.generate(r'"quote" = "He said \"Next\"\nPlay";' + '\n')
        self.assertEqual(code, 0)
        self.assertIn(r'He said \"Next\"\nPlay', output)

    def test_mixed_positions_are_rejected(self):
        code, error, _ = self.generate('"invalid" = "%1$@ %d";\n')
        self.assertNotEqual(code, 0)
        self.assertIn("Cannot mix positional", error)

    def test_identical_output_does_not_trigger_recompile(self):
        with tempfile.TemporaryDirectory() as directory:
            input_path = Path(directory) / "Localizable.strings"
            output = Path(directory) / "Strings.swift"
            input_path.write_text('"next" = "Next";\n')
            subprocess.run([str(BINARY), str(input_path), str(output)], check=True)
            os.utime(output, ns=(123000000000, 123000000000))
            subprocess.run([str(BINARY), str(input_path), str(output)], check=True)
            self.assertEqual(output.stat().st_mtime_ns, 123000000000)

if __name__ == "__main__":
    unittest.main()
