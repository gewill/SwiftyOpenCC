import copy
import importlib.util
import json
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
import opencc_build


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


generator = module('generator', 'update-opencc-resources.py')
cli = module('cli', 'check-official-cli.py')


class BuildValidationTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(generator.MANIFEST.read_text())

    def test_check_requires_no_tool_download_or_compilation(self):
        with patch.object(opencc_build, 'cmake', side_effect=AssertionError('must not build')):
            generator.check(generator.source_version())

    def test_tool_version_and_empty_version_are_rejected(self):
        for output in ('cmake version 0.0.0\n', ''):
            with self.assertRaisesRegex(ValueError, 'CMake version'):
                opencc_build.validate_version(output, opencc_build.lock()['version'])

    def test_changed_generation_parameters_or_archive_hash_are_rejected(self):
        for key in ('configureArguments', 'cmake', 'compiler', 'host'):
            value = copy.deepcopy(self.manifest['generation'])
            if key == 'cmake':
                value[key]['sha256'] = '0' * 64
            else:
                value[key] = [] if key == 'configureArguments' else {}
            with self.assertRaises(ValueError):
                opencc_build.check_provenance(value)

    def test_manifest_provenance_and_resource_tampering_fail_real_check(self):
        for field in ('generation', 'files'):
            value = copy.deepcopy(self.manifest)
            value[field] = {}
            with tempfile.TemporaryDirectory() as directory:
                manifest = Path(directory) / 'manifest.json'
                manifest.write_text(json.dumps(value))
                with patch.object(generator, 'MANIFEST', manifest), self.assertRaises(ValueError):
                    generator.check(generator.source_version())

    def test_corrupt_cmake_archive_is_never_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            archive = root / '.build/pinned-cmake' / (opencc_build.lock()['sha256'] + '.tar.gz')
            archive.parent.mkdir(parents=True)
            archive.write_bytes(b'corrupt cache')
            with patch.object(opencc_build, 'ROOT', root), patch.object(opencc_build.platform, 'system', return_value='Darwin'):
                with patch.object(opencc_build.subprocess, 'run') as execute:
                    with self.assertRaisesRegex(ValueError, 'Cached CMake archive'):
                        opencc_build.cmake()
                    execute.assert_not_called()

    def test_wrong_download_hash_is_rejected_and_temporary_file_removed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with patch.object(opencc_build, 'ROOT', root), patch.object(opencc_build.platform, 'system', return_value='Darwin'):
                with patch.object(opencc_build.urllib.request, 'urlopen', return_value=io.BytesIO(b'wrong download')):
                    with patch.object(opencc_build.subprocess, 'run') as execute:
                        with self.assertRaisesRegex(ValueError, 'Downloaded CMake archive'):
                            opencc_build.cmake()
                        execute.assert_not_called()
            self.assertEqual(list((root / '.build/pinned-cmake').iterdir()), [])

    def test_failed_cli_check_replaces_old_green_report(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'report.json'
            output.write_text(json.dumps({'status': 'passed'}))
            with patch.object(sys, 'argv', ['check-official-cli.py', '--output', str(output)]):
                with patch.object(cli, 'run_comparison', side_effect=ValueError('fixture byte mismatch')):
                    with self.assertRaises(ValueError):
                        cli.main()
            self.assertEqual(json.loads(output.read_text()), {'status': 'failed', 'reason': 'fixture byte mismatch'})


if __name__ == '__main__':
    unittest.main()
