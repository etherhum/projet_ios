import Foundation
import UIKit

/// Détenteur de secrets de session (clés, nonces, compteurs…) à effacer en fin d'appel (M3-11).
/// Adopté par `CallSession` (`wipeSecrets()` → raccrocher si besoin + `teardown()`, donc `SessionKeys.destroy()`),
/// enregistrée par `AppState` via `janitor.register(_:)` au début de chaque appel.
@MainActor
protocol SessionSecretHolder: AnyObject {
    func wipeSecrets()
}

/// Politique en arrière-plan (voir JOURNAL_LOG, M3-11) : l'appel est terminé et les secrets effacés.
enum BackgroundCallPolicy: Equatable {
    case endCall
    case keepCall

    static let current: BackgroundCallPolicy = .endCall
}

/// Enregistre les détenteurs de secrets (références faibles) et les efface
/// en fin d'appel, au passage en arrière-plan (selon la politique) et à la terminaison.
@MainActor
final class SecretsJanitor {
    private struct WeakHolder { weak var value: SessionSecretHolder? }
    private var holders: [WeakHolder] = []
    let backgroundPolicy: BackgroundCallPolicy
    private var terminationObserver: NSObjectProtocol?

    init(backgroundPolicy: BackgroundCallPolicy = .current, observeTermination: Bool = true) {
        self.backgroundPolicy = backgroundPolicy
        if observeTermination {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willTerminateNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.appWillTerminate() }
            }
        }
    }

    deinit {
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    /// Nombre de détenteurs encore vivants.
    var liveHolderCount: Int { holders.filter { $0.value != nil }.count }

    func register(_ holder: SessionSecretHolder) {
        compact()
        guard !holders.contains(where: { $0.value === holder }) else { return }
        holders.append(WeakHolder(value: holder))
    }

    /// Fin d'appel (raccrocher, erreur, pair perdu) : efface tout puis oublie les détenteurs.
    func callDidEnd() { wipeAll() }

    /// Passage en arrière-plan : `true` si l'appel doit être coupé (secrets effacés).
    @discardableResult
    func appDidEnterBackground() -> Bool {
        guard backgroundPolicy == .endCall else { return false }
        wipeAll()
        return true
    }

    func appWillTerminate() { wipeAll() }

    private func wipeAll() {
        let alive = holders.compactMap(\.value)
        holders.removeAll()
        alive.forEach { $0.wipeSecrets() }
    }

    private func compact() { holders.removeAll { $0.value == nil } }
}
