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

            // Corner bracket marks
            let gc = ctx.cgContext
            UIColor.lightGray.setStroke()
            gc.setLineWidth(1)
            let bracketLen: CGFloat = 20
            let r: CGFloat = 6 // corner radius
            let inset: CGFloat = 2

            // Top-left
            gc.move(to: CGPoint(x: inset, y: inset + bracketLen))
            gc.addLine(to: CGPoint(x: inset, y: inset + r))
            gc.addQuadCurve(to: CGPoint(x: inset + r, y: inset),
                            control: CGPoint(x: inset, y: inset))
            gc.addLine(to: CGPoint(x: inset + bracketLen, y: inset))
            gc.strokePath()

            // Top-right
            gc.move(to: CGPoint(x: labelWidth - inset - bracketLen, y: inset))
            gc.addLine(to: CGPoint(x: labelWidth - inset - r, y: inset))
            gc.addQuadCurve(to: CGPoint(x: labelWidth - inset, y: inset + r),
                            control: CGPoint(x: labelWidth - inset, y: inset))
            gc.addLine(to: CGPoint(x: labelWidth - inset, y: inset + bracketLen))
            gc.strokePath()

            // Bottom-left
            gc.move(to: CGPoint(x: inset, y: labelHeight - inset - bracketLen))
            gc.addLine(to: CGPoint(x: inset, y: labelHeight - inset - r))
            gc.addQuadCurve(to: CGPoint(x: inset + r, y: labelHeight - inset),
                            control: CGPoint(x: inset, y: labelHeight - inset))
            gc.addLine(to: CGPoint(x: inset + bracketLen, y: labelHeight - inset))
            gc.strokePath()

            // Bottom-right
            gc.move(to: CGPoint(x: labelWidth - inset - bracketLen, y: labelHeight - inset))
            gc.addLine(to: CGPoint(x: labelWidth - inset - r, y: labelHeight - inset))
            gc.addQuadCurve(to: CGPoint(x: labelWidth - inset, y: labelHeight - inset - r),
                            control: CGPoint(x: labelWidth - inset, y: labelHeight - inset))
            gc.addLine(to: CGPoint(x: labelWidth - inset, y: labelHeight - inset - bracketLen))
            gc.strokePath()
        }
    }

    /// Generates a rounded-style QR code UIImage that remains scannable.
    private static func generateQRCode(from string: String) -> UIImage {
        let ciContext = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"

        guard let ciImage = filter.outputImage,
              let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)
        else { return UIImage(systemName: "qrcode") ?? UIImage() }

        let rawGrid = extractModuleGrid(from: cgImage, size: cgImage.width)

        // CIFilter adds a 1-module quiet zone border — strip it so standard QR positions work
        let quiet = detectQuietZone(rawGrid)
        let grid = stripQuietZone(rawGrid, border: quiet)
        let moduleCount = grid.count
        let alignCenters = alignmentPatternCenters(moduleCount: moduleCount)

        let m: CGFloat = 10 // module size in points
        let imageSize = CGFloat(moduleCount) * m
        let r = m * 0.35 // corner radius for data modules

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: imageSize, height: imageSize))
        return renderer.image { ctx in
            let gc = ctx.cgContext
            UIColor.white.setFill()
            gc.fill(CGRect(x: 0, y: 0, width: imageSize, height: imageSize))
            UIColor.black.setFill()

            // Rounded finder patterns (three corners)
            drawFinderPattern(in: gc, row: 0, col: 0, m: m)
            drawFinderPattern(in: gc, row: 0, col: moduleCount - 7, m: m)
            drawFinderPattern(in: gc, row: moduleCount - 7, col: 0, m: m)

            // Rounded alignment patterns
            for c in alignCenters {
                drawAlignmentPattern(in: gc, centerRow: c.row, centerCol: c.col, m: m)
            }

            // All remaining dark modules — rounded corners on exposed edges
            for row in 0..<moduleCount {
                for col in 0..<moduleCount {
                    guard grid[row][col] else { continue }
                    if isInFinderPattern(row: row, col: col, moduleCount: moduleCount) { continue }
                    if isInAlignmentPattern(row: row, col: col, centers: alignCenters) { continue }

                    let x = CGFloat(col) * m
                    let y = CGFloat(row) * m
                    let rect = CGRect(x: x, y: y, width: m, height: m)

                    let hasTop = row > 0 && grid[row - 1][col]
                    let hasBottom = row + 1 < moduleCount && grid[row + 1][col]
                    let hasLeft = col > 0 && grid[row][col - 1]
                    let hasRight = col + 1 < moduleCount && grid[row][col + 1]

                    var corners: UIRectCorner = []
                    if !hasTop && !hasLeft { corners.insert(.topLeft) }
                    if !hasTop && !hasRight { corners.insert(.topRight) }
                    if !hasBottom && !hasLeft { corners.insert(.bottomLeft) }
                    if !hasBottom && !hasRight { corners.insert(.bottomRight) }

                    if corners.isEmpty {
                        gc.fill(rect)
                    } else {
                        UIBezierPath(roundedRect: rect, byRoundingCorners: corners,
                                     cornerRadii: CGSize(width: r, height: r)).fill()
                    }
                }
            }
        }
    }

    // MARK: - QR Helpers

    private static func extractModuleGrid(from cgImage: CGImage, size: Int) -> [[Bool]] {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var pixels = [UInt8](repeating: 0, count: size * size)
        guard let ctx = CGContext(data: &pixels, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size,
                                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return Array(repeating: Array(repeating: false, count: size), count: size) }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        return (0..<size).map { row in
            (0..<size).map { col in pixels[row * size + col] < 128 }
        }
    }

    /// Detects how many rows/cols of quiet zone border CIFilter added.
    private static func detectQuietZone(_ grid: [[Bool]]) -> Int {
        let size = grid.count
        guard size > 0 else { return 0 }
        var border = 0
        for i in 0..<size {
            if grid[i].allSatisfy({ !$0 }) {
                border += 1
            } else {
                break
            }
        }
        return border
    }

    /// Strips `border` rows/cols from all sides of the grid.
    private static func stripQuietZone(_ grid: [[Bool]], border: Int) -> [[Bool]] {
        guard border > 0 else { return grid }
        let size = grid.count
        let end = size - border
        guard end > border else { return grid }
        return (border..<end).map { row in
            Array(grid[row][border..<end])
        }
    }

    private static func isInFinderPattern(row: Int, col: Int, moduleCount: Int) -> Bool {
        (row < 7 && col < 7) ||
        (row < 7 && col >= moduleCount - 7) ||
        (row >= moduleCount - 7 && col < 7)
    }

    private static func isInAlignmentPattern(row: Int, col: Int, centers: [(row: Int, col: Int)]) -> Bool {
        centers.contains { abs(row - $0.row) <= 2 && abs(col - $0.col) <= 2 }
    }

    private static func alignmentPatternCenters(moduleCount: Int) -> [(row: Int, col: Int)] {
        let version = (moduleCount - 17) / 4
        guard version >= 2 else { return [] }

        let table: [[Int]] = [
            [], [],
            [6, 18], [6, 22], [6, 26], [6, 30], [6, 34],
            [6, 22, 38], [6, 24, 42], [6, 26, 46], [6, 28, 50],
        ]
        let positions = version < table.count ? table[version] : table.last!

        var centers: [(row: Int, col: Int)] = []
        for r in positions {
            for c in positions {
                if r < 8 && c < 8 { continue }
                if r < 8 && c >= moduleCount - 8 { continue }
                if r >= moduleCount - 8 && c < 8 { continue }
                centers.append((row: r, col: c))
            }
        }
        return centers
    }

    /// Draws a 7x7 finder pattern with rounded corners.
    private static func drawFinderPattern(in gc: CGContext, row: Int, col: Int, m: CGFloat) {
        let x = CGFloat(col) * m
        let y = CGFloat(row) * m

        // Outer ring: rounded 7x7 with 5x5 cutout
        let outer = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 7 * m, height: 7 * m),
                                 cornerRadius: m * 0.8)
        let cutout = UIBezierPath(roundedRect: CGRect(x: x + m, y: y + m, width: 5 * m, height: 5 * m),
                                  cornerRadius: m * 0.5)
        outer.append(cutout.reversing())
        outer.fill()

        // Center: rounded 3x3
        UIBezierPath(roundedRect: CGRect(x: x + 2 * m, y: y + 2 * m, width: 3 * m, height: 3 * m),
                     cornerRadius: m * 0.4).fill()
    }

    /// Draws a 5x5 alignment pattern with rounded corners.
    private static func drawAlignmentPattern(in gc: CGContext, centerRow: Int, centerCol: Int, m: CGFloat) {
        let x = CGFloat(centerCol - 2) * m
        let y = CGFloat(centerRow - 2) * m

        // Outer ring: rounded 5x5 with 3x3 cutout
        let outer = UIBezierPath(roundedRect: CGRect(x: x, y: y, width: 5 * m, height: 5 * m),
                                 cornerRadius: m * 0.5)
        let cutout = UIBezierPath(roundedRect: CGRect(x: x + m, y: y + m, width: 3 * m, height: 3 * m),
                                  cornerRadius: m * 0.3)
        outer.append(cutout.reversing())
        outer.fill()

        // Center dot: rounded 1x1
        UIBezierPath(roundedRect: CGRect(x: x + 2 * m, y: y + 2 * m, width: m, height: m),
                     cornerRadius: m * 0.2).fill()
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
