import SwiftUI
import SwiftData

struct PlacesTab: View {
    @Query(sort: \House.name) private var houses: [House]
    @Environment(\.modelContext) private var modelContext
    @State private var showAddHouse = false
    @State private var newHouseName = ""

    var body: some View {
        NavigationStack {
            Group {
                if houses.isEmpty {
                    EmptyStateView(
                        icon: "house",
                        title: "No Places Yet",
                        message: "Add a house or property to start tracking your inventory."
                    )
                } else {
                    List {
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

private struct HouseRow: View {
    let house: House

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(house.name)
                .font(.headline)
            HStack(spacing: 12) {
                Label("\(house.locations.count) locations", systemImage: "mappin")
                let itemCount = house.locations.reduce(0) { $0 + $1.items.count + $1.containers.reduce(0) { $0 + countItems(in: $1) } }
                Label("\(itemCount) items", systemImage: "shippingbox")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func countItems(in container: Container) -> Int {
        container.items.count + container.subContainers.reduce(0) { $0 + countItems(in: $1) }
    }
}
