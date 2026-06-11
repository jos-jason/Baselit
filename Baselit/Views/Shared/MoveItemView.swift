import SwiftUI
import SwiftData

struct MoveItemView: View {
    let item: Item
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var selectedHouse: House?
    @State private var selectedLocation: Location?
    @State private var selectedContainer: Container?
    @State private var allContainers: [Container] = []

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    private var availableContainers: [Container] {
        guard let location = selectedLocation else { return [] }
        // Show containers at this location and their nested children
        return location.containers.sorted(by: { $0.name < $1.name })
    }

    var body: some View {
        Form {
            Section("Current Location") {
                Text(item.breadcrumbPath)
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
                    selectedContainer = nil
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
                        // Also show nested containers
                        ForEach(nestedContainers()) { container in
                            Text(indentedName(for: container)).tag(container as Container?)
                        }
                    }
                }
            }

            if selectedLocation != nil || selectedContainer != nil {
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
                .disabled(selectedLocation == nil)
            }
        }
        .onAppear {
            do {
                houses = try InventoryService.allHouses(in: modelContext)
            } catch {
                houses = []
            }
            // Pre-select current house and location
            selectedHouse = item.resolvedHouse
            selectedLocation = item.container?.resolvedLocation ?? item.location
            selectedContainer = item.container
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
            // Build container path
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
        let indent = String(repeating: "  ", count: depth)
        return indent + container.name
    }

    private func performMove() {
        ContainerService.moveItem(
            item,
            toContainer: selectedContainer,
            toLocation: selectedContainer == nil ? selectedLocation : nil
        )
        dismiss()
    }
}
