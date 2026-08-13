import Foundation
import CoreImage.CIFilterBuiltins
import UIKit

/// UIKit port of the Mac QR generator. Renders at a larger size than the Mac's
/// 200pt because the iPad shows the code full-screen for the phone to scan.
enum QRCodeGenerator {

    static func generate(from string: String, size: CGFloat = 420) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        let scaleX = size / outputImage.extent.size.width
        let scaleY = size / outputImage.extent.size.height
        let transformed = outputImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
