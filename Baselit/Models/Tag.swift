import Foundation
import SwiftData

@Model
final class Tag {
    @Attribute(.unique) var name: String

    var items: [Item] = []

    init(name: String) {
        self.name = name
    }
}
