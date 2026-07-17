import SwiftUI
import SwiftData

private enum HouseSelection: Hashable {
    case none
    case unassigned
    case house(PersistentIdentifier)
}

struct MoveItemView: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var allUnassignedContainers: [Container] = []
    @State private var houseSelection: HouseSelection = .none
    /// Cascading location selections: index 0 = top-level, index 1 = sub-location, etc.
    @State private var locationSelections: [Location?] = [nil]
    @State private var selectedContainer: Container?

    private var selectedHouse: House? {
        guard case .house(let id) = houseSelection else { return nil }
        return houses.first { $0.persistentModelID == id }
    }

    private var isUnassigned: Bool {
        houseSelection == .unassigned
    }

    /// The deepest selected location across all cascading pickers
    private var deepestSelectedLocation: Location? {
        locationSelections.compactMap { $0 }.last
    }

    /// Top-level locations for the selected house
    private var topLevelLocations: [Location] {
        selectedHouse?.locations
            .filter { $0.parentLocation == nil }
            .sorted(by: { $0.name < $1.name }) ?? []
    }

    /// Sub-locations available at a given depth (children of the selection at depth-1)
    private func subLocations(atDepth depth: Int) -> [Location] {
        guard depth > 0, depth <= locationSelections.count,
              let parent = locationSelections[depth - 1] else { return [] }
        return parent.subLocations.sorted(by: { $0.name < $1.name })
    }

    /// Containers at the deepest selected location
    private var availableContainers: [Container] {
        guard let location = deepestSelectedLocation else { return [] }
        return location.containers.sorted(by: { $0.name < $1.name })
    }

    /// Top-level unassigned containers available as destinations
    private var unassignedContainerOptions: [Container] {
        allUnassignedContainers.sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        Form {
            Section("Current Location") {
                Text(item.breadcrumbPath)
                    .foregroundStyle(.secondary)
            }

            Section("Move To") {
                // House picker
                Picker("House", selection: $houseSelection) {
                    Text("Select house...").tag(HouseSelection.none)
                    Text("Unassigned").tag(HouseSelection.unassigned)
                    ForEach(houses) { house in
                        Text(house.name).tag(HouseSelection.house(house.persistentModelID))
                    }
                }
                .onChange(of: houseSelection) {
                    locationSelections = [nil]
                    selectedContainer = nil
                }

                // Unassigned container picker
                if isUnassigned && !unassignedContainerOptions.isEmpty {
                    Picker("Container (optional)", selection: $selectedContainer) {
                        Text("No container").tag(nil as Container?)
                        ForEach(unassignedContainerOptions) { container in
                            Text(container.name).tag(container as Container?)
                        }
                        ForEach(nestedUnassignedContainers()) { container in
                            Text(indentedName(for: container)).tag(container as Container?)
                        }
                    }
                }

                // Cascading location pickers
                if selectedHouse != nil {
                    // Top-level location picker
                    locationPicker(atDepth: 0, label: "Location", locations: topLevelLocations)

                    // Sub-location pickers for each level that has a selection with children
                    ForEach(1..<locationSelections.count, id: \.self) { depth in
                        let subs = subLocations(atDepth: depth)
                        if !subs.isEmpty {
                            locationPicker(atDepth: depth, label: subLocationLabel(depth: depth), locations: subs)
                        }
                    }
                }

                // Container picker at the deepest selected location
                if deepestSelectedLocation != nil {
                    Picker("Container (optional)", selection: $selectedContainer) {
                        Text("Directly in location").tag(nil as Container?)
                        ForEach(availableContainers) { container in
                            Text(container.name).tag(container as Container?)
                        }
                        ForEach(nestedContainers()) { container in
                            Text(indentedName(for: container)).tag(container as Container?)
                        }
                    }
                }
            }

            if isUnassigned {
                Section("New Path") {
                    if let container = selectedContainer {
                        Text("Unassigned › \(container.name)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unassigned")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if deepestSelectedLocation != nil || selectedContainer != nil {
                Section("New Path") {
                    Text(previewPath)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Move Item")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Move") {
                    performMove()
                }
                .disabled(!isUnassigned && selectedHouse == nil)
            }
        }
        .onAppear {
            do {
                houses = try InventoryService.allHouses(in: modelContext)
                let allContainers = try InventoryService.allContainers(in: modelContext)
                allUnassignedContainers = allContainers.filter {
                    $0.parentContainer == nil && $0.location == nil && $0.house == nil
                }
            } catch {
                houses = []
                allUnassignedContainers = []
            }
            if let house = item.resolvedHouse {
                houseSelection = .house(house.persistentModelID)
                // Rebuild cascading selections from the item's current location
                if let currentLocation = item.container?.resolvedLocation ?? item.location {
                    let chain = locationChain(for: currentLocation)
                    locationSelections = chain.map { $0 as Location? }
                    // Add a nil slot if the deepest location has sub-locations
                    if let deepest = chain.last, !deepest.subLocations.isEmpty {
                        locationSelections.append(nil)
                    }
                }
                selectedContainer = item.container
            } else if item.container == nil && item.location == nil && item.house == nil {
                houseSelection = .unassigned
            }
        }
    }

    /// Build a picker for a specific depth in the location hierarchy
    private func locationPicker(atDepth depth: Int, label: String, locations: [Location]) -> some View {
        let binding = Binding<Location?>(
            get: {
                guard depth < locationSelections.count else { return nil }
                return locationSelections[depth]
            },
            set: { newValue in
                // Update the selection at this depth
                if depth < locationSelections.count {
                    locationSelections[depth] = newValue
                }
                // Remove any deeper selections
                if locationSelections.count > depth + 1 {
                    locationSelections.removeSubrange((depth + 1)...)
                }
                // If the new selection has sub-locations, add a nil slot for the next level
                if let loc = newValue, !loc.subLocations.isEmpty {
                    locationSelections.append(nil)
                }
                // Reset container when location changes
                selectedContainer = nil
            }
        )

        return Picker(label, selection: binding) {
            Text(depth == 0 ? "Select location..." : "None").tag(nil as Location?)
            ForEach(locations) { loc in
                Text(loc.name).tag(loc as Location?)
            }
        }
    }

    /// Returns a label like "Sub-location" or "Sub-sub-location" based on depth
    private func subLocationLabel(depth: Int) -> String {
        let prefix = String(repeating: "Sub-", count: depth)
        return prefix + "location"
    }

    /// Builds the chain of locations from top-level down to the given location
    private func locationChain(for location: Location) -> [Location] {
        var chain: [Location] = [location]
        var current = location.parentLocation
        while let parent = current {
            chain.insert(parent, at: 0)
            current = parent.parentLocation
        }
        return chain
    }

    private var previewPath: String {
        var components: [String] = []
        if let location = deepestSelectedLocation {
            components = location.breadcrumbComponents
        } else if let house = selectedHouse {
            components.append(house.name)
        }
        if let container = selectedContainer {
            var containerPath: [String] = [container.name]
            var current = container.parentContainer
            while let parent = current {
                containerPath.insert(parent.name, at: 0)
                current = parent.parentContainer
            }
            components.append(contentsOf: containerPath)
        }
        return components.joined(separator: " › ")
    }

    private func nestedUnassignedContainers() -> [Container] {
        var result: [Container] = []
        for container in unassignedContainerOptions {
            collectNested(container: container, into: &result)
        }
        return result
    }

    private func nestedContainers() -> [Container] {
        var result: [Container] = []
        for container in availableContainers {
            collectNested(container: container, into: &result)
        }
        return result
    }

    private func collectNested(container: Container, into result: inout [Container]) {
        for sub in container.subContainers.sorted(by: { $0.name < $1.name }) {
            result.append(sub)
            collectNested(container: sub, into: &result)
        }
    }

    private func indentedName(for container: Container) -> String {
        var depth = 0
        var current = container.parentContainer
        while current != nil {
            depth += 1
            current = current?.parentContainer
        }
        return String(repeating: "  ", count: depth) + container.name
    }

    private func performMove() {
        let targetContainer: Container?
        let targetLocation: Location?
        let targetHouse: House?

        if isUnassigned {
            targetContainer = selectedContainer
            targetLocation = nil
            targetHouse = nil
        } else {
            targetContainer = selectedContainer
            targetLocation = selectedContainer == nil ? deepestSelectedLocation : nil
            targetHouse = selectedHouse
        }

        ContainerService.moveItem(
            item,
            toContainer: targetContainer,
            toLocation: targetLocation,
            toHouse: targetHouse
        )
        dismiss()
    }
}
