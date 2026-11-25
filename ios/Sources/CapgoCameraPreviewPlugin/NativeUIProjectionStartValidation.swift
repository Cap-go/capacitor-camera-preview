enum NativeUIProjectionStartValidation {
    static let missingSelectorMessage = "nativeUIProjectionSelector is required when nativeUIProjection is true"

    static func isMissingSelector(enabled: Bool, selector: String?) -> Bool {
        let trimmed = selector?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return enabled && trimmed.isEmpty
    }
}