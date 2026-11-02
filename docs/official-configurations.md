# Official configurations

`ChineseConverter(configuration:)` opens any of the 16 official configurations
bundled with OpenCC 1.4.2 by name. Before this API, `Options` reached ten of them;
`s2hkp`, `hk2sp`, `tw2t`, `hk2t`, `t2jp` and `jp2t` were bundled but unreachable.
Tracked by [OpenCCman#302](https://github.com/gewill/OpenCCman/issues/302).

| Configuration | `Options` equivalent |
| --- | --- |
| `s2t`, `t2s`, `s2tw`, `tw2s`, `s2hk`, `hk2s`, `s2twp`, `tw2sp`, `t2tw`, `t2hk` | Yes; both APIs load the same file |
| `s2hkp`, `hk2sp`, `tw2t`, `hk2t`, `t2jp`, `jp2t` | None; only `Configuration` reaches them |

The `Options` API is unchanged: all 32 option combinations keep their 14
effective modes, including the four compatibility configurations.

## Streaming

`makeStream()` supports every configuration, so nothing falls back silently.
`tw2t`, `hk2t`, `t2jp` and `jp2t` have no segmentation stage; the stream bridge
already treats a missing segmenter as one dictionary match per position, the
same as complete-string conversion.

`StreamingTests` runs every stream test on the 14 option modes plus the six new
configurations: every byte cut, chunk sizes from 1 to 1,024 bytes, all official
fixtures joined, phrase partitions, IDS limits, bounded pending input and long
unmatched runs. In each case the output equals complete-string conversion byte
for byte.

## Comparison with the OpenCC command-line tool

`scripts/check-official-cli.py` builds the `opencc` tool from the locked
submodule and compares it with the wrapper:

- Every configuration is checked through `init(configuration:)`.
- The ten with an equivalent are checked again through `init(options:)`.
- Inputs are the upstream fixtures for each mode plus nine boundary strings per
  configuration: empty, CRLF/CR, Emoji, combining marks, a 4,000-byte run, and
  characters that only `tw2t`, `hk2t`, `t2jp` and `jp2t` change.

Result on 2026-11-03, before CI:

| Item | Value |
| --- | --- |
| OpenCC | `ver.1.4.2`, `025f371dc76b598d77384fbdab90c937471844d8` |
| Toolchain | Xcode 27.1, Swift 6.4, AppleClang 21.0.0.21000334, macOS 27.2 arm64 |
| Fixture file SHA-256 | `3f8273c5f432090ec1a8a01bd4d545046ad5a28e69eb41a081c5e3e54d3e402b` |
| Comparisons | 1,285 byte-identical (1,051 from fixtures, 234 boundary) |
| New configurations | `s2hkp` 18, `hk2sp` 18, `tw2t` 27, `hk2t` 26, `t2jp` 13, `jp2t` 13 |

```sh
git submodule update --init --recursive
python3 scripts/check-official-cli.py
```

The full per-case report is written to `.build/official-cli-report.json` and
kept by CI as the `official-cli-comparison` artifact.
