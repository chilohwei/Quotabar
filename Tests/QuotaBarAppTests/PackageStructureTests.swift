import Testing
@testable import QuotaBarApp

@Suite("Package structure")
struct PackageStructureTests {
    @Test("Quota windows calculate bounded percentages")
    func quotaWindowPercentages() {
        let window = QuotaWindow(label: "5h", used: 25, limit: 100, resetAt: nil)

        #expect(window.remaining == 75)
        #expect(window.usagePercent == 0.25)
        #expect(window.remainingPercent == 75)
    }
}
