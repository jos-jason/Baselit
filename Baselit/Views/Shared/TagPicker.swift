import SwiftUI
import SwiftData

struct TagPicker: View {
    @Binding var selectedTags: [Tag]
    @Environment(\.modelContext) private var modelContext
    @State private var newTagName = ""
    @State private var availableTags: [Tag] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Current tags
            if !selectedTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(selectedTags) { tag in
                            HStack(spacing: 4) {
                                Text(tag.name)
                                    .font(.caption)
                                Button {
                                    selectedTags.removeAll { $0.persistentModelID == tag.persistentModelID }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.fill.tertiary)
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            // Add tag field
            HStack {
                TextField("Add tag...", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { addTag() }

                Button("Add") { addTag() }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            // Suggestions from existing tags
            if !availableTags.isEmpty {
                let unselectedTags = availableTags.filter { tag in
                    !selectedTags.contains(where: { $0.persistentModelID == tag.persistentModelID })
                }
                if !unselectedTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(unselectedTags) { tag in
                                Button {
                                    selectedTags.append(tag)
                                } label: {
                                    Text(tag.name)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(.fill.quaternary)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadTags() }
    }

    private func addTag() {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return }
        guard !selectedTags.contains(where: { $0.name == trimmed }) else {
            newTagName = ""
            return
        }

        do {
            let tag = try InventoryService.findOrCreateTag(name: trimmed, in: modelContext)
            selectedTags.append(tag)
            newTagName = ""
            loadTags()
        } catch {
            // Silently fail - tag creation is non-critical
        }
    }

    private func loadTags() {
        do {
            availableTags = try InventoryService.allTags(in: modelContext)
        } catch {
            availableTags = []
        }
    }
}
