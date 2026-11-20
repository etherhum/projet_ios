import XCTest
@testable import Proxima

/// M3-12 : la façade AppLog ne permet pas de fuite.
///
/// Test de CONCEPTION (vérifié par le compilateur, donc non exécutable en négatif) :
/// - `AppLog.Event` n'a AUCUNE valeur associée : `AppLog.log(.found(pseudonym))` ne compile pas.
/// - `AppLog.Event.message` est un `StaticString` : `return "\(pseudonym)"` ne compile pas
///   (« cannot convert value of type 'String' to specified type 'StaticString' »).
/// - La seule entrée dynamique (`correlation:`) est codée en dur en `.private(mask: .hash)`.
final class LogTests: XCTestCase {
    private let pseudonymPattern = "[A-Z2-7]{13}"

    func testEventsHaveNoAssociatedValues() {
        // CaseIterable n'est synthétisable que pour une enum sans valeur associée.
        XCTAssertGreaterThanOrEqual(AppLog.Event.allCases.count, 6)
        for e in AppLog.Event.allCases {
            XCTAssertEqual(Mirror(reflecting: e).children.count, 0, "\(e) porte une donnée")
        }
    }

    func testMessagesAreStaticAndContainNoPseudonymPattern() {
        for e in AppLog.Event.allCases {
            let m: StaticString = e.message
            XCTAssertTrue(m.hasPointerRepresentation, "message non littéral")
            let s = m.description
            XCTAssertFalse(s.isEmpty)
            XCTAssertNil(s.range(of: pseudonymPattern, options: .regularExpression), s)
            XCTAssertNil(s.range(of: "%@|%s|%d|\\\\\\(", options: .regularExpression), "format dans \(s)")
        }
    }

    func testMessagesDoNotMatchAnyRealPseudonymOrAlias() {
        let samples = (0..<200).map { _ in Pseudonym.random() }
        let animals = ["Renard", "Loutre", "Hibou", "Lynx", "Castor", "Faucon", "Blaireau", "Héron",
                       "Lièvre", "Martre", "Chouette", "Cerf", "Bouquetin", "Marmotte", "Écureuil", "Mésange"]
        for e in AppLog.Event.allCases {
            let s = e.message.description
            for p in samples { XCTAssertFalse(s.contains(p.value) || s.contains(p.alias)) }
            for a in animals { XCTAssertFalse(s.contains(a), "nom d'alias dans \(s)") }
        }
    }

    /// Chaque phase terminale ou significative a un événement distinct ; aucune donnée de la phase (code) n'est journalisée.
    func testCallPhaseEventsCoverEveryOutcome() {
        let phases: [CallPhase] = [.outgoingRequest, .incomingRequest, .verifying(code: "123456"), .active(code: "123456"),
                                   .ended(.localHangUp), .ended(.remoteHangUp), .ended(.declined),
                                   .failed(.declinedOrNoAnswer), .failed(.timeout), .failed(.protocolError),
                                   .failed(.codeMismatch), .failed(.disconnected)]
        let events = phases.compactMap(AppLog.Event.forCallPhase)
        XCTAssertEqual(events.count, phases.count)
        XCTAssertEqual(Set(events.map { $0.message.description }).count, phases.count)
        for e in events { XCTAssertFalse(e.message.description.contains("123456")) }
        XCTAssertNil(AppLog.Event.forCallPhase(.idle))
    }

    func testMessagesAreUnique() {
        let all = AppLog.Event.allCases.map { $0.message.description }
        XCTAssertEqual(Set(all).count, all.count)
    }

    func testSubsystemAndCategories() {
        XCTAssertTrue(AppLog.subsystem.hasPrefix("fr.epita.projetios.proxima"))
        XCTAssertEqual(Set(AppLog.Category.allCases.map(\.rawValue)), ["discovery", "session", "crypto", "audio", "ui"])
    }

    func testDebugLevelGatedByBuildConfiguration() {
        XCTAssertTrue(AppLog.shouldEmit(.info))
        XCTAssertTrue(AppLog.shouldEmit(.error))
        XCTAssertEqual(AppLog.shouldEmit(.debug), AppLog.isDebugEnabled)
        #if DEBUG
        XCTAssertTrue(AppLog.isDebugEnabled)
        #else
        XCTAssertFalse(AppLog.isDebugEnabled)
        #endif
    }

    func testLoggingAllEventsDoesNotCrash() {
        for e in AppLog.Event.allCases { AppLog.log(e); AppLog.log(e, correlation: "opaque") }
    }
}
