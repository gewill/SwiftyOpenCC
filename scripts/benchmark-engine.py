#!/usr/bin/env python3
"""Compare two local SDK checkouts with the same release-mode Swift harness.

Uses five fresh processes per checkout and five hot conversions per process.
Does not change either SDK checkout. Output is JSON; build artifacts are temporary.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import statistics
import subprocess
import tempfile

HARNESS = r'''
import Foundation
import Darwin
import CryptoKit
import OpenCC

func rss() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Int64(usage.ru_maxrss)
}
func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000 }
let sample = "鼠标里面的硅二极管坏了，导致光标分辨率降低。\n\n臺灣滑鼠、数字人文與內存條。ASCII 123 👨‍👩‍👧‍👦\r\n"
let input = String(repeating: sample, count: 8000)
let baselineRSS = rss()
let creationStart = now()
let converter = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
let coldMs = now() - creationStart
let loadedRSS = rss()
var hotMs: [Double] = []
var output = ""
for _ in 0..<5 {
    let start = now()
    output = converter.convert(input)
    hotMs.append(now() - start)
}
func hash(_ s: String) -> String { SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
let data: [String: Any] = ["coldCreateMs": coldMs, "hotConvertMs": hotMs,
    "inputUTF8Bytes": input.utf8.count, "inputSHA256": hash(input),
    "outputUTF8Bytes": output.utf8.count, "outputSHA256": hash(output),
    "baselineMaxRSSBytes": baselineRSS, "loadedMaxRSSBytes": loadedRSS, "maxRSSBytes": rss()]
print(String(data: try JSONSerialization.data(withJSONObject: data, options: [.sortedKeys]), encoding: .utf8)!)
'''


def run(path, work):
    (work / "Sources/EngineBenchmark").mkdir(parents=True)
    (work / "Sources/EngineBenchmark/main.swift").write_text(HARNESS)
    (work / "Package.swift").write_text('''// swift-tools-version:5.4
import PackageDescription
let package = Package(name: "EngineBenchmark", platforms: [.macOS(.v11)],
    dependencies: [.package(name: "engine", path: ''' + json.dumps(str(path)) + ''')],
    targets: [.executableTarget(name: "EngineBenchmark", dependencies: [.product(name: "OpenCC", package: "engine")])])
''')
    subprocess.run(["swift", "build", "-c", "release", "--package-path", str(work)], check=True, stdout=subprocess.DEVNULL)
    bindir = subprocess.check_output(["swift", "build", "-c", "release", "--package-path", str(work), "--show-bin-path"], text=True).strip()
    samples = [json.loads(subprocess.check_output([str(Path(bindir) / "EngineBenchmark")], text=True)) for _ in range(5)]
    revision = subprocess.check_output(["git", "-C", str(path), "rev-parse", "HEAD"], text=True).strip()
    engine_revision = subprocess.check_output(["git", "-C", str(path / "OpenCC"), "rev-parse", "HEAD"], text=True).strip()
    source_paths = ["Package.swift", "Sources/OpenCC/ChineseConverter.swift", "Sources/copencc/source.cpp", "Sources/OpenCC/Resources/manifest.json"]
    source_hashes = {name: hashlib.sha256((path / name).read_bytes()).hexdigest()
                     for name in source_paths if (path / name).is_file()}
    return {"wrapperBaseRevision": revision, "openccRevision": engine_revision, "sourceSHA256": source_hashes,
            "workingTreeHasChanges": bool(subprocess.check_output(["git", "-C", str(path), "status", "--porcelain"], text=True).strip()),
            "samples": samples,
            "median": {"coldCreateMs": statistics.median(s["coldCreateMs"] for s in samples),
                       "hotConvertMs": statistics.median(v for s in samples for v in s["hotConvertMs"]),
                       "baselineMaxRSSBytes": statistics.median(s["baselineMaxRSSBytes"] for s in samples),
                       "loadedMaxRSSBytes": statistics.median(s["loadedMaxRSSBytes"] for s in samples),
                       "maxRSSBytes": statistics.median(s["maxRSSBytes"] for s in samples)}}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="swiftyopencc-engine-benchmark-") as temporary:
        root = Path(temporary)
        result = {"host": platform.platform(), "architecture": platform.machine(),
                  "swift": subprocess.check_output(["swift", "--version"], text=True).strip(),
                  "mode": "s2twp", "processSamplesPerVersion": 5, "hotIterationsPerProcess": 5,
                  "memoryMetric": "getrusage.ru_maxrss; macOS bytes; peak includes input/output buffers",
                  "baseline": run(args.baseline.resolve(), root / "baseline"),
                  "candidate": run(args.candidate.resolve(), root / "candidate")}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(json.dumps({name: result[name]["median"] for name in ("baseline", "candidate")}, indent=2))


if __name__ == "__main__":
    main()
