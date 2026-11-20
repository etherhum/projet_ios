import Foundation

/// Minuterie de rotation injectable (tests sans attente).
@MainActor
protocol RotationTimer: AnyObject {
    func start(interval: TimeInterval, handler: @escaping @MainActor () -> Void)
    func stop()
}

@MainActor
final class SystemRotationTimer: RotationTimer {
    private var timer: Timer?

    func start(interval: TimeInterval, handler: @escaping @MainActor () -> Void) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            Task { @MainActor in handler() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

enum RotationPolicy {
    /// M2-03 : rotation du pseudonyme toutes les 10 minutes hors appel.
    static let defaultInterval: TimeInterval = 600

    /// En DEBUG uniquement, intervalle surchargeable au lancement par l'argument
    /// `-ProximaRotationSeconds <n>` (n ≥ 10), pour observer la rotation sans attendre. Jamais persisté.
    static var interval: TimeInterval {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-ProximaRotationSeconds"), i + 1 < args.count,
           let s = TimeInterval(args[i + 1]), s >= 10 { return s }
        #endif
        return defaultInterval
    }
}
