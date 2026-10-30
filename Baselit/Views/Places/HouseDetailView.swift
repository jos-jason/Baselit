import SwiftUI
import SwiftData

struct HouseDetailView: View {
    @Bindable var house: House
    @Environment(\.modelContext) private var modelContext
    @State private var showAddLocation = false
    @State private var newLocationName = ""
    @State private var showEditHouse = false
    @State private var editedHouseName = ""
    @State private var showCamera = false
    @State private var showBubbleGrid = false

    private var topLevelLocations: [Location] {
        house.locations
            .filter { $0.parentLocation == nil }
            .sorted(by: { $0.name < $1.name })
    }

    private var directItems: [Item] {
        house.items.sorted(by: { $0.name < $1.name })
    }

    private var directContainers: [Container] {
        house.containers.sorted(by: { $0.name < $1.name })
    }

    /// Recursively collect all items and containers across all locations in this house.
    private var allBubbleEntries: [BubbleEntry] {
        var entries: [BubbleEntry] = []

        func collectFromContainer(_ container: Container) {
            entries.append(BubbleEntry(
                id: "container-\(container.persistentModelID.hashValue)",
                name: container.name,
                photos: container.photos,
                placeholderIcon: "archivebox",
                destination: .container(container)
            ))
            for item in container.items {
                entries.append(BubbleEntry(
                    id: "item-\(item.persistentModelID.hashValue)",
                    name: item.name,
                    photos: item.photos,
                    placeholderIcon: "shippingbox",
                    destination: .item(item)
                ))
            }
            for sub in container.subContainers {
                collectFromContainer(sub)
            }
        }

        func collectFromLocation(_ location: Location) {
            for item in location.items {
                entries.append(BubbleEntry(
                    id: "item-\(item.persistentModelID.hashValue)",
                    name: item.name,
                    photos: item.photos,
                    placeholderIcon: "shippingbox",
                    destination: .item(item)
                ))
            }
            for container in location.containers {
                collectFromContainer(container)
            }
            for sub in location.subLocations {
                collectFromLocation(sub)
            }
        }

        // Items and containers directly assigned to the house (no location)
        for item in house.items {
            entries.append(BubbleEntry(
                id: "item-\(item.persistentModelID.hashValue)",
                name: item.name,
                photos: item.photos,
                placeholderIcon: "shippingbox",
                destination: .item(item)
            ))
        }
        for container in house.containers {
            collectFromContainer(container)
        }

        // Items and containers within locations
        for location in house.locations {
            collectFromLocation(location)
        }

        return entries
    }

    var body: some View {
        List {
            // Photos
            Section("Photos") {
                PhotoGalleryView(
                    photos: house.photos,
                    onAdd: { photo in
                        house.photos.append(photo)
                    },
                    onDelete: { photo in
                        house.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
                    },
                    showCamera: $showCamera
                )
            }

            if !topLevelLocations.isEmpty {
                Section("Locations") {
                    ForEach(topLevelLocations) { location in
                        NavigationLink(value: location) {
                            LocationRow(location: location)
                        }
                    }
                    .onDelete(perform: deleteLocations)
                }
            }

            if !directContainers.isEmpty {
                Section("Containers") {
                    ForEach(directContainers) { container in
                        NavigationLink(value: container) {
                            ContainerRow(container: container)
                        }
                    }
                }
            }

            if !directItems.isEmpty {
                Section("Items") {
                    ForEach(directItems) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }

            if topLevelLocations.isEmpty && directContainers.isEmpty && directItems.isEmpty {
                ContentUnavailableView {
                    Label("No Locations", systemImage: "mappin")
                } description: {
                    Text("Add rooms, closets, or areas within this house.")
                } actions: {
                    Button {
                        showAddLocation = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2)
                            .padding(8)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                }
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

            if !allBubbleEntries.isEmpty {
                Section {
                    Button {
                        showBubbleGrid = true
                    } label: {
                        Label("View All Items & Containers", systemImage: "circle.hexagongrid")
                    }
                }
            }
        }
        .navigationTitle(house.name)
        .fullScreenCover(isPresented: $showBubbleGrid) {
            BubbleGridFullScreenView(
                title: house.name,
                entries: allBubbleEntries
            )
        }
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
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                let context = modelContext
                let nextOrder = (house.photos.map(\.sortOrder).max() ?? -1) + 1
                Task.detached {
                    let compressed = compressImageForGallery(data: data, maxDimension: 1200)
                    await MainActor.run {
                        let photo = Photo(imageData: compressed, sortOrder: nextOrder)
                        context.insert(photo)
                        house.photos.append(photo)
                    }
                }
            }
            .ignoresSafeArea()
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
        for index in offsets {
            modelContext.delete(topLevelLocations[index])
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
                if !location.subLocations.isEmpty {
                    Label("\(location.subLocations.count) sub-locations", systemImage: "mappin")
                }
                Label("\(location.containers.count) containers", systemImage: "archivebox")
                Label("\(location.items.count) items", systemImage: "shippingbox")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
