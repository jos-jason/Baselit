import SwiftUI

struct PrintQueueView: View {
    @Environment(PrintQueueService.self) private var printQueue
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var generatedPDFData: Data?
    @State private var isGenerating = false
    @State private var labelSize: LabelSize = .full

    enum LabelSize: String, CaseIterable {
        case full = "Full"
        case mini = "Mini"
    }

    var body: some View {
        NavigationStack {
            List {
                if printQueue.isEmpty {
                    ContentUnavailableView {
                        Label("Print Queue Empty", systemImage: "printer")
                    } description: {
                        Text("Add items or containers to the print queue from their detail views.")
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        Picker("Label Size", selection: $labelSize) {
                            ForEach(LabelSize.allCases, id: \.self) { size in
                                Text(size.rawValue).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

                        if labelSize == .mini {
                            Text("Compact QR code with identifier only — no item name.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .listRowBackground(Color.clear)
                        }
                    }

                    Section {
                        ForEach(printQueue.entries) { entry in
                            HStack(spacing: 12) {
                                Image(systemName: entry.type == "container" ? "archivebox" : "shippingbox")
                                    .foregroundStyle(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.name)
                                        .font(.headline)
                                    Text(entry.identifier)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(.tertiary)
                                }

                                Spacer()
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    printQueue.remove(entry)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(printQueue.count) label\(printQueue.count == 1 ? "" : "s") queued")
                            Spacer()
                            Button("Clear All") {
                                printQueue.removeAll()
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Print Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        generateAndShare()
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("Print (\(printQueue.count))")
                        }
                    }
                    .disabled(printQueue.isEmpty || isGenerating)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = generatedPDFData {
                    ShareSheet(activityItems: [data])
                }
            }
        }
    }

    private func generateAndShare() {
        isGenerating = true

        let labelEntries = printQueue.entries.map { entry in
            LabelGenerator.LabelEntry(
                name: entry.name,
                identifier: entry.identifier,
                type: entry.type
            )
        }

        let useMini = labelSize == .mini
        Task.detached {
            let pdfData: Data
            if useMini {
                pdfData = LabelGenerator.generateMiniLabelSheet(entries: labelEntries)
            } else {
                pdfData = LabelGenerator.generateLabelSheet(entries: labelEntries)
            }
            await MainActor.run {
                generatedPDFData = pdfData
                isGenerating = false
                showShareSheet = true
            }
        }
    }
}
