import Foundation
import Observation
import Security
import SwiftData

/// Syncs the inventory with the user's PocketBase server, the same way the Flutter
/// app does (baselit_flutter/lib/sync.dart). Every record is one row in the
/// `baselit_records` collection (pocketbase/pb_migrations), holding its backup JSON.
///
/// Each sync pulls rows the server changed since the last pull, then pushes
/// records whose JSON differs from what was last synced; records that vanished
/// here become `deleted` rows. When both sides changed a record, the newer
/// `updatedAt` wins. For each record this device remembers its own JSON and the
/// server's `updated` time, since iOS and Flutter write slightly different JSON.
@Observable
final class SyncService {
    enum FirstSync { case useServer, merge }

    struct SyncError: LocalizedError {
        let message: String
        var status = 0
        var errorDescription: String? { message }
    }

    private(set) var serverURL: String?
    private(set) var email: String?
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSynced: Date?
    var isSignedIn: Bool { token != nil }

    private var token: String?
    private var userID: String?
    private var lastPull: String?
    private var known: [String: Known] = [:]

    private var context: ModelContext?
    private var syncAgain = false
    private var applying = false
    private var debounce: Task<Void, Never>?
    private var started = false

    private static let collection = "baselit_records"
    private let session = URLSession(configuration: .ephemeral)

    private struct Known: Codable {
        var local: String
        var server: String
    }

    private struct SavedState: Codable {
        var serverURL: String?
        var email: String?
        var userID: String?
        var lastPull: String?
        var lastSynced: Date?
        var known: [String: Known]
    }

    // MARK: - Starting

    /// Loads the saved sign-in, then syncs now, a few seconds after each save, and every minute.
    func start(context: ModelContext) {
        guard !started else { return }
        started = true
        self.context = context
        loadState()
        try? Self.repairSyncIDs(in: context)

        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: ModelContext.didSave) {
                guard let self, !self.applying, self.isSignedIn else { continue }
                self.debounce?.cancel()
                self.debounce = Task {
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled { await self.sync() }
                }
            }
        }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(60))
                await self?.sync()
            }
        }
        Task { await sync() }
    }

    /// Gives every record a unique sync ID. Records from before sync existed,
    /// or copies imported from a backup of this device, may share one.
    static func repairSyncIDs(in context: ModelContext) throws {
        var changed = false
        func repair<T: PersistentModel>(_ type: T.Type, _ id: ReferenceWritableKeyPath<T, String>) throws {
            var seen = Set<String>()
            for model in try context.fetch(FetchDescriptor<T>()) {
                let current = model[keyPath: id].lowercased()
                if current.isEmpty || UUID(uuidString: current) == nil || seen.contains(current) {
                    model[keyPath: id] = UUID().uuidString
                    changed = true
                }
                seen.insert(model[keyPath: id].lowercased())
            }
        }
        try repair(House.self, \.syncID)
        try repair(Location.self, \.syncID)
        try repair(Container.self, \.syncID)
        try repair(Item.self, \.syncID)
        try repair(Photo.self, \.syncID)
        try repair(HomeLocation.self, \.syncID)
        if changed { try context.save() }
    }

    // MARK: - Saved state

    private var stateURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("baselit_sync.json")
    }

    private func loadState() {
        token = Keychain.read()
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(SavedState.self, from: data)
        else { return }
        serverURL = state.serverURL
        email = state.email
        userID = state.userID
        lastPull = state.lastPull
        lastSynced = state.lastSynced
        known = state.known
    }

    private func saveState() {
        let state = SavedState(
            serverURL: serverURL, email: email, userID: userID,
            lastPull: lastPull, lastSynced: lastSynced, known: known
        )
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateURL, options: .atomic)
        }
        if let token { Keychain.save(token) } else { Keychain.delete() }
    }

    // MARK: - Signing in

    /// Signs in and returns whether this device and the server both already hold
    /// an inventory, in which case the caller asks which `FirstSync` to use.
    func signIn(url: String, email: String, password: String) async throws -> Bool {
        var base = url.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let parsed = URL(string: base), parsed.scheme != nil, parsed.host() != nil else {
            throw SyncError(message: "Enter the full server address, like https://pb.example.com")
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let response = try await send(
            "POST", "/api/collections/users/auth-with-password", base: base,
            body: ["identity": trimmedEmail, "password": password], authorized: false
        )
        serverURL = base
        self.email = trimmedEmail
        token = response["token"] as? String
        userID = (response["record"] as? [String: Any])?["id"] as? String
        lastPull = nil
        known = [:]
        lastError = nil
        saveState()

        let filter = "deleted = false".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let remote = try await send("GET", "/api/collections/\(Self.collection)/records?perPage=1&skipTotal=1&filter=\(filter)")
        let serverHasData = !((remote["items"] as? [Any]) ?? []).isEmpty
        let localHasData = try context.map { try !snapshot(in: $0).isEmpty } ?? false
        return serverHasData && localHasData
    }

    /// Runs the first sync after signing in.
    func firstSync(_ choice: FirstSync) async {
        if choice == .useServer, let context {
            applying = true
            for type in [HomeLocation.self, Photo.self, Item.self, Container.self, Location.self, House.self] as [any PersistentModel.Type] {
                try? context.delete(model: type)
            }
            try? context.save()
            applying = false
        }
        await sync()
    }

    func signOut() {
        token = nil
        userID = nil
        lastPull = nil
        known = [:]
        lastSynced = nil
        lastError = nil
        saveState()
    }

    // MARK: - Syncing

    func sync() async {
        guard isSignedIn, let context else { return }
        if isSyncing {
            syncAgain = true
            return
        }
        isSyncing = true
        defer {
            isSyncing = false
            applying = false
            saveState()
        }
        do {
            repeat {
                syncAgain = false
                try await syncOnce(context)
            } while syncAgain
            lastError = nil
            lastSynced = .now
        } catch let error as URLError {
            lastError = error.code == .notConnectedToInternet || error.code == .cannotFindHost || error.code == .cannotConnectToHost || error.code == .timedOut
                ? "Can't reach the server."
                : error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func syncOnce(_ context: ModelContext) async throws {
        try await refreshToken()
        try Self.repairSyncIDs(in: context)
        applying = true
        var local = try snapshot(in: context, touchingChanged: true)
        var newestPull = lastPull
        var models = ModelIndex(context: context)
        var incoming: [(kind: String, data: Data, imageData: Data?)] = []
        var removed = false

        for row in try await pullChanges() {
            guard let id = row["id"] as? String, let kind = row["kind"] as? String,
                  let updated = row["updated"] as? String else { continue }
            if newestPull == nil || updated > newestPull! { newestPull = updated }
            let previous = known[id]
            // Unchanged on the server since this device last synced it (often our own push)
            if let previous, previous.server == updated { continue }

            let mine = local[id]
            let remoteData = (row["data"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            let localChanged = mine == nil ? previous != nil : mine!.canonical != previous?.local
            let localWins = mine != nil && localChanged && remoteData != nil
                && mine!.stamp > (Self.stamp(of: remoteData!) ?? .distantPast)

            if localWins {
                // Keep this device's version; it's pushed below over the server's
                known[id] = Known(local: previous?.local ?? "", server: updated)
                continue
            }
            if (row["deleted"] as? Bool) == true || remoteData == nil {
                if let model = models.find(kind: kind, id: id) {
                    context.delete(model)
                    removed = true
                }
                local[id] = nil
                known[id] = nil
                continue
            }

            var imageData: Data?
            if kind == "photo", models.photos[id]?.imageData == nil {
                imageData = try await downloadPhoto(row: row)
            }
            incoming.append((kind, remoteData!, imageData))
            // Filled in with this device's JSON once the record is applied
            known[id] = Known(local: "", server: updated)
        }

        // Parents first, so a home location never arrives before its house
        let order = ["house", "location", "container", "item", "photo", "homeLocation"]
        incoming.sort { (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9) }
        for record in incoming { try models.apply(kind: record.kind, data: record.data, imageData: record.imageData) }
        for record in incoming { try models.link(kind: record.kind, data: record.data) }
        if !incoming.isEmpty || removed {
            try context.save()
            local = try snapshot(in: context)
            for record in incoming {
                guard let id = Self.exportID(of: record.data), let mine = local[id] else { continue }
                known[id]?.local = mine.canonical
            }
        }
        applying = false
        lastPull = newestPull
        saveState()

        for (id, record) in local where known[id]?.local != record.canonical {
            let server = try await push(id: id, record: record, isNew: known[id] == nil)
            known[id] = Known(local: record.canonical, server: server)
        }
        for (id, entry) in known where local[id] == nil {
            // A server row this device couldn't use (like a home location with no house)
            if entry.local.isEmpty {
                known[id] = nil
                continue
            }
            _ = try? await sendOrNil("PATCH", "/api/collections/\(Self.collection)/records/\(id)", body: ["deleted": true])
            known[id] = nil
        }
    }

    // MARK: - Local records

    private struct LocalRecord {
        let kind: String
        let canonical: String
        let json: Any
        let stamp: Date
        let imageData: Data?
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func uuid(_ syncID: String) -> UUID { UUID(uuidString: syncID) ?? UUID() }
    private static func ref(_ syncID: String?) -> UUID? { syncID.flatMap(UUID.init(uuidString:)) }

    private static func exportID(of data: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["exportID"]
            .flatMap { $0 as? String }?.lowercased()
    }

    private static func stamp(of data: Data) -> Date? {
        struct Stamp: Decodable { let updatedAt: Date?; let createdAt: Date? }
        let stamp = try? decoder.decode(Stamp.self, from: data)
        return stamp?.updatedAt ?? stamp?.createdAt
    }

    /// Every record as its backup JSON, keyed by lowercase sync ID. With `touchingChanged`,
    /// records edited since the last sync get `updatedAt` set to now first, since not
    /// every screen updates it and conflicts are settled by it.
    private func snapshot(in context: ModelContext, touchingChanged: Bool = false) throws -> [String: LocalRecord] {
        var records: [String: LocalRecord] = [:]
        func add<T: Encodable>(_ kind: String, _ syncID: String, _ dto: T, stamp: Date, imageData: Data? = nil) throws {
            let data = try Self.encoder.encode(dto)
            records[syncID.lowercased()] = LocalRecord(
                kind: kind,
                canonical: String(decoding: data, as: UTF8.self),
                json: try JSONSerialization.jsonObject(with: data),
                stamp: stamp,
                imageData: imageData
            )
        }
        func touch<T: PersistentModel>(_ model: T, _ syncID: String, _ dto: () -> some Encodable, _ updatedAt: ReferenceWritableKeyPath<T, Date>) {
            guard touchingChanged, let previous = known[syncID.lowercased()],
                  let data = try? Self.encoder.encode(dto()),
                  String(decoding: data, as: UTF8.self) != previous.local
            else { return }
            model[keyPath: updatedAt] = .now
        }

        for house in try context.fetch(FetchDescriptor<House>()) {
            let dto = { ExportHouse(exportID: Self.uuid(house.syncID), name: house.name, address: house.address,
                                    notes: house.notes, createdAt: house.createdAt, updatedAt: house.updatedAt) }
            touch(house, house.syncID, dto, \.updatedAt)
            try add("house", house.syncID, dto(), stamp: house.updatedAt)
        }
        for location in try context.fetch(FetchDescriptor<Location>()) {
            let dto = { ExportLocation(exportID: Self.uuid(location.syncID), name: location.name, notes: location.notes,
                                       createdAt: location.createdAt, updatedAt: location.updatedAt,
                                       houseExportID: Self.ref(location.house?.syncID),
                                       parentLocationExportID: Self.ref(location.parentLocation?.syncID)) }
            touch(location, location.syncID, dto, \.updatedAt)
            try add("location", location.syncID, dto(), stamp: location.updatedAt)
        }
        for container in try context.fetch(FetchDescriptor<Container>()) {
            let dto = { ExportContainer(exportID: Self.uuid(container.syncID), name: container.name,
                                        containerType: container.containerType, notes: container.notes,
                                        identifier: container.identifier, createdAt: container.createdAt,
                                        updatedAt: container.updatedAt, lastLabelPrintedAt: container.lastLabelPrintedAt,
                                        parentContainerExportID: Self.ref(container.parentContainer?.syncID),
                                        locationExportID: Self.ref(container.location?.syncID),
                                        houseExportID: Self.ref(container.house?.syncID)) }
            touch(container, container.syncID, dto, \.updatedAt)
            try add("container", container.syncID, dto(), stamp: container.updatedAt)
        }
        for item in try context.fetch(FetchDescriptor<Item>()) {
            let dto = { ExportItem(exportID: Self.uuid(item.syncID), name: item.name, itemDescription: item.itemDescription,
                                   quantity: item.quantity, brand: item.brand, model: item.model,
                                   condition: item.condition, notes: item.notes, identifier: item.identifier,
                                   createdAt: item.createdAt, updatedAt: item.updatedAt,
                                   lastLabelPrintedAt: item.lastLabelPrintedAt,
                                   containerExportID: Self.ref(item.container?.syncID),
                                   locationExportID: Self.ref(item.location?.syncID),
                                   houseExportID: Self.ref(item.house?.syncID)) }
            touch(item, item.syncID, dto, \.updatedAt)
            try add("item", item.syncID, dto(), stamp: item.updatedAt)
        }
        for photo in try context.fetch(FetchDescriptor<Photo>()) {
            let dto = ExportPhoto(exportID: Self.uuid(photo.syncID), filename: "photo_\(photo.syncID.uppercased()).jpg",
                                  caption: photo.caption, createdAt: photo.createdAt, sortOrder: photo.sortOrder,
                                  houseExportID: Self.ref(photo.house?.syncID),
                                  locationExportID: Self.ref(photo.location?.syncID),
                                  containerExportID: Self.ref(photo.container?.syncID),
                                  itemExportID: Self.ref(photo.item?.syncID))
            try add("photo", photo.syncID, dto, stamp: photo.createdAt, imageData: photo.imageData)
        }
        for home in try context.fetch(FetchDescriptor<HomeLocation>()) {
            guard let house = home.house else { continue }
            let dto = { ExportHomeLocation(exportID: Self.uuid(home.syncID), createdAt: home.createdAt,
                                           updatedAt: home.updatedAt, houseExportID: Self.uuid(house.syncID),
                                           locationExportID: Self.ref(home.location?.syncID),
                                           containerExportID: Self.ref(home.container?.syncID),
                                           itemExportID: Self.ref(home.item?.syncID),
                                           ownerContainerExportID: Self.ref(home.ownerContainer?.syncID)) }
            touch(home, home.syncID, dto, \.updatedAt)
            try add("homeLocation", home.syncID, dto(), stamp: home.updatedAt)
        }
        return records
    }

    // MARK: - Applying server records

    /// Every record by lowercase sync ID, for applying server rows and linking them up.
    private struct ModelIndex {
        let context: ModelContext
        var houses: [String: House] = [:]
        var locations: [String: Location] = [:]
        var containers: [String: Container] = [:]
        var items: [String: Item] = [:]
        var photos: [String: Photo] = [:]
        var homes: [String: HomeLocation] = [:]

        init(context: ModelContext) {
            self.context = context
            func index<T: PersistentModel>(_ type: T.Type, _ id: KeyPath<T, String>) -> [String: T] {
                let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
                return Dictionary(all.map { ($0[keyPath: id].lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            }
            houses = index(House.self, \.syncID)
            locations = index(Location.self, \.syncID)
            containers = index(Container.self, \.syncID)
            items = index(Item.self, \.syncID)
            photos = index(Photo.self, \.syncID)
            homes = index(HomeLocation.self, \.syncID)
        }

        func find(kind: String, id: String) -> (any PersistentModel)? {
            switch kind {
            case "house": houses[id]
            case "location": locations[id]
            case "container": containers[id]
            case "item": items[id]
            case "photo": photos[id]
            case "homeLocation": homes[id]
            default: nil
            }
        }

        private func key(_ id: UUID?) -> String? { id?.uuidString.lowercased() }

        /// Creates or updates the record's own fields. Relationships are set by `link`
        /// once every row in the batch exists.
        mutating func apply(kind: String, data: Data, imageData: Data?) throws {
            let decoder = SyncService.decoder
            switch kind {
            case "house":
                let dto = try decoder.decode(ExportHouse.self, from: data)
                let id = key(dto.exportID)!
                let house = houses[id] ?? House(name: dto.name)
                if houses[id] == nil { context.insert(house); houses[id] = house }
                house.syncID = dto.exportID.uuidString
                house.name = dto.name
                house.address = dto.address
                house.notes = dto.notes
                house.createdAt = dto.createdAt
                house.updatedAt = dto.updatedAt
            case "location":
                let dto = try decoder.decode(ExportLocation.self, from: data)
                let id = key(dto.exportID)!
                let location = locations[id] ?? Location(name: dto.name)
                if locations[id] == nil { context.insert(location); locations[id] = location }
                location.syncID = dto.exportID.uuidString
                location.name = dto.name
                location.notes = dto.notes
                location.createdAt = dto.createdAt
                location.updatedAt = dto.updatedAt
            case "container":
                let dto = try decoder.decode(ExportContainer.self, from: data)
                let id = key(dto.exportID)!
                let container = containers[id] ?? Container(name: dto.name)
                if containers[id] == nil { context.insert(container); containers[id] = container }
                container.syncID = dto.exportID.uuidString
                container.name = dto.name
                container.containerType = dto.containerType
                container.notes = dto.notes
                container.identifier = dto.identifier
                container.createdAt = dto.createdAt
                container.updatedAt = dto.updatedAt
                container.lastLabelPrintedAt = dto.lastLabelPrintedAt
            case "item":
                let dto = try decoder.decode(ExportItem.self, from: data)
                let id = key(dto.exportID)!
                let item = items[id] ?? Item(name: dto.name)
                if items[id] == nil { context.insert(item); items[id] = item }
                item.syncID = dto.exportID.uuidString
                item.name = dto.name
                item.itemDescription = dto.itemDescription
                item.quantity = dto.quantity
                item.brand = dto.brand
                item.model = dto.model
                item.condition = dto.condition
                item.notes = dto.notesWithLegacyKeywords(tags: [])
                item.identifier = dto.identifier
                item.createdAt = dto.createdAt
                item.updatedAt = dto.updatedAt
                item.lastLabelPrintedAt = dto.lastLabelPrintedAt
            case "photo":
                let dto = try decoder.decode(ExportPhoto.self, from: data)
                let id = key(dto.exportID)!
                let photo = photos[id] ?? Photo(imageData: nil)
                if photos[id] == nil { context.insert(photo); photos[id] = photo }
                photo.syncID = dto.exportID.uuidString
                photo.caption = dto.caption
                photo.sortOrder = dto.sortOrder
                photo.createdAt = dto.createdAt
                if let imageData { photo.imageData = imageData }
            case "homeLocation":
                let dto = try decoder.decode(ExportHomeLocation.self, from: data)
                let id = key(dto.exportID)!
                guard let house = houses[key(dto.houseExportID)!] else { return }
                let home = homes[id] ?? HomeLocation(house: house)
                if homes[id] == nil { context.insert(home); homes[id] = home }
                home.syncID = dto.exportID.uuidString
                home.createdAt = dto.createdAt
                home.updatedAt = dto.updatedAt
            default:
                break
            }
        }

        func link(kind: String, data: Data) throws {
            let decoder = SyncService.decoder
            switch kind {
            case "location":
                let dto = try decoder.decode(ExportLocation.self, from: data)
                guard let location = locations[key(dto.exportID)!] else { return }
                location.house = key(dto.houseExportID).flatMap { houses[$0] }
                location.parentLocation = key(dto.parentLocationExportID).flatMap { locations[$0] }
            case "container":
                let dto = try decoder.decode(ExportContainer.self, from: data)
                guard let container = containers[key(dto.exportID)!] else { return }
                container.parentContainer = key(dto.parentContainerExportID).flatMap { containers[$0] }
                container.location = key(dto.locationExportID).flatMap { locations[$0] }
                container.house = key(dto.houseExportID).flatMap { houses[$0] }
            case "item":
                let dto = try decoder.decode(ExportItem.self, from: data)
                guard let item = items[key(dto.exportID)!] else { return }
                item.container = key(dto.containerExportID).flatMap { containers[$0] }
                item.location = key(dto.locationExportID).flatMap { locations[$0] }
                item.house = key(dto.houseExportID).flatMap { houses[$0] }
            case "photo":
                let dto = try decoder.decode(ExportPhoto.self, from: data)
                guard let photo = photos[key(dto.exportID)!] else { return }
                photo.house = key(dto.houseExportID).flatMap { houses[$0] }
                photo.location = key(dto.locationExportID).flatMap { locations[$0] }
                photo.container = key(dto.containerExportID).flatMap { containers[$0] }
                photo.item = key(dto.itemExportID).flatMap { items[$0] }
            case "homeLocation":
                let dto = try decoder.decode(ExportHomeLocation.self, from: data)
                guard let home = homes[key(dto.exportID)!] else { return }
                home.house = houses[key(dto.houseExportID)!]
                home.location = key(dto.locationExportID).flatMap { locations[$0] }
                home.container = key(dto.containerExportID).flatMap { containers[$0] }
                home.item = key(dto.itemExportID).flatMap { items[$0] }
                home.ownerContainer = key(dto.ownerContainerExportID).flatMap { containers[$0] }
            default:
                break
            }
        }
    }

    // MARK: - Server requests

    private func pullChanges() async throws -> [[String: Any]] {
        var rows: [[String: Any]] = []
        var page = 1
        while true {
            var path = "/api/collections/\(Self.collection)/records?page=\(page)&perPage=500&skipTotal=1"
                + "&sort=updated,id&fields=id,kind,data,deleted,photo,updated"
            if let lastPull {
                let filter = "updated >= \"\(lastPull)\""
                path += "&filter=" + (filter.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
            }
            let items = (try await send("GET", path)["items"] as? [[String: Any]]) ?? []
            rows += items
            if items.count < 500 { return rows }
            page += 1
        }
    }

    private func downloadPhoto(row: [String: Any]) async throws -> Data? {
        guard let id = row["id"] as? String, let name = row["photo"] as? String, !name.isEmpty,
              let serverURL else { return nil }
        let fileToken = try await send("POST", "/api/files/token")["token"] as? String ?? ""
        guard let url = URL(string: "\(serverURL)/api/files/\(Self.collection)/\(id)/\(name)?token=\(fileToken)") else { return nil }
        let (data, response) = try await session.data(from: url)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 200 { return data }
        if status == 404 { return nil }
        // Stop before this pull is recorded, so the photo is fetched again next time
        throw SyncError(message: "Couldn't download a photo (\(status)).", status: status)
    }

    /// Creates or updates the row and returns the server's new `updated` time.
    private func push(id: String, record: LocalRecord, isNew: Bool) async throws -> String {
        let fields: [String: Any] = ["kind": record.kind, "data": record.json, "deleted": false]
        if !isNew, let updated = try await sendOrNil("PATCH", "/api/collections/\(Self.collection)/records/\(id)", body: fields) {
            return updated["updated"] as? String ?? ""
        }
        var create = fields
        create["id"] = id
        create["owner"] = userID ?? ""
        let created: [String: Any]?
        if isNew, record.kind == "photo", let imageData = record.imageData {
            created = try await upload(fields: create, photo: imageData, id: id)
        } else {
            created = try await sendOrNil("POST", "/api/collections/\(Self.collection)/records", body: create)
        }
        // Already on the server (synced from elsewhere before this device knew it)
        var row = created
        if row == nil {
            row = try await send("PATCH", "/api/collections/\(Self.collection)/records/\(id)", body: fields)
        }
        return row?["updated"] as? String ?? ""
    }

    private func upload(fields: [String: Any], photo: Data, id: String) async throws -> [String: Any]? {
        let boundary = "Baselit-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields {
            let text: String
            if let string = value as? String {
                text = string
            } else if let bool = value as? Bool {
                text = bool ? "true" : "false"
            } else {
                text = String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
            }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(text)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"photo_\(id).jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(photo)
        append("\r\n--\(boundary)--\r\n")

        var request = try makeRequest("POST", "/api/collections/\(Self.collection)/records")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        do {
            return try await perform(request)
        } catch let error as SyncError where error.status == 400 {
            return nil
        }
    }

    private func refreshToken() async throws {
        guard let response = try await sendOrNil("POST", "/api/collections/users/auth-refresh") else {
            signOut()
            throw SyncError(message: "Signed out. Sign in to your server again to keep syncing.")
        }
        token = response["token"] as? String ?? token
    }

    /// Like `send`, but returns nil for 400, 401, and 404 (a row that doesn't exist
    /// yet, or one that already does).
    private func sendOrNil(_ method: String, _ path: String, body: [String: Any]? = nil) async throws -> [String: Any]? {
        do {
            return try await send(method, path, body: body)
        } catch let error as SyncError where [400, 401, 404].contains(error.status) {
            return nil
        }
    }

    private func send(
        _ method: String, _ path: String, base: String? = nil,
        body: [String: Any]? = nil, authorized: Bool = true
    ) async throws -> [String: Any] {
        var request = try makeRequest(method, path, base: base, authorized: authorized)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return try await perform(request)
    }

    private func makeRequest(_ method: String, _ path: String, base: String? = nil, authorized: Bool = true) throws -> URLRequest {
        guard let url = URL(string: (base ?? serverURL ?? "") + path) else {
            throw SyncError(message: "The server address isn't valid.")
        }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        if authorized, let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status < 300 else {
            throw SyncError(message: json["message"] as? String ?? "Server error \(status)", status: status)
        }
        return json
    }
}

// MARK: - Keychain

/// Keeps the PocketBase sign-in token in the keychain rather than in the state file.
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Babymechanical.Baselit.PocketBase",
        kSecAttrAccount as String: "token",
    ]

    static func read() -> String? {
        var search = query
        search[kSecReturnData as String] = true
        var result: AnyObject?
        guard SecItemCopyMatching(search as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String) {
        let data = Data(token.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    static func delete() {
        SecItemDelete(query as CFDictionary)
    }
}
