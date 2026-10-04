import XCTest
@testable import PTMate

final class SmokeTests: XCTestCase {
    func testAppVersion() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        XCTAssertNotNil(version)
    }
}
