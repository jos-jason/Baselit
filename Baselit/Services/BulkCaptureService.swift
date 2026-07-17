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
    /// The created Item (only set when mode is .items)
    var item: Item?
    /// The created Container (only set when mode is .containers)
    var container: Container?
}

struct BulkCaptureService {

    /// Creates and inserts a new Item with a photo from the captured image.
    /// If `targetContainer` is provided, the item is placed inside that container.
    @MainActor
    static func createItem(
        index: Int,
        compressedImageData: Data,
        targetContainer: Container? = nil,
        in context: ModelContext
    ) -> CapturedEntry {
        let name = "Untitled Item \(index)"
        let item = Item(name: name, quantity: 1)
        context.insert(item)

        if let targetContainer {
            item.container = targetContainer
        }

        let photo = Photo(imageData: compressedImageData)
        context.insert(photo)
        item.photos.append(photo)

        return CapturedEntry(
            name: name,
            identifier: item.identifier,
            thumbnailData: compressedImageData,
            item: item
        )
    }

    /// Creates and inserts a new Container with a photo from the captured image.
    /// If `parentContainer` is provided, the container is created as a sub-container.
    @MainActor
    static func createContainer(
        index: Int,
        compressedImageData: Data,
        parentContainer: Container? = nil,
        in context: ModelContext
    ) -> CapturedEntry {
        let name = "Untitled Container \(index)"
        let container = Container(name: name, parentContainer: parentContainer)
        context.insert(container)

        let photo = Photo(imageData: compressedImageData)
        context.insert(photo)
        container.photos.append(photo)

        return CapturedEntry(
            name: name,
            identifier: container.identifier,
            thumbnailData: compressedImageData,
            container: container
        )
    }
}
