import SwiftUI
import SwiftData

struct SearchFilterView: View {
    @Binding var selectedHouse: House?
    @Binding var selectedCategory: ItemCategory?
    @Binding var selectedColor: ItemColor?
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

                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag(nil as ItemCategory?)
                        ForEach(ItemCategory.allCases) { cat in
                            Text(cat.displayName).tag(cat as ItemCategory?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Color") {
                    Picker("Color", selection: $selectedColor) {
                        Text("All Colors").tag(nil as ItemColor?)
                        ForEach(ItemColor.allCases) { c in
                            Text(c.displayName).tag(c as ItemColor?)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    Button("Clear All Filters") {
                        selectedHouse = nil
                        selectedCategory = nil
                        selectedColor = nil
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
