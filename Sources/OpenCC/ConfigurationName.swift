extension ChineseConverter.Options {
    // This retains all 32 combinations of the five existing option bits.
    // Four mixed idiom/character combinations require legacy configurations.
    var configurationName: String {
        if contains(.traditionalize) {
            if contains(.hkStandard) {
                return contains(.twIdiom) ? "legacy-s2hk-tw-idiom" : "s2hk"
            }
            if contains(.twStandard) {
                return contains(.twIdiom) ? "s2twp" : "s2tw"
            }
            return contains(.twIdiom) ? "legacy-s2t-tw-idiom" : "s2t"
        }
        if contains(.simplify) {
            if contains(.hkStandard) {
                return contains(.twIdiom) ? "legacy-hk2s-tw-idiom" : "hk2s"
            }
            if contains(.twStandard) {
                return contains(.twIdiom) ? "tw2sp" : "tw2s"
            }
            return contains(.twIdiom) ? "legacy-t2s-tw-idiom" : "t2s"
        }
        if contains(.hkStandard) { return "t2hk" }
        if contains(.twStandard) { return "t2tw" }
        return "s2t"
    }
}
