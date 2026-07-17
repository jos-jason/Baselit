import SwiftUI
import SwiftData

/// Represents the house selection in move destination pickers.
/// Allows "Unassigned" to appear alongside real houses in a single Picker.
private enum HouseSelection: Hashable {
    case none
    case unassigned
    case house(PersistentIdentifier)
}

struct BatchMoveView: View {
    let items: [Item]
    let containers: [Container]
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var allUnassignedContainers: [Container] = []
    @State private var houseSelection: HouseSelection = .none
    @State private var selectedLocation: Location?
    @State private var selectedContainer: Container?
    @State private var errorMessage: String?

    private var totalCount: Int {
        items.count + containers.count
    }

    private var selectedHouse: House? {
        guard case .house(let id) = houseSelection else { return nil }
        return houses.first { $0.persistentModelID == id }
    }

    private var isUnassigned: Bool {
        houseSelection == .unassigned
    }

    private var availableLocations: [Location] {
        selectedHouse?.locations
            .filter { $0.parentLocation == nil }
            .sorted(by: { $0.name < $1.name }) ?? []
    }

    private var movingContainerIDs: Set<PersistentIdentifier> {
        Set(containers.map(\.persistentModelID))
    }

    private var availableContainers: [Container] {
        guard let location = selectedLocation else { return [] }
        return location.containers
            .filter { !isExcluded($0) }
            .sorted(by: { $0.name < $1.name })
    }

    /// Top-level unassigned containers available as destinations
    private var unassignedContainerOptions: [Container] {
        allUnassignedContainers
            .filter { !isExcluded($0) }
            .sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        Form {
            Section("Moving \(totalCount) item\(totalCount == 1 ? "" : "s")") {
                if !items.isEmpty {
                    Label("\(items.count) item\(items.count == 1 ? "" : "s")",
                          systemImage: "shippingbox")
                }
                if !containers.isEmpty {
                    Label("\(containers.count) container\(containers.count == 1 ? "" : "s")",
                          systemImage: "archivebox")
                }
            }

            Section("Destination") {
                Picker("House", selection: $houseSelection) {
                    Text("Select house...").tag(HouseSelection.none)
                    Text("Unassigned").tag(HouseSelection.unassigned)
                    ForEach(houses) { house in
                        Text(house.name).tag(HouseSelection.house(house.persistentModelID))
                    }
                }
                .onChange(of: houseSelection) {
                    selectedLocation = nil
                    selectedContainer = nil
                }

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

                if selectedHouse != nil {
                    Picker("Location", selection: $selectedLocation) {
                        Text("Select location...").tag(nil as Location?)
                        ForEach(availableLocations) { loc in
                            Text(loc.name).tag(loc as Location?)
                        }
                        ForEach(nestedLocations()) { loc in
                            Text(indentedLocationName(for: loc)).tag(loc as Location?)
                        }
                    }
                    .onChange(of: selectedLocation) {
                        selectedContainer = nil
                    }
                }

                if selectedLocation != nil {
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
            } else if selectedLocation != nil || selectedContainer != nil {
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
        .navigationTitle("Move to Container")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Move") { performBatchMove() }
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
        }
    }

    // MARK: - Path Preview

    private var previewPath: String {
        var components: [String] = []
        if let location = selectedLocation {
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

    // MARK: - Container Filtering

    private func isExcluded(_ container: Container) -> Bool {
        if movingContainerIDs.contains(container.persistentModelID) {
            return true
        }
        for moving in containers {
            if isDescendant(container, of: moving) {
                return true
            }
        }
        return false
    }

    private func isDescendant(_ candidate: Container, of ancestor: Container) -> Bool {
        var current: Container? = candidate.parentContainer
        while let c = current {
            if c.persistentModelID == ancestor.persistentModelID { return true }
            current = c.parentContainer
        }
        return false
    }

    private func nestedLocations() -> [Location] {
        var result: [Location] = []
        for location in availableLocations {
            collectNestedLocations(location: location, into: &result)
        }
        return result
    }

    private func collectNestedLocations(location: Location, into result: inout [Location]) {
        for sub in location.subLocations.sorted(by: { $0.name < $1.name }) {
            result.append(sub)
            collectNestedLocations(location: sub, into: &result)
        }
    }

    private func indentedLocationName(for location: Location) -> String {
        var depth = 0
        var current = location.parentLocation
        while current != nil {
            depth += 1
            current = current?.parentLocation
        }
        return String(repeating: "  ", count: depth) + location.name
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
            guard !isExcluded(sub) else { continue }
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

    // MARK: - Perform Move

    private func performBatchMove() {
        let targetContainer: Container?
        let targetLocation: Location?
        let targetHouse: House?

        if isUnassigned {
            targetContainer = selectedContainer  // may be an unassigned container or nil
            targetLocation = nil
            targetHouse = nil
        } else {
            targetContainer = selectedContainer
            targetLocation = selectedContainer == nil ? selectedLocation : nil
            targetHouse = selectedHouse
        }

        for item in items {
            ContainerService.moveItem(
                item,
                toContainer: targetContainer,
                toLocation: targetLocation,
                toHouse: targetHouse
            )
        }

        for container in containers {
            do {
                try ContainerService.moveContainer(
                    container,
                    toParent: targetContainer,
                    inLocation: targetLocation,
                    inHouse: targetHouse
                )
            } catch {
                errorMessage = "Failed to move \(container.name): \(error.localizedDescription)"
                return
            }
        }

        dismiss()
        onComplete()
    }
}
