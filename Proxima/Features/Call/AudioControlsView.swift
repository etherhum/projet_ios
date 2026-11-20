import SwiftUI

/// Contrôles audio de l'appel actif (M3-07) : micro coupé, haut-parleur ; compteurs de paquets en DEBUG.
struct AudioControlsView: View {
    @ObservedObject var audio: AudioPipeline

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 32) {
                toggle(audio.isMuted ? "mic.slash.fill" : "mic.fill", on: audio.isMuted,
                       label: audio.isMuted ? "Réactiver le micro" : "Couper le micro") { audio.isMuted.toggle() }
                toggle("speaker.wave.2.fill", on: audio.speakerOn,
                       label: audio.speakerOn ? "Écouteur" : "Haut-parleur") { audio.speakerOn.toggle() }
            }
            if !audio.isRunning {
                Text("Audio indisponible").font(.footnote).foregroundStyle(.orange)
            }
            #if DEBUG
            // Démo « paquets chiffrés vérifiés » : uniquement des nombres, aucun contenu.
            Text("Envoyés \(audio.stats.sent) · reçus \(audio.stats.received) · rejetés \(audio.stats.rejected) · \(audio.codec.rawValue)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            #endif
        }
    }

    private func toggle(_ symbol: String, on: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title2).frame(width: 56, height: 56)
                .background(Circle().fill(on ? Color.primary : Color.secondary.opacity(0.2)))
                .foregroundStyle(on ? Color(uiColor: .systemBackground) : .primary)
        }
        .accessibilityLabel(label)
    }
}
