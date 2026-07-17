import SwiftUI
import SwiftData

struct BulkCaptureView: View {
    let mode: BulkCaptureMode
    /// When set, items are added to this container and sub-containers are created inside it.
    var targetContainer: Container?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var captureCount = 0
    @State private var capturedEntries: [CapturedEntry] = []
    @State private var showSummary = false
    @State private var isProcessing = false
    @State private var cameraCoordinator = ContinuousCameraCoordinator()
    @State private var selectedEntryIDs: Set<UUID> = []
    @State private var showBatchMove = false
    @State private var showDeleteConfirmation = false

    private var modeLabel: String {
        switch mode {
        case .items: return "Item"
        case .containers: return "Container"
        }
    }

    var body: some View {
        ZStack {
            if showSummary {
                summaryView
            } else {
                cameraLayer
            }
        }
        .onAppear {
            cameraCoordinator.onImageCaptured = { image in
                handleCapture(image: image)
            }
            cameraCoordinator.onDone = {
                withAnimation { showSummary = true }
            }
        }
    }

    // MARK: - Camera Layer

    private var cameraLayer: some View {
        ContinuousCameraView(
            onImageCaptured: { image in
                handleCapture(image: image)
            },
            coordinator: cameraCoordinator
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            // Count badge and Done button
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: mode == .items ? "shippingbox.fill" : "archivebox.fill")
                    Text("\(captureCount) captured")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: Capsule())

                Spacer()

                Button {
                    withAnimation { showSummary = true }
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.top, 60)
        }
        .overlay(alignment: .bottom) {
            // Shutter button
            Button {
                cameraCoordinator.takePicture()
            } label: {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 70, height: 70)
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }
            }
            .padding(.bottom, 40)
        }
        .overlay {
            if isProcessing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Summary View

    private var selectedItems: [Item] {
        capturedEntries
            .filter { selectedEntryIDs.contains($0.id) }
            .compactMap(\.item)
    }

    private var selectedContainers: [Container] {
        capturedEntries
            .filter { selectedEntryIDs.contains($0.id) }
            .compactMap(\.container)
    }

    private var summaryView: some View {
        NavigationStack {
            Group {
                if capturedEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No \(modeLabel)s Captured", systemImage: "camera")
                    } description: {
                        Text("You didn't capture any photos.")
                    }
                } else {
                    List(selection: $selectedEntryIDs) {
                        Section {
                            if let targetContainer {
                                Text("Created \(capturedEntries.count) \(modeLabel.lowercased())\(capturedEntries.count == 1 ? "" : "s") with photos inside \"\(targetContainer.name)\". Tap each to add names and details.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Created \(capturedEntries.count) \(modeLabel.lowercased())\(capturedEntries.count == 1 ? "" : "s") with photos. Find them in the \(mode == .items ? "Items" : "Containers") tab to add names and details.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Section("\(modeLabel)s Created") {
                            ForEach(capturedEntries) { entry in
                                HStack(spacing: 12) {
                                    if let data = entry.thumbnailData,
                                       let uiImage = UIImage(data: data) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 50, height: 50)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(.quaternary)
                                            .frame(width: 50, height: 50)
                                    }

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.name)
                                            .font(.headline)
                                        Text(entry.identifier)
                                            .font(.caption)
                                            .fontDesign(.monospaced)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(entry.id)
                            }
                        }

                        if !selectedEntryIDs.isEmpty {
                            Section {
                                Button {
                                    showBatchMove = true
                                } label: {
                                    Label("Move \(selectedEntryIDs.count) Selected", systemImage: "arrow.right")
                                }

                                Button(role: .destructive) {
                                    showDeleteConfirmation = true
                                } label: {
                                    Label("Delete \(selectedEntryIDs.count) Selected", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Bulk Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if !capturedEntries.isEmpty {
                    ToolbarItem(placement: .bottomBar) {
                        HStack {
                            Button {
                                if selectedEntryIDs.count == capturedEntries.count {
                                    selectedEntryIDs.removeAll()
                                } else {
                                    selectedEntryIDs = Set(capturedEntries.map(\.id))
                                }
                            } label: {
                                Text(selectedEntryIDs.count == capturedEntries.count ? "Deselect All" : "Select All")
                            }
                            Spacer()
                        }
                    }
                }
            }
            .sheet(isPresented: $showBatchMove) {
                NavigationStack {
                    BatchMoveView(
                        items: selectedItems,
                        containers: selectedContainers,
                        onComplete: {
                            selectedEntryIDs.removeAll()
                        }
                    )
                }
            }
            .confirmationDialog(
                "Delete \(selectedEntryIDs.count) \(modeLabel.lowercased())\(selectedEntryIDs.count == 1 ? "" : "s")?",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    deleteSelected()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete the selected \(modeLabel.lowercased())\(selectedEntryIDs.count == 1 ? "" : "s").")
            }
        }
    }

    // MARK: - Capture Handling

    private func handleCapture(image: UIImage) {
        captureCount += 1
        let currentIndex = captureCount
        let context = modelContext

        guard let rawData = image.jpegData(compressionQuality: 0.9) else { return }

        isProcessing = true

        Task.detached {
            let compressed = compressImageForGallery(data: rawData, maxDimension: 1200)

            await MainActor.run {
                let entry: CapturedEntry
                switch mode {
                case .items:
                    entry = BulkCaptureService.createItem(
                        index: currentIndex,
                        compressedImageData: compressed,
                        targetContainer: targetContainer,
                        in: context
                    )
                case .containers:
                    entry = BulkCaptureService.createContainer(
                        index: currentIndex,
                        compressedImageData: compressed,
                        parentContainer: targetContainer,
                        in: context
                    )
                }
                capturedEntries.append(entry)
                isProcessing = false
            }
        }
    }

    private func deleteSelected() {
        let idsToDelete = selectedEntryIDs
        for entry in capturedEntries where idsToDelete.contains(entry.id) {
            if let item = entry.item {
                modelContext.delete(item)
            }
            if let container = entry.container {
                modelContext.delete(container)
            }
        }
        capturedEntries.removeAll { idsToDelete.contains($0.id) }
        selectedEntryIDs.removeAll()
    }
}
