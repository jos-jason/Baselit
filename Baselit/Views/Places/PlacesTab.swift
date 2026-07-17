import SwiftUI
import SwiftData

struct PlacesTab: View {
    @Query(sort: \House.name) private var houses: [House]
    @Query(sort: \Item.name) private var allItems: [Item]
    @Query(sort: \Container.name) private var allContainers: [Container]

    private var unassignedItems: [Item] {
        allItems.filter { $0.container == nil && $0.location == nil && $0.house == nil }
    }

    private var unassignedContainers: [Container] {
        allContainers.filter { $0.parentContainer == nil && $0.location == nil && $0.house == nil }
    }

    @Environment(\.modelContext) private var modelContext
    @State private var showAddHouse = false
    @State private var newHouseName = ""

    private var hasUnassigned: Bool {
        !unassignedItems.isEmpty || !unassignedContainers.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if houses.isEmpty && !hasUnassigned {
                    EmptyStateView(
                        icon: "house",
                        title: "No Places Yet",
                        message: "Add a house or property to start tracking your inventory."
                    )
                } else {
                    List {
                        if hasUnassigned {
                            NavigationLink(value: "unassigned") {
                                UnassignedHouseRow(
                                    containerCount: unassignedContainers.count,
                                    itemCount: unassignedItems.count
                                )
                            }
                        }

                        ForEach(houses) { house in
                            NavigationLink(value: house) {
                                HouseRow(house: house)
                            }
                        }
                        .onDelete(perform: deleteHouses)
                    }
                }
            }
            .navigationTitle("Places")
            .navigationDestination(for: String.self) { value in
                if value == "unassigned" {
                    UnassignedHouseDetailView()
                }
            }
            .navigationDestination(for: House.self) { house in
                HouseDetailView(house: house)
            }
            .navigationDestination(for: Location.self) { location in
                LocationDetailView(location: location)
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container)
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddHouse = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonBorderShape(.circle)
                }
            }
            .alert("New House", isPresented: $showAddHouse) {
                TextField("House name", text: $newHouseName)
                Button("Cancel", role: .cancel) {
                    newHouseName = ""
                }
                Button("Add") {
                    addHouse()
                }
            } message: {
                Text("Enter a name for the new house or property.")
            }
        }
    }

    private func addHouse() {
        let trimmed = newHouseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let house = House(name: trimmed)
        modelContext.insert(house)
        newHouseName = ""
    }

    private func deleteHouses(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(houses[index])
        }
    }
}

// MARK: - Unassigned House Detail View

struct UnassignedHouseDetailView: View {
    @Query(sort: \Item.name) private var allItems: [Item]
    @Query(sort: \Container.name) private var allContainers: [Container]

    private var unassignedItems: [Item] {
        allItems.filter { $0.container == nil && $0.location == nil && $0.house == nil }
    }

    private var unassignedContainers: [Container] {
        allContainers.filter { $0.parentContainer == nil && $0.location == nil && $0.house == nil }
    }

    @Environment(\.modelContext) private var modelContext
    @State private var selection: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @State private var showBatchMoveSheet = false
    @State private var showDeleteConfirmation = false

    private var hasContent: Bool {
        !unassignedItems.isEmpty || !unassignedContainers.isEmpty
    }

    /// Unified row model
    private enum ListEntry: Identifiable {
        case item(Item)
        case container(Container)

        var id: String {
            switch self {
            case .item(let item): return "item-\(item.persistentModelID.hashValue)"
            case .container(let container): return "container-\(container.persistentModelID.hashValue)"
            }
        }
    }

    private var entries: [ListEntry] {
        unassignedContainers.map { .container($0) } + unassignedItems.map { .item($0) }
    }

    private var selectedItems: [Item] {
        let ids = selection
        return entries.compactMap { entry in
            if case .item(let item) = entry, ids.contains(entry.id) {
                return item
            }
            return nil
        }
    }

    private var selectedContainers: [Container] {
        let ids = selection
        return entries.compactMap { entry in
            if case .container(let container) = entry, ids.contains(entry.id) {
                return container
            }
            return nil
        }
    }

    var body: some View {
        Group {
            if !hasContent {
                ContentUnavailableView {
                    Label("Nothing Unassigned", systemImage: "checkmark.circle")
                } description: {
                    Text("All items and containers have been assigned to locations.")
                }
            } else {
                List(selection: $selection) {
                    ForEach(entries) { entry in
                        switch entry {
                        case .container(let container):
                            NavigationLink(value: container) {
                                ContainerRow(container: container)
                            }
                        case .item(let item):
                            NavigationLink(value: item) {
                                ItemRow(item: item)
                            }
                        }
                    }

                    if editMode == .active && !selection.isEmpty {
                        Section {
                            Button {
                                showBatchMoveSheet = true
                            } label: {
                                Label("Move \(selection.count) Selected", systemImage: "arrow.right")
                            }

                            Button(role: .destructive) {
                                showDeleteConfirmation = true
                            } label: {
                                Label("Delete \(selection.count) Selected", systemImage: "trash")
                            }
                        }
                    }
                }
                .environment(\.editMode, $editMode)
            }
        }
        .navigationTitle("Unassigned")
        .toolbar {
            if hasContent {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editMode == .active ? "Done" : "Select") {
                        withAnimation {
                            if editMode == .active {
                                editMode = .inactive
                                selection.removeAll()
                            } else {
                                editMode = .active
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showBatchMoveSheet) {
            NavigationStack {
                BatchMoveView(
                    items: selectedItems,
                    containers: selectedContainers
                ) {
                    withAnimation {
                        editMode = .inactive
                        selection.removeAll()
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete \(selection.count) selected?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                deleteSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete the selected items and containers.")
        }
    }

    private func deleteSelected() {
        for item in selectedItems {
            modelContext.delete(item)
        }
        for container in selectedContainers {
            modelContext.delete(container)
        }
        withAnimation {
            editMode = .inactive
            selection.removeAll()
        }
    }
}

// MARK: - Row Views

private struct UnassignedHouseRow: View {
    let containerCount: Int
    let itemCount: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.fill.tertiary)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                Text("Unassigned")
                    .font(.headline)
                HStack(spacing: 12) {
                    if containerCount > 0 {
                        Label("\(containerCount) containers", systemImage: "archivebox")
                    }
                    if itemCount > 0 {
                        Label("\(itemCount) items", systemImage: "shippingbox")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct HouseRow: View {
    let house: House

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: house.photos, placeholderIcon: "house")

            VStack(alignment: .leading, spacing: 4) {
                Text(house.name)
                    .font(.headline)
                if let address = house.address, !address.isEmpty {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Label("\(house.locations.count) locations", systemImage: "mappin")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
