#!/bin/bash
set -euo pipefail

# Exercise the same ad-hoc bundle signing used before Xcode Cloud distribution.
# No developer certificate, device, provisioning profile or simulator is needed.
cd "$(dirname "$0")/.."
scratch=$(mktemp -d "${TMPDIR:-/tmp}/opencc-ios-signing.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
xcodebuild -scheme SwiftyOpenCC -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$scratch" \
  CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES \
  IPHONEOS_DEPLOYMENT_TARGET=14.0 build
bundle="$scratch/Build/Products/Release-iphoneos/SwiftyOpenCC_OpenCC.bundle"
test -d "$bundle/Official"
test -d "$bundle/Compatibility"
test -f "$bundle/manifest.json"
test ! -e "$bundle/Resources"
python3 - "$bundle" <<'PY'
import hashlib
import json
from pathlib import Path
import sys

bundle = Path(sys.argv[1])
manifest = Path("Sources/OpenCC/Resources/manifest.json")
assert (bundle / "manifest.json").read_bytes() == manifest.read_bytes()
files = json.loads(manifest.read_text())["files"]
for relative, expected in files.items():
    assert hashlib.sha256((bundle / relative).read_bytes()).hexdigest() == expected, relative
print(f"Verified {len(files)} packaged resource hashes.")
PY
/usr/bin/codesign --verify --strict "$bundle"
echo 'iOS resource bundle built and signature verified.'
