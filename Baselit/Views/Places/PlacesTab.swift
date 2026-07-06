import SwiftUI
import SwiftData

struct PlacesTab: View {
    @Query(sort: \House.name) private var houses: [House]
    @Query(filter: #Predicate<Item> { $0.container == nil && $0.location == nil },
           sort: \Item.name)
    private var unassignedItems: [Item]

    @Query(filter: #Predicate<Container> { $0.parentContainer == nil && $0.location == nil },
           sort: \Container.name)
    private var unassignedContainers: [Container]

    @Environment(\.modelContext) private var modelContext
    @State private var showAddHouse = false
    @State private var newHouseName = ""

    private var hasUnassigned: Bool {
        !unassignedItems.isEmpty || !unassignedContainers.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if houses.isEmpty && !hasUnassigned {
                    EmptyStateView(
                        icon: "house",
                        title: "No Places Yet",
                        message: "Add a house or property to start tracking your inventory."
                    )
                } else {
                    List {
                        if hasUnassigned {
                            NavigationLink(value: "unassigned") {
                                UnassignedHouseRow(
                                    containerCount: unassignedContainers.count,
                                    itemCount: unassignedItems.count
                                )
                            }
                        }

                        ForEach(houses) { house in
                            NavigationLink(value: house) {
                                HouseRow(house: house)
                            }
                        }
                        .onDelete(perform: deleteHouses)
                    }
                }
            }
            .navigationTitle("Places")
            .navigationDestination(for: String.self) { value in
                if value == "unassigned" {
                    UnassignedHouseDetailView()
                }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddHouse = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonBorderShape(.circle)
                }
            }
            .alert("New House", isPresented: $showAddHouse) {
                TextField("House name", text: $newHouseName)
                Button("Cancel", role: .cancel) {
                    newHouseName = ""
                }
                Button("Add") {
                    addHouse()
                }
            } message: {
                Text("Enter a name for the new house or property.")
            }
        }
    }

    private func addHouse() {
        let trimmed = newHouseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let house = House(name: trimmed)
        modelContext.insert(house)
        newHouseName = ""
    }

    private func deleteHouses(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(houses[index])
        }
    }
}

// MARK: - Unassigned House Detail View

struct UnassignedHouseDetailView: View {
    @Query(filter: #Predicate<Item> { $0.container == nil && $0.location == nil },
           sort: \Item.name)
    private var unassignedItems: [Item]

    @Query(filter: #Predicate<Container> { $0.parentContainer == nil && $0.location == nil },
           sort: \Container.name)
    private var unassignedContainers: [Container]

    var body: some View {
        List {
            if !unassignedContainers.isEmpty {
                Section("Containers") {
                    ForEach(unassignedContainers) { container in
                        NavigationLink(value: container) {
                            ContainerRow(container: container)
                        }
                    }
                }
            }

            if !unassignedItems.isEmpty {
                Section("Items") {
                    ForEach(unassignedItems) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }

            if unassignedContainers.isEmpty && unassignedItems.isEmpty {
                ContentUnavailableView {
                    Label("Nothing Unassigned", systemImage: "checkmark.circle")
                } description: {
                    Text("All items and containers have been assigned to locations.")
                }
            }
        }
        .navigationTitle("Unassigned")
    }
}

// MARK: - Row Views

private struct UnassignedHouseRow: View {
    let containerCount: Int
    let itemCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Unassigned")
                    .font(.headline)
                HStack(spacing: 12) {
                    if containerCount > 0 {
                        Label("\(containerCount) containers", systemImage: "archivebox")
                    }
                    if itemCount > 0 {
                        Label("\(itemCount) items", systemImage: "shippingbox")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HouseRow: View {
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
