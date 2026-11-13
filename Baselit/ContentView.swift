import SwiftUI

enum AppTab: String, Hashable {
    case search, places, containers, items
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .search
    @Environment(SyncService.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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
        .task { sync.start(context: modelContext) }
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await sync.sync() } }
        }
    }
}

#Preview {
    ContentView()
        .environment(SyncService())
}
