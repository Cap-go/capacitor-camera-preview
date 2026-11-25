enum NativeUIProjectionStartValidation {
    static let missingSelectorMessage = "nativeUIProjectionSelector is required when nativeUIProjection is true"

    static func isMissingSelector(enabled: Bool, selector: String?) -> Bool {
        enabled && isBlankCssWhitespace(selector)
    }

    private static func isBlankCssWhitespace(_ selector: String?) -> Bool {
        guard let selector, !selector.isEmpty else {
            return true
        }
        for scalar in selector.unicodeScalars {
            switch scalar.value {
            case 0x20, 0x9, 0xA, 0xC, 0xD:
                continue
            default:
                return false
            }
        }
        return true
    }
}