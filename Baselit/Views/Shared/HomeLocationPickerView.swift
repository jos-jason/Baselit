import SwiftUI
import SwiftData

struct HomeLocationPickerView: View {
    /// IDs of houses that already have a home location for this owner
    let existingHouseIDs: Set<PersistentIdentifier>
    let onSave: (House, Location?, Container?) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var selectedHouse: House?
    /// Cascading location selections: index 0 = top-level, index 1 = sub-location, etc.
    @State private var locationSelections: [Location?] = [nil]
    @State private var selectedContainer: Container?

    /// Houses that don't already have a home location entry
    private var availableHouses: [House] {
        houses
            .filter { !existingHouseIDs.contains($0.persistentModelID) }
            .sorted(by: { $0.name < $1.name })
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

    /// Sub-locations available at a given depth
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

    var body: some View {
        Form {
            Section("Select Home Location") {
                // House picker
                Picker("House", selection: $selectedHouse) {
                    Text("Select house...").tag(nil as House?)
                    ForEach(availableHouses) { house in
                        Text(house.name).tag(house as House?)
                    }
                }
                .onChange(of: selectedHouse) {
                    locationSelections = [nil]
                    selectedContainer = nil
                }

                // Cascading location pickers
                if selectedHouse != nil {
                    locationPicker(atDepth: 0, label: "Location", locations: topLevelLocations)

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
                        Text("No container").tag(nil as Container?)
                        ForEach(availableContainers) { container in
                            Text(container.name).tag(container as Container?)
                        }
                        ForEach(nestedContainers()) { container in
                            Text(indentedName(for: container)).tag(container as Container?)
                        }
                    }
                }
            }

            // Preview
            if selectedHouse != nil {
                Section("Preview") {
                    BreadcrumbView(components: previewComponents)
                }
            }
        }
        .navigationTitle("Add Home Location")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    guard let house = selectedHouse else { return }
                    onSave(house, deepestSelectedLocation, selectedContainer)
                    dismiss()
                }
                .disabled(selectedHouse == nil)
            }
        }
        .onAppear {
            do {
                houses = try InventoryService.allHouses(in: modelContext)
            } catch {
                houses = []
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
                if depth < locationSelections.count {
                    locationSelections[depth] = newValue
                }
                if locationSelections.count > depth + 1 {
                    locationSelections.removeSubrange((depth + 1)...)
                }
                if let loc = newValue, !loc.subLocations.isEmpty {
                    locationSelections.append(nil)
                }
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

    private func subLocationLabel(depth: Int) -> String {
        let prefix = String(repeating: "Sub-", count: depth)
        return prefix + "location"
    }

    private var previewComponents: [String] {
        var components: [String] = []
        if let house = selectedHouse {
            components.append(house.name)
        }
        if let location = deepestSelectedLocation {
            var locComponents: [String] = [location.name]
            var current = location.parentLocation
            while let parent = current {
                locComponents.insert(parent.name, at: 0)
                current = parent.parentLocation
            }
            components.append(contentsOf: locComponents)
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
        return components
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
}
