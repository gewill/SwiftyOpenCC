extension ChineseConverter {

    /// The official OpenCC configurations bundled with this package. Raw values
    /// are the upstream configuration names, such as `s2twp`.
    ///
    /// Six of these (`s2hkp`, `hk2sp`, `tw2t`, `hk2t`, `t2jp`, `jp2t`) have no
    /// `Options` equivalent. Every case supports `makeStream()`.
    public enum Configuration: String, CaseIterable {

        /// Simplified Chinese to Traditional Chinese (OpenCC standard).
        case s2t
        /// Traditional Chinese (OpenCC standard) to Simplified Chinese.
        case t2s
        /// Simplified Chinese to Traditional Chinese (Taiwan standard).
        case s2tw
        /// Traditional Chinese (Taiwan standard) to Simplified Chinese.
        case tw2s
        /// Simplified Chinese to Traditional Chinese (Hong Kong variant).
        case s2hk
        /// Traditional Chinese (Hong Kong variant) to Simplified Chinese.
        case hk2s
        /// Simplified Chinese to Traditional Chinese (Taiwan standard, with Taiwan phrases).
        case s2twp
        /// Traditional Chinese (Taiwan standard) to Simplified Chinese, with Mainland phrases.
        case tw2sp
        /// Simplified Chinese to Traditional Chinese (Hong Kong variant, with Hong Kong phrases).
        case s2hkp
        /// Traditional Chinese (Hong Kong variant) to Simplified Chinese, with Mainland phrases.
        case hk2sp
        /// Traditional Chinese (OpenCC standard) to Taiwan standard.
        case t2tw
        /// Traditional Chinese (Taiwan standard) to OpenCC standard.
        case tw2t
        /// Traditional Chinese (OpenCC standard) to Hong Kong variant.
        case t2hk
        /// Traditional Chinese (Hong Kong variant) to OpenCC standard.
        case hk2t
        /// Old Japanese Kanji (Kyūjitai) to New Japanese Kanji (Shinjitai).
        case t2jp
        /// New Japanese Kanji (Shinjitai) to Old Japanese Kanji (Kyūjitai).
        case jp2t
    }
}
