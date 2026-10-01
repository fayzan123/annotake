@testable import AnnotakeApp
import Testing

struct AppVersionTests {
    @Test func readsBothKeys() {
        let version = AppVersion.from(infoDictionary: ["CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "74"])
        #expect(version == AppVersion(short: "0.2.0", build: "74"))
        #expect(version.description == "0.2.0 (74)")
    }

    @Test func missingKeysFallBack() {
        #expect(AppVersion.from(infoDictionary: nil).description == "0.0.0 (0)")
        #expect(AppVersion.from(infoDictionary: ["CFBundleVersion": "74"]).description == "0.0.0 (74)")
    }
}
