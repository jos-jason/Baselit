import SwiftUI
import SwiftData

struct ContainersTab: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Container.name) private var allContainers: [Container]
    @State private var searchText = ""
    @State private var filterHouse: House?
    @State private var filterLocation: Location?
    @State private var houses: [House] = []

    private var availableLocations: [Location] {
        filterHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    private var filteredContainers: [Container] {
        var result = allContainers

        // Filter by house
        if let filterHouse {
            result = result.filter { $0.resolvedHouse?.persistentModelID == filterHouse.persistentModelID }
        }

        // Filter by location
        if let filterLocation {
            result = result.filter { $0.resolvedLocation?.persistentModelID == filterLocation.persistentModelID }
        }

        // Filter by keyword: match against container name, sub-container names, or item names
        if !searchText.isEmpty {
            result = result.filter { containerMatchesKeyword($0, keyword: searchText) }
        }

        return result
    }

    /// Group filtered containers by their resolved house name
    private var groupedByHouse: [(String, [Container])] {
        let grouped = Dictionary(grouping: filteredContainers) { container in
            container.resolvedHouse?.name ?? "No House"
        }
        return grouped.sorted { $0.key < $1.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allContainers.isEmpty {
                    EmptyStateView(
                        icon: "archivebox",
                        title: "No Containers",
                        message: "Containers are created from within a location. Go to Places to add one."
                    )
                } else {
                    List {
                        // Filter controls
                        Section {
                            Picker("House", selection: $filterHouse) {
                                Text("All Houses").tag(nil as House?)
                                ForEach(houses) { house in
                                    Text(house.name).tag(house as House?)
                                }
                            }
                            .onChange(of: filterHouse) {
                                filterLocation = nil
                            }

                            if filterHouse != nil && !availableLocations.isEmpty {
                                Picker("Location", selection: $filterLocation) {
                                    Text("All Locations").tag(nil as Location?)
                                    ForEach(availableLocations) { loc in
                                        Text(loc.name).tag(loc as Location?)
                                    }
                                }
                            }
                        }

                        if filteredContainers.isEmpty {
                            ContentUnavailableView {
                                Label("No Matches", systemImage: "archivebox")
                            } description: {
                                Text("No containers match your filters.")
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        } else {
                            ForEach(groupedByHouse, id: \.0) { houseName, containers in
                                Section(houseName) {
                                    ForEach(containers.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })) { container in
                                        NavigationLink(value: container) {
                                            ContainerListRow(container: container)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search containers and contents...")
                }
            }
            .navigationTitle("Containers")
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container)
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .onAppear { loadHouses() }
        }
    }

    private func loadHouses() {
        do {
            houses = try InventoryService.allHouses(in: modelContext)
        } catch {
            houses = []
        }
    }

    /// Check if a container or any of its descendants match the keyword
    private func containerMatchesKeyword(_ container: Container, keyword: String) -> Bool {
        // Check the container's own name
        if container.name.localizedCaseInsensitiveContains(keyword) {
            return true
        }

        // Check items directly in this container
        if container.items.contains(where: { itemMatchesKeyword($0, keyword: keyword) }) {
            return true
        }

        // Check sub-containers recursively
        if container.subContainers.contains(where: { containerMatchesKeyword($0, keyword: keyword) }) {
            return true
        }

        return false
    }

    private func itemMatchesKeyword(_ item: Item, keyword: String) -> Bool {
        item.name.localizedCaseInsensitiveContains(keyword) ||
        (item.itemDescription ?? "").localizedCaseInsensitiveContains(keyword) ||
        (item.notes ?? "").localizedCaseInsensitiveContains(keyword) ||
        (item.brand ?? "").localizedCaseInsensitiveContains(keyword) ||
        (item.model ?? "").localizedCaseInsensitiveContains(keyword)
    }
}

/// A row for the containers list that shows the parent path for nested containers.
private struct ContainerListRow: View {
    let container: Container

    /// The parent portion of the breadcrumb (location and parent containers, excluding self)
    private var parentPath: [String] {
        var components: [String] = []
        var current = container.parentContainer
        while let parent = current {
            components.insert(parent.name, at: 0)
            current = parent.parentContainer
        }
        if let loc = container.resolvedLocation {
            components.insert(loc.name, at: 0)
        }
        return components
    }

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: container.photos, placeholderIcon: "archivebox")

            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)

                if !parentPath.isEmpty {
                    BreadcrumbView(components: parentPath)
                }

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
