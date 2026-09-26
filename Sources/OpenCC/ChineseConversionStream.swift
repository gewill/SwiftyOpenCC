import Foundation
import copencc

/// Incrementally converts UTF-8 with the same output as `ChineseConverter.convert`.
///
/// Append chunks in order and call `finish()` exactly once. Chunks may split UTF-8
/// scalars and dictionary phrases. Newlines, embedded NUL and BOM are preserved;
/// file callers that omit a leading BOM must remove it before appending.
///
/// This mutable session is single-consumer: serialize all calls. Any error makes
/// it terminal; discard previously returned output on failure. Its retained
/// input is bounded by dictionary lookahead and IDS limits, not document length.
public final class ChineseConversionStream {
    private let stream: CCStreamRef

    init(stream: CCStreamRef) { self.stream = stream }

    deinit { CCStreamDestroy(stream) }

    /// Converts the stable prefix and returns its bytes; an empty result is valid.
    /// Throws `ConversionError.invalidUTF8` for malformed UTF-8, or
    /// `ConversionStreamError.closed` after completion or a previous failure.
    public func append(_ utf8: Data) throws -> Data {
        var error = CCErrorCode.unknown
        let result = utf8.withUnsafeBytes { bytes -> STLString? in
            CCStreamAppend(stream, bytes.baseAddress?.assumingMemoryBound(to: CChar.self), bytes.count, &error)
        }
        return try consume(result, error: error)
    }

    /// Converts all remaining input, failing if the final UTF-8 scalar is incomplete.
    public func finish() throws -> Data {
        var error = CCErrorCode.unknown
        return try consume(CCStreamFinish(stream, &error), error: error)
    }

    // Internal diagnostics: retained undecided input across all stages, excluding
    // dictionary storage, output returned to the caller, and string capacity.
    var pendingByteCount: Int { CCStreamGetPendingByteCount(stream) }

    private func consume(_ result: STLString?, error: CCErrorCode) throws -> Data {
        guard let result = result else { throw streamError(error) }
        defer { STLStringDestroy(result) }
        return Data(bytes: STLStringGetUTF8String(result), count: STLStringGetLength(result))
    }
}
