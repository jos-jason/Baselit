import Foundation

/// Generates memorable two-word identifiers for containers (e.g. "Bright Falcon", "Calm River").
/// Uses an adjective + noun pattern similar to Wi-Fi network naming conventions.
enum IdentifierGenerator {

    // MARK: - Word Lists

    private static let adjectives = [
        "Amber", "Bold", "Bright", "Calm", "Clear",
        "Coral", "Crisp", "Dusk", "Fern", "Frost",
        "Gold", "Grand", "Green", "Iron", "Jade",
        "Keen", "Lush", "Maple", "Misty", "Noble",
        "Oak", "Pearl", "Pine", "Quiet", "Rapid",
        "Reed", "Ruby", "Sage", "Salt", "Silver",
        "Slate", "Snow", "Solar", "Stone", "Storm",
        "Swift", "Teal", "Timber", "Warm", "Wild",
        "Birch", "Cloud", "Copper", "Dawn", "Ember",
        "Flint", "Glen", "Hazel", "Ivy", "Lake",
        "Lunar", "Moss", "North", "Olive", "Onyx",
        "Plum", "Rain", "Rust", "Sandy", "Silk",
        "Smoky", "Steep", "Sunlit", "Thistle", "Velvet",
        "Violet", "Willow", "Aspen", "Basalt", "Blaze",
        "Brisk", "Cedar", "Clay", "Cobalt", "Crest",
        "Drift", "Dusky", "Forge", "Gale", "Harbor",
        "Linen", "Mallow", "Mint", "Opal", "Polar",
        "Pyre", "Quartz", "Raven", "Ridge", "Rowan",
        "Scarlet", "Spruce", "Tide", "Umber", "Vista"
    ]

    private static let nouns = [
        "Arrow", "Basin", "Bear", "Brook", "Canyon",
        "Cliff", "Cove", "Crane", "Creek", "Crow",
        "Deer", "Dove", "Dune", "Eagle", "Elk",
        "Falcon", "Field", "Finch", "Flare", "Fox",
        "Grove", "Gull", "Hawk", "Haven", "Heron",
        "Hill", "Hollow", "Inlet", "Lark", "Ledge",
        "Lodge", "Marsh", "Mesa", "Moth", "Nest",
        "Otter", "Owl", "Pass", "Path", "Peak",
        "Pike", "Pond", "Quail", "Reef", "Ridge",
        "River", "Robin", "Shore", "Spark", "Sprout",
        "Stone", "Summit", "Swallow", "Thicket", "Trail",
        "Vale", "Wren", "Arch", "Badger", "Bluff",
        "Briar", "Bridge", "Burrow", "Cape", "Cavern",
        "Cinder", "Dale", "Den", "Drift", "Fern",
        "Fjord", "Forge", "Glade", "Gorge", "Heath",
        "Hound", "Isle", "Knoll", "Lynx", "Meadow",
        "Mink", "Moose", "Notch", "Osprey", "Pebble",
        "Perch", "Prairie", "Quarry", "Raven", "Shoal",
        "Slope", "Spire", "Stag", "Terrace", "Timber",
        "Tower", "Tundra", "Viper", "Wharf", "Wolf"
    ]

    // MARK: - Generation

    /// Generates a new two-word identifier (e.g. "Bright Falcon").
    /// Uses random selection from the word lists.
    static func generate() -> String {
        let adjective = adjectives.randomElement()!
        let noun = nouns.randomElement()!
        return "\(adjective) \(noun)"
    }

    /// Total number of possible combinations (100 × 100 = 10,000).
    static var combinationCount: Int {
        adjectives.count * nouns.count
    }
}
