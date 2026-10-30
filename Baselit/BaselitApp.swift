//
//  BaselitApp.swift
//  Baselit
//
//  Created by JJ vollum on 6/10/26.
//

import SwiftUI
import SwiftData

@main
struct BaselitApp: App {
    let modelContainer: ModelContainer
    @State private var printQueue = PrintQueueService()

    init() {
        let schema = Schema([
            House.self,
            Location.self,
            Container.self,
            Item.self,
            Tag.self,
            Photo.self,
            HomeLocation.self
        ])
        let configuration = ModelConfiguration(schema: schema)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])

            // Backfill identifiers for any existing containers that pre-date the identifier feature
            let context = ModelContext(container)
            let predicate = #Predicate<Container> { $0.identifier.isEmpty }
            let descriptor = FetchDescriptor<Container>(predicate: predicate)
            let needsBackfill = try context.fetch(descriptor)
            for c in needsBackfill {
                c.identifier = IdentifierGenerator.generate()
            }
            if !needsBackfill.isEmpty {
                try context.save()
            }

            // Backfill identifiers for any existing items that pre-date the identifier feature
            let itemPredicate = #Predicate<Item> { $0.identifier.isEmpty }
            let itemDescriptor = FetchDescriptor<Item>(predicate: itemPredicate)
            let itemsNeedingBackfill = try context.fetch(itemDescriptor)
            for item in itemsNeedingBackfill {
                item.identifier = IdentifierGenerator.generate()
            }
            if !itemsNeedingBackfill.isEmpty {
                try context.save()
            }

            // Move legacy category and color values into notes as keywords.
            // Filtered in memory to avoid SwiftData #Predicate issues with enum fields.
            var movedLegacyFields = false
            for item in try context.fetch(FetchDescriptor<Item>()) {
                if item.moveLegacyCategoryAndColorsToNotes() {
                    movedLegacyFields = true
                }
            }
            if movedLegacyFields {
                try context.save()
            }

            self.modelContainer = container
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(printQueue)
        }
        .modelContainer(modelContainer)
    }
}
