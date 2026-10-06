#!/usr/bin/env python3
"""Verify declared library edges and source imports without reading media or server state.

This covers the extracted libraries. It does not claim the remaining application
sources have been refactored or that public APIs/runtime behavior are correct.
"""
from pathlib import Path
import argparse
import json
import re
import subprocess

# Explicit responsibilities, not a permission derived from whatever code happens to import.
EXTERNAL_POLICIES = {
    "SwiftfinVLC": ("swiftvlc", "https://github.com/harflabs/SwiftVLC", "1.0.0"),
    "SwiftfinStorage": ("corestore", "https://github.com/JohnEstropia/CoreStore.git", "9.2.0"),
    "SwiftfinStoredValues": ("defaults", "https://github.com/sindresorhus/Defaults", "9.0.9"),
}
POLICIES = {
    "SwiftfinCredentials": ({}, {"Foundation", "Security"}),
    "SwiftfinConnectivity": ({"SwiftfinAccountModels"}, {"Foundation", "Network", "NetworkExtension", "os"}),
    "SwiftfinAccountModels": ({"SwiftfinLocalization"}, {"Foundation"}),
    "SwiftfinStorage": ({"SwiftfinAccountModels"}, {"CoreStore", "Foundation"}),
    "SwiftfinStoredValues": ({"SwiftfinStorage", "SwiftfinAccountModels"}, {"Defaults", "Foundation", "Combine"}),
    "SwiftfinStoredValuesUI": ({"SwiftfinStoredValues"}, {"SwiftUI"}),
    "SwiftfinVLC": ({"KidsDiagnostics"}, {"Foundation", "Combine", "SwiftUI", "SwiftVLC"}),
    "SwiftfinNowPlaying": ({}, {"Foundation", "MediaPlayer", "UIKit"}),
    "SwiftfinAudioSession": ({"KidsDiagnostics"}, {"Foundation", "OSLog", "AVFAudio"}),
    "KidsApplication": ({"KidsAccounts","KidsArtwork","KidsArtworkUI","KidsCatalog","KidsDiagnostics","KidsDomain","KidsPersistence","KidsPlaybackSession"}, {"Foundation", "Combine", "CoreData", "SwiftData", "UIKit", "AVFoundation"}),
    "KidsExperience": ({"KidsApplication","KidsCatalog","KidsDiagnostics","KidsDiagnosticsUI","KidsDomain","KidsPlaybackSession","SwiftfinUIState"}, {"SwiftUI", "Combine"}),
    "KidsDomain": ({}, {"Foundation"}),
    "KidsAccounts": ({"KidsDomain"}, {"Foundation", "Combine"}),
    "KidsDiagnostics": ({"KidsDomain"}, {"Foundation", "OSLog"}),
    "KidsCatalog": ({"KidsDomain", "KidsDiagnostics"}, {"Foundation"}),
    "KidsArtwork": ({"KidsDomain", "KidsCatalog", "KidsDiagnostics"}, {"Foundation"}),
    "KidsArtworkUI": ({"KidsDomain", "KidsCatalog", "KidsDiagnostics", "KidsArtwork"}, {"UIKit", "Combine"}),
    "KidsDiagnosticsUI": ({"KidsDiagnostics"}, {"UIKit", "SwiftUI"}),
    "KidsPlaybackSession": ({"KidsDomain", "KidsPlayback", "KidsDiagnostics"}, {"Foundation", "Combine"}),
    "KidsPlayback": ({"KidsDiagnostics"}, {"Foundation"}),
    "KidsPersistence": ({"KidsDomain", "KidsDiagnostics"}, {"Foundation", "SwiftData", "CryptoKit"}),
    "SwiftfinLocalization": ({}, {"Foundation"}),
    "SwiftfinUIState": ({}, {"SwiftUI", "Combine"}),
}
IMPORT = re.compile(r"(?m)^\s*(?:@\w+(?:\([^\n)]*\))?\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|func|let|var)\s+)?(\w+)")


def cycles(graph):
    visiting = []
    done = set()
    result = []

    def visit(node):
        if node in visiting:
            result.append(visiting[visiting.index(node):] + [node])
            return
        if node in done:
            return
        visiting.append(node)
        for dependency in sorted(graph.get(node, [])):
            visit(dependency)
        visiting.pop()
        done.add(node)

    for node in sorted(graph):
        visit(node)
    return result


def validate_source(name, source, dependencies, frameworks):
    allowed = set(dependencies) | set(frameworks)
    problems = [f"{name}: forbidden or undeclared import {module}" for module in sorted(set(IMPORT.findall(source)) - allowed)]
    if any("@_exported" in match.group(0) for match in IMPORT.finditer(source)):
        problems.append(f"{name}: umbrella re-export hides an explicit dependency")
    return problems


def inspect_package(path, root):
    manifest = json.loads(subprocess.check_output(["swift", "package", "--package-path", str(path), "dump-package"], text=True))
    dependencies = set()
    for dependency in manifest["dependencies"]:
        filesystem = dependency.get("fileSystem")
        if not filesystem:
            source = dependency.get("sourceControl", [])
            policy = EXTERNAL_POLICIES.get(path.name)
            if (policy is None or len(source) != 1
                    or source[0].get("identity") != policy[0]
                    or source[0].get("location") != {"remote": [{"urlString": policy[1]}]}
                    or source[0].get("requirement") != {"exact": [policy[2]]}):
                raise ValueError(f"{path.name}: external dependency is outside its recorded responsibility")
            continue
        destination = Path(filesystem[0]["path"]).resolve()
        if not destination.is_relative_to(root / "Packages"):
            raise ValueError(f"{path.name}: dependency escapes the local library graph")
        dependencies.add(destination.name)
    if path.name in EXTERNAL_POLICIES and sum("sourceControl" in d for d in manifest["dependencies"]) != 1:
        raise ValueError(f"{path.name}: exactly one pinned owned SDK dependency is required")
    return manifest, dependencies


def check(root):
    root = root.resolve()
    problems = []
    graph = {}
    actual = {p.parent.name for p in (root / "Packages").glob("*/Package.swift")}
    if actual != set(POLICIES):
        problems.append(f"Package responsibility inventory differs: missing={sorted(set(POLICIES)-actual)}, unassigned={sorted(actual-set(POLICIES))}")
    for name in sorted(actual & set(POLICIES)):
        path = root / "Packages" / name
        manifest, dependencies = inspect_package(path, root)
        graph[name] = dependencies
        expected, frameworks = POLICIES[name]
        if dependencies != set(expected):
            problems.append(f"{name}: expected dependencies {sorted(expected)}, found {sorted(dependencies)}")
        production = [t for t in manifest["targets"] if t["type"] == "regular"]
        if manifest["name"] != name or [t["name"] for t in production] != [name]:
            problems.append(f"{name}: library/module identity does not match its owner")
        products = manifest["products"]
        if len(products) != 1 or products[0]["name"] != name or products[0]["targets"] != [name] or "library" not in products[0]["type"]:
            problems.append(f"{name}: expected one focused production library")
        sources = list((path / "Sources" / name).rglob("*.swift"))
        if not sources:
            problems.append(f"{name}: production implementation is missing")
        for source in sources:
            if not source.resolve().is_relative_to(path.resolve()):
                problems.append(f"{name}: source escapes its owning library")
                continue
            problems.extend(f"{source.relative_to(root)}: {problem}" for problem in validate_source(name, source.read_text(), dependencies, frameworks))
    problems.extend("Library dependency cycle: " + " -> ".join(cycle) for cycle in cycles(graph))
    tools = json.loads(subprocess.check_output(["swift", "package", "--package-path", str(root / "KidsCore"), "dump-package"], text=True))
    if any("library" in product["type"] for product in tools["products"]):
        problems.append("KidsCore: production aggregate facade must not be restored")
    return graph, problems


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    graph, problems = check(args.root)
    if problems:
        for problem in problems:
            print(problem)
        raise SystemExit(1)
    print(f"PASS: {len(graph)} individually owned libraries; exact declared edges; no cycles, hidden re-exports, or app/SDK imports outside their responsibilities.")
    print("Remaining application extraction is a separate completion requirement.")


if __name__ == "__main__":
    main()
