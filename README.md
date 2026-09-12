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

## Updating OpenCC

The `OpenCC` submodule selects one official stable release. Source code, configurations, dictionaries and test fixtures must be updated together.

```sh
git -C OpenCC fetch --tags
git -C OpenCC checkout ver.1.4.2
python3 scripts/update-opencc-resources.py
python3 scripts/update-opencc-resources.py --check
swift test
```

Generation requires Python 3 and CMake on a little-endian host. It builds dictionaries into `.build/opencc-resources`, copies the official JSON configurations and generated `.ocd2` files into the SwiftPM resource bundle, and records the exact release and SHA-256 inventory in `Sources/OpenCC/Resources/manifest.json`. It never edits the OpenCC submodule. `--check` only verifies the source lock and bundled files and requires no CMake or compilation.

The four reviewed configurations in `Configuration/Compatibility` belong to this wrapper. They retain the old mixed-option meanings and must not be replaced by a fork-sync operation. An OpenCC release that changes its C++ source/dependency layout may also require a reviewed `Package.swift` update; changing the submodule alone is not sufficient.

Tests read their fixture from the resource bundle, without a source-tree fallback. Ten official conversion modes are checked against upstream expected output; unsupported modes such as `tw2t` are explicitly excluded because the current public options cannot express them. There is no new public conversion mode in this migration.

## Validation and performance

See [the 1.4.2 migration record](docs/opencc-1.4.2-migration.md) for test coverage, known semantic changes and the measured cold-start/memory tradeoff. Reproduce the engine comparison with:

```sh
python3 scripts/benchmark-engine.py --baseline /path/to/SwiftyOpenCC-at-53f200c --candidate . --output /tmp/engine-benchmark.json
```

## License

The Swift wrapper is available under the [MIT license](LICENSE). OpenCC and its bundled dependencies retain their respective upstream licenses.
