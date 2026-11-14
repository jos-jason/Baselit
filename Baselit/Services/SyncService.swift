import Foundation
import Observation
import Security
import SwiftData
import UIKit

/// Syncs the inventory with the NAS the same way Inkpad and the Flutter app do,
/// through the shared `sync_items` collection from github.com/jos-jason/nas-sync,
/// filed under app `baselit`. This is a Swift port of that repo's Dart engine
/// (dart/nas_sync/lib/src/engine.dart); keep the two in step.
///
/// Each house, location, container, item, photo, and home location is one item:
/// kind plus its lowercase sync ID as the key, its backup JSON as `data`, and for
/// photos the image as the `blob`. Each sync pulls rows changed since the last
/// pull, then pushes this device's changes. When both sides changed an item, the
/// newer `modified` time wins.
///
/// SwiftData has no per-record change hooks, so before each sync this compares
/// every record's JSON with what it was last time and marks whatever changed or
/// vanished, stamped with the current time.
@Observable
final class SyncService {
    enum FirstSync { case useServer, merge }

    struct SyncError: LocalizedError {
        let message: String
        var status = 0
        var notUnique = false
        var errorDescription: String? { message }
        var isAuth: Bool { status == 401 || status == 403 }
    }

    /// The app name the server files Baselit's items under.
    static let app = "baselit"
    private static let collection = "sync_items"
    private static let pageSize = 200

    private(set) var serverURL: String?
    private(set) var email: String?
    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var lastSynced: Date?
    var isSignedIn: Bool { token != nil }

    private var token: String?
    private var userID: String?
    private var state = EngineState()
    /// Each record's JSON as of the last sync, and when this device saw it change (ms).
    private var seen: [String: Seen] = [:]

    private var context: ModelContext?
    private var syncAgain = false
    private var applying = false
    private var debounce: Task<Void, Never>?
    private var started = false
    private let session = URLSession(configuration: .ephemeral)
    /// Stored with each version (informational), like Inkpad's device name.
    private let device = UIDevice.current.name

    // MARK: - Saved state

    /// What the engine remembers about one item, as in nas_sync's `ItemState`.
    private struct ItemState: Codable {
        /// The server row, once there is one.
        var recordID: String?
        /// The server's `updated` stamp of the version this device last synced.
        var baseUpdated: String?
        /// When it was last edited (ms): the local edit while dirty, else the synced version's.
        var modified: Int64
        /// Changed here and not yet sent.
        var dirty = false
        /// Deleted (here if dirty, or the synced version is a deletion).
        var deleted = false
    }

    private struct EngineState: Codable {
        /// The newest server `updated` stamp already pulled.
        var cursor: String?
        /// The user these records belong to; a different sign-in starts over.
        var userID: String?
        var items: [String: ItemState] = [:]
    }

    private struct Seen: Codable {
        var json: String
        var at: Int64
    }

    private struct SavedSettings: Codable {
        var serverURL: String?
        var email: String?
        var userID: String?
        var lastSynced: Date?
        var engine: EngineState
        var seen: [String: Seen]
    }

    private var stateURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("baselit_sync.json")
    }

    private func loadState() {
        token = Keychain.read()
        guard let data = try? Data(contentsOf: stateURL),
              let saved = try? JSONDecoder().decode(SavedSettings.self, from: data)
        else { return }
        serverURL = saved.serverURL
        email = saved.email
        userID = saved.userID
        lastSynced = saved.lastSynced
        state = saved.engine
        seen = saved.seen
    }

    private func saveState() {
        let saved = SavedSettings(serverURL: serverURL, email: email, userID: userID,
                                  lastSynced: lastSynced, engine: state, seen: seen)
        try? FileManager.default.createDirectory(at: .applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: stateURL, options: .atomic)
        }
        if let token { Keychain.save(token) } else { Keychain.delete() }
    }

    private static func itemID(_ kind: String, _ key: String) -> String { "\(kind)/\(key)" }

    private static func split(_ id: String) -> (kind: String, key: String) {
        let slash = id.firstIndex(of: "/")!
        return (String(id[..<slash]), String(id[id.index(after: slash)...]))
    }

    private static var now: Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    // MARK: - Starting

    /// Restores a saved login, then syncs now, a few seconds after each save,
    /// and every five minutes (like Inkpad).
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
                    try? await Task.sleep(for: .seconds(5))
                    if !Task.isCancelled { await self.sync() }
                }
            }
        }
        Task { [weak self] in
            while true {
                try? await Task.sleep(for: .seconds(300))
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

    // MARK: - Signing in

    /// Signs in with an account from the NAS admin page and returns whether this
    /// device and the server both already hold a Baselit inventory, in which case
    /// the caller asks which `FirstSync` to use.
    func signIn(url: String, email: String, password: String) async throws -> Bool {
        var base = url.trimmingCharacters(in: .whitespaces)
        while base.hasSuffix("/") { base.removeLast() }
        guard let parsed = URL(string: base), parsed.scheme != nil, parsed.host() != nil else {
            throw SyncError(message: "Enter the full server address, like https://nas.tailnet.ts.net:8443")
        }
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let response: [String: Any]
        do {
            response = try await send("POST", "api/collections/users/auth-with-password", base: base,
                                      body: ["identity": trimmedEmail, "password": password], authorized: false)
        } catch let error as URLError {
            throw SyncError(message: Self.offlineMessage(error))
        }
        let record = response["record"] as? [String: Any]
        serverURL = base
        self.email = record?["email"] as? String ?? trimmedEmail
        token = response["token"] as? String
        userID = record?["id"] as? String
        lastError = nil
        saveState()

        let filter = Self.query("app = \"\(Self.app)\" && deleted = false")
        let remote = try await send("GET", "api/collections/\(Self.collection)/records?perPage=1&skipTotal=1&filter=\(filter)")
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
            seen = [:]
            state.items = state.items.filter { !$0.value.dirty }
            applying = false
        }
        await sync()
    }

    /// Stops syncing on this device. The inventory stays here and on the server.
    func signOut() {
        token = nil
        lastError = nil
        saveState()
    }

    private static func offlineMessage(_ error: URLError) -> String {
        // Most likely Tailscale is off or the NAS is down.
        [.notConnectedToInternet, .cannotFindHost, .cannotConnectToHost, .timedOut,
         .networkConnectionLost, .dnsLookupFailed, .secureConnectionFailed].contains(error.code)
            ? "Can't reach the server. Is Tailscale on?"
            : error.localizedDescription
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
            lastSynced = .now
        } catch let error as URLError {
            lastError = Self.offlineMessage(error)
        } catch let error as SyncError where error.isAuth {
            signOut()
            lastError = "Your sign-in expired or was removed. Sign in again to keep syncing."
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func syncOnce(_ context: ModelContext) async throws {
        try await refreshToken()
        try Self.repairSyncIDs(in: context)
        guard let userID else { return }
        if state.userID != userID {
            // A different account: everything here goes up as new to that account.
            if state.userID != nil {
                state.cursor = nil
                state.items = state.items.filter { !$0.value.deleted }
                for id in state.items.keys {
                    state.items[id]!.recordID = nil
                    state.items[id]!.baseUpdated = nil
                    state.items[id]!.dirty = true
                }
            }
            state.userID = userID
        }
        var local = try noteLocalChanges(in: context)
        var problems: [String] = []
        // A push can find that another device changed an item since the pull;
        // then pull again (resolving the conflict) and push once more.
        for _ in 0..<3 {
            if try await pull(into: context, local: &local) {
                local = try snapshot(in: context)
            }
            if try await !push(local: local, problems: &problems) { break }
        }
        lastError = problems.isEmpty ? nil : "Some changes couldn't be sent: " + problems.joined(separator: "; ")
    }

    /// Marks every record that changed or vanished since the last sync, and
    /// returns the current records.
    private func noteLocalChanges(in context: ModelContext) throws -> [String: LocalRecord] {
        let now = Self.now
        let local = try snapshot(in: context)
        for (id, record) in local where seen[id]?.json != record.canonical {
            seen[id] = Seen(json: record.canonical, at: now)
            markChanged(id, modified: now)
        }
        for id in seen.keys where local[id] == nil {
            seen[id] = nil
            markChanged(id, deleted: true, modified: now)
        }
        saveState()
        return local
    }

    private func markChanged(_ id: String, deleted: Bool = false, modified: Int64) {
        var item = state.items[id] ?? ItemState(modified: 0)
        item.dirty = true
        item.deleted = deleted
        item.modified = modified
        state.items[id] = item
    }

    // MARK: - Pull

    private struct Remote {
        let row: [String: Any]
        let id: String
        let kind: String
        let key: String
        let modified: Int64
        let deleted: Bool
        let data: Data?
        var blob: Data?
    }

    /// Pulls rows changed since the cursor and applies them. Returns whether
    /// anything here changed.
    private func pull(into context: ModelContext, local: inout [String: LocalRecord]) async throws -> Bool {
        var incoming: [Remote] = []
        var fileToken: String?
        // Advanced only once the rows are saved, so a failure pulls them again
        var cursor = state.cursor
        for row in try await listSince(state.cursor) {
            guard let recordID = row["id"] as? String, let kind = row["kind"] as? String,
                  let key = row["item_key"] as? String, let updated = row["updated"] as? String
            else { continue }
            defer { cursor = updated }
            let id = Self.itemID(kind, key)
            let st = state.items[id]
            if let st, st.recordID == recordID, st.baseUpdated == updated { continue }

            let deleted = row["deleted"] as? Bool ?? false
            var remote = Remote(
                row: row, id: id, kind: kind, key: key,
                modified: (row["modified"] as? NSNumber)?.int64Value ?? 0,
                deleted: deleted,
                data: deleted ? nil : (row["data"] as? [String: Any]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            )
            if !deleted, let file = row["blob"] as? String, !file.isEmpty {
                if fileToken == nil { fileToken = try await self.fileToken() }
                remote.blob = try await download(recordID: recordID, file: file, token: fileToken!)
            }

            guard let st, st.dirty else {
                incoming.append(remote)
                continue
            }
            // Changed here too: the newer edit wins. Baselit keeps no losing copies.
            let localModified = local[id].map { max($0.stamp, seen[id]?.at ?? 0) } ?? st.modified
            let localDeleted = st.deleted || local[id] == nil
            if localDeleted && remote.deleted || remote.modified >= localModified {
                incoming.append(remote)
            } else {
                // Stays dirty: the push sends this device's version over the server's
                state.items[id]?.recordID = recordID
                state.items[id]?.baseUpdated = updated
            }
        }
        guard !incoming.isEmpty else {
            state.cursor = cursor
            saveState()
            return false
        }

        applying = true
        defer { applying = false }
        var models = ModelIndex(context: context)
        // Parents first, so a home location never arrives before its house
        let order = ["house", "location", "container", "item", "photo", "homeLocation"]
        incoming.sort { (order.firstIndex(of: $0.kind) ?? 9) < (order.firstIndex(of: $1.kind) ?? 9) }
        for remote in incoming {
            if remote.deleted || remote.data == nil {
                if let model = models.find(kind: remote.kind, id: remote.key) { context.delete(model) }
            } else {
                try models.apply(kind: remote.kind, data: remote.data!, imageData: remote.blob)
            }
        }
        for remote in incoming where !remote.deleted && remote.data != nil {
            try models.link(kind: remote.kind, data: remote.data!)
        }
        try context.save()

        local = try snapshot(in: context)
        for remote in incoming {
            state.items[remote.id] = ItemState(
                recordID: remote.row["id"] as? String,
                baseUpdated: remote.row["updated"] as? String,
                modified: remote.modified,
                deleted: remote.deleted
            )
            if let mine = local[remote.id] {
                seen[remote.id] = Seen(json: mine.canonical, at: remote.modified)
            } else {
                seen[remote.id] = nil
            }
        }
        state.cursor = cursor
        saveState()
        return true
    }

    // MARK: - Push

    /// Sends this device's changes. Returns true if some item changed on the
    /// server meanwhile and needs another pull first.
    private func push(local: [String: LocalRecord], problems: inout [String]) async throws -> Bool {
        var retry = false
        for (id, st) in state.items where st.dirty {
            let (kind, key) = Self.split(id)
            let record = st.deleted ? nil : local[id]
            let deleted = record == nil

            if st.recordID == nil && deleted {
                // Made and deleted here before it ever reached the server.
                state.items[id] = nil
                continue
            }
            var recordID = st.recordID
            if let current = recordID {
                if let row = try await getRecord(current) {
                    if row["updated"] as? String != st.baseUpdated {
                        retry = true
                        continue
                    }
                } else {
                    recordID = nil
                    if deleted {
                        state.items[id] = nil
                        continue
                    }
                }
            }

            var fields: [String: Any] = [
                "owner": userID ?? "", "app": Self.app, "kind": kind, "item_key": key,
                "modified": st.modified, "deleted": deleted, "device": device,
                "data": record?.json ?? NSNull(),
            ]
            let saved: [String: Any]
            do {
                if let blob = record?.imageData {
                    saved = try await saveMultipart(recordID: recordID, fields: fields, blob: blob)
                } else {
                    if recordID != nil { fields["blob"] = NSNull() }
                    let path = "api/collections/\(Self.collection)/records" + (recordID.map { "/\($0)" } ?? "")
                    saved = try await send(recordID == nil ? "POST" : "PATCH", path, body: fields)
                }
            } catch let error as SyncError where !error.isAuth {
                if error.notUnique {
                    // Another device made the same item meanwhile.
                    retry = true
                } else {
                    problems.append("\(id): \(error.message)")
                }
                continue
            }
            state.items[id] = ItemState(
                recordID: saved["id"] as? String,
                baseUpdated: saved["updated"] as? String,
                modified: st.modified,
                dirty: false,
                deleted: deleted
            )
            saveState()
        }
        return retry
    }

    // MARK: - Local records

    private struct LocalRecord {
        let kind: String
        let canonical: String
        let json: Any
        /// When the record says it last changed (ms).
        let stamp: Int64
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
    private static func ms(_ date: Date) -> Int64 { Int64(date.timeIntervalSince1970 * 1000) }

    /// Every record as its backup JSON, keyed by "kind/lowercase sync ID".
    private func snapshot(in context: ModelContext) throws -> [String: LocalRecord] {
        var records: [String: LocalRecord] = [:]
        func add<T: Encodable>(_ kind: String, _ syncID: String, _ dto: T, stamp: Date, imageData: Data? = nil) throws {
            let data = try Self.encoder.encode(dto)
            records[Self.itemID(kind, syncID.lowercased())] = LocalRecord(
                kind: kind,
                canonical: String(decoding: data, as: UTF8.self),
                json: try JSONSerialization.jsonObject(with: data),
                stamp: Self.ms(stamp),
                imageData: imageData
            )
        }

        for house in try context.fetch(FetchDescriptor<House>()) {
            try add("house", house.syncID, ExportHouse(
                exportID: Self.uuid(house.syncID), name: house.name, address: house.address,
                notes: house.notes, createdAt: house.createdAt, updatedAt: house.updatedAt
            ), stamp: house.updatedAt)
        }
        for location in try context.fetch(FetchDescriptor<Location>()) {
            try add("location", location.syncID, ExportLocation(
                exportID: Self.uuid(location.syncID), name: location.name, notes: location.notes,
                createdAt: location.createdAt, updatedAt: location.updatedAt,
                houseExportID: Self.ref(location.house?.syncID),
                parentLocationExportID: Self.ref(location.parentLocation?.syncID)
            ), stamp: location.updatedAt)
        }
        for container in try context.fetch(FetchDescriptor<Container>()) {
            try add("container", container.syncID, ExportContainer(
                exportID: Self.uuid(container.syncID), name: container.name,
                containerType: container.containerType, notes: container.notes,
                identifier: container.identifier, createdAt: container.createdAt,
                updatedAt: container.updatedAt, lastLabelPrintedAt: container.lastLabelPrintedAt,
                parentContainerExportID: Self.ref(container.parentContainer?.syncID),
                locationExportID: Self.ref(container.location?.syncID),
                houseExportID: Self.ref(container.house?.syncID)
            ), stamp: container.updatedAt)
        }
        for item in try context.fetch(FetchDescriptor<Item>()) {
            try add("item", item.syncID, ExportItem(
                exportID: Self.uuid(item.syncID), name: item.name, itemDescription: item.itemDescription,
                quantity: item.quantity, brand: item.brand, model: item.model,
                condition: item.condition, notes: item.notes, identifier: item.identifier,
                createdAt: item.createdAt, updatedAt: item.updatedAt,
                lastLabelPrintedAt: item.lastLabelPrintedAt,
                containerExportID: Self.ref(item.container?.syncID),
                locationExportID: Self.ref(item.location?.syncID),
                houseExportID: Self.ref(item.house?.syncID)
            ), stamp: item.updatedAt)
        }
        for photo in try context.fetch(FetchDescriptor<Photo>()) {
            try add("photo", photo.syncID, ExportPhoto(
                exportID: Self.uuid(photo.syncID), filename: "photo_\(photo.syncID.uppercased()).jpg",
                caption: photo.caption, createdAt: photo.createdAt, sortOrder: photo.sortOrder,
                houseExportID: Self.ref(photo.house?.syncID),
                locationExportID: Self.ref(photo.location?.syncID),
                containerExportID: Self.ref(photo.container?.syncID),
                itemExportID: Self.ref(photo.item?.syncID)
            ), stamp: photo.createdAt, imageData: photo.imageData)
        }
        for home in try context.fetch(FetchDescriptor<HomeLocation>()) {
            guard let house = home.house else { continue }
            try add("homeLocation", home.syncID, ExportHomeLocation(
                exportID: Self.uuid(home.syncID), createdAt: home.createdAt,
                updatedAt: home.updatedAt, houseExportID: Self.uuid(house.syncID),
                locationExportID: Self.ref(home.location?.syncID),
                containerExportID: Self.ref(home.container?.syncID),
                itemExportID: Self.ref(home.item?.syncID),
                ownerContainerExportID: Self.ref(home.ownerContainer?.syncID)
            ), stamp: home.updatedAt)
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

    // MARK: - Server requests (the calls nas_sync's PbClient makes)

    private static func query(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// Baselit rows changed at or after `since` (a server `updated` stamp), oldest first.
    private func listSince(_ since: String?) async throws -> [[String: Any]] {
        var filter = "app = \"\(Self.app)\""
        if let since { filter += " && updated >= \"\(since)\"" }
        var rows: [[String: Any]] = []
        var page = 1
        while true {
            let path = "api/collections/\(Self.collection)/records?filter=\(Self.query(filter))"
                + "&sort=updated,id&page=\(page)&perPage=\(Self.pageSize)&skipTotal=1"
            let items = (try await send("GET", path)["items"] as? [[String: Any]]) ?? []
            rows += items
            if items.count < Self.pageSize { return rows }
            page += 1
        }
    }

    /// One row, or nil if it no longer exists.
    private func getRecord(_ id: String) async throws -> [String: Any]? {
        do {
            return try await send("GET", "api/collections/\(Self.collection)/records/\(id)")
        } catch let error as SyncError where error.status == 404 {
            return nil
        }
    }

    private func fileToken() async throws -> String {
        try await send("POST", "api/files/token")["token"] as? String ?? ""
    }

    private func download(recordID: String, file: String, token fileToken: String) async throws -> Data {
        let request = try makeRequest("GET", "api/files/\(Self.collection)/\(recordID)/\(file)?token=\(fileToken)")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw SyncError(message: "Could not download \(file)", status: status) }
        return data
    }

    private func saveMultipart(recordID: String?, fields: [String: Any], blob: Data) async throws -> [String: Any] {
        let boundary = "Baselit-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        for (name, value) in fields {
            let text: String
            if let string = value as? String {
                text = string
            } else {
                // Numbers, booleans, and JSON go as JSON text, like nas_sync does
                text = String(decoding: try JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed), as: UTF8.self)
            }
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(text)\r\n")
        }
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"blob\"; filename=\"item.bin\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(blob)
        append("\r\n--\(boundary)--\r\n")

        let path = "api/collections/\(Self.collection)/records" + (recordID.map { "/\($0)" } ?? "")
        var request = try makeRequest(recordID == nil ? "POST" : "PATCH", path)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return try await perform(request)
    }

    private func refreshToken() async throws {
        let response = try await send("POST", "api/collections/users/auth-refresh")
        token = response["token"] as? String ?? token
        if let id = (response["record"] as? [String: Any])?["id"] as? String { userID = id }
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
        guard let url = URL(string: (base ?? serverURL ?? "") + "/" + path) else {
            throw SyncError(message: "The server address isn't valid.")
        }
        // Large photos can take a while over Tailscale
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = method
        if authorized, let token { request.setValue(token, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func perform(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard status < 300 else {
            let details = json["data"] as? [String: Any] ?? [:]
            let notUnique = details.values.contains { ($0 as? [String: Any])?["code"] as? String == "validation_not_unique" }
            throw SyncError(message: json["message"] as? String ?? "Server error \(status)",
                            status: status, notUnique: notUnique)
        }
        return json
    }
}

// MARK: - Keychain

/// Keeps the sign-in token in the keychain rather than in the state file.
private enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Babymechanical.Baselit.NasSync",
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
