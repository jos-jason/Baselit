import SwiftUI

enum AppTab: String, Hashable {
    case search, places, containers, items
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .search

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Search", systemImage: "magnifyingglass", value: AppTab.search) {
                SearchTab()
            }
            Tab("Places", systemImage: "house", value: AppTab.places) {
                PlacesTab()
            }
            Tab("Containers", systemImage: "archivebox", value: AppTab.containers) {
                ContainersTab()
            }
            Tab("Items", systemImage: "shippingbox", value: AppTab.items) {
                ItemsTab()
            }
        }
    }
}

#Preview {
    ContentView()
}
