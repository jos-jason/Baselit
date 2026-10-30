import SwiftUI
import SwiftData

struct ItemDetailView: View {
    @Bindable var item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showEditSheet = false
    @State private var showMoveSheet = false
    @State private var showDeleteConfirmation = false
    @State private var showCamera = false
    @State private var showShareSheet = false
    @State private var showAddedToQueue = false
    @State private var showAddHomeLocation = false
    /// Bumped each time the home is set, to play a success haptic
    @State private var homeSetCount = 0
    @Environment(PrintQueueService.self) private var printQueue

    var body: some View {
        List {
            // Title
            Section {
                Text(item.name)
                    .font(.title)
                    .fontWeight(.bold)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            // Photos
            Section("Photos") {
                PhotoGalleryView(
                    photos: item.photos,
                    onAdd: { photo in
                        item.photos.append(photo)
                    },
                    onDelete: { photo in
                        item.photos.removeAll { $0.persistentModelID == photo.persistentModelID }
                    },
                    showCamera: $showCamera
                )
            }

            // Breadcrumb & ID
            Section {
                LabeledContent("ID") {
                    Text(item.identifier)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.secondary)
                }
                BreadcrumbView(components: item.breadcrumbComponents)
                if let printedAt = item.lastLabelPrintedAt {
                    LabeledContent("Label Printed") {
                        Text(printedAt, format: .dateTime.month(.abbreviated).day().year().hour().minute())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Main info
            Section("Details") {
                if let description = item.itemDescription, !description.isEmpty {
                    LabeledContent("Description", value: description)
                }
                if item.quantity > 1 {
                    LabeledContent("Quantity", value: "\(item.quantity)")
                }
                if let brand = item.brand, !brand.isEmpty {
                    LabeledContent("Brand", value: brand)
                }
                if let model = item.model, !model.isEmpty {
                    LabeledContent("Model", value: model)
                }
                if let condition = item.condition, !condition.isEmpty {
                    LabeledContent("Condition", value: condition)
                }
            }

            // Notes
            if let notes = item.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }

            // Stored in
            Section("Stored In") {
                Text(item.breadcrumbPath)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Home locations (where this item belongs)
            Section("Belongs") {
                ForEach(item.homeLocations.sorted(by: {
                    ($0.house?.name ?? "") < ($1.house?.name ?? "")
                })) { homeLocation in
                    BreadcrumbView(components: homeLocation.breadcrumbComponents)
                }
                .onDelete { offsets in
                    let sorted = item.homeLocations.sorted(by: {
                        ($0.house?.name ?? "") < ($1.house?.name ?? "")
                    })
                    for index in offsets {
                        modelContext.delete(sorted[index])
                    }
                }

                if item.resolvedHouse != nil {
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

            // Actions
            Section {
                Button {
                    showShareSheet = true
                } label: {
                    Label("Print Label", systemImage: "qrcode")
                }

                Button {
                    printQueue.add(PrintQueueService.QueueEntry(
                        name: item.name,
                        identifier: item.identifier,
                        type: "item"
                    ))
                    showAddedToQueue = true
                } label: {
                    Label(
                        printQueue.contains(identifier: item.identifier)
                            ? "Already in Print Queue"
                            : "Add to Print Queue",
                        systemImage: "list.bullet.rectangle"
                    )
                }
                .disabled(printQueue.contains(identifier: item.identifier))

                Button {
                    showMoveSheet = true
                } label: {
                    Label("Move Item", systemImage: "arrow.right")
                }

                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Item", systemImage: "trash")
                }
            }
        }
        .navigationTitle(item.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showEditSheet) {
            NavigationStack {
                ItemFormView(editingItem: item)
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            NavigationStack {
                MoveItemView(item: item)
            }
        }
        .sheet(isPresented: $showAddHomeLocation) {
            NavigationStack {
                HomeLocationPickerView(
                    existingHouseIDs: Set(item.homeLocations.compactMap { $0.house?.persistentModelID })
                ) { house, location, container in
                    try? HomeLocationService.addHomeLocation(
                        for: item,
                        house: house,
                        location: location,
                        container: container,
                        context: modelContext
                    )
                }
            }
        }
        .confirmationDialog(
            "Delete \(item.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                modelContext.delete(item)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete this item.")
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                let context = modelContext
                let nextOrder = (item.photos.map(\.sortOrder).max() ?? -1) + 1
                Task.detached {
                    let compressed = compressImageForGallery(data: data, maxDimension: 1200)
                    await MainActor.run {
                        let photo = Photo(imageData: compressed, sortOrder: nextOrder)
                        context.insert(photo)
                        item.photos.append(photo)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [
                LabelGenerator.generateLabel(
                    name: item.name,
                    identifier: item.identifier,
                    type: "item"
                )
            ])
            .onAppear {
                item.lastLabelPrintedAt = .now
            }
        }
        .sensoryFeedback(.success, trigger: homeSetCount)
        .overlay {
            if showAddedToQueue {
                addedToQueueOverlay
            }
        }
    }

    /// The house, location, and container the item is in right now
    private var currentSpot: (house: House, location: Location?, container: Container?)? {
        guard let house = item.resolvedHouse else { return nil }
        if let itemContainer = item.container {
            return (house, itemContainer.resolvedLocation, itemContainer)
        }
        return (house, item.location, nil)
    }

    /// Whether the item's home for its current house is already where it is now
    private var isCurrentLocationHome: Bool {
        guard let spot = currentSpot,
              let home = item.homeLocations.first(where: {
                  $0.house?.persistentModelID == spot.house.persistentModelID
              }) else { return false }
        return home.matches(location: spot.location, container: spot.container)
    }

    private func setCurrentLocationAsHome() {
        guard let spot = currentSpot else { return }
        HomeLocationService.setHomeLocation(
            for: item,
            house: spot.house,
            location: spot.location,
            container: spot.container,
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
}
