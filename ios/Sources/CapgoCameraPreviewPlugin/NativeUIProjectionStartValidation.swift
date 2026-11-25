enum NativeUIProjectionStartValidation {
    static let missingSelectorMessage = "nativeUIProjectionSelector is required when nativeUIProjection is true"

    static func isMissingSelector(enabled: Bool, selector: String?) -> Bool {
        enabled && (selector?.isEmpty ?? true)
    }
}