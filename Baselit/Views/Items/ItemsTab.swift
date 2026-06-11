import SwiftUI
import SwiftData

enum ItemSortOrder: String, CaseIterable {
    case name = "Name"
    case recentlyUpdated = "Recently Updated"
    case category = "Category"
}

struct ItemsTab: View {
    @Query(sort: \Item.name) private var allItems: [Item]
    @State private var sortOrder: ItemSortOrder = .name
    @State private var filterCategory: ItemCategory?

    private var sortedItems: [Item] {
        var items = allItems
        if let filterCategory {
            items = items.filter { $0.category == filterCategory }
        }
        switch sortOrder {
        case .name:
            return items.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .recentlyUpdated:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .category:
            return items.sorted {
                let cat0 = $0.category?.displayName ?? "zzz"
                let cat1 = $1.category?.displayName ?? "zzz"
                return cat0 < cat1
            }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if allItems.isEmpty {
                    EmptyStateView(
                        icon: "shippingbox",
                        title: "No Items",
                        message: "Add items from a location or container to start tracking."
                    )
                } else {
                    List(sortedItems) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }
            .navigationTitle("Items")
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
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
                        Menu("Filter by Category") {
                            Button("All Categories") {
                                filterCategory = nil
                            }
                            ForEach(ItemCategory.allCases) { cat in
                                Button(cat.displayName) {
                                    filterCategory = cat
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }
}
