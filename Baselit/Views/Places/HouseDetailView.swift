import SwiftUI
import SwiftData

struct HouseDetailView: View {
    @Bindable var house: House
    @Environment(\.modelContext) private var modelContext
    @State private var showAddLocation = false
    @State private var newLocationName = ""
    @State private var showEditHouse = false
    @State private var editedHouseName = ""

    var body: some View {
        List {
            if !house.locations.isEmpty {
                Section("Locations") {
                    ForEach(house.locations.sorted(by: { $0.name < $1.name })) { location in
                        NavigationLink(value: location) {
                            LocationRow(location: location)
                        }
                    }
                    .onDelete(perform: deleteLocations)
                }
            } else {
                EmptyStateView(
                    icon: "mappin",
                    title: "No Locations",
                    message: "Add rooms, closets, or areas within this house."
                )
            }

            if let address = house.address, !address.isEmpty {
                Section("Details") {
                    LabeledContent("Address", value: address)
                }
            }

            if let notes = house.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .navigationTitle(house.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddLocation = true
                    } label: {
                        Label("Add Location", systemImage: "plus")
                    }
                    Button {
                        editedHouseName = house.name
                        showEditHouse = true
                    } label: {
                        Label("Edit House", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("New Location", isPresented: $showAddLocation) {
            TextField("Location name", text: $newLocationName)
            Button("Cancel", role: .cancel) {
                newLocationName = ""
            }
            Button("Add") {
                addLocation()
            }
        } message: {
            Text("Enter a name for the location (e.g. Kitchen, Garage, Master Bedroom).")
        }
        .alert("Edit House", isPresented: $showEditHouse) {
            TextField("House name", text: $editedHouseName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = editedHouseName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    house.name = trimmed
                    house.updatedAt = .now
                }
            }
        }
    }

    private func addLocation() {
        let trimmed = newLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let location = Location(name: trimmed, house: house)
        modelContext.insert(location)
        newLocationName = ""
    }

    private func deleteLocations(at offsets: IndexSet) {
        let sorted = house.locations.sorted(by: { $0.name < $1.name })
        for index in offsets {
            modelContext.delete(sorted[index])
        }
    }
}

private struct LocationRow: View {
    let location: Location

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(location.name)
                .font(.headline)
            HStack(spacing: 12) {
                Label("\(location.containers.count) containers", systemImage: "archivebox")
                Label("\(location.items.count) items", systemImage: "shippingbox")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
