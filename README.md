# Swifty Open Chinese Convert

Swift port of [OpenCC](https://github.com/BYVoid/OpenCC), with bundled offline dictionaries.

## Requirements

- Swift 5.4 or later; C++17-compatible Apple toolchain.
- This fork is validated for the OpenCCman deployment targets: macOS 11 and iOS 14. It adds no newer OS API requirement.
- Initialize the OpenCC submodule when building a source checkout: `git submodule update --init --recursive`.

## Usage

```swift
import OpenCC

let converter = try ChineseConverter(options: [.traditionalize, .twStandard, .twIdiom])
converter.convert("鼠标里面的硅二极管坏了，导致光标分辨率降低。")
// 滑鼠裡面的矽二極體壞了，導致游標解析度降低。
```

`ChineseConverter` remains immutable and supports concurrent conversion. All five public option bits and their existing precedence are preserved, including the four mixed character/idiom combinations without an exact official configuration. Conversion accepts embedded U+0000 without truncating the suffix. Native handles are released when the Swift object is deinitialized.

### Incremental UTF-8 conversion

Use an independent session for large files without retaining the complete input
or output. Process returned bytes immediately, then write the final tail:

```swift
let stream = try converter.makeStream()
while let chunk = try input.read(upToCount: 256 * 1024), !chunk.isEmpty {
    try output.write(contentsOf: stream.append(chunk))
}
try output.write(contentsOf: stream.finish())
```

`input` and `output` are caller-owned `FileHandle` values. Serialize calls to each
mutable `ChineseConversionStream`; independent sessions can run concurrently
and may outlive their converter. The stream preserves embedded NUL, line endings
and BOM, matching complete-string conversion. File applications that omit the
leading BOM must strip it before appending. Chunk boundaries may split UTF-8
scalars or phrases. Malformed UTF-8 throws `ConversionError.invalidUTF8`;
`finish()` also rejects a truncated final scalar. Completion or any error makes
the session terminal (`ConversionStreamError.closed` on subsequent use).
Stream-only failures use `ConversionStreamError`, so exhaustive switches over
`ConversionError` keep compiling.
Discard partial output after an error; applications should write to a temporary
file and commit it only after successful completion.

The bridge consumes complete dictionary/IDS match units, retaining bounded
lookahead from actual dictionary key lengths. It preserves normalization,
mmseg segment boundaries and conversion-chain order, including arbitrarily long
unmatched runs. All 14 existing option modes are supported. Future unsupported
converter or segmenter implementations fail explicitly with
`ConversionStreamError.unsupportedConfiguration`. See
[streaming validation](docs/streaming.md) for the algorithm and regression cases.

### Cancellation

OpenCC 1.4.2 cannot interrupt a conversion: its C and C++ APIs have no cancel,
progress or deadline hook, and every native call runs to completion. Once
`convert(_:)` starts, a caller can only discard its result.

A stream can be abandoned between calls. Check for cancellation before each
`append(_:)`, then release the session without calling `finish()`. This frees its
native state and leaves the converter and other sessions unaffected. The call
already running still completes, so cancellation takes effect within the time
needed to convert one chunk; smaller chunks respond sooner.

## Upstream sync and maintenance

This fork follows [`ddddxxx/SwiftyOpenCC`](https://github.com/ddddxxx/SwiftyOpenCC) wrapper commits and stable [`BYVoid/OpenCC`](https://github.com/BYVoid/OpenCC) releases. The coordinator lives in **OpenCCman/main**: it proposes a fork PR, then an **OpenCCman/build** revision-update PR after this fork's merge commit passes CI. Each PR is reviewed and merged by a maintainer.

See the [fork maintenance guide](docs/upstream-sync.md) for source/resource updates, compatibility constraints and required checks. The shared [coordinator guide](https://github.com/gewill/OpenCCman/blob/main/docs/upstream-sync.md) covers scheduling, commands, credentials and rollback. Updating only the OpenCC submodule is insufficient: source, configurations, dictionaries and fixtures must stay in sync.

## Validation and performance

See [the 1.4.2 migration record](docs/opencc-1.4.2-migration.md) for test coverage, known semantic changes and the measured cold-start/memory tradeoff. Reproduce the engine comparison with:

```sh
python3 scripts/benchmark-engine.py --baseline /path/to/SwiftyOpenCC-at-53f200c --candidate . --output /tmp/engine-benchmark.json
```

Run `bash scripts/check-ios-resource-signing.sh` to verify iOS resource packaging with Xcode Cloud's archive signing settings. See the [resource bundle signing fix](docs/xcode-cloud-resource-signing.md) for the reproduced failure and validation boundary.

## License

The Swift wrapper is available under the [MIT license](LICENSE). OpenCC and its bundled dependencies retain their respective upstream licenses.
