import UIKit
import CoreImage.CIFilterBuiltins

enum LabelGenerator {

    /// Renders a printable label image containing a QR code, name, and identifier.
    /// - Parameters:
    ///   - name: The display name (e.g. "Kitchen Drawer")
    ///   - identifier: The two-word identifier (e.g. "Bright Falcon")
    ///   - type: Either "container" or "item"
    /// - Returns: A rendered UIImage suitable for sharing/printing
    static func generateLabel(
        name: String,
        identifier: String,
        type: String
    ) -> UIImage {
        let slug = identifier.lowercased().replacingOccurrences(of: " ", with: "-")
        let payload = "baselit:\(type):\(slug)"
        let qrImage = generateQRCode(from: payload)

        let labelWidth: CGFloat = 400
        let padding: CGFloat = 20
        let qrSize: CGFloat = 160
        let textAreaWidth = labelWidth - qrSize - padding * 3

        let nameFont = UIFont.systemFont(ofSize: 22, weight: .bold)
        let idFont = UIFont.systemFont(ofSize: 16, weight: .regular)

        let nameRect = (name as NSString).boundingRect(
            with: CGSize(width: textAreaWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: nameFont],
            context: nil
        )
        let idRect = (identifier as NSString).boundingRect(
            with: CGSize(width: textAreaWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: idFont],
            context: nil
        )

        let textHeight = nameRect.height + 8 + idRect.height
        let contentHeight = max(qrSize, textHeight)
        let labelHeight = contentHeight + padding * 2

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: labelWidth, height: labelHeight)
        )

        return renderer.image { ctx in
            // White background
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight))

            // QR code on the left
            let qrRect = CGRect(
                x: padding,
                y: (labelHeight - qrSize) / 2,
                width: qrSize,
                height: qrSize
            )
            qrImage.draw(in: qrRect)

            // Name text
            let textX = padding + qrSize + padding
            let textY = (labelHeight - textHeight) / 2

            let nameAttrs: [NSAttributedString.Key: Any] = [
                .font: nameFont,
                .foregroundColor: UIColor.black
            ]
            (name as NSString).draw(
                in: CGRect(x: textX, y: textY, width: textAreaWidth, height: nameRect.height),
                withAttributes: nameAttrs
            )

            // Identifier text below name
            let idAttrs: [NSAttributedString.Key: Any] = [
                .font: idFont,
                .foregroundColor: UIColor.darkGray
            ]
            (identifier as NSString).draw(
                in: CGRect(
                    x: textX,
                    y: textY + nameRect.height + 8,
                    width: textAreaWidth,
                    height: idRect.height
                ),
                withAttributes: idAttrs
            )

            // Thin border
            UIColor.lightGray.setStroke()
            let borderRect = CGRect(
                x: 1, y: 1,
                width: labelWidth - 2, height: labelHeight - 2
            )
            ctx.stroke(borderRect, width: 1)
        }
    }

    /// Generates a QR code UIImage from a string payload.
    private static func generateQRCode(from string: String) -> UIImage {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        // Scale up the QR code (CIFilter output is tiny)
        let scale: CGFloat = 10
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(transformed, from: transformed.extent) else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        return UIImage(cgImage: cgImage)
    }
}
