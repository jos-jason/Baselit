import SwiftUI
import SwiftData

struct BatchLabelView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var containers: [Container] = []
    @State private var items: [Item] = []
    @State private var selectedContainerIDs: Set<PersistentIdentifier> = []
    @State private var selectedItemIDs: Set<PersistentIdentifier> = []
    @State private var searchText = ""
    @State private var showShareSheet = false
    @State private var generatedPDFData: Data?
    @State private var isGenerating = false
    @State private var labelSize: LabelSize = .full

    enum LabelSize: String, CaseIterable {
        case full = "Full"
        case mini = "Mini"
    }

    // MARK: - Unified Entry

    /// Wraps either a Container or Item so we can sort/group them together.
    private enum LabelEntry: Identifiable {
        case container(Container)
        case item(Item)

        var id: PersistentIdentifier {
            switch self {
            case .container(let c): c.persistentModelID
            case .item(let i): i.persistentModelID
            }
        }

        var name: String {
            switch self {
            case .container(let c): c.name
            case .item(let i): i.name
            }
        }

        var identifier: String {
            switch self {
            case .container(let c): c.identifier
            case .item(let i): i.identifier
            }
        }

        var lastLabelPrintedAt: Date? {
            switch self {
            case .container(let c): c.lastLabelPrintedAt
            case .item(let i): i.lastLabelPrintedAt
            }
        }

        var breadcrumbComponents: [String] {
            switch self {
            case .container(let c): c.breadcrumbComponents.dropLast().map { $0 }
            case .item(let i): i.breadcrumbComponents
            }
        }

        var iconName: String {
            switch self {
            case .container: "archivebox"
            case .item: "shippingbox"
            }
        }

        var isContainer: Bool {
            if case .container = self { return true }
            return false
        }
    }

    /// Groups entries by print status for display.
    private struct LabelGroup: Identifiable {
        let id: String
        let title: String
        let entries: [LabelEntry]
    }

    // MARK: - Computed Properties

    private var allEntries: [LabelEntry] {
        let filtered: [LabelEntry]
        if searchText.isEmpty {
            filtered = containers.map { .container($0) } + items.map { .item($0) }
        } else {
            let fc = containers.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.identifier.localizedCaseInsensitiveContains(searchText)
            }.map { LabelEntry.container($0) }
            let fi = items.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.identifier.localizedCaseInsensitiveContains(searchText)
            }.map { LabelEntry.item($0) }
            filtered = fc + fi
        }
        return filtered
    }

    private var groupedEntries: [LabelGroup] {
        let neverPrinted = allEntries.filter { $0.lastLabelPrintedAt == nil }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let printed = allEntries.filter { $0.lastLabelPrintedAt != nil }
            .sorted { ($0.lastLabelPrintedAt ?? .distantPast) > ($1.lastLabelPrintedAt ?? .distantPast) }

        var groups: [LabelGroup] = []
        if !neverPrinted.isEmpty {
            groups.append(LabelGroup(id: "never", title: "Never Printed", entries: neverPrinted))
        }
        if !printed.isEmpty {
            groups.append(LabelGroup(id: "printed", title: "Previously Printed", entries: printed))
        }
        return groups
    }

    private var totalSelectedCount: Int {
        selectedContainerIDs.count + selectedItemIDs.count
    }

    private func isSelected(_ entry: LabelEntry) -> Bool {
        switch entry {
        case .container(let c): selectedContainerIDs.contains(c.persistentModelID)
        case .item(let i): selectedItemIDs.contains(i.persistentModelID)
        }
    }

    private func allSelected(in group: LabelGroup) -> Bool {
        !group.entries.isEmpty && group.entries.allSatisfy { isSelected($0) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
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

                ForEach(groupedEntries) { group in
                    Section {
                        ForEach(group.entries) { entry in
                            entryRow(entry)
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Button(allSelected(in: group) ? "Deselect All" : "Select All") {
                                toggleAll(in: group)
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                if allEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        if containers.isEmpty && items.isEmpty {
                            Text("Add containers or items first to print labels.")
                        } else {
                            Text("Nothing matches your search.")
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
            .searchable(text: $searchText, prompt: "Filter by name or identifier...")
            .navigationTitle("Print Labels")
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
                            Text("Generate (\(totalSelectedCount))")
                        }
                    }
                    .disabled(totalSelectedCount == 0 || isGenerating)
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let data = generatedPDFData {
                    ShareSheet(activityItems: [data])
                }
            }
            .onAppear { loadData() }
        }
    }

    // MARK: - Row View

    private func entryRow(_ entry: LabelEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isSelected(entry) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected(entry) ? .primary : .secondary)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    Text(entry.identifier)
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(.tertiary)
                    Image(systemName: entry.iconName)
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                }
                BreadcrumbView(components: entry.breadcrumbComponents)
                if let printedAt = entry.lastLabelPrintedAt {
                    Text("Printed \(printedAt, format: .relative(presentation: .named))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture { toggle(entry) }
    }

    // MARK: - Actions

    private func loadData() {
        do {
            containers = try InventoryService.allContainers(in: modelContext)
            items = try InventoryService.allItems(in: modelContext)
        } catch {
            containers = []
            items = []
        }
    }

    private func toggle(_ entry: LabelEntry) {
        switch entry {
        case .container(let c):
            if selectedContainerIDs.contains(c.persistentModelID) {
                selectedContainerIDs.remove(c.persistentModelID)
            } else {
                selectedContainerIDs.insert(c.persistentModelID)
            }
        case .item(let i):
            if selectedItemIDs.contains(i.persistentModelID) {
                selectedItemIDs.remove(i.persistentModelID)
            } else {
                selectedItemIDs.insert(i.persistentModelID)
            }
        }
    }

    private func toggleAll(in group: LabelGroup) {
        let allSel = allSelected(in: group)
        for entry in group.entries {
            switch entry {
            case .container(let c):
                if allSel {
                    selectedContainerIDs.remove(c.persistentModelID)
                } else {
                    selectedContainerIDs.insert(c.persistentModelID)
                }
            case .item(let i):
                if allSel {
                    selectedItemIDs.remove(i.persistentModelID)
                } else {
                    selectedItemIDs.insert(i.persistentModelID)
                }
            }
        }
    }

    private func generateAndShare() {
        isGenerating = true

        var entries: [LabelGenerator.LabelEntry] = []

        for container in containers where selectedContainerIDs.contains(container.persistentModelID) {
            entries.append(LabelGenerator.LabelEntry(
                name: container.name,
                identifier: container.identifier,
                type: "container"
            ))
        }

        for item in items where selectedItemIDs.contains(item.persistentModelID) {
            entries.append(LabelGenerator.LabelEntry(
                name: item.name,
                identifier: item.identifier,
                type: "item"
            ))
        }

        let now = Date.now
        for container in containers where selectedContainerIDs.contains(container.persistentModelID) {
            container.lastLabelPrintedAt = now
        }
        for item in items where selectedItemIDs.contains(item.persistentModelID) {
            item.lastLabelPrintedAt = now
        }

        let useMini = labelSize == .mini
        Task.detached {
            let pdfData: Data
            if useMini {
                pdfData = LabelGenerator.generateMiniLabelSheet(entries: entries)
            } else {
                pdfData = LabelGenerator.generateLabelSheet(entries: entries)
            }
            await MainActor.run {
                generatedPDFData = pdfData
                isGenerating = false
                showShareSheet = true
            }
        }
    }
}
