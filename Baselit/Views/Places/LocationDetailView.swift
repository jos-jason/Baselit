import SwiftUI
import SwiftData

struct LocationDetailView: View {
    @Bindable var location: Location
    @Environment(\.modelContext) private var modelContext
    @State private var showAddContainer = false
    @State private var newContainerName = ""
    @State private var showAddItem = false
    @State private var showAddSubLocation = false
    @State private var newSubLocationName = ""
    @State private var showEditLocation = false
    @State private var editedName = ""
    @State private var showCamera = false
    @State private var showBubbleGrid = false

    /// Recursively collect all items and containers within this location.
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

        func collectFromLocation(_ loc: Location) {
            for item in loc.items {
                entries.append(BubbleEntry(
                    id: "item-\(item.persistentModelID.hashValue)",
                    name: item.name,
                    photos: item.photos,
                    placeholderIcon: "shippingbox",
                    destination: .item(item)
                ))
            }
            for container in loc.containers {
                collectFromContainer(container)
            }
            for sub in loc.subLocations {
                collectFromLocation(sub)
            }
        }

        collectFromLocation(location)
        return entries
    }

    var body: some View {
        List {
            // Photos
            Section("Photos") {
                PhotoGalleryView(
                    photos: location.photos,
                    onAdd: { photo in
                        location.photos.append(photo)
                    },
                    onDelete: { photo in
                        location.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
                    },
                    showCamera: $showCamera
                )
            }

            // Breadcrumb
            if location.breadcrumbComponents.count > 1 {
                Section {
                    BreadcrumbView(components: location.breadcrumbComponents)
                }
            }

            // Sub-locations
            if !location.subLocations.isEmpty {
                Section("Sub-Locations") {
                    ForEach(location.subLocations.sorted(by: { $0.name < $1.name })) { subLocation in
                        NavigationLink(value: subLocation) {
                            SubLocationRow(location: subLocation)
                        }
                    }
                }
            }

            // Containers at this location
            if !location.containers.isEmpty {
                Section("Containers") {
                    ForEach(location.containers.sorted(by: { $0.name < $1.name })) { container in
                        NavigationLink(value: container) {
                            ContainerRow(container: container)
                        }
                    }
                }
            }

            // Items directly at this location
            if !location.items.isEmpty {
                Section("Items") {
                    ForEach(location.items.sorted(by: { $0.name < $1.name })) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }

            if location.subLocations.isEmpty && location.containers.isEmpty && location.items.isEmpty {
                ContentUnavailableView {
                    Label("Empty Location", systemImage: "tray")
                } description: {
                    Text("Add sub-locations, containers, or items to this location.")
                } actions: {
                    HStack(spacing: 16) {
                        Button {
                            showAddSubLocation = true
                        } label: {
                            Label("Add Sub-Location", systemImage: "mappin")
                        }
                        Button {
                            showAddContainer = true
                        } label: {
                            Label("Add Container", systemImage: "archivebox")
                        }
                        Button {
                            showAddItem = true
                        } label: {
                            Label("Add Item", systemImage: "shippingbox")
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if let notes = location.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
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
        .navigationTitle(location.name)
        .navigationDestination(for: Location.self) { subLocation in
            LocationDetailView(location: subLocation)
        }
        .fullScreenCover(isPresented: $showBubbleGrid) {
            BubbleGridFullScreenView(
                title: location.name,
                entries: allBubbleEntries
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddSubLocation = true
                    } label: {
                        Label("Add Sub-Location", systemImage: "mappin")
                    }
                    Button {
                        showAddContainer = true
                    } label: {
                        Label("Add Container", systemImage: "archivebox")
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "shippingbox")
                    }
                    Divider()
                    Button {
                        editedName = location.name
                        showEditLocation = true
                    } label: {
                        Label("Edit Location", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("New Container", isPresented: $showAddContainer) {
            TextField("Container name", text: $newContainerName)
            Button("Cancel", role: .cancel) {
                newContainerName = ""
            }
            Button("Add") {
                addContainer()
            }
        } message: {
            Text("Enter a name (e.g. Blue Tote, Cupboard, Shelf A).")
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                ItemFormView(location: location)
            }
        }
        .alert("New Sub-Location", isPresented: $showAddSubLocation) {
            TextField("Sub-location name", text: $newSubLocationName)
            Button("Cancel", role: .cancel) {
                newSubLocationName = ""
            }
            Button("Add") {
                addSubLocation()
            }
        } message: {
            Text("Enter a name (e.g. Pantry, Closet, Workbench Area).")
        }
        .alert("Edit Location", isPresented: $showEditLocation) {
            TextField("Location name", text: $editedName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    location.name = trimmed
                    location.updatedAt = .now
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                let context = modelContext
                let nextOrder = (location.photos.map(\.sortOrder).max() ?? -1) + 1
                Task.detached {
                    let compressed = compressImageForGallery(data: data, maxDimension: 1200)
                    await MainActor.run {
                        let photo = Photo(imageData: compressed, sortOrder: nextOrder)
                        context.insert(photo)
                        location.photos.append(photo)
                    }
                }
            }
            .ignoresSafeArea()
        }
    }

    private func addContainer() {
        let trimmed = newContainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let container = Container(name: trimmed, location: location)
        modelContext.insert(container)
        newContainerName = ""
    }

    private func addSubLocation() {
        let trimmed = newSubLocationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let subLocation = Location(name: trimmed, parentLocation: location)
        modelContext.insert(subLocation)
        newSubLocationName = ""
    }
}

private struct SubLocationRow: View {
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

struct ContainerRow: View {
    let container: Container

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: container.photos, placeholderIcon: "archivebox")

            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)
                Text(container.identifier)
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(.tertiary)
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

struct ItemRow: View {
    let item: Item

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: item.photos, placeholderIcon: "shippingbox")

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
