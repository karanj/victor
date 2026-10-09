import Foundation
@testable import Victor

struct DebounceNeverRegistered: Error, CustomStringConvertible {
    var description: String { "debounce never registered within the timeout" }
}

/// Waits for a debounce Task to actually register, rather than sleeping a fixed
/// interval and hoping it has (#51): Task scheduling lags under full-suite load.
/// Pair with a debounce delay far longer than the test, so the only way the
/// debounce can end is the cancellation under test.
func waitForDebounceRegistration(on service: AutoSaveService, timeout: TimeInterval = 5) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while await service.debounceRegistrationCount == 0 {
        guard Date() < deadline else { throw DebounceNeverRegistered() }
        try await Task.sleep(for: .milliseconds(5))
    }
}
