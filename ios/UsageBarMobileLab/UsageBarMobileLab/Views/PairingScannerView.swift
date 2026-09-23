import AVFoundation
import SwiftUI
import UsageBarPairing

/// Scans the Mac's pairing QR.
///
/// AVFoundation's own metadata detector — no third-party scanner in a path that
/// handles a credential. The camera runs only while this view is on screen, no
/// frame is ever retained, written or uploaded, and the only thing taken from
/// the video stream is the decoded string.
struct PairingScannerView: UIViewControllerRepresentable {
    let onScan: (UsageBarPairingPayload) -> Void
    let onFailure: (Error) -> Void

    func makeUIViewController(context: Context) -> PairingScannerController {
        let controller = PairingScannerController()
        controller.onScan = onScan
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ controller: PairingScannerController, context: Context) {}
}

final class PairingScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((UsageBarPairingPayload) -> Void)?
    var onFailure: ((Error) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    /// One scan per presentation. A QR in view produces a steady stream of
    /// detections, and every one after the first would be a replay of a code
    /// the desktop has already consumed.
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onFailure?(PairingError.transportFailure)
            return
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            onFailure?(PairingError.transportFailure)
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // QR only. Nothing here should be reading barcodes off a shelf.
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        guard !session.isRunning else { return }
        // Off the main queue: `startRunning` blocks until the camera is ready.
        DispatchQueue.global(qos: .userInitiated).async { [session] in
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // The camera stops the moment the scanner leaves the screen.
        if session.isRunning { session.stopRunning() }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasScanned else { return }
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let text = object.stringValue else { return }

        // Parsed strictly. A QR that is not a UsageBar pairing payload is
        // ignored rather than guessed at — the user may simply be pointing the
        // camera at something else while they find the Mac's window.
        guard let payload = try? UsageBarPairingPayload.decode(text) else { return }

        hasScanned = true
        session.stopRunning()
        onScan?(payload)
    }
}
