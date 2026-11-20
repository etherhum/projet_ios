import AVFoundation

/// Configuration de l'`AVAudioSession` pour un appel (M2-09) : `.playAndRecord` + `.voiceChat`
/// (annulation d'écho, contrôle de gain). Activée seulement pendant un appel actif, désactivée à la fin.
/// Interruptions (appel GSM, Siri…) et changements de route (casque débranché…) relayés au moteur.
final class AudioSessionController {
    enum Event {
        case interruptionBegan
        case interruptionEnded(shouldResume: Bool)
        case routeChanged
    }

    var onEvent: ((Event) -> Void)?
    private(set) var isActive = false
    private(set) var speakerOn = false
    private var observers: [NSObjectProtocol] = []
    private let session = AVAudioSession.sharedInstance()

    func activate() throws {
        guard !isActive else { return }
        // 0x4 = `.allowBluetooth` (renommé `.allowBluetoothHFP` dans le SDK iOS 26) : casque Bluetooth autorisé.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [AVAudioSession.CategoryOptions(rawValue: 0x4)])
        try session.setPreferredSampleRate(VoiceFormat.sampleRate)
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        isActive = true
        try? applySpeaker()
        observe()
    }

    func deactivate() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        guard isActive else { return }
        isActive = false
        speakerOn = false
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Haut-parleur (`true`) ou écouteur / casque (`false`, défaut de `.voiceChat`).
    func setSpeaker(_ on: Bool) {
        speakerOn = on
        if isActive { try? applySpeaker() }
    }

    private func applySpeaker() throws {
        try session.overrideOutputAudioPort(speakerOn ? .speaker : .none)
    }

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            switch type {
            case .began: self?.onEvent?(.interruptionBegan)
            case .ended:
                let opts = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map(AVAudioSession.InterruptionOptions.init) ?? []
                self?.onEvent?(.interruptionEnded(shouldResume: opts.contains(.shouldResume)))
            @unknown default: break
            }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: session, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                if let self { try? self.applySpeaker() }
                self?.onEvent?(.routeChanged)
            default: break
            }
        })
    }
}
