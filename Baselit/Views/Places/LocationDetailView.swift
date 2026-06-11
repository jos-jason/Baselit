import SwiftUI
import SwiftData

struct LocationDetailView: View {
    @Bindable var location: Location
    @Environment(\.modelContext) private var modelContext
    @State private var showAddContainer = false
    @State private var newContainerName = ""
    @State private var showAddItem = false
    @State private var showEditLocation = false
    @State private var editedName = ""

    var body: some View {
        List {
            // Breadcrumb
            if let house = location.house {
                Section {
                    BreadcrumbView(components: [house.name, location.name])
                }
            }

            // Containers at this location
            if !location.containers.isEmpty {
                Section("Containers") {
                    ForEach(location.containers.sorted(by: { $0.name < $1.name })) { container in
                        NavigationLink(value: container) {
                            ContainerRow(container: container)
                        }
                    }
                }
            }

            // Items directly at this location
            if !location.items.isEmpty {
                Section("Items") {
                    ForEach(location.items.sorted(by: { $0.name < $1.name })) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }

            if location.containers.isEmpty && location.items.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "Empty Location",
                    message: "Add containers or items to this location."
                )
            }

            if let notes = location.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(location.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddContainer = true
                    } label: {
                        Label("Add Container", systemImage: "archivebox")
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "shippingbox")
                    }
                    Divider()
                    Button {
                        editedName = location.name
                        showEditLocation = true
                    } label: {
                        Label("Edit Location", systemImage: "pencil")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("New Container", isPresented: $showAddContainer) {
            TextField("Container name", text: $newContainerName)
            Button("Cancel", role: .cancel) {
                newContainerName = ""
            }
            Button("Add") {
                addContainer()
            }
        } message: {
            Text("Enter a name (e.g. Blue Tote, Cupboard, Shelf A).")
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                ItemFormView(location: location)
            }
        }
        .alert("Edit Location", isPresented: $showEditLocation) {
            TextField("Location name", text: $editedName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    location.name = trimmed
                    location.updatedAt = .now
                }
            }
        }
    }

    private func addContainer() {
        let trimmed = newContainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let container = Container(name: trimmed, location: location)
        modelContext.insert(container)
        newContainerName = ""
    }
}

struct ContainerRow: View {
    let container: Container

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(container.name)
                .font(.headline)
            HStack(spacing: 12) {
                if !container.subContainers.isEmpty {
                    Label("\(container.subContainers.count) sub-containers", systemImage: "archivebox")
                }
                Label("\(container.items.count) items", systemImage: "shippingbox")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

struct ItemRow: View {
    let item: Item

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.headline)
            HStack(spacing: 8) {
                if let category = item.category {
                    Text(category.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary)
                        .clipShape(Capsule())
                }
                if let color = item.color {
                    Text(color.displayName)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.fill.tertiary)
                        .clipShape(Capsule())
                }
                if item.quantity > 1 {
                    Text("×\(item.quantity)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            BreadcrumbView(components: item.breadcrumbComponents)
        }
        .padding(.vertical, 2)
    }
}
