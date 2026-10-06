import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location("package_boundaries", Path(__file__).parents[1] / "package_boundaries.py")
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class PackageBoundariesTests(unittest.TestCase):
    def test_one_way_graph_has_no_cycle(self):
        self.assertEqual(MODULE.cycles({"UI": {"Catalog", "Domain"}, "Catalog": {"Domain"}, "Domain": set()}), [])

    def test_cycle_reports_actual_dependency_path(self):
        self.assertEqual(MODULE.cycles({"Domain": {"Catalog"}, "Catalog": {"Domain"}}), [["Catalog", "Domain", "Catalog"]])

    def test_preconcurrency_import_does_not_bypass_ownership(self):
        problems = MODULE.validate_source("Domain", "@preconcurrency import FactoryKit", set(), {"Foundation"})
        self.assertEqual(len(problems), 1)
        self.assertIn("FactoryKit", problems[0])

    def test_transitive_import_requires_a_direct_manifest_edge(self):
        problems = MODULE.validate_source("UI", "import Domain", {"Catalog"}, {"UIKit"})
        self.assertEqual(len(problems), 1)
        self.assertIn("undeclared", problems[0])

    def test_umbrella_is_rejected_even_for_declared_dependency(self):
        problems = MODULE.validate_source("UI", "@_exported import Domain", {"Domain"}, {"UIKit"})
        self.assertEqual(len(problems), 1)
        self.assertIn("re-export", problems[0])

    def test_access_level_and_multiple_attributes_do_not_hide_imports(self):
        for source in ["public import FactoryKit", "@preconcurrency public import FactoryKit", "@_spi(Test) @preconcurrency import struct FactoryKit.Container"]:
            with self.subTest(source=source):
                problems = MODULE.validate_source("Domain", source, set(), {"Foundation"})
                self.assertEqual(len(problems), 1)
                self.assertIn("FactoryKit", problems[0])

    def test_attributed_public_reexport_cannot_create_hidden_facade(self):
        source = "@_exported\n@preconcurrency public import Domain"
        problems = MODULE.validate_source("UI", source, {"Domain"}, {"UIKit"})
        self.assertEqual(len(problems), 1)
        self.assertIn("re-export", problems[0])

    def test_direct_value_and_framework_imports_are_allowed(self):
        self.assertEqual(MODULE.validate_source("UI", "import Domain\nimport UIKit", {"Domain"}, {"UIKit"}), [])


if __name__ == "__main__":
    unittest.main()
