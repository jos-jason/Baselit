import SwiftUI
import SwiftData

struct SearchTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var selectedHouse: House?
    @State private var selectedCategory: ItemCategory?
    @State private var selectedColor: ItemColor?
    @State private var searchResults: [Item] = []
    @State private var hasSearched = false

    var body: some View {
        NavigationStack {
            Group {
                if !hasSearched && searchText.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Search Items",
                        message: "Type to search across all your items by name, description, notes, brand, or model."
                    )
                } else if searchResults.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "No items matched your search."
                    )
                } else {
                    List(searchResults) { item in
                        NavigationLink(value: item) {
                            SearchResultRow(item: item)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search items...")
            .onChange(of: searchText) { performSearch() }
            .onChange(of: selectedHouse) { performSearch() }
            .onChange(of: selectedCategory) { performSearch() }
            .onChange(of: selectedColor) { performSearch() }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                SearchFilterView(
                    selectedHouse: $selectedHouse,
                    selectedCategory: $selectedCategory,
                    selectedColor: $selectedColor
                )
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .navigationTitle("Search")
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if selectedHouse != nil { count += 1 }
        if selectedCategory != nil { count += 1 }
        if selectedColor != nil { count += 1 }
        return count
    }

    private func performSearch() {
        hasSearched = true
        do {
            searchResults = try InventoryService.searchItems(
                query: searchText,
                house: selectedHouse,
                category: selectedCategory,
                color: selectedColor,
                in: modelContext
            )
        } catch {
            searchResults = []
        }
    }
}
