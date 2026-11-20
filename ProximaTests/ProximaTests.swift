import XCTest
@testable import Proxima

@MainActor
final class TransportPrototypeTests: XCTestCase {
    @MainActor
    func testPseudonymIsEphemeralAndAnonymous() {
        let a = TransportPrototype(), b = TransportPrototype()
        XCTAssertNotEqual(a.pseudonym, b.pseudonym)
        XCTAssertTrue(a.pseudonym.hasPrefix("P-"))
        XCTAssertFalse(a.pseudonym.contains(UIDevice.current.name))
    }

    func testServiceTypeIsValidBonjourName() {
        let s = TransportPrototype.serviceType
        XCTAssertTrue((1...15).contains(s.count))
        XCTAssertNil(s.range(of: "[^a-z0-9-]", options: .regularExpression))
    }
}
