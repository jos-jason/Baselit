import SwiftUI
import UIKit

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showBatchLabels = false
    @State private var showExportBackup = false
    @State private var showImportBackup = false
    @State private var showBulkCaptureItems = false
    @State private var showBulkCaptureContainers = false

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

                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Section("Bulk Capture") {
                        Button {
                            showBulkCaptureItems = true
                        } label: {
                            Label("Capture Items", systemImage: "shippingbox")
                        }

                        Button {
                            showBulkCaptureContainers = true
                        } label: {
                            Label("Capture Containers", systemImage: "archivebox")
                        }
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
            .fullScreenCover(isPresented: $showBulkCaptureItems) {
                BulkCaptureView(mode: .items)
            }
            .fullScreenCover(isPresented: $showBulkCaptureContainers) {
                BulkCaptureView(mode: .containers)
            }
        }
    }
}
