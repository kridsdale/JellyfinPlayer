#!/usr/bin/env python3
"""Read-only source inventory for the remaining full-client ownership audit.

Import/coupling/isolation signals are lexical review aids, not proof of correct
API boundaries, actor ownership or runtime behavior. Never inspects server/media.
"""
import argparse
from collections import Counter
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

SPEC = importlib.util.spec_from_file_location("package_boundaries", Path(__file__).with_name("package_boundaries.py"))
BOUNDARIES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BOUNDARIES)
APP_DIRECTORIES = ("Shared", "Swiftfin", "Swiftfin tvOS")


def review_signals(source, modules):
    signals = []
    for name, present in [
        ("application-factory", "FactoryKit" in modules or "Container.shared" in source),
        ("settings-access", "Defaults" in modules or "StoredValues[" in source),
        ("mutable-sdk-client", "JellyfinClient(" in source),
        ("native-socket", "JellyfinSocket.Session" in source),
        ("native-video-sdk", "SwiftVLC" in modules),
        ("unchecked-sendable", "@unchecked Sendable" in source),
        ("unsafe-nonisolation", "nonisolated(unsafe)" in source),
        ("preconcurrency", "@preconcurrency" in source),
        ("assumed-main-actor", "MainActor.assumeIsolated" in source),
    ]:
        if present:
            signals.append(name)
    return signals


def inventory(root):
    records = []
    for directory in APP_DIRECTORIES:
        for path in sorted((root / directory).rglob("*.swift")):
            if not path.resolve().is_relative_to(root):
                raise ValueError("Source escapes the client checkout")
            source = path.read_text()
            modules = set(BOUNDARIES.IMPORT.findall(source))
            relative = path.relative_to(root)
            signals = review_signals(source, modules)
            records.append({
                "path": str(relative),
                "subsystem": "/".join(relative.parts[:2]),
                "sha256": hashlib.sha256(source.encode()).hexdigest(),
                "imports": sorted(modules),
                "ownedLibraries": sorted(modules & set(BOUNDARIES.POLICIES)),
                "reviewSignals": signals,
            })
    packages = []
    for directory in sorted((root / "Packages").iterdir()):
        if not (directory / "Package.swift").exists():
            continue
        sources = list((directory / "Sources" / directory.name).rglob("*.swift"))
        source_records = []
        for path in sorted(sources):
            if not path.resolve().is_relative_to(root):
                raise ValueError("Library source escapes the client checkout")
            source = path.read_text()
            modules = set(BOUNDARIES.IMPORT.findall(source))
            source_records.append({"path": str(path.relative_to(root)), "sha256": hashlib.sha256(source.encode()).hexdigest(), "imports": sorted(modules), "reviewSignals": review_signals(source, modules)})
        packages.append({"module": directory.name, "productionSwiftFiles": len(sources), "sources": source_records})
    return {
        "schemaVersion": 1,
        "scope": "client Swift source only; no server, account, media or simulator data",
        "limits": "Lexical signals require source review; retained platform composition/UI may be intentional. File counts do not establish refactor completion.",
        "summary": {
            "applicationSwiftFiles": len(records),
            "applicationFilesByDirectory": dict(sorted(Counter(Path(r["path"]).parts[0] for r in records).items())),
            "applicationFilesBySubsystem": dict(sorted(Counter(r["subsystem"] for r in records).items())),
            "reviewSignals": dict(sorted(Counter(signal for r in records for signal in r["reviewSignals"]).items())),
            "ownedLibraries": len(packages),
            "libraryReviewSignals": dict(sorted(Counter(signal for package in packages for source in package["sources"] for signal in source["reviewSignals"]).items())),
        },
        "libraries": packages,
        "applicationSources": records,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    root = args.root.resolve()
    result = inventory(root)
    encoded = json.dumps(result, indent=2) + "\n"
    if args.output:
        output = args.output.resolve()
        if not output.is_relative_to(root / "build"):
            parser.error("Inventory artifacts must remain in the ignored client build directory")
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(encoded)
        print(json.dumps(result["summary"], sort_keys=True))
    else:
        sys.stdout.write(encoded)


if __name__ == "__main__":
    main()
