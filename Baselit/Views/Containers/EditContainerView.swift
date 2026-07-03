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
    @State private var selectedLocation: Location?
    @State private var selectedParentContainer: Container?

    init(container: Container) {
        self.container = container
        _name = State(initialValue: container.name)
        _containerType = State(initialValue: container.containerType ?? "")
        _notes = State(initialValue: container.notes ?? "")
        _selectedHouse = State(initialValue: container.resolvedHouse)
        _selectedLocation = State(initialValue: container.resolvedLocation)
        _selectedParentContainer = State(initialValue: container.parentContainer)
    }

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    /// Containers available as parents — exclude self and descendants
    private var availableParentContainers: [Container] {
        let excluded = descendantIDs(of: container)
        var candidates = allContainers.filter { !excluded.contains($0.persistentModelID) }

        if let selectedLocation {
            candidates = candidates.filter {
                $0.resolvedLocation?.persistentModelID == selectedLocation.persistentModelID
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
                    selectedLocation = nil
                    selectedParentContainer = nil
                }

                if selectedHouse != nil && !availableLocations.isEmpty {
                    Picker("Location", selection: $selectedLocation) {
                        Text("None").tag(nil as Location?)
                        ForEach(availableLocations) { loc in
                            Text(loc.name).tag(loc as Location?)
                        }
                    }
                    .onChange(of: selectedLocation) {
                        selectedParentContainer = nil
                    }
                }

                if !availableParentContainers.isEmpty {
                    Picker("Inside Container", selection: $selectedParentContainer) {
                        Text("None (top level)").tag(nil as Container?)
                        ForEach(availableParentContainers) { c in
                            Text(c.breadcrumbPath).tag(c as Container?)
                        }
                    }
                }
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
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        container.name = trimmed
        container.containerType = containerType.isEmpty ? nil : containerType
        container.notes = notes.isEmpty ? nil : notes
        container.parentContainer = selectedParentContainer
        container.location = selectedParentContainer != nil ? nil : selectedLocation
        container.updatedAt = .now

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
