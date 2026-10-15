import Testing

extension Tag {
    /// Guards a bug that was fixed; named after its REG id in Tests/E2E/regressions.md.
    /// Run just these with `swift test --filter` on the REG id, or by tag in a test plan.
    @Tag static var regression: Self
}
