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
