import SwiftUI
import SwiftData

struct ContainerDetailView: View {
    @Bindable var container: Container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSubContainer = false
    @State private var newSubContainerName = ""
    @State private var showAddItem = false
    @State private var showEditContainer = false
    @State private var showDeleteConfirmation = false
    @State private var showMoveContainer = false
    @State private var showCamera = false
    @State private var showShareSheet = false
    @State private var showAddedToQueue = false
    @State private var showBubbleGrid = false
    @Environment(PrintQueueService.self) private var printQueue
    @State private var showBulkCaptureItems = false
    @State private var showBulkCaptureContainers = false
    @State private var showAddHomeLocation = false
    /// Bumped each time the home is set, to play a success haptic
    @State private var homeSetCount = 0

    /// Recursively collect all items and sub-containers within this container.
    private var allBubbleEntries: [BubbleEntry] {
        var entries: [BubbleEntry] = []

        func collect(_ c: Container) {
            for item in c.items {
                entries.append(BubbleEntry(
                    id: "item-\(item.persistentModelID.hashValue)",
                    name: item.name,
                    photos: item.photos,
                    placeholderIcon: "shippingbox",
                    destination: .item(item)
                ))
            }
            for sub in c.subContainers {
                entries.append(BubbleEntry(
                    id: "container-\(sub.persistentModelID.hashValue)",
                    name: sub.name,
                    photos: sub.photos,
                    placeholderIcon: "archivebox",
                    destination: .container(sub)
                ))
                collect(sub)
            }
        }

        collect(container)
        return entries
    }

    var body: some View {
        List {
            // Photos
            Section("Photos") {
                PhotoGalleryView(
                    photos: container.photos,
                    onAdd: { photo in
                        container.photos.append(photo)
                    },
                    onDelete: { photo in
                        container.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
                    },
                    showCamera: $showCamera
                )
            }

            // Identifier & Breadcrumb
            Section {
                LabeledContent("ID") {
                    Text(container.identifier)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                BreadcrumbView(components: container.breadcrumbComponents)
                if let printedAt = container.lastLabelPrintedAt {
                    LabeledContent("Label Printed") {
                        Text(printedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Home locations (where this container belongs)
            Section("Belongs") {
                ForEach(container.homeLocations.sorted(by: {
                    ($0.house?.name ?? "") < ($1.house?.name ?? "")
                })) { homeLocation in
                    BreadcrumbView(components: homeLocation.breadcrumbComponents)
                }
                .onDelete { offsets in
                    let sorted = container.homeLocations.sorted(by: {
                        ($0.house?.name ?? "") < ($1.house?.name ?? "")
                    })
                    for index in offsets {
                        modelContext.delete(sorted[index])
                    }
                }

                if container.resolvedHouse != nil {
                    if isCurrentLocationHome {
                        Label("Current location is home", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            setCurrentLocationAsHome()
                        } label: {
                            Label("Set Current Location as Home", systemImage: "house.fill")
                        }
                    }
                }

                Button {
                    showAddHomeLocation = true
                } label: {
                    Label("Add Home Location", systemImage: "house.badge.plus")
                }
            }

            // Sub-containers
            if !container.subContainers.isEmpty {
                Section("Sub-containers") {
                    ForEach(container.subContainers.sorted(by: { $0.name < $1.name })) { sub in
                        NavigationLink(value: sub) {
                            ContainerRow(container: sub)
                        }
                    }
                }
            }

            // Items in this container
            if !container.items.isEmpty {
                Section("Items") {
                    ForEach(container.items.sorted(by: { $0.name < $1.name })) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }

            if container.subContainers.isEmpty && container.items.isEmpty {
                ContentUnavailableView {
                    Label("Empty Container", systemImage: "tray")
                } description: {
                    Text("Add items or sub-containers to this container.")
                } actions: {
                    HStack(spacing: 24) {
                        Button {
                            showAddSubContainer = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "archivebox.fill")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(.fill.tertiary, in: Circle())
                                Text("Add Container")
                                    .font(.caption)
                            }
                        }
                        Button {
                            showAddItem = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: "shippingbox.fill")
                                    .font(.title3)
                                    .frame(width: 44, height: 44)
                                    .background(.fill.tertiary, in: Circle())
                                Text("Add Item")
                                    .font(.caption)
                            }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }

            if let notes = container.notes, !notes.isEmpty {
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

            // Actions
            Section {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Print Label", systemImage: "qrcode")
                }

                Button {
                    printQueue.add(PrintQueueService.QueueEntry(
                        name: container.name,
                        identifier: container.identifier,
                        type: "container"
                    ))
                    showAddedToQueue = true
                } label: {
                    Label(
                        printQueue.contains(identifier: container.identifier)
                            ? "Already in Print Queue"
                            : "Add to Print Queue",
                        systemImage: "list.bullet.rectangle"
                    )
                }
                .disabled(printQueue.contains(identifier: container.identifier))

                Button {
                    showMoveContainer = true
                } label: {
                    Label("Move Container", systemImage: "arrow.right")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Container", systemImage: "trash")
                }
            }
        }
        .navigationTitle(container.name)
        .fullScreenCover(isPresented: $showBubbleGrid) {
            BubbleGridFullScreenView(
                title: container.name,
                entries: allBubbleEntries
            )
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddSubContainer = true
                    } label: {
                        Label("Add Sub-container", systemImage: "archivebox")
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "shippingbox")
                    }
                    Divider()
                    Button {
                        showBulkCaptureItems = true
                    } label: {
                        Label("Bulk Add Items", systemImage: "camera.on.rectangle")
                    }
                    Button {
                        showBulkCaptureContainers = true
                    } label: {
                        Label("Bulk Add Sub-containers", systemImage: "camera.on.rectangle.fill")
                    }
                    Divider()
                    Button {
                        showEditContainer = true
                    } label: {
                        Label("Edit Container", systemImage: "pencil")
                    }
                    Button {
                        showMoveContainer = true
                    } label: {
                        Label("Move Container", systemImage: "arrow.right")
                    }
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Print Label", systemImage: "qrcode")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Container", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("New Sub-container", isPresented: $showAddSubContainer) {
            TextField("Container name", text: $newSubContainerName)
            Button("Cancel", role: .cancel) {
                newSubContainerName = ""
            }
            Button("Add") {
                addSubContainer()
            }
        } message: {
            Text("Enter a name for the sub-container.")
        }
        .sheet(isPresented: $showEditContainer) {
            NavigationStack {
                EditContainerView(container: container)
            }
        }
        .confirmationDialog(
            "Delete \(container.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if !container.subContainers.isEmpty || !container.items.isEmpty {
                Button("Move contents out, then delete") {
                    reparentAndDelete()
                }
                Button("Delete container and all contents", role: .destructive) {
                    deleteWithContents()
                }
            } else {
                Button("Delete", role: .destructive) {
                    modelContext.delete(container)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if !container.subContainers.isEmpty || !container.items.isEmpty {
                Text("This container has \(container.subContainers.count) sub-containers and \(container.items.count) items.")
            }
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                ItemFormView(container: container)
            }
        }
        .sheet(isPresented: $showMoveContainer) {
            NavigationStack {
                MoveContainerView(container: container)
            }
        }
        .sheet(isPresented: $showAddHomeLocation) {
            NavigationStack {
                HomeLocationPickerView(
                    existingHouseIDs: Set(container.homeLocations.compactMap { $0.house?.persistentModelID })
                ) { house, location, targetContainer in
                    try? HomeLocationService.addHomeLocation(
                        for: container,
                        house: house,
                        location: location,
                        targetContainer: targetContainer,
                        context: modelContext
                    )
                }
            }
        }
        .fullScreenCover(isPresented: $showBulkCaptureItems) {
            BulkCaptureView(mode: .items, targetContainer: container)
        }
        .fullScreenCover(isPresented: $showBulkCaptureContainers) {
            BulkCaptureView(mode: .containers, targetContainer: container)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                let context = modelContext
                let nextOrder = (container.photos.map(\.sortOrder).max() ?? -1) + 1
                Task.detached {
                    let compressed = compressImageForGallery(data: data, maxDimension: 1200)
                    await MainActor.run {
                        let photo = Photo(imageData: compressed, sortOrder: nextOrder)
                        context.insert(photo)
                        container.photos.append(photo)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [
                LabelGenerator.generateLabel(
                    name: container.name,
                    identifier: container.identifier,
                    type: "container"
                )
            ])
            .onAppear {
                container.lastLabelPrintedAt = .now
            }
        }
        .sensoryFeedback(.success, trigger: homeSetCount)
        .overlay {
            if showAddedToQueue {
                addedToQueueOverlay
            }
        }
    }

    /// The house, location, and parent container this container is in right now
    private var currentSpot: (house: House, location: Location?, parentContainer: Container?)? {
        guard let house = container.resolvedHouse else { return nil }
        if let parent = container.parentContainer {
            return (house, parent.resolvedLocation, parent)
        }
        return (house, container.resolvedLocation, nil)
    }

    /// Whether the container's home for its current house is already where it is now
    private var isCurrentLocationHome: Bool {
        guard let spot = currentSpot,
              let home = container.homeLocations.first(where: {
                  $0.house?.persistentModelID == spot.house.persistentModelID
              }) else { return false }
        return home.matches(location: spot.location, container: spot.parentContainer)
    }

    private func setCurrentLocationAsHome() {
        guard let spot = currentSpot else { return }
        HomeLocationService.setHomeLocation(
            for: container,
            house: spot.house,
            location: spot.location,
            targetContainer: spot.parentContainer,
            context: modelContext
        )
        homeSetCount += 1
    }

    private var addedToQueueOverlay: some View {
        Text("Added to Print Queue")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial, in: Capsule())
            .transition(.scale.combined(with: .opacity))
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation { showAddedToQueue = false }
                }
            }
    }

    private func addSubContainer() {
        let trimmed = newSubContainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sub = Container(name: trimmed, parentContainer: container)
        modelContext.insert(sub)
        newSubContainerName = ""
    }

    private func reparentAndDelete() {
        let parent = container.parentContainer
        let loc = container.resolvedLocation

        for sub in container.subContainers {
            sub.parentContainer = parent
            if parent == nil {
                sub.location = loc
            }
        }
        for item in container.items {
            item.container = parent
            if parent == nil {
                item.location = loc
            }
        }
        modelContext.delete(container)
        dismiss()
    }

    private func deleteWithContents() {
        // Delete all nested items and sub-containers recursively
        deleteContainerRecursive(container)
        dismiss()
    }

    private func deleteContainerRecursive(_ c: Container) {
        for sub in c.subContainers {
            deleteContainerRecursive(sub)
        }
        for item in c.items {
            modelContext.delete(item)
        }
        modelContext.delete(c)
    }
}
