import SwiftUI
import SwiftData

struct ExportBackupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var includePhotos = true
    @State private var isExporting = false
    @State private var exportProgress = ""
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?
    @State private var errorMessage: String?

    // Summary counts
    @State private var housesCount = 0
    @State private var locationsCount = 0
    @State private var containersCount = 0
    @State private var itemsCount = 0
    @State private var photosCount = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Backup Contents") {
                    LabeledContent("Houses", value: "\(housesCount)")
                    LabeledContent("Locations", value: "\(locationsCount)")
                    LabeledContent("Containers", value: "\(containersCount)")
                    LabeledContent("Items", value: "\(itemsCount)")
                    LabeledContent("Photos", value: "\(photosCount)")
                }

                Section {
                    Toggle("Include Photos", isOn: $includePhotos)
                } footer: {
                    Text("Excluding photos creates a smaller backup file. Your data can be fully restored without photos — you'll just need to re-add images.")
                }

                if isExporting {
                    Section {
                        HStack {
                            ProgressView()
                            Text(exportProgress)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Export Backup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isExporting)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Export") {
                        performExport()
                    }
                    .disabled(isExporting)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedFileURL {
                    ShareSheet(activityItems: [url])
                }
            }
            .onAppear { loadCounts() }
        }
    }

    private func loadCounts() {
        do {
            let counts = try BackupExportService.entityCounts(in: modelContext)
            housesCount = counts.houses
            locationsCount = counts.locations
            containersCount = counts.containers
            itemsCount = counts.items
            photosCount = counts.photos
        } catch {
            errorMessage = "Failed to load data counts: \(error.localizedDescription)"
        }
    }

    private func performExport() {
        isExporting = true
        errorMessage = nil
        exportProgress = "Preparing backup..."

        Task.detached {
            do {
                let options = BackupExportService.ExportOptions(includePhotos: includePhotos)
                let url = try BackupExportService.exportBackup(options: options, context: modelContext)

                await MainActor.run {
                    exportedFileURL = url
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Export failed: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }
}
