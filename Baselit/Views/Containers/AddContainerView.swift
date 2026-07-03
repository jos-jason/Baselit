import SwiftUI
import SwiftData

struct AddContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \House.name) private var houses: [House]

    @State private var name = ""
    @State private var containerType = ""
    @State private var notes = ""
    @State private var selectedHouse: House?
    @State private var selectedLocation: Location?

    private var availableLocations: [Location] {
        selectedHouse?.locations.sorted(by: { $0.name < $1.name }) ?? []
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
                }

                if selectedHouse != nil && !availableLocations.isEmpty {
                    Picker("Location", selection: $selectedLocation) {
                        Text("None").tag(nil as Location?)
                        ForEach(availableLocations) { loc in
                            Text(loc.name).tag(loc as Location?)
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
        .navigationTitle("New Container")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    addContainer()
                }
                .disabled(!isValid)
            }
        }
    }

    private func addContainer() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let container = Container(
            name: trimmed,
            containerType: containerType.isEmpty ? nil : containerType,
            location: selectedLocation,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(container)
        dismiss()
    }
}
