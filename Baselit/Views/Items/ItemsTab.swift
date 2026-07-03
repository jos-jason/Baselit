import SwiftUI
import SwiftData

enum ItemSortOrder: String, CaseIterable {
    case name = "Name"
    case recentlyUpdated = "Recently Updated"
    case category = "Category"
}

enum ItemsFilter: Hashable {
    case all            // Items + Containers
    case itemsOnly      // Items only (no containers)
    case category(ItemCategory) // Specific category (items only)
}

struct ItemsTab: View {
    @Query(sort: \Item.name) private var allItems: [Item]
    @Query(sort: \Container.name) private var allContainers: [Container]
    @State private var sortOrder: ItemSortOrder = .name
    @State private var activeFilter: ItemsFilter = .all

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

        var categoryName: String {
            switch self {
            case .item(let item): return item.category?.displayName ?? "zzz"
            case .container: return "Container"
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
        case .category(let category):
            result = allItems.filter { $0.category == category }.map { .item($0) }
        }

        switch sortOrder {
        case .name:
            result.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .recentlyUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .category:
            result.sort { $0.categoryName < $1.categoryName }
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
        case .category(let cat): return cat.displayName
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
                    List(entries) { entry in
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
                            Divider()
                            ForEach(ItemCategory.allCases) { cat in
                                Button {
                                    activeFilter = .category(cat)
                                } label: {
                                    HStack {
                                        Text(cat.displayName)
                                        if case .category(let active) = activeFilter, active == cat {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: activeFilter is ItemsFilter ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}
