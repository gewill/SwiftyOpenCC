#!/usr/bin/env python3
"""Compare public wrapper modes byte-for-byte with the locked core's real CLI.

Uses same-release official fixtures plus format boundaries. NUL workaround and
four compatibility modes remain separate contracts; no fixture is rewritten.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

import opencc_build

ROOT = Path(__file__).resolve().parents[1]
MODES = {'s2t': 1, 't2s': 2, 's2hk': 65, 'hk2s': 66, 's2tw': 33,
         'tw2s': 34, 's2twp': 1057, 'tw2sp': 1058, 't2hk': 64, 't2tw': 32}
HARNESS = '''import Foundation
import OpenCC
struct Request: Decodable { let flags: Int; let input: String }
let requests = try JSONDecoder().decode([Request].self, from: FileHandle.standardInput.readDataToEndOfFile())
var converters: [Int: ChineseConverter] = [:]
var outputs: [String] = []
for request in requests {
    if converters[request.flags] == nil {
        converters[request.flags] = try ChineseConverter(options: .init(rawValue: request.flags))
    }
    outputs.append(converters[request.flags]!.convert(request.input))
}
FileHandle.standardOutput.write(try JSONEncoder().encode(outputs))
'''


def digest(data):
    return hashlib.sha256(data).hexdigest()


def compare(actual, expected, label):
    if actual != expected:
        offset = next((i for i, (a, b) in enumerate(zip(actual, expected)) if a != b), min(len(actual), len(expected)))
        raise ValueError(f'{label}: byte mismatch at {offset}; wrapper={actual[offset:offset+32]!r}; CLI={expected[offset:offset+32]!r}')


def wrapper(requests, directory):
    source = directory / 'Sources/CLIConsumer'
    source.mkdir(parents=True)
    (source / 'main.swift').write_text(HARNESS)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.4
import PackageDescription
let package = Package(name: "CLIConsumer", platforms: [.macOS(.v11)],
    dependencies: [.package(name: "engine", path: ''' + json.dumps(str(ROOT)) + ''')],
    targets: [.executableTarget(name: "CLIConsumer", dependencies: [.product(name: "OpenCC", package: "engine")])])
''')
    subprocess.run(['swift', 'build', '-c', 'release', '--package-path', str(directory)], check=True)
    bindir = subprocess.check_output(['swift', 'build', '-c', 'release', '--package-path', str(directory), '--show-bin-path'], text=True).strip()
    return json.loads(subprocess.check_output([str(Path(bindir) / 'CLIConsumer')], input=json.dumps(requests).encode()))


def run_comparison(args):
    subprocess.run(['python3', str(ROOT / 'scripts/update-opencc-resources.py'), '--check'], check=True)
    executable = opencc_build.cmake()
    build = ROOT / '.build/official-cli'
    opencc_build.configure(executable, ROOT / 'OpenCC', build)
    subprocess.run([executable, '--build', str(build), '--target', 'opencc', 'Dictionaries', '--parallel', '4'], check=True)
    cli = build / 'src/tools/opencc'
    fixtures_path = ROOT / 'OpenCC/test/testcases/testcases.json'
    # Upstream fixtures permit trailing commas. Decode with the same Foundation
    # decoder as the existing Swift tests; never regex-rewrite fixture contents.
    decoder = 'import Foundation; struct F: Codable { let id: String; let input: String; let expected: [String:String] }; struct FS: Codable { let cases: [F] }; let value = try JSONDecoder().decode(FS.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))); FileHandle.standardOutput.write(try JSONEncoder().encode(value))'
    fixtures = json.loads(subprocess.check_output(['swift', '-e', decoder, str(fixtures_path)]))['cases']
    cases = []
    for fixture in fixtures:
        for mode in sorted(fixture['expected']):
            if mode in MODES:
                cases.append({'id': fixture['id'], 'mode': mode, 'input': fixture['input']})
    official_count = len(cases)
    for mode in MODES:
        for index, value in enumerate(['', '鼠标\r\n\r\n汉字\n', '👨‍👩‍👧‍👦e\u0301\t台湾', '鼠标', 'a' * 3999 + '鼠标', '\n\n', '汉字\r台湾\r\n']):
            cases.append({'id': f'boundary-{index}', 'mode': mode, 'input': value})
    if any('\0' in c['input'] for c in cases):
        raise ValueError('Official CLI parity corpus contains NUL; classify this separately')
    requests = [{'flags': MODES[c['mode']], 'input': c['input']} for c in cases]
    # This fixed independent assertion protects the known wrapper NUL behavior.
    requests.append({'flags': MODES['s2twp'], 'input': '\0鼠标\0\0汉字\0'})
    with tempfile.TemporaryDirectory(prefix='opencc-official-cli-') as temporary:
        outputs = wrapper(requests, Path(temporary) / 'consumer')
    if len(outputs) != len(requests):
        raise ValueError('Wrapper output count differs from request count')
    compare(outputs[-1].encode(), '\0滑鼠\0\0漢字\0'.encode(), 'NUL preservation (fixed wrapper contract)')
    rows = []
    for case, output in zip(cases, outputs):
        raw = case['input'].encode()
        mode = case['mode']
        # ConfigLoadOptions defaults true in the library; CLI defaults false.
        # Explicitly match the existing wrapper contract for a like-for-like test.
        command = [str(cli), '--include-tofu-risk-dictionaries', '-c', str(ROOT / f'OpenCC/data/config/{mode}.json'), '--path', str(build / 'data')]
        expected = subprocess.check_output(command, input=raw)
        compare(output.encode(), expected, f"{case['id']}:{mode}")
        rows.append({'id': case['id'], 'mode': mode, 'inputSHA256': digest(raw), 'outputSHA256': digest(expected)})
    manifest = json.loads((ROOT / 'Sources/OpenCC/Resources/manifest.json').read_text())
    report = {'status': 'passed', 'opencc': manifest['opencc'], 'cmake': opencc_build.lock(),
              'cliSHA256': digest(cli.read_bytes()), 'cliConversionArguments': ['--include-tofu-risk-dictionaries'], 'cliConfigureArguments': opencc_build.CONFIGURE,
              'cliBuildArguments': ['--target', 'opencc', 'Dictionaries', '--parallel', '4'],
              'cliCompiler': opencc_build.provenance(build)['compiler'],
              'cliHost': opencc_build.provenance(build)['host'],
              'officialFixtureSHA256': digest(fixtures_path.read_bytes()),
              'wrapperSourceSHA256': {name: digest((ROOT / name).read_bytes()) for name in
                  ('Package.swift', 'Sources/OpenCC/ChineseConverter.swift', 'Sources/copencc/source.cpp')},
              'coverage': {mode: sum(row['mode'] == mode for row in rows) for mode in MODES},
              'officialFixtureComparisons': official_count, 'comparisons': len(rows),
              'nulContract': 'fixed wrapper expectation passed; excluded from native CLI parity', 'rows': rows}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + '\n')
    print(f'Passed {len(rows)} byte comparisons across {len(MODES)} modes; NUL preserved; report: {args.output}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, default=ROOT / '.build/official-cli-report.json')
    args = parser.parse_args()
    # Clear any prior green report before work, including compilation failures.
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({'status': 'running'}) + '\n')
    try:
        run_comparison(args)
    except Exception as error:
        args.output.write_text(json.dumps({'status': 'failed', 'reason': str(error)}, indent=2) + '\n')
        raise


if __name__ == '__main__':
    main()
