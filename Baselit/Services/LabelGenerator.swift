import UIKit
import CoreImage.CIFilterBuiltins

enum LabelGenerator {

    /// Describes one label to include in a batch print sheet.
    struct LabelEntry {
        let name: String
        let identifier: String
        let type: String  // "container" or "item"
    }

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
            ctx.cgContext.setLineWidth(1)
            ctx.cgContext.stroke(borderRect)
        }
    }

    /// Generates a rounded-style QR code UIImage from a string payload.
    private static func generateQRCode(from string: String) -> UIImage {
        let ciContext = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let ciImage = filter.outputImage else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        // Render at 1x so each pixel = one QR module
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else {
            return UIImage(systemName: "qrcode") ?? UIImage()
        }

        let moduleCount = cgImage.width
        let grid = extractModuleGrid(from: cgImage, size: moduleCount)

        // Draw the rounded QR code
        let moduleSize: CGFloat = 10
        let imageSize = CGFloat(moduleCount) * moduleSize
        let cornerRadius = moduleSize * 0.38

        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: imageSize, height: imageSize)
        )

        return renderer.image { ctx in
            let gc = ctx.cgContext

            UIColor.white.setFill()
            gc.fill(CGRect(x: 0, y: 0, width: imageSize, height: imageSize))

            UIColor.black.setFill()

            // Draw the three finder patterns with rounded styling
            drawFinderPattern(in: gc, row: 0, col: 0, moduleSize: moduleSize)
            drawFinderPattern(in: gc, row: 0, col: moduleCount - 7, moduleSize: moduleSize)
            drawFinderPattern(in: gc, row: moduleCount - 7, col: 0, moduleSize: moduleSize)

            // Draw data modules (skip finder pattern areas)
            for row in 0..<moduleCount {
                for col in 0..<moduleCount {
                    guard grid[row][col] else { continue }
                    if isInFinderPatternArea(row: row, col: col, moduleCount: moduleCount) { continue }

                    let hasRight = col + 1 < moduleCount && grid[row][col + 1]
                        && !isInFinderPatternArea(row: row, col: col + 1, moduleCount: moduleCount)
                    let hasBottom = row + 1 < moduleCount && grid[row + 1][col]
                        && !isInFinderPatternArea(row: row + 1, col: col, moduleCount: moduleCount)
                    let hasLeft = col - 1 >= 0 && grid[row][col - 1]
                        && !isInFinderPatternArea(row: row, col: col - 1, moduleCount: moduleCount)
                    let hasTop = row - 1 >= 0 && grid[row - 1][col]
                        && !isInFinderPatternArea(row: row - 1, col: col, moduleCount: moduleCount)

                    let x = CGFloat(col) * moduleSize
                    let y = CGFloat(row) * moduleSize
                    let rect = CGRect(x: x, y: y, width: moduleSize, height: moduleSize)

                    // Isolated dot: draw as circle
                    if !hasRight && !hasBottom && !hasLeft && !hasTop {
                        let inset = moduleSize * 0.1
                        let ovalRect = rect.insetBy(dx: inset, dy: inset)
                        gc.fillEllipse(in: ovalRect)
                        continue
                    }

                    // Connected module: use selectively rounded corners
                    var corners: UIRectCorner = []
                    if !hasTop && !hasLeft { corners.insert(.topLeft) }
                    if !hasTop && !hasRight { corners.insert(.topRight) }
                    if !hasBottom && !hasLeft { corners.insert(.bottomLeft) }
                    if !hasBottom && !hasRight { corners.insert(.bottomRight) }

                    let path = UIBezierPath(
                        roundedRect: rect,
                        byRoundingCorners: corners,
                        cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
                    )
                    path.fill()
                }
            }
        }
    }

    /// Extracts a boolean grid from a 1x-scale QR code CGImage.
    private static func extractModuleGrid(from cgImage: CGImage, size: Int) -> [[Bool]] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixelData = [UInt8](repeating: 0, count: size * size)
        guard let context = CGContext(
            data: &pixelData,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Array(repeating: Array(repeating: false, count: size), count: size)
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        var grid = Array(repeating: Array(repeating: false, count: size), count: size)
        for row in 0..<size {
            for col in 0..<size {
                // Dark module = pixel value < 128
                grid[row][col] = pixelData[row * size + col] < 128
            }
        }
        return grid
    }

    /// Checks if a module position falls within a finder pattern area (including separator).
    private static func isInFinderPatternArea(row: Int, col: Int, moduleCount: Int) -> Bool {
        let finderSize = 8 // 7 modules + 1 separator
        // Top-left
        if row < finderSize && col < finderSize { return true }
        // Top-right
        if row < finderSize && col >= moduleCount - finderSize { return true }
        // Bottom-left
        if row >= moduleCount - finderSize && col < finderSize { return true }
        return false
    }

    /// Draws a single rounded finder pattern (the big squares in QR corners).
    private static func drawFinderPattern(in gc: CGContext, row: Int, col: Int, moduleSize: CGFloat) {
        let x = CGFloat(col) * moduleSize
        let y = CGFloat(row) * moduleSize

        let outerRadius = moduleSize * 1.2
        let innerRadius = moduleSize * 0.8
        let dotRadius = moduleSize * 0.5

        // Outer ring (7x7)
        let outerRect = CGRect(x: x, y: y, width: 7 * moduleSize, height: 7 * moduleSize)
        let outerPath = UIBezierPath(roundedRect: outerRect, cornerRadius: outerRadius)
        let innerCutout = CGRect(
            x: x + moduleSize,
            y: y + moduleSize,
            width: 5 * moduleSize,
            height: 5 * moduleSize
        )
        let innerCutoutPath = UIBezierPath(roundedRect: innerCutout, cornerRadius: innerRadius)
        outerPath.append(innerCutoutPath.reversing())

        UIColor.black.setFill()
        outerPath.fill()

        // Inner square (3x3)
        let centerRect = CGRect(
            x: x + 2 * moduleSize,
            y: y + 2 * moduleSize,
            width: 3 * moduleSize,
            height: 3 * moduleSize
        )
        let centerPath = UIBezierPath(roundedRect: centerRect, cornerRadius: dotRadius)
        centerPath.fill()
    }

    /// Generates a multi-page PDF with labels arranged in a 2-column grid on US Letter pages.
    /// - Parameter entries: The labels to generate.
    /// - Returns: PDF data suitable for sharing or printing.
    static func generateLabelSheet(entries: [LabelEntry]) -> Data {
        // US Letter at 72 dpi
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let columns = 2
        let margin: CGFloat = 36
        let cellSpacing: CGFloat = 12
        let cellWidth = (pageWidth - margin * 2 - cellSpacing * CGFloat(columns - 1)) / CGFloat(columns)

        // Render each label using the existing single-label method
        let labelImages = entries.map { entry in
            generateLabel(name: entry.name, identifier: entry.identifier, type: entry.type)
        }

        // Fixed cell height based on standard label aspect ratio (400:200)
        let scaleFactor = cellWidth / 400.0
        let cellHeight: CGFloat = 200 * scaleFactor

        let usableHeight = pageHeight - margin * 2
        let rowsPerPage = Int((usableHeight + cellSpacing) / (cellHeight + cellSpacing))

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            var index = 0
            while index < labelImages.count {
                context.beginPage()

                for row in 0..<rowsPerPage {
                    for col in 0..<columns {
                        guard index < labelImages.count else { break }

                        let x = margin + CGFloat(col) * (cellWidth + cellSpacing)
                        let y = margin + CGFloat(row) * (cellHeight + cellSpacing)
                        let destRect = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)

                        labelImages[index].draw(in: destRect)
                        index += 1
                    }
                    if index >= labelImages.count { break }
                }
            }
        }

        return data
    }
}
