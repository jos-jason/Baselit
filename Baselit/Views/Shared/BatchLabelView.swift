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

    // MARK: - Computed Properties

    private var filteredContainers: [Container] {
        guard !searchText.isEmpty else { return containers }
        return containers.filter { container in
            container.name.localizedCaseInsensitiveContains(searchText) ||
            container.identifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredItems: [Item] {
        guard !searchText.isEmpty else { return items }
        return items.filter { item in
            item.name.localizedCaseInsensitiveContains(searchText) ||
            item.identifier.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var totalSelectedCount: Int {
        selectedContainerIDs.count + selectedItemIDs.count
    }

    private var allFilteredContainersSelected: Bool {
        !filteredContainers.isEmpty &&
        filteredContainers.allSatisfy { selectedContainerIDs.contains($0.persistentModelID) }
    }

    private var allFilteredItemsSelected: Bool {
        !filteredItems.isEmpty &&
        filteredItems.allSatisfy { selectedItemIDs.contains($0.persistentModelID) }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                if !filteredContainers.isEmpty {
                    Section {
                        ForEach(filteredContainers) { container in
                            HStack(spacing: 12) {
                                Image(systemName: selectedContainerIDs.contains(container.persistentModelID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedContainerIDs.contains(container.persistentModelID)
                                                     ? .primary : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(container.name)
                                        .font(.headline)
                                    Text(container.identifier)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(.tertiary)
                                    BreadcrumbView(components: container.breadcrumbComponents.dropLast().map { $0 })
                                }

                                Spacer()

                                Image(systemName: "archivebox")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleContainer(container) }
                        }
                    } header: {
                        HStack {
                            Text("Containers")
                            Spacer()
                            Button(allFilteredContainersSelected ? "Deselect All" : "Select All") {
                                toggleAllContainers()
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                if !filteredItems.isEmpty {
                    Section {
                        ForEach(filteredItems) { item in
                            HStack(spacing: 12) {
                                Image(systemName: selectedItemIDs.contains(item.persistentModelID)
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedItemIDs.contains(item.persistentModelID)
                                                     ? .primary : .secondary)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.identifier)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundStyle(.tertiary)
                                    BreadcrumbView(components: item.breadcrumbComponents)
                                }

                                Spacer()

                                Image(systemName: "shippingbox")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            .padding(.vertical, 2)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleItem(item) }
                        }
                    } header: {
                        HStack {
                            Text("Items")
                            Spacer()
                            Button(allFilteredItemsSelected ? "Deselect All" : "Select All") {
                                toggleAllItems()
                            }
                            .font(.caption)
                            .textCase(nil)
                        }
                    }
                }

                if filteredContainers.isEmpty && filteredItems.isEmpty {
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

    private func toggleContainer(_ container: Container) {
        if selectedContainerIDs.contains(container.persistentModelID) {
            selectedContainerIDs.remove(container.persistentModelID)
        } else {
            selectedContainerIDs.insert(container.persistentModelID)
        }
    }

    private func toggleItem(_ item: Item) {
        if selectedItemIDs.contains(item.persistentModelID) {
            selectedItemIDs.remove(item.persistentModelID)
        } else {
            selectedItemIDs.insert(item.persistentModelID)
        }
    }

    private func toggleAllContainers() {
        if allFilteredContainersSelected {
            for container in filteredContainers {
                selectedContainerIDs.remove(container.persistentModelID)
            }
        } else {
            for container in filteredContainers {
                selectedContainerIDs.insert(container.persistentModelID)
            }
        }
    }

    private func toggleAllItems() {
        if allFilteredItemsSelected {
            for item in filteredItems {
                selectedItemIDs.remove(item.persistentModelID)
            }
        } else {
            for item in filteredItems {
                selectedItemIDs.insert(item.persistentModelID)
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

        Task.detached {
            let pdfData = LabelGenerator.generateLabelSheet(entries: entries)
            await MainActor.run {
                generatedPDFData = pdfData
                isGenerating = false
                showShareSheet = true
            }
        }
    }
}
