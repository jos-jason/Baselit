import SwiftUI
import SwiftData
import PhotosUI

struct ItemFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // If editing an existing item
    var editingItem: Item?

    // If creating a new item in a specific location or container
    var location: Location?
    var container: Container?

    @Query(sort: \House.name) private var houses: [House]
    @Query(sort: \Container.name) private var allContainers: [Container]

    @State private var name = ""
    @State private var itemDescription = ""
    @State private var quantity = 1
    @State private var brand = ""
    @State private var model = ""
    @State private var condition = ""
    @State private var notes = ""
    @State private var selectedTags: [Tag] = []
    @State private var selectedPhotos: [Photo] = []
    @State private var photoPickerItems: [PhotosPickerItem] = []
    @State private var showCamera = false
    @State private var isProcessingPhoto = false
    @State private var isEditingPhotoOrder = false
    @State private var photoOrderVersion = 0
    @State private var showOptionalFields = false
    @State private var showMoveSheet = false
    @State private var showAddHomeLocation = false
    @State private var homeLocationsToAdd: [(house: House, location: Location?, container: Container?)] = []
    @State private var homeLocationIDsToRemove: Set<PersistentIdentifier> = []

    // Location selection state (for create mode)
    @State private var selectedHouse: House?
    /// Cascading location selections: index 0 = top-level, index 1 = sub-location, etc.
    @State private var locationSelections: [Location?] = [nil]
    @State private var selectedContainer: Container?
    
    /// Guards against cascading onChange handlers clearing pre-populated selections during onAppear.
    @State private var didFinishInitialSetup = false

    private var isEditing: Bool { editingItem != nil }
    private var isValid: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The deepest selected location across all cascading pickers
    private var deepestSelectedLocation: Location? {
        locationSelections.compactMap { $0 }.last
    }

    /// Top-level locations for the selected house
    private var topLevelLocations: [Location] {
        selectedHouse?.locations
            .filter { $0.parentLocation == nil }
            .sorted(by: { $0.name < $1.name }) ?? []
    }

    /// Sub-locations available at a given depth (children of the selection at depth-1)
    private func subLocations(atDepth depth: Int) -> [Location] {
        guard depth > 0, depth <= locationSelections.count,
              let parent = locationSelections[depth - 1] else { return [] }
        return parent.subLocations.sorted(by: { $0.name < $1.name })
    }

    private var availableContainers: [Container] {
        if let deepestSelectedLocation {
            return allContainers.filter {
                $0.resolvedLocation?.persistentModelID == deepestSelectedLocation.persistentModelID
            }.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
        }
        if selectedHouse != nil {
            return allContainers.filter {
                $0.resolvedHouse?.persistentModelID == selectedHouse?.persistentModelID
            }.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
        }
        return allContainers.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
    }

    var body: some View {
        Form {
            Section("Basic Info") {
                TextField("Item name", text: $name)
                TextField("Description", text: $itemDescription)
                Stepper("Quantity: \(quantity)", value: $quantity, in: 1...9999)
            }

            Section("Tags") {
                TagPicker(selectedTags: $selectedTags)
            }

            Section("Photos") {
                if !selectedPhotos.isEmpty {
                    if isEditingPhotoOrder {
                        HStack {
                            Text("Reorder Photos")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Done") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isEditingPhotoOrder = false
                                }
                            }
                            .font(.subheadline.bold())
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(selectedPhotos.sorted(by: { $0.sortOrder < $1.sortOrder })) { photo in
                                if isEditingPhotoOrder {
                                    editableFormThumbnail(for: photo)
                                } else {
                                    normalFormThumbnail(for: photo)
                                }
                            }
                        }
                        .id(photoOrderVersion)
                        .padding(.vertical, isEditingPhotoOrder ? 6 : 0)
                    }
                }

                PhotosPicker(selection: $photoPickerItems, matching: .images) {
                    Label(isProcessingPhoto ? "Adding…" : "Choose Photos", systemImage: "photo.badge.plus")
                }
                .disabled(isProcessingPhoto)
                .onChange(of: photoPickerItems) { _, newItems in
                    guard !newItems.isEmpty else { return }
                    let items = newItems
                    photoPickerItems = []
                    addFromPicker(items: items)
                }

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                    }
                }
            }

            // Location section — pickers for create mode, move button for edit mode
            if isEditing {
                Section("Location") {
                    if let item = editingItem {
                        LabeledContent("Current Location") {
                            Text(item.breadcrumbPath)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        showMoveSheet = true
                    } label: {
                        Label("Move Item", systemImage: "arrow.right")
                    }
                }
            } else {
                Section("Location") {
                    Picker("House", selection: $selectedHouse) {
                        Text("None").tag(nil as House?)
                        ForEach(houses) { house in
                            Text(house.name).tag(house as House?)
                        }
                    }
                    .onChange(of: selectedHouse) {
                        guard didFinishInitialSetup else { return }
                        locationSelections = [nil]
                        selectedContainer = nil
                    }

                    // Cascading location pickers
                    if selectedHouse != nil {
                        locationPicker(atDepth: 0, label: "Location", locations: topLevelLocations)

                        ForEach(1..<locationSelections.count, id: \.self) { depth in
                            let subs = subLocations(atDepth: depth)
                            if !subs.isEmpty {
                                locationPicker(atDepth: depth, label: subLocationLabel(depth: depth), locations: subs)
                            }
                        }
                    }

                    if !availableContainers.isEmpty {
                        Picker("Container", selection: $selectedContainer) {
                            Text(deepestSelectedLocation != nil ? "Directly in location" : "None").tag(nil as Container?)
                            ForEach(availableContainers) { c in
                                Text(c.name).tag(c as Container?)
                            }
                        }
                    }
                }
            }

            Section("Notes") {
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }

            // Home locations (where this item belongs)
            Section("Belongs") {
                // Existing home locations (from an item being edited)
                if let item = editingItem {
                    ForEach(item.homeLocations.filter {
                        !homeLocationIDsToRemove.contains($0.persistentModelID)
                    }.sorted(by: { ($0.house?.name ?? "") < ($1.house?.name ?? "") })) { hl in
                        HStack {
                            BreadcrumbView(components: hl.breadcrumbComponents)
                            Spacer()
                            Button(role: .destructive) {
                                homeLocationIDsToRemove.insert(hl.persistentModelID)
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Newly added home locations (not yet saved)
                ForEach(Array(homeLocationsToAdd.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        BreadcrumbView(components: homeLocationPreviewComponents(entry))
                        Spacer()
                        Button(role: .destructive) {
                            homeLocationsToAdd.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showAddHomeLocation = true
                } label: {
                    Label("Add Home Location", systemImage: "house.badge.plus")
                }
                .disabled(availableHousesForHomeLocation.isEmpty)
            }

            // Optional fields behind a disclosure
            Section {
                DisclosureGroup("More Details", isExpanded: $showOptionalFields) {
                    TextField("Brand", text: $brand)
                    TextField("Model", text: $model)
                    TextField("Condition", text: $condition)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Item" : "New Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isEditing ? "Save" : "Add") {
                    save()
                }
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let item = editingItem {
                populateFrom(item)
            } else {
                // Pre-populate location selections from passed-in location/container
                if let container {
                    selectedHouse = container.resolvedHouse
                    if let loc = container.resolvedLocation {
                        locationSelections = locationChain(for: loc).map { $0 as Location? }
                        if !loc.subLocations.isEmpty {
                            locationSelections.append(nil)
                        }
                    }
                    selectedContainer = container
                } else if let location {
                    selectedHouse = location.resolvedHouse
                    locationSelections = locationChain(for: location).map { $0 as Location? }
                    if !location.subLocations.isEmpty {
                        locationSelections.append(nil)
                    }
                }
            }
            // Defer so that onChange handlers triggered by the above
            // assignments still see didFinishInitialSetup == false and
            // won't cascade-clear the pre-populated selections.
            DispatchQueue.main.async {
                didFinishInitialSetup = true
            }
        }
        .sheet(isPresented: $showMoveSheet) {
            if let item = editingItem {
                NavigationStack {
                    MoveItemView(item: item)
                }
            }
        }
        .sheet(isPresented: $showAddHomeLocation) {
            NavigationStack {
                HomeLocationPickerView(
                    existingHouseIDs: existingHomeLocationHouseIDs
                ) { house, location, container in
                    homeLocationsToAdd.append((house: house, location: location, container: container))
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraView { capturedImage in
                let data = capturedImage.jpegData(compressionQuality: 0.9) ?? Data()
                compressAndAddPhoto(data: data)
            }
            .ignoresSafeArea()
        }
    
    }

    /// House IDs that already have a home location (existing + newly added)
    private var existingHomeLocationHouseIDs: Set<PersistentIdentifier> {
        var ids = Set<PersistentIdentifier>()
        if let item = editingItem {
            for hl in item.homeLocations where !homeLocationIDsToRemove.contains(hl.persistentModelID) {
                if let house = hl.house {
                    ids.insert(house.persistentModelID)
                }
            }
        }
        for entry in homeLocationsToAdd {
            ids.insert(entry.house.persistentModelID)
        }
        return ids
    }

    /// Houses available for adding a new home location
    private var availableHousesForHomeLocation: [House] {
        houses.filter { !existingHomeLocationHouseIDs.contains($0.persistentModelID) }
    }

    /// Build preview breadcrumb components for a pending home location entry
    private func homeLocationPreviewComponents(_ entry: (house: House, location: Location?, container: Container?)) -> [String] {
        var components: [String] = [entry.house.name]
        if let location = entry.location {
            var locComponents: [String] = [location.name]
            var current = location.parentLocation
            while let parent = current {
                locComponents.insert(parent.name, at: 0)
                current = parent.parentLocation
            }
            components.append(contentsOf: locComponents)
        }
        if let container = entry.container {
            var containerComponents: [String] = [container.name]
            var current = container.parentContainer
            while let parent = current {
                containerComponents.insert(parent.name, at: 0)
                current = parent.parentContainer
            }
            components.append(contentsOf: containerComponents)
        }
        return components
    }

    /// Build a picker for a specific depth in the location hierarchy
    private func locationPicker(atDepth depth: Int, label: String, locations: [Location]) -> some View {
        let binding = Binding<Location?>(
            get: {
                guard depth < locationSelections.count else { return nil }
                return locationSelections[depth]
            },
            set: { newValue in
                guard didFinishInitialSetup else { return }
                if depth < locationSelections.count {
                    locationSelections[depth] = newValue
                }
                if locationSelections.count > depth + 1 {
                    locationSelections.removeSubrange((depth + 1)...)
                }
                if let loc = newValue, !loc.subLocations.isEmpty {
                    locationSelections.append(nil)
                }
                selectedContainer = nil
            }
        )

        return Picker(label, selection: binding) {
            Text(depth == 0 ? "Select location..." : "None").tag(nil as Location?)
            ForEach(locations) { loc in
                Text(loc.name).tag(loc as Location?)
            }
        }
    }

    /// Returns a label like "Sub-location" or "Sub-sub-location" based on depth
    private func subLocationLabel(depth: Int) -> String {
        let prefix = String(repeating: "Sub-", count: depth)
        return prefix + "location"
    }

    /// Builds the chain of locations from top-level down to the given location
    private func locationChain(for location: Location) -> [Location] {
        var chain: [Location] = [location]
        var current = location.parentLocation
        while let parent = current {
            chain.insert(parent, at: 0)
            current = parent.parentLocation
        }
        return chain
    }

    private func populateFrom(_ item: Item) {
        name = item.name
        itemDescription = item.itemDescription ?? ""
        quantity = item.quantity
        brand = item.brand ?? ""
        model = item.model ?? ""
        condition = item.condition ?? ""
        notes = item.notes ?? ""
        selectedTags = item.tags
        selectedPhotos = item.photos
        if !brand.isEmpty || !model.isEmpty || !condition.isEmpty {
            showOptionalFields = true
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let item: Item
        if let existing = editingItem {
            item = existing
        } else {
            item = Item(name: trimmedName)
            modelContext.insert(item)
            // Set location from pickers
            if let selectedContainer {
                item.container = selectedContainer
                item.location = nil
                item.house = nil
            } else if let loc = deepestSelectedLocation {
                item.location = loc
                item.container = nil
                item.house = nil
            } else if let selectedHouse {
                item.house = selectedHouse
                item.location = nil
                item.container = nil
            }
        }

        item.name = trimmedName
        item.itemDescription = itemDescription.isEmpty ? nil : itemDescription
        item.quantity = quantity
        item.brand = brand.isEmpty ? nil : brand
        item.model = model.isEmpty ? nil : model
        item.condition = condition.isEmpty ? nil : condition
        item.notes = notes.isEmpty ? nil : notes
        item.tags = selectedTags
        item.photos = selectedPhotos
        item.updatedAt = .now

        // Remove home locations marked for deletion
        for hl in item.homeLocations where homeLocationIDsToRemove.contains(hl.persistentModelID) {
            modelContext.delete(hl)
        }

        // Add new home locations
        for entry in homeLocationsToAdd {
            try? HomeLocationService.addHomeLocation(
                for: item,
                house: entry.house,
                location: entry.location,
                container: entry.container,
                context: modelContext
            )
        }

        dismiss()
    }

    @ViewBuilder
    private func normalFormThumbnail(for photo: Photo) -> some View {
        FormPhotoThumbnail(photo: photo) {
            withAnimation {
                selectedPhotos.removeAll { $0.persistentModelID == photo.persistentModelID }
                modelContext.delete(photo)
            }
        }
        .onLongPressGesture {
            ensureUniquePhotoSortOrders()
            withAnimation(.easeInOut(duration: 0.2)) {
                isEditingPhotoOrder = true
            }
        }
    }

    private func ensureUniquePhotoSortOrders() {
        let sorted = selectedPhotos.sorted {
            if $0.sortOrder != $1.sortOrder { return $0.sortOrder < $1.sortOrder }
            return $0.createdAt < $1.createdAt
        }
        for (i, photo) in sorted.enumerated() where photo.sortOrder != i {
            photo.sortOrder = i
        }
        photoOrderVersion += 1
    }

    @ViewBuilder
    private func editableFormThumbnail(for photo: Photo) -> some View {
        let sorted = selectedPhotos.sorted(by: { $0.sortOrder < $1.sortOrder })
        let index = sorted.firstIndex(where: { $0.persistentModelID == photo.persistentModelID })
        let isFirst = index == sorted.startIndex
        let isLast = index == sorted.index(before: sorted.endIndex)

        FormPhotoThumbnail(photo: photo) {
            withAnimation {
                selectedPhotos.removeAll { $0.persistentModelID == photo.persistentModelID }
                modelContext.delete(photo)
                if selectedPhotos.isEmpty { isEditingPhotoOrder = false }
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                if !isFirst, let index {
                    Button {
                        withAnimation { swapPhotoOrder(sorted[index], sorted[index - 1]) }
                    } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                }
                if !isLast, let index {
                    Button {
                        withAnimation { swapPhotoOrder(sorted[index], sorted[index + 1]) }
                    } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.5))
                    }
                }
            }
            .offset(y: -6)
        }
        .jiggleEffect()
    }

    private func swapPhotoOrder(_ a: Photo, _ b: Photo) {
        let temp = a.sortOrder
        a.sortOrder = b.sortOrder
        b.sortOrder = temp
        photoOrderVersion += 1
    }

    private func addFromPicker(items: [PhotosPickerItem]) {
        isProcessingPhoto = true
        let nextSortOrder = (selectedPhotos.map(\.sortOrder).max() ?? -1) + 1
        Task {
            for (index, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    compressAndAddPhoto(data: data, sortOrder: nextSortOrder + index)
                }
            }
            isProcessingPhoto = false
        }
    }

    /// Compresses image data on a background thread, then adds the photo on the main actor.
    private func compressAndAddPhoto(data: Data, sortOrder: Int? = nil) {
        let context = modelContext
        let order = sortOrder ?? ((selectedPhotos.map(\.sortOrder).max() ?? -1) + 1)
        Task.detached {
            let compressed = compressImageData(data: data, maxDimension: 1200)
            await MainActor.run {
                let photo = Photo(imageData: compressed, sortOrder: order)
                context.insert(photo)
                selectedPhotos.append(photo)
            }
        }
    }
}
/// Compresses image data to a max dimension. Safe to call from any thread.
nonisolated private func compressImageData(data: Data, maxDimension: CGFloat) -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
        return data
    }
    return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.7) ?? data
}

/// Downsamples image data to a target pixel size. Safe to call from any thread.
nonisolated private func downsampleForForm(data: Data, maxPixelSize: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceShouldCacheImmediately: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: cgImage)
}

/// Async thumbnail for the item form photo strip — avoids decoding full images on the main thread.
private struct FormPhotoThumbnail: View {
    let photo: Photo
    var onDelete: () -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.fill.quaternary)
            }
        }
        .frame(width: 80, height: 80)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .topTrailing) {
            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.white, .red)
                    .font(.caption)
            }
            .offset(x: 4, y: -4)
        }
        .onAppear { loadImage() }
    }

    private func loadImage() {
        guard let data = photo.imageData else { return }
        let scale = UIScreen.main.scale  // capture on main thread
        Task.detached {
            let img = downsampleForForm(data: data, maxPixelSize: 80 * scale)
            await MainActor.run { image = img }
        }
    }
}

/// A simple wrapping flow layout that arranges views horizontally,
/// moving to the next row when content exceeds the available width.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var height: CGFloat = 0
        for (index, row) in rows.enumerated() {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            height += rowHeight
            if index < rows.count - 1 { height += spacing }
        }
        return CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
            var x = bounds.minX
            for subview in row {
                let size = subview.sizeThatFits(.unspecified)
                subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += rowHeight + spacing
        }
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [[LayoutSubviews.Element]] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [[LayoutSubviews.Element]] = [[]]
        var currentWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentWidth + size.width > maxWidth && !rows[rows.count - 1].isEmpty {
                rows.append([])
                currentWidth = 0
            }
            rows[rows.count - 1].append(subview)
            currentWidth += size.width + spacing
        }
        return rows
    }
}


