// The app's data, saved on disk in the same layout as an iOS backup:
// `baselit_backup.json` plus a `photos/` folder. Importing or exporting a
// backup is therefore just copying that layout in or out of a zip.

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

class InventoryStore extends ChangeNotifier {
  late Directory _root;
  bool loaded = false;

  List<House> houses = [];
  List<Location> locations = [];
  List<StorageContainer> containers = [];
  List<Item> items = [];
  List<Photo> photos = [];
  List<HomeLocation> homeLocations = [];

  File get _dataFile => File('${_root.path}/baselit_backup.json');
  Directory get _photosDir => Directory('${_root.path}/photos');

  // MARK: - Loading and saving

  /// [folder] replaces the app's own data folder, for tests.
  Future<void> load({Directory? folder}) async {
    _root =
        folder ??
        Directory('${(await getApplicationSupportDirectory()).path}/inventory');
    await _photosDir.create(recursive: true);
    if (await _dataFile.exists()) {
      _readManifest(jsonDecode(await _dataFile.readAsString()));
    }
    loaded = true;
    notifyListeners();
  }

  void _readManifest(Map<String, dynamic> json) {
    List<Map<String, dynamic>> list(String key) =>
        ((json[key] as List?) ?? []).cast<Map<String, dynamic>>();
    final tagNames = {
      for (final tag in list('tags'))
        tag['exportID'] as String: tag['name'] as String,
    };
    houses = list('houses').map(House.fromJson).toList();
    locations = list('locations').map(Location.fromJson).toList();
    containers = list('containers').map(StorageContainer.fromJson).toList();
    items = list('items').map((j) => Item.fromJson(j, tagNames)).toList();
    photos = list('photos').map(Photo.fromJson).toList();
    homeLocations = list('homeLocations').map(HomeLocation.fromJson).toList();
  }

  Map<String, Object?> _manifest() => {
    'version': 2,
    'exportDate': isoDate(DateTime.now()),
    'includesPhotos': true,
    'houses': houses.map((h) => h.toJson()).toList(),
    'locations': locations.map((l) => l.toJson()).toList(),
    'containers': containers.map((c) => c.toJson()).toList(),
    'items': items.map((i) => i.toJson()).toList(),
    'tags': <Object>[],
    'photos': photos.map((p) => p.toJson()).toList(),
    'homeLocations': homeLocations.map((h) => h.toJson()).toList(),
  };

  Future<void> _save() async {
    final encoder = const JsonEncoder.withIndent('  ');
    final temp = File('${_dataFile.path}.tmp');
    await temp.writeAsString(encoder.convert(_manifest()));
    await temp.rename(_dataFile.path);
  }

  /// Saves and refreshes every screen.
  Future<void> commit() async {
    notifyListeners();
    await _save();
  }

  // MARK: - Lookups

  House? house(String? id) => _find(houses, id, (h) => h.exportID);
  Location? location(String? id) => _find(locations, id, (l) => l.exportID);
  StorageContainer? container(String? id) =>
      _find(containers, id, (c) => c.exportID);
  Item? item(String? id) => _find(items, id, (i) => i.exportID);

  static T? _find<T>(List<T> list, String? id, String Function(T) key) {
    if (id == null) return null;
    for (final element in list) {
      if (key(element) == id) return element;
    }
    return null;
  }

  House? locationHouse(Location location) {
    var current = location;
    final seen = <String>{};
    while (seen.add(current.exportID)) {
      if (current.houseID != null) return house(current.houseID);
      final parent = this.location(current.parentLocationID);
      if (parent == null) return null;
      current = parent;
    }
    return null;
  }

  Location? containerLocation(StorageContainer container) {
    var current = container;
    final seen = <String>{};
    while (seen.add(current.exportID)) {
      if (current.locationID != null) return location(current.locationID);
      final parent = this.container(current.parentContainerID);
      if (parent == null) return null;
      current = parent;
    }
    return null;
  }

  House? containerHouse(StorageContainer container) {
    if (container.houseID != null) return house(container.houseID);
    final location = containerLocation(container);
    if (location != null) return locationHouse(location);
    final parent = this.container(container.parentContainerID);
    return parent == null ? null : containerHouse(parent);
  }

  House? itemHouse(Item item) {
    if (item.houseID != null) return house(item.houseID);
    final container = this.container(item.containerID);
    if (container != null) return containerHouse(container);
    final location = this.location(item.locationID);
    return location == null ? null : locationHouse(location);
  }

  // MARK: - Breadcrumbs (same order as iOS: house › location › container)

  List<String> locationPath(Location location) {
    final parts = <String>[location.name];
    var parent = this.location(location.parentLocationID);
    final seen = {location.exportID};
    while (parent != null && seen.add(parent.exportID)) {
      parts.insert(0, parent.name);
      parent = this.location(parent.parentLocationID);
    }
    final house = locationHouse(location);
    if (house != null) parts.insert(0, house.name);
    return parts;
  }

  List<String> containerPath(StorageContainer container) {
    final parts = <String>[container.name];
    var parent = this.container(container.parentContainerID);
    final seen = {container.exportID};
    while (parent != null && seen.add(parent.exportID)) {
      parts.insert(0, parent.name);
      parent = this.container(parent.parentContainerID);
    }
    final location = containerLocation(container);
    if (location != null) return [...locationPath(location), ...parts];
    final house = containerHouse(container);
    return house == null ? parts : [house.name, ...parts];
  }

  List<String> itemPath(Item item) {
    final container = this.container(item.containerID);
    if (container != null) return containerPath(container);
    final location = this.location(item.locationID);
    if (location != null) return locationPath(location);
    final house = this.house(item.houseID);
    return house == null ? ['Unassigned'] : [house.name];
  }

  List<String> homePath(HomeLocation home) {
    final container = this.container(home.containerID);
    if (container != null) return containerPath(container);
    final location = this.location(home.locationID);
    if (location != null) return locationPath(location);
    return [house(home.houseID)?.name ?? 'Unknown house'];
  }

  // MARK: - Children

  List<T> _sorted<T>(Iterable<T> list, String Function(T) name) => list.toList()
    ..sort((a, b) => name(a).toLowerCase().compareTo(name(b).toLowerCase()));

  List<House> get sortedHouses => _sorted(houses, (h) => h.name);

  List<Location> topLocations(House house) => _sorted(
    locations.where(
      (l) => l.houseID == house.exportID && l.parentLocationID == null,
    ),
    (l) => l.name,
  );

  List<Location> subLocations(Location location) => _sorted(
    locations.where((l) => l.parentLocationID == location.exportID),
    (l) => l.name,
  );

  List<StorageContainer> containersInHouse(House house) => _sorted(
    containers.where(
      (c) =>
          c.houseID == house.exportID &&
          c.locationID == null &&
          c.parentContainerID == null,
    ),
    (c) => c.name,
  );

  List<StorageContainer> containersInLocation(Location location) => _sorted(
    containers.where(
      (c) => c.locationID == location.exportID && c.parentContainerID == null,
    ),
    (c) => c.name,
  );

  List<StorageContainer> subContainers(StorageContainer container) => _sorted(
    containers.where((c) => c.parentContainerID == container.exportID),
    (c) => c.name,
  );

  List<Item> itemsInHouse(House house) => _sorted(
    items.where(
      (i) =>
          i.houseID == house.exportID &&
          i.locationID == null &&
          i.containerID == null,
    ),
    (i) => i.name,
  );

  List<Item> itemsInLocation(Location location) => _sorted(
    items.where(
      (i) => i.locationID == location.exportID && i.containerID == null,
    ),
    (i) => i.name,
  );

  List<Item> itemsInContainer(StorageContainer container) => _sorted(
    items.where((i) => i.containerID == container.exportID),
    (i) => i.name,
  );

  List<Item> get unassignedItems =>
      _sorted(items.where((i) => itemHouse(i) == null), (i) => i.name);

  List<StorageContainer> get sortedContainers =>
      _sorted(containers, (c) => c.name);

  List<Item> get sortedItems => _sorted(items, (i) => i.name);

  // MARK: - Everything inside a place, at any depth (for "View All" bubble grids)

  bool _containerInside(StorageContainer container, StorageContainer outer) {
    var parent = this.container(container.parentContainerID);
    final seen = <String>{container.exportID};
    while (parent != null && seen.add(parent.exportID)) {
      if (parent.exportID == outer.exportID) return true;
      parent = this.container(parent.parentContainerID);
    }
    return false;
  }

  bool _locationInside(Location? location, Location outer) {
    final seen = <String>{};
    while (location != null && seen.add(location.exportID)) {
      if (location.exportID == outer.exportID) return true;
      location = this.location(location.parentLocationID);
    }
    return false;
  }

  List<StorageContainer> containersWithinContainer(StorageContainer outer) =>
      containers.where((c) => _containerInside(c, outer)).toList();

  List<Item> itemsWithinContainer(StorageContainer outer) => items.where((i) {
    final container = this.container(i.containerID);
    return container != null &&
        (container.exportID == outer.exportID ||
            _containerInside(container, outer));
  }).toList();

  List<StorageContainer> containersWithinLocation(Location outer) => containers
      .where((c) => _locationInside(containerLocation(c), outer))
      .toList();

  List<Item> itemsWithinLocation(Location outer) => items.where((i) {
    final container = this.container(i.containerID);
    final location = container != null
        ? containerLocation(container)
        : this.location(i.locationID);
    return _locationInside(location, outer);
  }).toList();

  List<StorageContainer> containersWithinHouse(House house) => containers
      .where((c) => containerHouse(c)?.exportID == house.exportID)
      .toList();

  List<Item> itemsWithinHouse(House house) =>
      items.where((i) => itemHouse(i)?.exportID == house.exportID).toList();

  List<HomeLocation> homesForItem(Item item) =>
      homeLocations.where((h) => h.itemID == item.exportID).toList();

  List<HomeLocation> homesForContainer(StorageContainer container) =>
      homeLocations
          .where((h) => h.ownerContainerID == container.exportID)
          .toList();

  // MARK: - Photos

  List<Photo> photosFor({String? itemID, String? containerID}) =>
      photos
          .where(
            (p) =>
                (itemID != null && p.itemID == itemID) ||
                (containerID != null && p.containerID == containerID),
          )
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  File photoFile(Photo photo) => File('${_photosDir.path}/${photo.filename}');

  Future<void> addPhoto(
    File source, {
    String? itemID,
    String? containerID,
  }) async {
    final id = newID();
    final extension = source.path.split('.').last.toLowerCase();
    final filename = 'photo_$id.${extension.length <= 4 ? extension : 'jpg'}';
    await source.copy('${_photosDir.path}/$filename');
    final existing = photosFor(itemID: itemID, containerID: containerID);
    photos.add(
      Photo(
        exportID: id,
        filename: filename,
        sortOrder: existing.isEmpty ? 0 : existing.last.sortOrder + 1,
        itemID: itemID,
        containerID: containerID,
      ),
    );
    await commit();
  }

  // MARK: - Search (name, description, notes, brand, model — like iOS)

  List<Item> searchItems(String query, {String? houseID}) {
    final q = query.trim().toLowerCase();
    return sortedItems.where((item) {
      final matches =
          q.isEmpty ||
          [
            item.name,
            item.itemDescription,
            item.notes,
            item.brand,
            item.model,
          ].any((field) => field?.toLowerCase().contains(q) ?? false);
      return matches &&
          (houseID == null || itemHouse(item)?.exportID == houseID);
    }).toList();
  }

  List<StorageContainer> searchContainers(String query, {String? houseID}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];
    return sortedContainers.where((c) {
      final matches = [
        c.name,
        c.containerType,
        c.notes,
      ].any((field) => field?.toLowerCase().contains(q) ?? false);
      return matches &&
          (houseID == null || containerHouse(c)?.exportID == houseID);
    }).toList();
  }

  // MARK: - Editing

  Future<void> saveItem(Item item) async {
    item.updatedAt = DateTime.now();
    if (!items.contains(item)) items.add(item);
    await commit();
  }

  Future<void> deleteItem(Item item) async {
    items.remove(item);
    homeLocations.removeWhere((h) => h.itemID == item.exportID);
    for (final photo
        in photos.where((p) => p.itemID == item.exportID).toList()) {
      photos.remove(photo);
      final file = photoFile(photo);
      if (await file.exists()) await file.delete();
    }
    await commit();
  }

  Future<void> addHouse(String name) async {
    houses.add(House(name: name));
    await commit();
  }

  Future<void> addLocation(String name, House house) async {
    locations.add(Location(name: name, houseID: house.exportID));
    await commit();
  }

  /// Sets the item's home at its current house to where it is right now.
  Future<void> setCurrentSpotAsHome(Item item) async {
    final house = itemHouse(item);
    if (house == null) return;
    final container = this.container(item.containerID);
    final locationID = container != null
        ? containerLocation(container)?.exportID
        : item.locationID;
    final existing = homesForItem(item)
        .where((h) => h.houseID == house.exportID);
    if (existing.isNotEmpty) {
      existing.first
        ..locationID = locationID
        ..containerID = container?.exportID
        ..updatedAt = DateTime.now();
    } else {
      homeLocations.add(
        HomeLocation(
          houseID: house.exportID,
          locationID: locationID,
          containerID: container?.exportID,
          itemID: item.exportID,
        ),
      );
    }
    await commit();
  }

  bool isAtHome(Item item) {
    final house = itemHouse(item);
    if (house == null) return false;
    final container = this.container(item.containerID);
    final locationID = container != null
        ? containerLocation(container)?.exportID
        : item.locationID;
    return homesForItem(item).any(
      (h) =>
          h.houseID == house.exportID &&
          h.locationID == locationID &&
          h.containerID == container?.exportID,
    );
  }

  // MARK: - Backups

  /// Replaces everything with the contents of an iOS (or Flutter) backup.
  /// [path] can be the backup .zip, an unzipped backup folder, or the
  /// `baselit_backup.json` inside one (photos are read from beside it).
  Future<String> importBackup(String path) async {
    final List<int> json;
    final photoFiles = <String, Future<List<int>> Function()>{};

    if (path.toLowerCase().endsWith('.zip')) {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final jsonEntry = archive.files.where(
        (f) =>
            f.isFile &&
            f.name.split('/').last == _backupJson &&
            !f.name.contains('__MACOSX'),
      );
      if (jsonEntry.isEmpty) {
        throw const FormatException('No baselit_backup.json in this zip.');
      }
      final entry = jsonEntry.first;
      final prefix = entry.name.substring(
        0,
        entry.name.length - _backupJson.length,
      );
      json = entry.content as List<int>;
      for (final file in archive.files) {
        if (file.isFile && file.name.startsWith('${prefix}photos/')) {
          photoFiles[file.name.split('/').last] = () async =>
              file.content as List<int>;
        }
      }
    } else {
      final jsonFile = await _findBackupJson(path);
      if (jsonFile == null) {
        throw const FormatException('No baselit_backup.json in this folder.');
      }
      json = await jsonFile.readAsBytes();
      final photosDir = Directory('${jsonFile.parent.path}/photos');
      if (await photosDir.exists()) {
        await for (final entity in photosDir.list()) {
          if (entity is File) {
            photoFiles[entity.uri.pathSegments.last] = entity.readAsBytes;
          }
        }
      }
    }

    _readManifest(jsonDecode(utf8.decode(json)));

    if (await _photosDir.exists()) await _photosDir.delete(recursive: true);
    await _photosDir.create(recursive: true);
    var photoCount = 0;
    for (final MapEntry(key: name, value: read) in photoFiles.entries) {
      if (name.isEmpty || name.startsWith('.')) continue;
      await File('${_photosDir.path}/$name').writeAsBytes(await read());
      photoCount++;
    }
    await commit();
    return '${houses.length} houses, ${locations.length} locations, '
        '${containers.length} containers, ${items.length} items, $photoCount photos';
  }

  static const _backupJson = 'baselit_backup.json';

  /// The backup JSON at [path], or inside it (the iOS export puts it one folder down).
  static Future<File?> _findBackupJson(String path) async {
    if (path.toLowerCase().endsWith('.json')) return File(path);
    final dir = Directory(path);
    final direct = File('${dir.path}/$_backupJson');
    if (await direct.exists()) return direct;
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final nested = File('${entity.path}/$_backupJson');
        if (await nested.exists()) return nested;
      }
    }
    return null;
  }

  /// Writes a backup zip the iOS app can import.
  Future<void> exportBackup(String zipPath) async {
    final archive = Archive();
    final json = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(_manifest()),
    );
    archive.addFile(ArchiveFile('baselit_backup.json', json.length, json));
    for (final photo in photos) {
      final file = photoFile(photo);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      archive.addFile(
        ArchiveFile('photos/${photo.filename}', bytes.length, bytes),
      );
    }
    await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));
  }
}

/// Makes the store available to every screen and rebuilds them when it changes.
class StoreScope extends InheritedNotifier<InventoryStore> {
  const StoreScope({
    super.key,
    required InventoryStore store,
    required super.child,
  }) : super(notifier: store);

  static InventoryStore of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StoreScope>()!.notifier!;
}
