import AppKit
import CoreImage
import Foundation
import UsageBarPairing

/// Renders a pairing payload as a QR image.
///
/// Core Image's built-in generator, so there is no third-party QR dependency in
/// a path that handles a secret. The payload is encoded, drawn and dropped: it
/// is never written to disk, never placed on the pasteboard and never rendered
/// as readable text beside the image.
enum MobileSyncPairingQR {
    static func image(for payload: UsageBarPairingPayload, size: CGFloat) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(payload.encoded().utf8), forKey: "inputMessage")
        // Medium correction: enough to survive a phone camera at arm's length
        // without inflating the symbol so much that it becomes hard to scan.
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }

        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: size, height: size))
    }
}
