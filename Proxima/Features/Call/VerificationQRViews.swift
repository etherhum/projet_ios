import AVFoundation
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// QR de vérification affiché par l'appelant (M2-06, variante QR). Généré localement (CoreImage).
struct VerificationQRCodeView: View {
    let payload: String

    var body: some View {
        if let image = Self.render(payload) {
            Image(uiImage: image)
                .interpolation(.none).resizable().scaledToFit()
                .frame(width: 220, height: 220)
                .padding(12).background(Color.white)
                .accessibilityLabel("QR de vérification à scanner par votre correspondant")
        } else {
            Text("QR indisponible").foregroundStyle(.secondary)
        }
    }

    private static func render(_ payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

/// Permission caméra demandée seulement quand l'utilisateur choisit le QR (moindre privilège, M2-06).
enum CameraPermission {
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }
}

/// Feuille de scan côté appelé : caméra (aucune image conservée), premier QR lu transmis une seule fois.
struct VerificationQRScannerSheet: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorized: Bool?

    var body: some View {
        NavigationStack {
            Group {
                switch authorized {
                case .none:
                    ProgressView()
                case .some(true):
                    QRScannerView { value in
                        dismiss()
                        onScanned(value)
                    }
                    .ignoresSafeArea(edges: .bottom)
                case .some(false):
                    Text("Accès à la caméra refusé. Comparez le code à 6 chiffres à voix haute, ou autorisez la caméra dans Réglages.")
                        .multilineTextAlignment(.center).padding()
                }
            }
            .navigationTitle("Scanner le QR de l'appelant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
            }
        }
        .task { authorized = await CameraPermission.request() }
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onScanned = onScanned
        return c
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onScanned: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var delivered = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
        }

        nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                        didOutput metadataObjects: [AVMetadataObject],
                                        from connection: AVCaptureConnection) {
            guard let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
            MainActor.assumeIsolated {
                guard !delivered else { return }
                delivered = true
                let s = session
                DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
                onScanned?(value)
            }
        }
    }
}
