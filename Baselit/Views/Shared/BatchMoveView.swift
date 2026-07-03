import SwiftUI
import SwiftData

struct BatchMoveView: View {
    let items: [Item]
    let containers: [Container]
    var onComplete: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var houses: [House] = []
    @State private var selectedHouse: House?
    @State private var selectedLocation: Location?
    @State private var selectedContainer: Container?
    @State private var errorMessage: String?

    private var totalCount: Int {
        items.count + containers.count
    }

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
    }

    /// IDs of containers being moved (used to exclude them from target picker)
    private var movingContainerIDs: Set<PersistentIdentifier> {
        Set(containers.map(\.persistentModelID))
    }

    /// Top-level containers at the selected location, excluding any being moved
    private var availableContainers: [Container] {
        guard let location = selectedLocation else { return [] }
        return location.containers
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
                    .disabled(selectedLocation == nil)
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

    // MARK: - Path Preview

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

    // MARK: - Container Filtering

    /// Check if a container should be excluded from the target picker
    /// (because it's being moved, or is a descendant of one being moved)
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
        let targetContainer = selectedContainer
        let targetLocation = selectedContainer == nil ? selectedLocation : nil

        // Move items (these never cause cycle errors)
        for item in items {
            ContainerService.moveItem(
                item,
                toContainer: targetContainer,
                toLocation: targetLocation
            )
        }

        // Move containers (may throw cycle errors)
        for container in containers {
            do {
                try ContainerService.moveContainer(
                    container,
                    toParent: targetContainer,
                    inLocation: targetLocation
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
