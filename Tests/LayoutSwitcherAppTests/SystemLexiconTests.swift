import Foundation
import XCTest
import LayoutSwitcherCore
@testable import LayoutSwitcherApp

private final class SendableGate: @unchecked Sendable {
    let semaphore = DispatchSemaphore(value: 0)
}

final class SystemLexiconTests: XCTestCase {
    func testUnknownSpellingLookupIsBoundedAndConservative() {
        let gate = SendableGate()
        let lexicon = SystemLexicon(
            words: [.english: [], .russian: []],
            spellingTimeout: .milliseconds(5)
        ) { _, _ in
            gate.semaphore.wait()
            return true
        }

        let started = ContinuousClock.now
        XCTAssertFalse(lexicon.contains("unknown", language: .english))
        XCTAssertLessThan(started.duration(to: .now), .milliseconds(100))
        gate.semaphore.signal()
    }
}
