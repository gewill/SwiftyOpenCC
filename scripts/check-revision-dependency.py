#!/usr/bin/env python3
"""Resolve a committed Git revision through SwiftPM's remote dependency path.

Uses a temporary file:// Git remote, not a local .package(path:) dependency.
No engine build is needed to catch manifest evaluation in SwiftPM's Git VFS.
"""
import argparse
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--revision", default="HEAD", help="Committed revision to consume (default: HEAD)")
    args = parser.parse_args()
    revision = subprocess.check_output(
        ["git", "-C", str(ROOT), "rev-parse", "--verify", args.revision + "^{commit}"], text=True
    ).strip()
    with tempfile.TemporaryDirectory(prefix="opencc-revision-consumer-") as temp:
        directory = Path(temp)
        remote = directory / "SwiftyOpenCC.git"
        subprocess.run(["git", "clone", "--bare", "--quiet", str(ROOT), str(remote)], check=True)
        consumer = directory / "consumer"
        consumer.mkdir()
        (consumer / "Package.swift").write_text('''// swift-tools-version:5.5
import PackageDescription
let package = Package(
    name: "RevisionConsumer",
    dependencies: [.package(url: "%s", revision: "%s")],
    targets: [.target(name: "RevisionConsumer", dependencies: [
        .product(name: "OpenCC", package: "SwiftyOpenCC")
    ])]
)
''' % (remote.as_uri(), revision))
        sources = consumer / "Sources/RevisionConsumer"
        sources.mkdir(parents=True)
        (sources / "main.swift").write_text("import OpenCC\n")
        # A new remote URL and isolated cache prevent a previous checkout or
        # manifest cache from skipping evaluation of the selected Git revision.
        subprocess.run(["swift", "package", "--package-path", str(consumer),
                        "--cache-path", str(directory / "cache"), "resolve"], check=True)
        resolved = json.loads((consumer / "Package.resolved").read_text())
        pins = resolved.get("pins", resolved.get("object", {}).get("pins", []))
        if len(pins) != 1 or pins[0]["state"]["revision"] != revision:
            raise SystemExit("SwiftPM did not resolve the requested SwiftyOpenCC revision")
        print(f"Verified Git revision dependency: {revision}")


if __name__ == "__main__":
    main()
