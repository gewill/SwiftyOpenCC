"""Pinned CMake and shared, recorded OpenCC generation configuration."""
import hashlib
import json
from pathlib import Path
import platform
import re
import subprocess
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / 'BuildTools/cmake.json'
CONFIGURE = [
    '-G', 'Unix Makefiles', '-DCMAKE_BUILD_TYPE=Release', '-DBUILD_SHARED_LIBS=OFF',
    '-DBUILD_DOCUMENTATION=OFF', '-DBUILD_OPENCC_JIEBA_PLUGIN=OFF',
    '-DBUILD_PYTHON=OFF', '-DENABLE_GTEST=OFF', '-DENABLE_BENCHMARK=OFF',
    '-DOPENCC_DICT_FORMAT=ocd2', '-DOPENCC_ENABLE_INSTALL=OFF',
]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lock():
    return json.loads(LOCK.read_text())


def validate_version(output, expected):
    if (output.splitlines() or [''])[0] != 'cmake version ' + expected:
        raise ValueError('CMake version differs from BuildTools/cmake.json')


def cmake():
    """Download a hash-locked official distribution without changing PATH/tools."""
    if platform.system() != 'Darwin':
        raise ValueError('Resource generation currently requires macOS; --check is portable')
    pinned = lock()
    directory = ROOT / '.build/pinned-cmake'
    directory.mkdir(parents=True, exist_ok=True)
    archive = directory / (pinned['sha256'] + '.tar.gz')
    if not archive.exists():
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as temporary:
            download = Path(temporary.name)
        try:
            with urllib.request.urlopen(pinned['url'], timeout=120) as response, download.open('wb') as output:
                while chunk := response.read(1024 * 1024):
                    output.write(chunk)
            if digest(download) != pinned['sha256']:
                raise ValueError('Downloaded CMake archive SHA-256 mismatch')
            download.replace(archive)
        finally:
            download.unlink(missing_ok=True)
    if digest(archive) != pinned['sha256']:
        raise ValueError('Cached CMake archive SHA-256 mismatch; remove the cache and retry')
    # Extract only an archive authenticated by the checked-in release checksum.
    # Re-extraction avoids trusting executables left from an earlier invocation.
    subprocess.run(['tar', '-xzf', str(archive), '-C', str(directory)], check=True)
    executable = directory / pinned['executable']
    validate_version(subprocess.check_output([str(executable), '--version'], text=True), pinned['version'])
    return str(executable)


def configure(executable, engine, build):
    subprocess.run([executable, '-S', str(engine), '-B', str(build), *CONFIGURE], check=True)


def provenance(build):
    compiler_files = sorted((build / 'CMakeFiles').glob('*/CMakeCXXCompiler.cmake'))
    if len(compiler_files) != 1:
        raise ValueError('Expected one configured C++ compiler; clean the resource build directory')
    source = compiler_files[0].read_text()
    compiler = {}
    for key in ('CMAKE_CXX_COMPILER_ID', 'CMAKE_CXX_COMPILER_VERSION'):
        match = re.search(r'set\(' + key + r' "([^"]+)"\)', source)
        if not match:
            raise ValueError('Missing configured compiler provenance: ' + key)
        compiler[key] = match[1]
    return {'schemaVersion': 1, 'cmake': lock(), 'configureArguments': CONFIGURE,
            'buildArguments': ['--target', 'Dictionaries', '--parallel', '4'],
            'host': {'system': platform.system(), 'version': platform.mac_ver()[0],
                     'architecture': platform.machine()}, 'compiler': compiler}


def check_provenance(value):
    if (not isinstance(value, dict) or value.get('schemaVersion') != 1
            or value.get('cmake') != lock() or value.get('configureArguments') != CONFIGURE
            or value.get('buildArguments') != ['--target', 'Dictionaries', '--parallel', '4']):
        raise ValueError('Generation provenance differs from locked tools/configuration; regenerate')
    if not all(value.get('compiler', {}).get(key) for key in ('CMAKE_CXX_COMPILER_ID', 'CMAKE_CXX_COMPILER_VERSION')):
        raise ValueError('Missing compiler provenance')
    if not all(value.get('host', {}).get(key) for key in ('system', 'version', 'architecture')):
        raise ValueError('Missing generation host provenance')
