import SwiftUI
import SwiftData

struct ContainerDetailView: View {
    @Bindable var container: Container
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showAddSubContainer = false
    @State private var newSubContainerName = ""
    @State private var showAddItem = false
    @State private var showEditContainer = false
    @State private var editedName = ""
    @State private var showDeleteConfirmation = false
    @State private var showMoveContainer = false

    var body: some View {
        List {
            // Breadcrumb
            Section {
                BreadcrumbView(components: container.breadcrumbComponents)
            }

            // Sub-containers
            if !container.subContainers.isEmpty {
                Section("Sub-containers") {
                    ForEach(container.subContainers.sorted(by: { $0.name < $1.name })) { sub in
                        NavigationLink(value: sub) {
                            ContainerRow(container: sub)
                        }
                    }
                }
            }

            // Items in this container
            if !container.items.isEmpty {
                Section("Items") {
                    ForEach(container.items.sorted(by: { $0.name < $1.name })) { item in
                        NavigationLink(value: item) {
                            ItemRow(item: item)
                        }
                    }
                }
            }

            if container.subContainers.isEmpty && container.items.isEmpty {
                EmptyStateView(
                    icon: "tray",
                    title: "Empty Container",
                    message: "Add items or sub-containers to this container."
                )
            }

            if let notes = container.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                }
            }
        }
        .navigationTitle(container.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showAddSubContainer = true
                    } label: {
                        Label("Add Sub-container", systemImage: "archivebox")
                    }
                    Button {
                        showAddItem = true
                    } label: {
                        Label("Add Item", systemImage: "shippingbox")
                    }
                    Divider()
                    Button {
                        editedName = container.name
                        showEditContainer = true
                    } label: {
                        Label("Edit Container", systemImage: "pencil")
                    }
                    Button {
                        showMoveContainer = true
                    } label: {
                        Label("Move Container", systemImage: "arrow.right")
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Container", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("New Sub-container", isPresented: $showAddSubContainer) {
            TextField("Container name", text: $newSubContainerName)
            Button("Cancel", role: .cancel) {
                newSubContainerName = ""
            }
            Button("Add") {
                addSubContainer()
            }
        } message: {
            Text("Enter a name for the sub-container.")
        }
        .alert("Edit Container", isPresented: $showEditContainer) {
            TextField("Container name", text: $editedName)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    container.name = trimmed
                    container.updatedAt = .now
                }
            }
        }
        .confirmationDialog(
            "Delete \(container.name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            if !container.subContainers.isEmpty || !container.items.isEmpty {
                Button("Move contents out, then delete") {
                    reparentAndDelete()
                }
                Button("Delete container and all contents", role: .destructive) {
                    deleteWithContents()
                }
            } else {
                Button("Delete", role: .destructive) {
                    modelContext.delete(container)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if !container.subContainers.isEmpty || !container.items.isEmpty {
                Text("This container has \(container.subContainers.count) sub-containers and \(container.items.count) items.")
            }
        }
        .sheet(isPresented: $showAddItem) {
            NavigationStack {
                ItemFormView(container: container)
            }
        }
        .sheet(isPresented: $showMoveContainer) {
            NavigationStack {
                MoveContainerView(container: container)
            }
        }
    }

    private func addSubContainer() {
        let trimmed = newSubContainerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let sub = Container(name: trimmed, parentContainer: container)
        modelContext.insert(sub)
        newSubContainerName = ""
    }

    private func reparentAndDelete() {
        let parent = container.parentContainer
        let loc = container.resolvedLocation

        for sub in container.subContainers {
            sub.parentContainer = parent
            if parent == nil {
                sub.location = loc
            }
        }
        for item in container.items {
            item.container = parent
            if parent == nil {
                item.location = loc
            }
        }
        modelContext.delete(container)
        dismiss()
    }

    private func deleteWithContents() {
        // Delete all nested items and sub-containers recursively
        deleteContainerRecursive(container)
        dismiss()
    }

    private func deleteContainerRecursive(_ c: Container) {
        for sub in c.subContainers {
            deleteContainerRecursive(sub)
        }
        for item in c.items {
            modelContext.delete(item)
        }
        modelContext.delete(c)
    }
}
