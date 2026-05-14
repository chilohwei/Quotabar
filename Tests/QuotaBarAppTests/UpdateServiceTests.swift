import Testing
@testable import QuotaBarApp

@Suite("Update service")
struct UpdateServiceTests {
    @Test("version comparison handles prefixes and suffixes")
    func appVersionComparison() {
        #expect(AppVersion("v1.2.10") > AppVersion("1.2.9"))
        #expect(AppVersion("1.2") == AppVersion("1.2.0"))
        #expect(AppVersion("1.2.0-beta.1") > AppVersion("1.1.9"))
    }

    @Test("release asset digest accepts GitHub SHA256 format")
    func releaseAssetDigestParsing() throws {
        let hex = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        #expect(try ReleaseAssetDigest.sha256Hex(from: "sha256:\(hex)") == hex)
        #expect(try ReleaseAssetDigest.sha256Hex(from: hex.uppercased()) == hex)
        #expect(try ReleaseAssetDigest.sha256Hex(from: "\(hex)  QuotaBar.dmg") == hex)
    }

    @Test("release asset digest rejects missing SHA256")
    func releaseAssetDigestRejectsInvalidValues() {
        #expect(throws: UpdateServiceError.self) {
            try ReleaseAssetDigest.sha256Hex(from: "md5:abc")
        }
    }
}
