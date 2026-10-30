import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showFilePicker = false
    @State private var importStage: ImportStage = .selectFile
    @State private var manifest: BackupManifest?
    @State private var extractedDir: URL?
    @State private var selectedMode: ImportMode = .replaceAll
    @State private var isProcessing = false
    @State private var progressMessage = ""
    @State private var errorMessage: String?
    @State private var importResult: ImportResult?
    @State private var showReplaceConfirmation = false

    // Conflict resolution
    @State private var conflicts: [ImportConflict] = []
    @State private var resolutions: [UUID: ConflictResolution] = [:]

    enum ImportStage {
        case selectFile
        case chooseMode
        case reviewConflicts
        case importing
        case complete
    }

    var body: some View {
        NavigationStack {
            Group {
                switch importStage {
                case .selectFile:
                    fileSelectionView
                case .chooseMode:
                    modeSelectionView
                case .reviewConflicts:
                    conflictReviewView
                case .importing:
                    importingView
                case .complete:
                    completionView
                }
            }
            .navigationTitle("Import Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(importStage == .complete ? "Done" : "Cancel") {
                        cleanup()
                        dismiss()
                    }
                    .disabled(isProcessing)
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [UTType.zip],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Replace All Data?", isPresented: $showReplaceConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Replace All", role: .destructive) {
                    performImport(mode: .replaceAll)
                }
            } message: {
                Text("This will permanently delete all existing data in the app and replace it with the backup. This cannot be undone.")
            }
        }
    }

    // MARK: - Stage Views

    private var fileSelectionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "doc.zipper")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Select a Baselit backup file")
                .font(.headline)
            Text("Choose a .zip file that was previously exported from Baselit.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button {
                showFilePicker = true
            } label: {
                Label("Choose File", systemImage: "folder")
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .padding(.horizontal)
            }
            Spacer()
        }
    }

    private var modeSelectionView: some View {
        Form {
            if let manifest {
                Section("Backup Summary") {
                    LabeledContent("Houses", value: "\(manifest.houses.count)")
                    LabeledContent("Locations", value: "\(manifest.locations.count)")
                    LabeledContent("Containers", value: "\(manifest.containers.count)")
                    LabeledContent("Items", value: "\(manifest.items.count)")
                    LabeledContent("Photos", value: "\(manifest.photos.count)")
                    if manifest.includesPhotos {
                        Label("Includes photo files", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Photo files not included", systemImage: "photo.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Import Mode") {
                    importModeButton(
                        mode: .replaceAll,
                        title: "Replace All",
                        description: "Delete all existing data and restore from backup.",
                        icon: "arrow.triangle.2.circlepath",
                        destructive: true
                    )

                    importModeButton(
                        mode: .importNonDuplicates,
                        title: "Import New Only",
                        description: "Add items from the backup that don't already exist. Skip duplicates.",
                        icon: "plus.rectangle.on.rectangle"
                    )

                    importModeButton(
                        mode: .reviewConflicts,
                        title: "Review Conflicts",
                        description: "Compare backup data with existing data and choose how to handle differences.",
                        icon: "arrow.left.arrow.right"
                    )
                }
            }
        }
    }

    private func importModeButton(mode: ImportMode, title: String, description: String, icon: String, destructive: Bool = false) -> some View {
        Button {
            selectedMode = mode
            switch mode {
            case .replaceAll:
                showReplaceConfirmation = true
            case .importNonDuplicates:
                performImport(mode: .importNonDuplicates)
            case .reviewConflicts:
                detectConflicts()
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(destructive ? .red : .accentColor)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(destructive ? .red : .primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 4)
        }
    }

    private var conflictReviewView: some View {
        Group {
            if conflicts.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)
                    Text("No Conflicts Found")
                        .font(.headline)
                    Text("All matching entries are identical. Non-matching entries will be imported as new.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Import Now") {
                        performImport(mode: .reviewConflicts)
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }
            } else {
                List {
                    Section {
                        HStack {
                            Button("Keep All Existing") {
                                for conflict in conflicts {
                                    resolutions[conflict.id] = .keepExisting
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            Button("Replace All") {
                                for conflict in conflicts {
                                    resolutions[conflict.id] = .replaceWithImport
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)
                        }
                    } header: {
                        Text("Batch Actions")
                    } footer: {
                        Text("\(resolutions.count) of \(conflicts.count) conflicts resolved. Identical entries were automatically skipped.")
                    }

                    Section("Conflicts") {
                        ForEach(conflicts) { conflict in
                            ConflictRow(
                                conflict: conflict,
                                resolution: resolutions[conflict.id],
                                onResolve: { resolution in
                                    resolutions[conflict.id] = resolution
                                }
                            )
                        }
                    }

                    Section {
                        Button("Apply Resolutions") {
                            performImport(mode: .reviewConflicts)
                        }
                        .disabled(resolutions.count < conflicts.count)
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private var importingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text(progressMessage)
                .font(.headline)
            Text("Please don't close the app.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    private var completionView: some View {
        Form {
            if let result = importResult {
                Section("Import Complete") {
                    if result.housesImported > 0 {
                        LabeledContent("Houses Imported", value: "\(result.housesImported)")
                    }
                    if result.locationsImported > 0 {
                        LabeledContent("Locations Imported", value: "\(result.locationsImported)")
                    }
                    if result.containersImported > 0 {
                        LabeledContent("Containers Imported", value: "\(result.containersImported)")
                    }
                    if result.itemsImported > 0 {
                        LabeledContent("Items Imported", value: "\(result.itemsImported)")
                    }
                    if result.photosImported > 0 {
                        LabeledContent("Photos Imported", value: "\(result.photosImported)")
                    }
                    if result.skipped > 0 {
                        LabeledContent("Skipped (duplicates)", value: "\(result.skipped)")
                    }
                }

                Section {
                    Label("Import completed successfully.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Actions

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }

            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            do {
                let parsed = try BackupImportService.parseBackup(at: url)
                manifest = parsed.manifest
                extractedDir = parsed.extractedDir

                if parsed.manifest.version > 1 {
                    errorMessage = "This backup was created by a newer version of Baselit."
                    return
                }

                importStage = .chooseMode
                errorMessage = nil
            } catch {
                errorMessage = "Failed to read backup: \(error.localizedDescription)"
            }

        case .failure(let error):
            errorMessage = "File selection failed: \(error.localizedDescription)"
        }
    }

    private func detectConflicts() {
        guard let manifest else { return }

        isProcessing = true
        progressMessage = "Analyzing conflicts..."
        importStage = .importing

        let context = modelContext
        Task {
            do {
                let detected = try BackupImportService.detectConflicts(manifest: manifest, context: context)
                conflicts = detected
                isProcessing = false
                importStage = .reviewConflicts
            } catch {
                errorMessage = "Failed to detect conflicts: \(error.localizedDescription)"
                isProcessing = false
                importStage = .chooseMode
            }
        }
    }

    private func performImport(mode: ImportMode) {
        guard let manifest, let extractedDir else { return }

        isProcessing = true
        importStage = .importing
        progressMessage = "Importing data..."

        let context = modelContext
        let currentResolutions = resolutions
        let currentConflicts = conflicts
        Task {
            do {
                let result: ImportResult
                switch mode {
                case .replaceAll:
                    result = try BackupImportService.importReplaceAll(
                        manifest: manifest,
                        extractedDir: extractedDir,
                        context: context
                    )
                case .importNonDuplicates:
                    result = try BackupImportService.importNonDuplicates(
                        manifest: manifest,
                        extractedDir: extractedDir,
                        context: context
                    )
                case .reviewConflicts:
                    result = try BackupImportService.importWithResolutions(
                        manifest: manifest,
                        extractedDir: extractedDir,
                        resolutions: currentResolutions,
                        conflicts: currentConflicts,
                        context: context
                    )
                }

                importResult = result
                isProcessing = false
                importStage = .complete
            } catch {
                errorMessage = "Import failed: \(error.localizedDescription)"
                isProcessing = false
                importStage = .complete
            }
        }
    }

    private func cleanup() {
        if let extractedDir {
            BackupImportService.cleanupExtractedFiles(at: extractedDir)
        }
    }
}

// MARK: - Conflict Row

private struct ConflictRow: View {
    let conflict: ImportConflict
    let resolution: ConflictResolution?
    let onResolve: (ConflictResolution) -> Void

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(conflict.differences) { diff in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(diff.propertyName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fontWeight(.semibold)
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Current")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(diff.existingValue)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Image(systemName: "arrow.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption)
                                .padding(.top, 14)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Backup")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text(diff.incomingValue)
                                    .font(.subheadline)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.vertical, 2)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Resolution")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fontWeight(.semibold)

                    resolutionButton(.keepExisting, label: "Keep Current", icon: "checkmark.shield")
                    resolutionButton(.replaceWithImport, label: "Use Backup Version", icon: "arrow.down.doc")
                    resolutionButton(.keepBoth, label: "Keep Both (new ID for backup)", icon: "doc.on.doc")
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: iconForType(conflict.entityType))
                    .foregroundStyle(.tint)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.entityName)
                        .font(.headline)
                    Text(conflict.identifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(conflict.differences.count) difference\(conflict.differences.count == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                if let resolution {
                    Image(systemName: resolutionIcon(resolution))
                        .foregroundStyle(resolutionColor(resolution))
                } else {
                    Image(systemName: "questionmark.circle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func resolutionButton(_ res: ConflictResolution, label: String, icon: String) -> some View {
        Button {
            onResolve(res)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(label)
                    .font(.subheadline)
                Spacer()
                if resolution == res {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func iconForType(_ type: ConflictEntityType) -> String {
        switch type {
        case .house: return "house"
        case .location: return "mappin"
        case .container: return "archivebox"
        case .item: return "shippingbox"
        }
    }

    private func resolutionIcon(_ resolution: ConflictResolution) -> String {
        switch resolution {
        case .keepExisting: return "checkmark.shield.fill"
        case .replaceWithImport: return "arrow.down.doc.fill"
        case .keepBoth: return "doc.on.doc.fill"
        }
    }

    private func resolutionColor(_ resolution: ConflictResolution) -> Color {
        switch resolution {
        case .keepExisting: return .blue
        case .replaceWithImport: return .orange
        case .keepBoth: return .green
        }
    }
}
