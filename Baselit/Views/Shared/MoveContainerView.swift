import SwiftUI
import SwiftData

struct MoveContainerView: View {
    let container: Container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var selectedHouse: House?
    @State private var selectedLocation: Location?
    @State private var selectedParentContainer: Container?
    @State private var errorMessage: String?

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    private var availableContainers: [Container] {
        guard let location = selectedLocation else { return [] }
        // Show containers at this location, excluding self and descendants
        return location.containers
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
                Picker("House", selection: $selectedHouse) {
                    Text("Select house...").tag(nil as House?)
                    ForEach(houses) { house in
                        Text(house.name).tag(house as House?)
                    }
                }
                .onChange(of: selectedHouse) {
                    selectedLocation = nil
                    selectedParentContainer = nil
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
                .disabled(selectedLocation == nil)
            }
        }
        .onAppear {
            do {
                houses = try InventoryService.allHouses(in: modelContext)
            } catch {
                houses = []
            }
            selectedHouse = container.resolvedHouse
            selectedLocation = container.resolvedLocation
            selectedParentContainer = container.parentContainer
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
        do {
            try ContainerService.moveContainer(
                container,
                toParent: selectedParentContainer,
                inLocation: selectedParentContainer == nil ? selectedLocation : nil
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
