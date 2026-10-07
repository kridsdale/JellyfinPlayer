import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch
import copy
import json
import tempfile

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

    def test_real_application_trees_require_explicit_file_imports(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for tree in ["Shared", "Swiftfin", "Swiftfin tvOS"]:
                folder = root / tree
                folder.mkdir()
                (folder / "UI.swift").write_text("import Engine\nimport SwiftUI\n")
            self.assertEqual(MODULE.application_import_problems(root), [])
            for tree, source in [
                ("Shared", "@_exported import Engine"),
                ("Swiftfin", "@_exported\n@preconcurrency public import CasePaths"),
                ("Swiftfin tvOS", "@_exported import struct FactoryKit.Container")
            ]:
                (root / tree / "Hidden.swift").write_text(source)
            problems = MODULE.application_import_problems(root)
            self.assertEqual(len(problems), 3)
            for path, module in [("Shared/Hidden.swift", "Engine"), ("Swiftfin/Hidden.swift", "CasePaths"), ("Swiftfin tvOS/Hidden.swift", "FactoryKit")]:
                self.assertTrue(any(path in problem and module in problem for problem in problems))

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


    def test_every_sdk_has_its_exact_recorded_owner_and_all_are_required(self):
        root = Path("/fixture")
        for owner, policies in MODULE.EXTERNAL_POLICIES.items():
            remotes = [{"sourceControl": [{"identity": identity, "location": {"remote": [{"urlString": url}]}, "requirement": {"exact": [version]}}]} for identity, url, version in policies]
            with self.subTest(owner=owner), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": remotes})):
                _, dependencies = MODULE.inspect_package(root / "Packages" / owner, root)
                self.assertEqual(dependencies, set())
            for index, (identity, url, version) in enumerate(policies):
                for field, value in [("requirement", {"range": [version, "99.0.0"]}), ("identity", "another-sdk"), ("location", {"remote": [{"urlString": "https://unexpected.invalid/SDK"}]})]:
                    changed = copy.deepcopy(remotes)
                    changed[index]["sourceControl"][0][field] = value
                    with self.subTest(owner=owner, sdk=identity, field=field), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": changed})):
                        with self.assertRaises(ValueError):
                            MODULE.inspect_package(root / "Packages" / owner, root)
                for changed in [remotes[:index] + remotes[index + 1:], remotes + [remotes[index]]]:
                    with self.subTest(owner=owner, missing_or_duplicate=identity), patch.object(MODULE.subprocess, "check_output", return_value=json.dumps({"dependencies": changed})):
                        with self.assertRaises(ValueError):
                            MODULE.inspect_package(root / "Packages" / owner, root)

    def test_session_lifecycle_and_stream_delivery_have_no_network_storage_or_ui_dependencies(self):
        for owner in ["SwiftfinSessions", "SwiftfinAsyncStreams"]:
            edges, frameworks = MODULE.POLICIES[owner]
            for module in ["JellyfinAPI", "Get", "Defaults", "CoreStore", "FactoryKit", "SwiftUI", "UIKit", "SwiftfinCredentials"]:
                with self.subTest(owner=owner, module=module):
                    self.assertTrue(MODULE.validate_source(owner, "import " + module, edges, frameworks))

    def test_transport_cannot_read_credentials_from_storage_or_resolve_application_globals(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinNetworking"]
        for module in ["SwiftfinCredentials", "Defaults", "FactoryKit", "UIKit", "SwiftUI", "Pulse", "SwiftfinStorage"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinNetworking", "import " + module, edges, frameworks))

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

    def test_account_store_cannot_contact_servers_or_resolve_ui_globals(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinAccountStore"]
        for module in ["JellyfinAPI", "FactoryKit", "UIKit", "SwiftUI", "Network", "CoreStore", "Defaults"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinAccountStore", "import " + module, edges, frameworks))
        self.assertNotIn("SwiftfinAccountStore", MODULE.EXTERNAL_POLICIES)

    def test_connection_selection_has_no_storage_native_transport_or_ui_globals(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinConnections"]
        for module in ["SwiftfinStorage", "SwiftfinStoredValues", "SwiftfinCredentials", "JellyfinAPI", "FactoryKit", "UIKit", "Network", "Defaults"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinConnections", "import " + module, edges, frameworks))
        self.assertNotIn("SwiftfinConnections", MODULE.EXTERNAL_POLICIES)

    def test_text_owner_has_no_ui_storage_transport_or_external_dependency(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinText"]
        self.assertEqual(set(edges), set())
        for module in ["SwiftUI", "UIKit", "JellyfinAPI", "SwiftfinNetworking", "Defaults", "CoreStore", "FactoryKit", "Algorithms"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinText", "import " + module, edges, frameworks))
        self.assertNotIn("SwiftfinText", MODULE.EXTERNAL_POLICIES)

    def test_image_processing_has_no_cache_transport_settings_or_localization(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinImageProcessing"]
        self.assertEqual(set(edges), set())
        for module in ["SwiftfinImages", "Nuke", "JellyfinAPI", "FactoryKit", "Defaults", "SwiftfinNetworking", "SwiftfinLocalization", "SwiftUI"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinImageProcessing", "import " + module, edges, frameworks))
        self.assertNotIn("SwiftfinImageProcessing", MODULE.EXTERNAL_POLICIES)

    def test_mpv_owner_cannot_access_application_accounts_settings_or_catalog(self):
        edges, frameworks = MODULE.POLICIES["SwiftfinMPV"]
        self.assertEqual(set(edges), set())
        for module in ["JellyfinAPI", "SwiftfinMediaTracks", "FactoryKit", "Defaults", "CoreStore", "SwiftfinCredentials", "KidsCatalog", "Pulse"]:
            with self.subTest(module=module):
                self.assertTrue(MODULE.validate_source("SwiftfinMPV", "import " + module, edges, frameworks))


if __name__ == "__main__":
    unittest.main()
