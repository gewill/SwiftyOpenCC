# Upstream sync and fork maintenance

This guide covers the **SwiftyOpenCC/master** side of the update chain. Scheduling, authentication, local coordinator commands, artifacts and rollback policy are maintained in the shared [OpenCCman coordinator guide](https://github.com/gewill/OpenCCman/blob/main/docs/upstream-sync.md).

## Sources and ownership

| Location | Responsibility |
| --- | --- |
| [ddddxxx/SwiftyOpenCC/master](https://github.com/ddddxxx/SwiftyOpenCC/tree/master) | Upstream Swift wrapper; merge incoming commits while preserving fork changes |
| [BYVoid/OpenCC releases](https://github.com/BYVoid/OpenCC/releases) | Stable core releases; lock the full commit SHA in the OpenCC submodule |
| [Package.swift](../Package.swift), `Sources`, `Configuration/Compatibility` | This fork's Swift/C++ bridge, source inventory and four reviewed compatibility configurations |
| [Resource manifest](../Sources/OpenCC/Resources/manifest.json) | Accepted core tag/SHA and SHA-256 inventory of bundled configurations and dictionaries |
| [OpenCCman/main coordinator](https://github.com/gewill/OpenCCman/blob/main/scripts/sync-upstream.py) | Prepare and validate isolated candidates, then open PRs in this fork and the application |

## Normal update flow

1. The [Sync OpenCC workflow](https://github.com/gewill/OpenCCman/actions/workflows/sync-opencc.yml) checks every Monday at 01:17 UTC (09:17 UTC+8), or on a manual run from `main`. There is no separate scheduled publisher in this fork.
2. It merges missing wrapper commits and, when needed, updates the core to an official stable release, regenerates resources and runs validation in a temporary checkout. It preserves fork patches and stops on conflicts, incoming workflow changes, moved accepted tags or automatic major-version upgrades.
3. Review the fork PR's source SHAs, diff, generated inventory, compatibility output changes and validation log. Merge with **Create a merge commit** into `master` to retain upstream ancestry; do not squash or rebase a fork sync PR.
4. Wait for **OpenCC Compatibility** on the resulting `master` SHA, not only the PR head. Run the coordinator again or wait for the next weekly check. It then proposes an **OpenCCman/build** PR that pins that exact revision, with app regression checks and no unrelated dependency changes.

To inspect or prepare locally, use an **OpenCCman/main checkout**, not this repository:

```sh
python3 scripts/sync-upstream.py check --stage fork
python3 scripts/sync-upstream.py prepare --stage fork
python3 scripts/sync-upstream.py pr --stage fork
```

`check` is read-only; `prepare` produces a patch, source manifest and report without pushing; `pr` validates and publishes. An existing pending PR makes that layer wait, and a manually closed candidate is not automatically reopened. See the coordinator guide for exit codes and recovery.

The app promotion compares full fork commit SHAs, not engine versions or changed file types. A documentation-only merge here can therefore result in a new app revision PR after CI passes, even if the bundled engine is unchanged.

## Manual core maintenance

Use a separate maintenance branch or checkout for compatibility work that the coordinator cannot perform automatically. Initialize the submodule first:

```sh
git submodule update --init --recursive
```

The following uses the already accepted 1.4.2 release as an example, not as a floating latest-version selector. For a new release, review the official release/tag and full SHA before selecting it; do not force-update an existing tag.

```sh
git -C OpenCC fetch --tags
git -C OpenCC checkout --detach ver.1.4.2
git -C OpenCC rev-parse HEAD
python3 scripts/update-opencc-resources.py
python3 scripts/update-opencc-resources.py --check
swift test
```

The accepted 1.4.2 SHA is `025f371dc76b598d77384fbdab90c937471844d8`. The current source of truth is the submodule and resource manifest, rather than this example.

Generation requires Python 3, a suitable macOS C++ toolchain and a little-endian host. The generator downloads the official CMake distribution locked by version and SHA-256 in [BuildTools/cmake.json](../BuildTools/cmake.json) into `.build/pinned-cmake`; it does not install or upgrade global tools. The checked-in checksum comes from the [official CMake release](https://cmake.org/download/). [The generator](../scripts/update-opencc-resources.py) builds the checked-out core's `Dictionaries` target in `.build/opencc-resources`. It copies official JSON configurations and `.ocd2` dictionaries, copies this fork's compatibility configurations and the same release's official test fixture, updates the generated `openccVersion` declaration in `Package.swift`, and records the core tag/SHA, resource checksums, pinned CMake source, actual configure/build arguments, configured compiler identity/version and generation host in the manifest. Compiler and OS versions are recorded, not claimed to be pinned. It never switches or edits the OpenCC submodule itself.

`--check` needs Python 3, Git and an initialized source submodule, but no CMake or compilation. It verifies the clean source lock, package version declaration, inventories, checksums, configuration references and bundled test fixture. Commit the submodule pointer and every corresponding generated change together. A new upstream C++ source/dependency layout also requires a reviewed `Package.swift` change.

## Compatibility and validation

The five public option bits retain their precedence: 32 combinations map to 14 effective modes. Ten use official configurations; four mixed Taiwan-idiom combinations use [Configuration/Compatibility](../Configuration/Compatibility). Those four source configurations belong to this fork and must not be replaced by upstream defaults. Dictionary changes may change output; explain actual changes in the PR instead of silently rewriting expectations. The [1.4.2 migration record](opencc-1.4.2-migration.md) documents supported modes, known output changes and measured performance tradeoffs.

Tests load fixtures from the resource bundle without a source-tree fallback. Modes such as `tw2t`, which the existing public options cannot express, remain explicitly unsupported. Embedded U+0000, native handle release and concurrent conversion are part of the compatibility contract.

[OpenCC Compatibility](../.github/workflows/ci.yml) runs for PRs to `master` and pushes to `master`, using these checks:

```sh
python3 scripts/update-opencc-resources.py --check
python3 -m unittest discover -s Tests -p 'test_*.py'
python3 scripts/check-official-cli.py
python3 scripts/check-revision-dependency.py
swift test
swift test --sanitize=address --scratch-path .build/asan
swift test --sanitize=thread --scratch-path .build/tsan --filter OpenCCTests.testConcurrentCreationAndSharedConversion
git diff --exit-code
```

The revision-consumer check resolves **committed HEAD** through a temporary Git remote and verifies the exact pin. Commit candidate changes before using it as evidence for that candidate: it does not test uncommitted edits. Keep `Package.swift` independent of adjacent runtime files; SwiftPM can evaluate a Git revision's manifest in a virtual filesystem where the resource JSON is unavailable.

The official CLI check builds the same locked source and dictionaries independently, then compares 495 official-fixture cases plus 70 format-boundary cases byte-for-byte across all ten public official modes. It passes `--include-tofu-risk-dictionaries` because `ConfigLoadOptions` defaults to true in the library while the CLI defaults to false; this preserves the existing wrapper's rare-character behavior. The four compatibility configurations remain covered by their fixed Swift tests. A separate fixed NUL assertion protects the wrapper workaround; NUL inputs are deliberately excluded from native parity.

The CLI check writes `.build/official-cli-report.json` (including failures) and CI retains it for 14 days. The report records source/configuration, compiler, hashes and per-case coverage; a previous green report is replaced before validation starts. See [the 1.3 validation follow-up](v1.3-validation-follow-up.md) for recorded evidence and remaining app acceptance work.

These engine checks do not replace app release acceptance. New compatibility changes still need the application checks and any relevant deployment/runtime validation. Benchmark actual versions on the same host when making performance claims; faster upstream conversion does not by itself prove faster application startup or lower memory usage.

## Rejection, rollback and coordinator changes

Close a fork candidate PR to reject it before merge. After promotion, restore the previous app revision through an **OpenCCman/build** PR first; if the fork itself needs rollback, revert its complete sync merge, including the submodule and generated resources, without rewriting history. Record the rejected candidate ID in `ignoredCandidates.fork` or `ignoredCandidates.app` in [OpenCCman/main's configuration](https://github.com/gewill/OpenCCman/blob/main/scripts/upstream-sync.json), as appropriate, so the same candidate is not proposed again.

Coordinator policy, credentials and schedule changes belong in **OpenCCman/main**. Bridge, generator, resource and engine CI changes belong here. Include the problem, implementation and validation log in each PR; recover failures using the shared guide rather than bypassing a failed check.
