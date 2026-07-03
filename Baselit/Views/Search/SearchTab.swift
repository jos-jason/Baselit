import SwiftUI
import SwiftData

struct SearchTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var selectedHouse: House?
    @State private var selectedCategory: ItemCategory?
    @State private var selectedColor: ItemColor?
    @State private var matchingHouses: [House] = []
    @State private var matchingLocations: [Location] = []
    @State private var matchingContainers: [Container] = []
    @State private var matchingItems: [Item] = []
    @State private var hasSearched = false

    private var hasAnyResults: Bool {
        !matchingHouses.isEmpty || !matchingLocations.isEmpty ||
        !matchingContainers.isEmpty || !matchingItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                if !hasSearched && searchText.isEmpty {
                    ContentUnavailableView {
                        Label("Search", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search across houses, locations, containers, and items.")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else if !hasAnyResults {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("Nothing matched your search.")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    if !matchingHouses.isEmpty {
                        Section("Houses") {
                            ForEach(matchingHouses) { house in
                                NavigationLink(value: house) {
                                    HouseSearchRow(house: house)
                                }
                            }
                        }
                    }

                    if !matchingLocations.isEmpty {
                        Section("Locations") {
                            ForEach(matchingLocations) { location in
                                NavigationLink(value: location) {
                                    LocationSearchRow(location: location)
                                }
                            }
                        }
                    }

                    if !matchingContainers.isEmpty {
                        Section("Containers") {
                            ForEach(matchingContainers) { container in
                                NavigationLink(value: container) {
                                    ContainerSearchRow(container: container)
                                }
                            }
                        }
                    }

                    if !matchingItems.isEmpty {
                        Section("Items") {
                            ForEach(matchingItems) { item in
                                NavigationLink(value: item) {
                                    SearchResultRow(item: item)
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search everything...")
            .onChange(of: searchText) { performSearch() }
            .onChange(of: selectedHouse) { performSearch() }
            .onChange(of: selectedCategory) { performSearch() }
            .onChange(of: selectedColor) { performSearch() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                SearchFilterView(
                    selectedHouse: $selectedHouse,
                    selectedCategory: $selectedCategory,
                    selectedColor: $selectedColor
                )
            }
            .navigationDestination(for: House.self) { house in
                HouseDetailView(house: house)
            }
            .navigationDestination(for: Location.self) { location in
                LocationDetailView(location: location)
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container)
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .navigationTitle("Search")
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedHouse != nil { count += 1 }
        if selectedCategory != nil { count += 1 }
        if selectedColor != nil { count += 1 }
        return count
    }

    private func performSearch() {
        hasSearched = true
        do {
            matchingHouses = try InventoryService.searchHouses(
                query: searchText, in: modelContext
            )
            matchingLocations = try InventoryService.searchLocations(
                query: searchText, in: modelContext
            )
            matchingContainers = try InventoryService.searchContainers(
                query: searchText, in: modelContext
            )
            matchingItems = try InventoryService.searchItems(
                query: searchText,
                house: selectedHouse,
                category: selectedCategory,
                color: selectedColor,
                in: modelContext
            )
        } catch {
            matchingHouses = []
            matchingLocations = []
            matchingContainers = []
            matchingItems = []
        }
    }
}

// MARK: - Search Row Views

private struct HouseSearchRow: View {
    let house: House

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: house.photos, placeholderIcon: "house")
            VStack(alignment: .leading, spacing: 4) {
                Text(house.name)
                    .font(.headline)
                if let address = house.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("\(house.locations.count) locations", systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LocationSearchRow: View {
    let location: Location

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: location.photos, placeholderIcon: "mappin")
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                if let house = location.house {
                    BreadcrumbView(components: [house.name])
                }
                HStack(spacing: 12) {
                    Label("\(location.containers.count) containers", systemImage: "archivebox")
                    Label("\(location.items.count) items", systemImage: "shippingbox")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ContainerSearchRow: View {
    let container: Container

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: container.photos, placeholderIcon: "archivebox")
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)
                BreadcrumbView(components: container.breadcrumbComponents.dropLast().map { $0 })
                HStack(spacing: 12) {
                    if !container.subContainers.isEmpty {
                        Label("\(container.subContainers.count) sub-containers", systemImage: "archivebox")
                    }
                    Label("\(container.items.count) items", systemImage: "shippingbox")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
