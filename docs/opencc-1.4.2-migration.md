# OpenCC 1.4.2 migration

The wrapper now uses official OpenCC configuration loading and lifetime management. Public Swift entry points and option values remain compatible. `swift-tools-version` increases from 5.3 to 5.4 because SwiftPM introduced `.cxx17` in PackageDescription 5.4; this does not increase the app's iOS 14/macOS 11 deployment targets.

## Source and resources

- Previous wrapper: `53f200cebe40eade3ebda025b0e8980e08cf23fa`; OpenCC `ver.1.2.0` at `907bfcbbd3aae86ff04bc8eaca67c8af03108ddf`.
- New engine: OpenCC [`ver.1.4.2`](https://github.com/BYVoid/OpenCC/releases/tag/ver.1.4.2), commit `025f371dc76b598d77384fbdab90c937471844d8`.
- The resource generator builds the official `Dictionaries` CMake target, bundles its 22 `.ocd2` dictionaries and 16 official configurations, and adds four reviewed compatibility configurations. A manifest records the source tag/SHA and hashes for all 42 resources. Official test fixtures are copied into the test bundle and checked against the locked source.
- The OpenCC submodule stays clean. No generated header, patch or binary is written into it. C++ source inventory and dependency paths are explicit in SwiftPM; a future upstream layout change requires compatibility review.
- `.ocd2` contains host-endian marisa data. These Apple resources are generated on a little-endian host and checked as such; this is not a claim of big-endian portability.

## Compatibility and intentional output changes

The 32 combinations of five option bits retain their priority: traditionalize before simplify, Hong Kong before Taiwan characters. Unknown bits are ignored. No direction plus a regional character flag selects `t2hk` or `t2tw`; otherwise conversion defaults to `s2t`, even when only `twIdiom` is set.

Ten effective modes use official JSON: `s2t`, `t2s`, `s2tw`, `s2hk`, `s2twp`, `tw2s`, `hk2s`, `tw2sp`, `t2tw`, `t2hk`. Four mixed character/idiom modes use `Configuration/Compatibility`. Their Taiwan-phrase stage and optional Hong Kong character stage remain distinct. The two forward compatibility configurations incorporate the new official regional segmentation/first-stage dictionaries so that, for example, `硅二极管` still receives its Taiwan phrase conversion after upstream split regional entries into `STPhrases_GeneratedFromRegionalPhrases`.

This updates dictionary and official configuration behavior, not just compiled code. Official normalization, regional phrase/variant protection, and dictionary corrections can change results. The fixed benchmark corpus below has different output SHA-256 hashes. Tests compare official modes with 495 expected outputs from the same upstream release, rather than requiring 1.2.0 output to remain unchanged.

`tw2t` is not expressible by the existing options. The old test incorrectly mapped it to `.traditionalize`, which is `s2t`. Tests now classify the six unsupported official modes explicitly; no new public flag or app feature was added.

## Ownership, concurrency and U+0000

The old Swift-owned dictionaries, partially locked cache, and incomplete dictionary destroy wrapper have been replaced with a single RAII converter handle created by official `Config`. Swift `deinit` deletes it. Creation errors use a per-call error value, not a shared global. Native string results are always destroyed after length-aware Swift decoding. Internal atomic handle counters make the ownership regressions directly testable.

Both sides of the C bridge carry UTF-8 byte lengths. Direct testing additionally found that OpenCC 1.4.2's mmseg conversion paths still truncate at embedded NUL even when called using `std::string_view`. The bridge therefore converts complete NUL-free spans and reinserts every original NUL. The no-NUL hot path still makes one engine call. This local wrapper workaround leaves the OpenCC submodule unchanged and can be removed only after an upstream fix passes all NUL cases.

A minimal upstream reproduction is `Config::NewFromFile(s2twp)` followed by `converter->Convert(std::string_view("鼠标\0汉字", 13))`; its result is truncated to `滑鼠` under 1.4.2. (The UTF-8 input has 6 + 1 + 6 = 13 bytes.)

## Verification

- `python3 scripts/update-opencc-resources.py --check`: exact source lock and all resource/configuration/test-fixture checks pass.
- Removed the entire CMake resource build directory and regenerated from scratch; the manifest reproduced SHA-256 `8ece25227da099f939c10bf9b1bcad8df009d667d0d903dc0daa543c10dbe7bf`.
- `swift test`: 7 tests pass, covering all 32 option combinations/14 effective modes, 495 official expected outputs, four compatibility outputs, empty/leading/trailing/consecutive NUL, CRLF/combining accents/emoji/long boundaries, 64 concurrent constructors with shared conversion, missing configurations, and 100 native create/convert/destroy cycles.
- `swift test --sanitize=address --scratch-path .build/asan`: all 7 tests pass; no AddressSanitizer report.
- `swift test --sanitize=thread --scratch-path .build/tsan --filter OpenCCTests.testConcurrentCreationAndSharedConversion`: passes; no ThreadSanitizer report.
- The benchmark builds and links both actual SDKs with the same release-mode Swift executable. No simulator or full Xcode app build was used.
- Before migration, official core/marisa sources were checked with C++17 and SDK availability errors enabled for `arm64-apple-macos11.0` and `arm64-apple-ios14.0`. Full application linkage/device behavior remains release acceptance work.

## Same-machine engine benchmark

[Raw measurements and source hashes](engine-benchmark-1.4.2.json) were produced with `scripts/benchmark-engine.py`: five fresh processes per version, five hot conversions per process, the same 1,176,000-byte UTF-8 mixed Chinese/ASCII/emoji corpus, `s2twp`, and release-mode builds. Cold creation uses the median of five samples; hot conversion uses the median of 25 samples. RSS is macOS `getrusage.ru_maxrss`, a process peak including input/output buffers.

| Metric | OpenCC 1.2.0 wrapper | OpenCC 1.4.2 wrapper |
| --- | ---: | ---: |
| Cold converter creation | 15.31 ms | 30.86 ms |
| Hot full-text conversion | 187.58 ms | 15.47 ms |
| Peak RSS after creation | 17.92 MB | 52.02 MB |
| Peak RSS after conversion | 38.42 MB | 64.93 MB |

This corpus's hot conversion is approximately 91.8% faster, with slower creation and higher peak memory. These are engine measurements on one host, not an app-wide speed claim. Retaining reusable converters still matters; the app's seven-option cache should not be removed on the strength of the faster hot path. Multiple-converter app memory and lower-end device behavior remain release acceptance checks.

Input SHA-256: `2dfa20d9efc595c4016b0b61401ae454939e3bf1a89c883355e50bc4aad033a4` (see the JSON as source of truth).
Old output SHA-256: `860676b3c864912a2738bf1ae42892409d6e15c56e8127dd48caeb503379e41f`.
New output SHA-256: `c7b23f5f742f02439da81cf28d553d429c090e54c8189e23a4af6c99ecb6a577`.
