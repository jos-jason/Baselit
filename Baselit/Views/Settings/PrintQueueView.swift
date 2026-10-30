import SwiftUI

struct PrintQueueView: View {
    @Environment(PrintQueueService.self) private var printQueue
    @Environment(\.dismiss) private var dismiss
    @State private var showShareSheet = false
    @State private var generatedPDFData: Data?
    @State private var isGenerating = false
    @State private var labelSize: LabelSize = .full
    @State private var selectedIdentifiers: Set<String> = []
    @State private var showPrintConfirmation = false
    @State private var printedIdentifiers: Set<String> = []

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
                                Image(systemName: selectedIdentifiers.contains(entry.identifier)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedIdentifiers.contains(entry.identifier)
                                                    ? .primary : .secondary)
                                    .font(.title3)

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
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSelection(entry) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    selectedIdentifiers.remove(entry.identifier)
                                    printQueue.remove(entry)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(selectedIdentifiers.count) of \(printQueue.count) selected")
                            Spacer()
                            Button(allSelected ? "Deselect All" : "Select All") {
                                toggleSelectAll()
                            }
                            .font(.caption)
                            .textCase(nil)
                            Button("Clear All") {
                                selectedIdentifiers.removeAll()
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
                            Text("Print (\(selectedIdentifiers.count))")
                        }
                    }
                    .disabled(selectedIdentifiers.isEmpty || isGenerating)
                }
            }
            .sheet(isPresented: $showShareSheet, onDismiss: {
                showPrintConfirmation = true
            }) {
                if let data = generatedPDFData {
                    ShareSheet(activityItems: [data])
                }
            }
            .confirmationDialog(
                "Did you print the labels successfully?",
                isPresented: $showPrintConfirmation,
                titleVisibility: .visible
            ) {
                Button("Yes, remove from queue") {
                    removePrintedEntries()
                }
                Button("No, keep in queue", role: .cancel) {}
            } message: {
                Text("\(printedIdentifiers.count) label\(printedIdentifiers.count == 1 ? "" : "s") were sent to print.")
            }
            .onAppear {
                selectedIdentifiers = Set(printQueue.entries.map(\.identifier))
            }
        }
    }

    // MARK: - Selection

    private var allSelected: Bool {
        !printQueue.isEmpty && printQueue.entries.allSatisfy { selectedIdentifiers.contains($0.identifier) }
    }

    private func toggleSelection(_ entry: PrintQueueService.QueueEntry) {
        if selectedIdentifiers.contains(entry.identifier) {
            selectedIdentifiers.remove(entry.identifier)
        } else {
            selectedIdentifiers.insert(entry.identifier)
        }
    }

    private func toggleSelectAll() {
        if allSelected {
            selectedIdentifiers.removeAll()
        } else {
            selectedIdentifiers = Set(printQueue.entries.map(\.identifier))
        }
    }

    // MARK: - Generate

    private func generateAndShare() {
        isGenerating = true

        printedIdentifiers = selectedIdentifiers

        let labelEntries = printQueue.entries
            .filter { selectedIdentifiers.contains($0.identifier) }
            .map { entry in
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

    private func removePrintedEntries() {
        let toRemove = printQueue.entries.filter { printedIdentifiers.contains($0.identifier) }
        for entry in toRemove {
            printQueue.remove(entry)
        }
        selectedIdentifiers.subtract(printedIdentifiers)
        printedIdentifiers.removeAll()
    }
}
