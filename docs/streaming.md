# Exact bounded UTF-8 streaming

`ChineseConverter.makeStream()` creates a wrapper-owned streaming session. The
complete-string API and pinned OpenCC submodule are unchanged. The session owns
its conversion stages/dictionaries independently of the original Swift object.
It is mutable and single-consumer; use separate sessions for concurrent jobs.

## Conversion equivalence

A fixed trailing window is insufficient: a dictionary phrase can straddle the
chosen flush boundary even if enough context remains in that window. The bridge
instead scans from the current undecided position, using upstream `PrefixMatch`
and each dictionary's actual maximum key byte length. It advances only over a
complete stable dictionary match or unmatched IDS/scalar. Upstream IDS helpers
decide whether additional input is required, using their depth-16 and 64-scalar
limits. No independent dictionary parser or matching policy is introduced.

Each conversion emits what upstream `Conversion::AppendConverted` would for those
units: a match appends its dictionary value and any other unit is copied as is.
The match comes from the scanner's own upstream `PrefixMatch`, so every byte is
matched once instead of being rescanned by a second conversion pass.
For mmseg, each dictionary match closes the preceding unmatched segment and is
converted as its own segment. An unmatched run can continue indefinitely, so it
is fed incrementally through every conversion in the chain; each conversion
retains its own undecided suffix. It is never accumulated into a whole segment.
Normalization runs before main segmentation, preserving the original stage
order. Each NUL flushes/resets all stages and is copied literally, matching the
existing complete-string bridge workaround.

UTF-8 is validated before upstream matching. Overlong forms, surrogates, invalid
continuation bytes and scalars above U+10FFFF are rejected. At most three bytes
of an incomplete scalar cross append calls. The session remains terminal after
any error, so partial output must not be committed by a file caller.
Dictionary output is not revalidated. If a malformed dictionary value ends in a
truncated scalar, the unit reading it waits for more input mid-stream and is
clamped at the end as upstream does, never reading past the buffered bytes.

The retained undecided input depends on dictionary/IDS limits and the number of
stages. Working allocations additionally depend on the largest caller chunk and
its converted size. Output already returned belongs to the caller; accumulating
it defeats bounded-memory file processing. A diagnostic pending-byte count in
the internal bridge tests detects accidental accumulation of whole runs; it is
not a process-memory measurement.

## Regression coverage

`StreamingTests` differentially compares streamed bytes with the complete API
across all 14 supported option modes, including the application's seven modes:

- Every possible two-chunk byte split and repeated one-byte appends.
- Official bundled fixtures, normalization, mixed line endings, BOM, Emoji,
  combining scalars and NUL separators.
- The `头发` / `干杯` phrase boundary regression with shifted input padding.
- Complete, incomplete and over-limit IDS sequences at depth/scalar limits.
- A custom text-dictionary chain with length changes and mmseg boundaries, proving
  unmatched bytes can interact across chunks but separate matched segments cannot.
- Long unmatched/Chinese/IDS runs with bounded pending input.
- Strict UTF-8 errors, truncated EOF, terminal state and native handle release.
- Stream-only failures as `ConversionStreamError`, with an exhaustive switch that
  keeps `ConversionError` source compatible.

The existing ThreadSanitizer concurrency regression also creates independent
sessions from a shared converter. `swift test --sanitize=address` covers the new
stream tests. Resource and official CLI validation still apply; CLI parity is
for the existing complete-string path because the upstream CLI uses its own
streaming algorithm. App file I/O, cancellation, sandbox saves and 1 GiB capacity
acceptance require separate application evidence.
