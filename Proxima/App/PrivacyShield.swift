import SwiftUI

/// Masque l'écran dès que la scène n'est plus active (M3-11, menace STRIDE I3).
/// `.inactive` couvre l'instantané de l'aperçu multitâche, le centre de contrôle et les notifications ;
/// `.background` couvre la capture système au passage en arrière-plan.
/// Aucun pseudonyme, alias ni durée d'appel n'est affiché : seulement le nom de l'app.
struct PrivacyShieldView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea() // fond opaque
            VStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 72)).foregroundStyle(.tint)
                Text("Proxima").font(.title.bold())
            }
        }
        .accessibilityHidden(true)
    }
}

/// Règle d'affichage, isolée pour être testable.
enum PrivacyShieldPolicy {
    static func isShielded(_ phase: ScenePhase) -> Bool { phase != .active }
}

private struct PrivacyShieldModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.overlay {
            if PrivacyShieldPolicy.isShielded(scenePhase) {
                PrivacyShieldView().transition(.identity) // pas d'animation : l'instantané doit être déjà masqué
            }
        }
    }
}

extension View {
    /// Masque le contenu quand l'app n'est pas au premier plan actif.
    func privacyShield() -> some View { modifier(PrivacyShieldModifier()) }
}
