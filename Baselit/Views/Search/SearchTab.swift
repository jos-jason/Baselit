import SwiftUI
import SwiftData

struct SearchTab: View {
    @Environment(\.modelContext) private var modelContext
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var selectedHouse: House?
    @State private var matchingHouses: [House] = []
    @State private var matchingLocations: [Location] = []
    @State private var matchingContainers: [Container] = []
    @State private var matchingItems: [Item] = []
    @State private var navigationPath = NavigationPath()
    @State private var showQRScanner = false
    @State private var showScanError = false
    @State private var scanErrorMessage = ""
    @State private var showSettings = false
    @State private var bubbleEntries: [BubbleEntry] = []

    private var hasActiveFilters: Bool {
        selectedHouse != nil
    }

    private var hasAnyResults: Bool {
        !matchingHouses.isEmpty || !matchingLocations.isEmpty ||
        !matchingContainers.isEmpty || !matchingItems.isEmpty
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if searchText.isEmpty {
                    if bubbleEntries.isEmpty && !hasActiveFilters {
                        ContentUnavailableView {
                            Label("Search", systemImage: "magnifyingglass")
                        } description: {
                            Text("Search across houses, locations, containers, and items.")
                        }
                    } else if bubbleEntries.isEmpty && hasActiveFilters {
                        filteredNoResultsView
                    } else {
                        BubbleGridView(entries: bubbleEntries) { destination in
                            switch destination {
                            case .item(let item):
                                navigationPath.append(item)
                            case .container(let container):
                                navigationPath.append(container)
                            }
                        }
                    }
                } else if !hasAnyResults {
                    if hasActiveFilters {
                        filteredNoResultsView
                    } else {
                        ContentUnavailableView {
                            Label("No Results", systemImage: "magnifyingglass")
                        } description: {
                            Text("Nothing matched your search.")
                        }
                    }
                } else {
                    List {
                        if !matchingHouses.isEmpty {
                            Section("Houses") {
                                ForEach(matchingHouses) { house in
                                    NavigationLink(value: house) {
                                        HouseSearchRow(house: house)
                                    }
                                }
                            }
                        }

                        if !matchingLocations.isEmpty {
                            Section("Locations") {
                                ForEach(matchingLocations) { location in
                                    NavigationLink(value: location) {
                                        LocationSearchRow(location: location)
                                    }
                                }
                            }
                        }

                        if !matchingContainers.isEmpty {
                            Section("Containers") {
                                ForEach(matchingContainers) { container in
                                    NavigationLink(value: container) {
                                        ContainerSearchRow(container: container)
                                    }
                                }
                            }
                        }

                        if !matchingItems.isEmpty {
                            Section("Items") {
                                ForEach(matchingItems) { item in
                                    NavigationLink(value: item) {
                                        SearchResultRow(item: item)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search everything...")
            .onChange(of: searchText) {
                    if searchText.isEmpty {
                        matchingHouses = []
                        matchingLocations = []
                        matchingContainers = []
                        matchingItems = []
                    } else {
                        performSearch()
                    }
                }
            .onChange(of: selectedHouse) {
                loadBubbleEntries()
                performSearch()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showQRScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showFilters = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                SearchFilterView(selectedHouse: $selectedHouse)
            }
            .fullScreenCover(isPresented: $showQRScanner) {
                QRScannerView { scannedValue in
                    handleScannedCode(scannedValue)
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showSettings) {
                SettingsSheet()
            }
            .alert("Scan Error", isPresented: $showScanError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(scanErrorMessage)
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
            .navigationTitle("Search")
            .onAppear { loadBubbleEntries() }
        }
    }

    /// Shown when filters hide every result, with a way to widen the search
    private var filteredNoResultsView: some View {
        ContentUnavailableView {
            Label("No Results", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("Nothing matched in \(selectedHouse?.name ?? "this house"). Switch back to All Houses to search everywhere.")
        } actions: {
            Button("Show All Houses") {
                selectedHouse = nil
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func handleScannedCode(_ code: String) {
        do {
            let result = try InventoryService.lookupByQRPayload(code, in: modelContext)
            switch result {
            case .container(let container):
                navigationPath.append(container)
            case .item(let item):
                navigationPath.append(item)
            case .notFound:
                scanErrorMessage = "No matching container or item found for this QR code."
                showScanError = true
            case .invalidFormat:
                scanErrorMessage = "This QR code is not a Baselit label."
                showScanError = true
            }
        } catch {
            scanErrorMessage = "Failed to look up QR code: \(error.localizedDescription)"
            showScanError = true
        }
    }

    private func performSearch() {
        do {
            matchingHouses = try InventoryService.searchHouses(
                query: searchText, house: selectedHouse, in: modelContext
            )
            matchingLocations = try InventoryService.searchLocations(
                query: searchText, house: selectedHouse, in: modelContext
            )
            matchingContainers = try InventoryService.searchContainers(
                query: searchText, house: selectedHouse, in: modelContext
            )
            matchingItems = try InventoryService.searchItems(
                query: searchText,
                house: selectedHouse,
                in: modelContext
            )
        } catch {
            matchingHouses = []
            matchingLocations = []
            matchingContainers = []
            matchingItems = []
        }
    }

    private func loadBubbleEntries() {
        do {
            var items = try InventoryService.allItems(in: modelContext)
            var containers = try InventoryService.allContainers(in: modelContext)

            // Apply active filters to bubble entries
            if let selectedHouse {
                items = items.filter { $0.resolvedHouse?.persistentModelID == selectedHouse.persistentModelID }
                containers = containers.filter { $0.resolvedHouse?.persistentModelID == selectedHouse.persistentModelID }
            }

            var entries: [BubbleEntry] = []

            for item in items {
                entries.append(BubbleEntry(
                    id: "item-\(item.persistentModelID.hashValue)",
                    name: item.name,
                    photos: item.photos,
                    placeholderIcon: "shippingbox",
                    destination: .item(item)
                ))
            }

            for container in containers {
                entries.append(BubbleEntry(
                    id: "container-\(container.persistentModelID.hashValue)",
                    name: container.name,
                    photos: container.photos,
                    placeholderIcon: "archivebox",
                    destination: .container(container)
                ))
            }

            bubbleEntries = entries.shuffled()
        } catch {
            bubbleEntries = []
        }
    }
}

// MARK: - Search Row Views

private struct HouseSearchRow: View {
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

private struct LocationSearchRow: View {
    let location: Location

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: location.photos, placeholderIcon: "mappin")
            VStack(alignment: .leading, spacing: 4) {
                Text(location.name)
                    .font(.headline)
                let parentComponents = location.breadcrumbComponents.dropLast()
                if !parentComponents.isEmpty {
                    BreadcrumbView(components: Array(parentComponents))
                }
                HStack(spacing: 12) {
                    if !location.subLocations.isEmpty {
                        Label("\(location.subLocations.count) sub-locations", systemImage: "mappin")
                    }
                    Label("\(location.containers.count) containers", systemImage: "archivebox")
                    Label("\(location.items.count) items", systemImage: "shippingbox")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ContainerSearchRow: View {
    let container: Container

    var body: some View {
        HStack(spacing: 12) {
            ThumbnailView(photos: container.photos, placeholderIcon: "archivebox")
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)
                BreadcrumbView(components: container.breadcrumbComponents.dropLast().map { $0 })
                HStack(spacing: 12) {
                    if !container.subContainers.isEmpty {
                        Label("\(container.subContainers.count) sub-containers", systemImage: "archivebox")
                    }
                    Label("\(container.items.count) items", systemImage: "shippingbox")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
