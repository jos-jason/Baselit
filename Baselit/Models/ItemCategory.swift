import Foundation

enum ItemCategory: String, Codable, CaseIterable, Identifiable {
    case electronics
    case clothing
    case tools
    case kitchenware
    case documents
    case books
    case toys
    case sports
    case seasonal
    case medical
    case crafts
    case furniture
    case decor
    case outdoor
    case other

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .kitchenware: return "Kitchenware"
        default: return rawValue.capitalized
        }
    }
}
