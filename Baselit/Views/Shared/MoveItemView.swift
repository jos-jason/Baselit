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
    @State private var selectedLocation: Location?
    @State private var selectedContainer: Container?

    private var selectedHouse: House? {
        guard case .house(let id) = houseSelection else { return nil }
        return houses.first { $0.persistentModelID == id }
    }

    private var isUnassigned: Bool {
        houseSelection == .unassigned
    }

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    private var availableContainers: [Container] {
        guard let location = selectedLocation else { return [] }
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
                .disabled(!isUnassigned && selectedLocation == nil)
            }
        }
        .onAppear {
            do {
                houses = try InventoryService.allHouses(in: modelContext)
                let allContainers = try InventoryService.allContainers(in: modelContext)
                allUnassignedContainers = allContainers.filter {
                    $0.parentContainer == nil && $0.location == nil
                }
            } catch {
                houses = []
                allUnassignedContainers = []
            }
            if let house = item.resolvedHouse {
                houseSelection = .house(house.persistentModelID)
                selectedLocation = item.container?.resolvedLocation ?? item.location
                selectedContainer = item.container
            } else if item.container == nil && item.location == nil {
                houseSelection = .unassigned
            }
        }
    }

    private var previewPath: String {
        var components: [String] = []
        if let house = selectedHouse {
            components.append(house.name)
        }
        if let location = selectedLocation {
            components.append(location.name)
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

        if isUnassigned {
            targetContainer = selectedContainer
            targetLocation = nil
        } else {
            targetContainer = selectedContainer
            targetLocation = selectedContainer == nil ? selectedLocation : nil
        }

        ContainerService.moveItem(
            item,
            toContainer: targetContainer,
            toLocation: targetLocation
        )
        dismiss()
    }
}
