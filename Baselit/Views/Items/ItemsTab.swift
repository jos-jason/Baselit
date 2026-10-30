import SwiftUI
import SwiftData

enum ItemSortOrder: String, CaseIterable {
    case name = "Name"
    case recentlyUpdated = "Recently Updated"
}

enum ItemsFilter: Hashable {
    case all            // Items + Containers
    case itemsOnly      // Items only (no containers)
    case uncontained    // Items & containers not inside a container
}

struct ItemsTab: View {
    @Query(sort: \Item.name) private var allItems: [Item]
    @Query(sort: \Container.name) private var allContainers: [Container]
    @State private var sortOrder: ItemSortOrder = .name
    @State private var activeFilter: ItemsFilter = .all
    @State private var selection: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @State private var showBatchMoveSheet = false
    @State private var showAddItem = false

    /// Unified row model for the list
    private enum ListEntry: Identifiable {
        case item(Item)
        case container(Container)

        var id: String {
            switch self {
            case .item(let item): return "item-\(item.persistentModelID.hashValue)"
            case .container(let container): return "container-\(container.persistentModelID.hashValue)"
            }
        }

        var name: String {
            switch self {
            case .item(let item): return item.name
            case .container(let container): return container.name
            }
        }

        var updatedAt: Date {
            switch self {
            case .item(let item): return item.updatedAt
            case .container(let container): return container.updatedAt
            }
        }
    }

    private var entries: [ListEntry] {
        var result: [ListEntry] = []

        switch activeFilter {
        case .all:
            result = allItems.map { .item($0) } + allContainers.map { .container($0) }
        case .itemsOnly:
            result = allItems.map { .item($0) }
        case .uncontained:
            result = allItems.filter { $0.container == nil }.map { .item($0) }
                   + allContainers.filter { $0.parentContainer == nil }.map { .container($0) }
        }

        switch sortOrder {
        case .name:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .recentlyUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        }

        return result
    }

    private var isEmpty: Bool {
        allItems.isEmpty && allContainers.isEmpty
    }

    private var filterLabel: String {
        switch activeFilter {
        case .all: return "All (Items & Containers)"
        case .itemsOnly: return "Items Only"
        case .uncontained: return "Not in a Container"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isEmpty {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "No Items",
                        message: "Add items from a location or container to start tracking."
                    )
                } else {
                    List(entries, selection: $selection) { entry in
                        switch entry {
                        case .item(let item):
                            NavigationLink(value: item) {
                                ItemRow(item: item)
                            }
                        case .container(let container):
                            NavigationLink(value: container) {
                                ContainerRow(container: container)
                            }
                        }
                    }
                    .environment(\.editMode, $editMode)
                    .safeAreaInset(edge: .bottom) {
                        if editMode == .active {
                            Button {
                                showBatchMoveSheet = true
                            } label: {
                                Label("Move \(selection.count) to Container…", systemImage: "arrow.right")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding()
                            .disabled(selection.isEmpty)
                        }
                    }
                }
            }
            .navigationTitle("Items")
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .navigationDestination(for: Container.self) { container in
                ContainerDetailView(container: container)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Picker("Sort by", selection: $sortOrder) {
                            ForEach(ItemSortOrder.allCases, id: \.self) { order in
                                Text(order.rawValue).tag(order)
                            }
                        }
                        Divider()
                        Menu("Filter") {
                            Button {
                                activeFilter = .all
                            } label: {
                                HStack {
                                    Text("All (Items & Containers)")
                                    if case .all = activeFilter { Image(systemName: "checkmark") }
                                }
                            }
                            Button {
                                activeFilter = .itemsOnly
                            } label: {
                                HStack {
                                    Text("Items Only")
                                    if case .itemsOnly = activeFilter { Image(systemName: "checkmark") }
                                }
                            }
                            Button {
                                activeFilter = .uncontained
                            } label: {
                                HStack {
                                    Text("Not in a Container")
                                    if case .uncontained = activeFilter { Image(systemName: "checkmark") }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: {
                            if case .all = activeFilter { return "line.3.horizontal.decrease.circle" }
                            return "line.3.horizontal.decrease.circle.fill"
                        }())
                    }
                }

                ToolbarItem(placement: .topBarLeading) {
                    if !isEmpty {
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
            .sheet(isPresented: $showAddItem) {
                NavigationStack {
                    ItemFormView()
                }
            }
        }
    }

    // MARK: - Selection Helpers

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
}
