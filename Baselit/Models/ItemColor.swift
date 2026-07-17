import Foundation

enum ItemColor: String, Codable, CaseIterable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case teal
    case turquoise
    case purple
    case pink
    case black
    case white
    case gray
    case brown
    case silver
    case gold
    case multicolor
    case clear
    case other

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}
