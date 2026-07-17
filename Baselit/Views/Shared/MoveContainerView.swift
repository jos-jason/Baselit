import SwiftUI
import SwiftData

private enum HouseSelection: Hashable {
    case none
    case unassigned
    case house(PersistentIdentifier)
}

struct MoveContainerView: View {
    let container: Container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var allUnassignedContainers: [Container] = []
    @State private var houseSelection: HouseSelection = .none
    /// Cascading location selections: index 0 = top-level, index 1 = sub-location, etc.
    @State private var locationSelections: [Location?] = [nil]
    @State private var selectedParentContainer: Container?
    @State private var errorMessage: String?

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

    /// Containers at the deepest selected location, excluding self and descendants
    private var availableContainers: [Container] {
        guard let location = deepestSelectedLocation else { return [] }
        return location.containers
            .filter { !isDescendantOrSelf($0) }
            .sorted(by: { $0.name < $1.name })
    }

    /// Top-level unassigned containers available as parent destinations (excluding self and descendants)
    private var unassignedContainerOptions: [Container] {
        allUnassignedContainers
            .filter { !isDescendantOrSelf($0) }
            .sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        Form {
            Section("Current Location") {
                Text(container.breadcrumbPath)
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
                    selectedParentContainer = nil
                }

                // Unassigned parent container picker
                if isUnassigned && !unassignedContainerOptions.isEmpty {
                    Picker("Parent Container (optional)", selection: $selectedParentContainer) {
                        Text("No parent container").tag(nil as Container?)
                        ForEach(unassignedContainerOptions) { c in
                            Text(c.name).tag(c as Container?)
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

                // Parent container picker at the deepest selected location
                if deepestSelectedLocation != nil {
                    Picker("Parent Container (optional)", selection: $selectedParentContainer) {
                        Text("Top level in location").tag(nil as Container?)
                        ForEach(availableContainers) { c in
                            Text(c.name).tag(c as Container?)
                        }
                    }
                }
            }

            if isUnassigned {
                Section("New Path") {
                    if let parent = selectedParentContainer {
                        Text("Unassigned › \(parent.name)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Unassigned")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if deepestSelectedLocation != nil || selectedParentContainer != nil {
                Section("New Path") {
                    Text(previewPath)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Move Container")
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
            if let house = container.resolvedHouse {
                houseSelection = .house(house.persistentModelID)
                // Rebuild cascading selections from the container's current location
                if let currentLocation = container.resolvedLocation {
                    let chain = locationChain(for: currentLocation)
                    locationSelections = chain.map { $0 as Location? }
                    // Add a nil slot if the deepest location has sub-locations
                    if let deepest = chain.last, !deepest.subLocations.isEmpty {
                        locationSelections.append(nil)
                    }
                }
                selectedParentContainer = container.parentContainer
            } else if container.parentContainer == nil && container.location == nil && container.house == nil {
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
                // Reset parent container when location changes
                selectedParentContainer = nil
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
        if let parent = selectedParentContainer {
            var containerPath: [String] = [parent.name]
            var current = parent.parentContainer
            while let p = current {
                containerPath.insert(p.name, at: 0)
                current = p.parentContainer
            }
            components.append(contentsOf: containerPath)
        }
        return components.joined(separator: " › ")
    }

    private func isDescendantOrSelf(_ other: Container) -> Bool {
        if other.persistentModelID == container.persistentModelID { return true }
        var current = other.parentContainer
        while let c = current {
            if c.persistentModelID == container.persistentModelID { return true }
            current = c.parentContainer
        }
        return false
    }

    private func performMove() {
        let targetParent: Container?
        let targetLocation: Location?
        let targetHouse: House?

        if isUnassigned {
            targetParent = selectedParentContainer
            targetLocation = nil
            targetHouse = nil
        } else {
            targetParent = selectedParentContainer
            targetLocation = selectedParentContainer == nil ? deepestSelectedLocation : nil
            targetHouse = selectedHouse
        }

        do {
            try ContainerService.moveContainer(
                container,
                toParent: targetParent,
                inLocation: targetLocation,
                inHouse: targetHouse
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
