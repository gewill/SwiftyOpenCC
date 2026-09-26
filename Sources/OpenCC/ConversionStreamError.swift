import copencc

/// Failures specific to `ChineseConversionStream`.
///
/// A stream also throws `ConversionError`, such as `.invalidUTF8` for malformed
/// input. These cases stay out of `ConversionError` so that existing exhaustive
/// switches over it keep compiling.
public enum ConversionStreamError: Error {

    /// The converter uses a stage or segmenter without exact streaming support.
    case unsupportedConfiguration

    /// The stream has already finished, or a previous append or finish failed.
    case closed
}

/// Maps a stream bridge failure; failures shared with complete-string
/// conversion remain `ConversionError`.
func streamError(_ code: CCErrorCode) -> Error {
    switch code {
    case .unsupportedStreamingConfiguration:
        return ConversionStreamError.unsupportedConfiguration
    case .streamClosed:
        return ConversionStreamError.closed
    default:
        return ConversionError(code)
    }
}
