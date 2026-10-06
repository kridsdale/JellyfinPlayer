import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import copy
import json

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

    def test_native_sdk_must_have_its_exact_owner_source_and_version(self):
        root = Path("/fixture")
        remote = {"sourceControl": [{"identity": "swiftvlc", "location": {"remote": [{"urlString": "https://github.com/harflabs/SwiftVLC"}]}, "requirement": {"exact": ["1.0.0"]}}]}
        manifest = {"dependencies": [remote]}
        with patch.object(MODULE.subprocess, "check_output", return_value=json.dumps(manifest)):
            _, local = MODULE.inspect_package(root / "Packages/SwiftfinVLC", root)
            self.assertEqual(local, set())
            with self.assertRaises(ValueError):
                MODULE.inspect_package(root / "Packages/SwiftfinAudioSession", root)
        for field, value in [("requirement", {"range": ["1.0.0", "2.0.0"]}), ("location", {"remote": [{"urlString": "https://unexpected.invalid/SwiftVLC"}]}), ("identity", "another-sdk")]:
            changed = copy.deepcopy(remote)
            changed["sourceControl"][0][field] = value
            with self.subTest(field=field), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": [changed]})):
                with self.assertRaises(ValueError):
                    MODULE.inspect_package(root / "Packages/SwiftfinVLC", root)
        with patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": []})):
            with self.assertRaises(ValueError):
                MODULE.inspect_package(root / "Packages/SwiftfinVLC", root)


    def test_storage_sdks_have_separate_exact_owners(self):
        root = Path("/fixture")
        for owner, (identity, url, version) in MODULE.EXTERNAL_POLICIES.items():
            remote = {"sourceControl": [{"identity": identity, "location": {"remote": [{"urlString": url}]}, "requirement": {"exact": [version]}}]}
            with self.subTest(owner=owner), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": [remote]})):
                _, dependencies = MODULE.inspect_package(root / "Packages" / owner, root)
                self.assertEqual(dependencies, set())
            for field, value in [("requirement", {"range": [version, "99.0.0"]}), ("identity", "another-sdk")]:
                changed = copy.deepcopy(remote)
                changed["sourceControl"][0][field] = value
                with self.subTest(owner=owner, field=field), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": [changed]})):
                    with self.assertRaises(ValueError):
                        MODULE.inspect_package(root / "Packages" / owner, root)
            with self.subTest(owner=owner, missing=True), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": []})):
                with self.assertRaises(ValueError):
                    MODULE.inspect_package(root / "Packages" / owner, root)

    def test_native_storage_cannot_import_presentation_or_credentials(self):
        for module in ["SwiftUI", "Defaults", "FactoryKit", "KeychainSwift", "JellyfinAPI"]:
            with self.subTest(module=module):
                edges, frameworks = MODULE.POLICIES["SwiftfinStorage"]
                self.assertTrue(MODULE.validate_source("SwiftfinStorage", "import " + module, edges, frameworks))

    def test_account_models_have_no_native_storage_network_or_credentials(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinAccountModels"]
        for module in ["Network", "Security", "CoreStore", "Defaults", "SwiftUI", "FactoryKit", "JellyfinAPI"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinAccountModels", "import " + module, edges, frameworks))
        self.assertNotIn("SwiftfinAccountModels", MODULE.EXTERNAL_POLICIES)

    def test_native_connectivity_and_credentials_cannot_resolve_application_globals(self):
        for owner in ["SwiftfinConnectivity", "SwiftfinCredentials"]:
            edges, frameworks = MODULE.POLICIES[owner]
            for module in ["Defaults", "SwiftUI", "FactoryKit", "JellyfinAPI", "CoreStore", "KeychainSwift"]:
                with self.subTest(owner=owner, module=module):
                    self.assertTrue(MODULE.validate_source(owner, "import " + module, edges, frameworks))


if __name__ == "__main__":
    unittest.main()
