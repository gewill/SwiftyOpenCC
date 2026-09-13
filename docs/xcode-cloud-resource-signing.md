# iOS resource bundle signing fix

2026-09-13; base `aa2f5d61e133d1dc61538428184bb5d0ae04ceef`. OpenCC remains 1.4.2, and all 42 resource hashes are unchanged.

## Observed failure

OpenCCman's Xcode Cloud run 42 (`2f6ea0dc-1f97-419a-a95c-c81b487712a3`, app commit `c2c8581b8f1b781f5c05321f58fe484634341374`, wrapper pin `eacb73dcb28c26e7cc5d8d9cb405e88fa2d59b13`) failed its iOS archive. macOS archive succeeded; subsequent TestFlight actions were skipped.

The failed action used `CODE_SIGN_IDENTITY=- AD_HOC_CODE_SIGNING_ALLOWED=YES`. Its error occurred while signing `SwiftyOpenCC_OpenCC.bundle`:

```text
bundle format unrecognized, invalid, or unsuitable
Command CodeSign failed with a nonzero exit code
```

The prior package declaration copied `Resources` as a directory into the iOS bundle root. On the same local Xcode 26.6 / SDK 26.5, the old package reproduced this error with the cloud signing settings. A copy of the actual exported iOS data bundle also failed `codesign`; renaming its top-level `Resources` directory made that isolated copy sign successfully. Neither experiment modified a production artifact.

Apple documents that [`Resource.copy`](https://developer.apple.com/documentation/xcode/bundling-resources-with-a-swift-package) preserves copied directory structure. The signing result here is established by the cloud log and local reproduction, not by assuming a certificate failure from a generic CodeSign error.

## Change

Copy `Resources/Official`, `Resources/Compatibility` and `Resources/manifest.json` individually. Their bundle paths are now `Official`, `Compatibility` and `manifest.json`; `ChineseConverter` resolves those paths through `Bundle.module`. Source resource locations and generator paths stay unchanged, as do dictionary bytes, public options and conversion behavior. This removes the problematic top-level directory without disabling signing or flattening the contents of each data folder.

## Regression and evidence

```bash
python3 scripts/update-opencc-resources.py --check
swift test
bash scripts/check-ios-resource-signing.sh
```

The new CI check builds the actual package for generic iOS in Release with the cloud ad-hoc signing settings and iOS 14 deployment target. It verifies the produced bundle signature, presence of both data folders, absence of the old root directory, exact manifest bytes and every packaged resource hash. It uses a fresh temporary DerivedData directory and needs no device, simulator or developer signing identity.

Local validation: resource manifest check passed; seven Swift tests passed (32 option combinations, official fixtures, compatibility modes, Unicode/NUL, native lifetime and concurrency); iOS Release package build and bundle signature verification passed. The old declaration failed under the same cloud signing settings. Complete application distribution still needs a newly merged app dependency pin and a successful Xcode Cloud run; this package check is not TestFlight acceptance.

This fix is independent of the generation/CLI tooling PR. Merge both engine changes and require successful checks on the resulting master SHA before the coordinator proposes an application dependency update. OpenCCman's formal release path remains Xcode Cloud on `build`-prefixed branches, as documented in its application guide.
