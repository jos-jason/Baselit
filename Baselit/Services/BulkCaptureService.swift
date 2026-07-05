import Foundation
import SwiftData
import UIKit

enum BulkCaptureMode {
    case items
    case containers
}

/// A record of one captured entity, used for the summary screen.
struct CapturedEntry: Identifiable {
    let id = UUID()
    let name: String
    let identifier: String
    let thumbnailData: Data?
}

struct BulkCaptureService {

    /// Creates and inserts a new Item with a photo from the captured image.
    @MainActor
    static func createItem(
        index: Int,
        compressedImageData: Data,
        in context: ModelContext
    ) -> CapturedEntry {
        let name = "Untitled Item \(index)"
        let item = Item(name: name, quantity: 1)
        context.insert(item)

        let photo = Photo(imageData: compressedImageData)
        context.insert(photo)
        item.photos.append(photo)

        return CapturedEntry(
            name: name,
            identifier: item.identifier,
            thumbnailData: compressedImageData
        )
    }

    /// Creates and inserts a new Container with a photo from the captured image.
    @MainActor
    static func createContainer(
        index: Int,
        compressedImageData: Data,
        in context: ModelContext
    ) -> CapturedEntry {
        let name = "Untitled Container \(index)"
        let container = Container(name: name)
        context.insert(container)

        let photo = Photo(imageData: compressedImageData)
        context.insert(photo)
        container.photos.append(photo)

        return CapturedEntry(
            name: name,
            identifier: container.identifier,
            thumbnailData: compressedImageData
        )
    }
}
