import SwiftUI
import SwiftData

struct SearchFilterView: View {
    @Binding var selectedHouse: House?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @State private var houses: [House] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("House") {
                    Picker("House", selection: $selectedHouse) {
                        Text("All Houses").tag(nil as House?)
                        ForEach(houses) { house in
                            Text(house.name).tag(house as House?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Clear All Filters") {
                        selectedHouse = nil
                    }
                    .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
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
    }
}
