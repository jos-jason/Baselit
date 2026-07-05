import SwiftUI

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showBatchLabels = false
    @State private var showExportBackup = false
    @State private var showImportBackup = false

    var body: some View {
        NavigationStack {
            List {
                Section("Labels") {
                    Button {
                        showBatchLabels = true
                    } label: {
                        Label("Print Labels", systemImage: "printer")
                    }
                }

                Section("Backup") {
                    Button {
                        showExportBackup = true
                    } label: {
                        Label("Export Backup", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showImportBackup = true
                    } label: {
                        Label("Import Backup", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showBatchLabels) {
                BatchLabelView()
            }
            .sheet(isPresented: $showExportBackup) {
                ExportBackupView()
            }
            .sheet(isPresented: $showImportBackup) {
                ImportBackupView()
            }
        }
    }
}
