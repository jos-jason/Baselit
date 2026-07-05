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
    @State private var selectedLocation: Location?
    @State private var selectedParentContainer: Container?
    @State private var errorMessage: String?

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
                Picker("House", selection: $houseSelection) {
                    Text("Select house...").tag(HouseSelection.none)
                    Text("Unassigned").tag(HouseSelection.unassigned)
                    ForEach(houses) { house in
                        Text(house.name).tag(HouseSelection.house(house.persistentModelID))
                    }
                }
                .onChange(of: houseSelection) {
                    selectedLocation = nil
                    selectedParentContainer = nil
                }

                if isUnassigned && !unassignedContainerOptions.isEmpty {
                    Picker("Parent Container (optional)", selection: $selectedParentContainer) {
                        Text("No parent container").tag(nil as Container?)
                        ForEach(unassignedContainerOptions) { c in
                            Text(c.name).tag(c as Container?)
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
                        selectedParentContainer = nil
                    }
                }

                if selectedLocation != nil {
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
            if let house = container.resolvedHouse {
                houseSelection = .house(house.persistentModelID)
                selectedLocation = container.resolvedLocation
                selectedParentContainer = container.parentContainer
            } else if container.parentContainer == nil && container.location == nil {
                houseSelection = .unassigned
            }
        }
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

        if isUnassigned {
            targetParent = selectedParentContainer
            targetLocation = nil
        } else {
            targetParent = selectedParentContainer
            targetLocation = selectedParentContainer == nil ? selectedLocation : nil
        }

        do {
            try ContainerService.moveContainer(
                container,
                toParent: targetParent,
                inLocation: targetLocation
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
