import SwiftUI
import SwiftData

struct EditContainerView: View {
    @Bindable var container: Container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \House.name) private var houses: [House]
    @Query(sort: \Container.name) private var allContainers: [Container]

    @State private var name: String
    @State private var containerType: String
    @State private var notes: String
    @State private var selectedHouse: House?
    /// Cascading location selections: index 0 = top-level, index 1 = sub-location, etc.
    @State private var locationSelections: [Location?] = [nil]
    @State private var selectedParentContainer: Container?
    @State private var showAddHomeLocation = false
    @State private var homeLocationsToAdd: [(house: House, location: Location?, container: Container?)] = []
    @State private var homeLocationIDsToRemove: Set<PersistentIdentifier> = []

    init(container: Container) {
        self.container = container
        _name = State(initialValue: container.name)
        _containerType = State(initialValue: container.containerType ?? "")
        _notes = State(initialValue: container.notes ?? "")
        _selectedHouse = State(initialValue: container.resolvedHouse)
        _selectedParentContainer = State(initialValue: container.parentContainer)

        // Build cascading location selections from the container's current location
        if let loc = container.resolvedLocation {
            var chain: [Location] = [loc]
            var current = loc.parentLocation
            while let parent = current {
                chain.insert(parent, at: 0)
                current = parent.parentLocation
            }
            var selections: [Location?] = chain.map { $0 as Location? }
            if !loc.subLocations.isEmpty {
                selections.append(nil)
            }
            _locationSelections = State(initialValue: selections)
        } else {
            _locationSelections = State(initialValue: [nil])
        }
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

    /// Containers available as parents — exclude self and descendants
    private var availableParentContainers: [Container] {
        let excluded = descendantIDs(of: container)
        var candidates = allContainers.filter { !excluded.contains($0.persistentModelID) }

        if let deepestSelectedLocation {
            candidates = candidates.filter {
                $0.resolvedLocation?.persistentModelID == deepestSelectedLocation.persistentModelID
            }
        } else if let selectedHouse {
            candidates = candidates.filter {
                $0.resolvedHouse?.persistentModelID == selectedHouse.persistentModelID
            }
        }

        return candidates.sorted(by: { $0.breadcrumbPath < $1.breadcrumbPath })
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Name") {
                TextField("Container name", text: $name)
            }

            Section("Location") {
                Picker("House", selection: $selectedHouse) {
                    Text("None").tag(nil as House?)
                    ForEach(houses) { house in
                        Text(house.name).tag(house as House?)
                    }
                }
                .onChange(of: selectedHouse) {
                    locationSelections = [nil]
                    selectedParentContainer = nil
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

                if !availableParentContainers.isEmpty {
                    Picker("Inside Container", selection: $selectedParentContainer) {
                        Text("None (top level)").tag(nil as Container?)
                        ForEach(availableParentContainers) { c in
                            Text(c.name).tag(c as Container?)
                        }
                    }
                }
            }

            // Home locations (where this container belongs)
            Section("Belongs") {
                ForEach(container.homeLocations.filter {
                    !homeLocationIDsToRemove.contains($0.persistentModelID)
                }.sorted(by: { ($0.house?.name ?? "") < ($1.house?.name ?? "") })) { hl in
                    HStack {
                        BreadcrumbView(components: hl.breadcrumbComponents)
                        Spacer()
                        Button(role: .destructive) {
                            homeLocationIDsToRemove.insert(hl.persistentModelID)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                ForEach(Array(homeLocationsToAdd.enumerated()), id: \.offset) { index, entry in
                    HStack {
                        BreadcrumbView(components: homeLocationPreviewComponents(entry))
                        Spacer()
                        Button(role: .destructive) {
                            homeLocationsToAdd.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button {
                    showAddHomeLocation = true
                } label: {
                    Label("Add Home Location", systemImage: "house.badge.plus")
                }
                .disabled(availableHousesForHomeLocation.isEmpty)
            }

            Section("Details") {
                TextField("Type (e.g. Box, Shelf, Drawer)", text: $containerType)
                TextField("Notes", text: $notes, axis: .vertical)
                    .lineLimit(3...6)
            }
        }
        .navigationTitle("Edit Container")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
                .disabled(!isValid)
            }
        }
        .sheet(isPresented: $showAddHomeLocation) {
            NavigationStack {
                HomeLocationPickerView(
                    existingHouseIDs: existingHomeLocationHouseIDs
                ) { house, location, targetContainer in
                    homeLocationsToAdd.append((house: house, location: location, container: targetContainer))
                }
            }
        }
    }

    /// House IDs that already have a home location (existing + newly added)
    private var existingHomeLocationHouseIDs: Set<PersistentIdentifier> {
        var ids = Set<PersistentIdentifier>()
        for hl in container.homeLocations where !homeLocationIDsToRemove.contains(hl.persistentModelID) {
            if let house = hl.house {
                ids.insert(house.persistentModelID)
            }
        }
        for entry in homeLocationsToAdd {
            ids.insert(entry.house.persistentModelID)
        }
        return ids
    }

    /// Houses available for adding a new home location
    private var availableHousesForHomeLocation: [House] {
        houses.filter { !existingHomeLocationHouseIDs.contains($0.persistentModelID) }
    }

    /// Build preview breadcrumb components for a pending home location entry
    private func homeLocationPreviewComponents(_ entry: (house: House, location: Location?, container: Container?)) -> [String] {
        var components: [String] = [entry.house.name]
        if let location = entry.location {
            var locComponents: [String] = [location.name]
            var current = location.parentLocation
            while let parent = current {
                locComponents.insert(parent.name, at: 0)
                current = parent.parentLocation
            }
            components.append(contentsOf: locComponents)
        }
        if let container = entry.container {
            var containerComponents: [String] = [container.name]
            var current = container.parentContainer
            while let parent = current {
                containerComponents.insert(parent.name, at: 0)
                current = parent.parentContainer
            }
            components.append(contentsOf: containerComponents)
        }
        return components
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

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        container.name = trimmed
        container.containerType = containerType.isEmpty ? nil : containerType
        container.notes = notes.isEmpty ? nil : notes
        container.parentContainer = selectedParentContainer
        container.location = selectedParentContainer != nil ? nil : deepestSelectedLocation
        // Set house when no location or parent container is selected
        if selectedParentContainer == nil && deepestSelectedLocation == nil {
            container.house = selectedHouse
        } else {
            container.house = nil
        }
        container.updatedAt = .now

        // Remove home locations marked for deletion
        for hl in container.homeLocations where homeLocationIDsToRemove.contains(hl.persistentModelID) {
            modelContext.delete(hl)
        }

        // Add new home locations
        for entry in homeLocationsToAdd {
            try? HomeLocationService.addHomeLocation(
                for: container,
                house: entry.house,
                location: entry.location,
                targetContainer: entry.container,
                context: modelContext
            )
        }

        dismiss()
    }

    /// Collect the persistent IDs of a container and all its descendants
    /// so we don't allow moving a container inside itself.
    private func descendantIDs(of c: Container) -> Set<PersistentIdentifier> {
        var ids: Set<PersistentIdentifier> = [c.persistentModelID]
        for sub in c.subContainers {
            ids.formUnion(descendantIDs(of: sub))
        }
        return ids
    }
}
