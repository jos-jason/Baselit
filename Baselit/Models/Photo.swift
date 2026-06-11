import Foundation
import SwiftData

@Model
final class Photo {
    @Attribute(.externalStorage) var imageData: Data?
    var caption: String?
    var createdAt: Date

    var item: Item?
    var container: Container?
    var house: House?

    init(imageData: Data?, caption: String? = nil) {
        self.imageData = imageData
        self.caption = caption
        self.createdAt = .now
    }
}
