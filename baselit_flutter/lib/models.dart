// Data models that mirror the iOS app's backup format (baselit_backup.json).
// Field names match the JSON keys so backups move between platforms unchanged.

import 'dart:math';

import 'package:uuid/uuid.dart';

const _uuid = Uuid();

String newID() => _uuid.v4().toUpperCase();

DateTime? _date(Object? value) =>
    value == null ? null : DateTime.parse(value as String).toLocal();

/// ISO 8601 without fractional seconds, which Swift's `.iso8601` decoder requires.
String isoDate(DateTime date) {
  final utc = date.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}'
      'T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

String? _isoOrNull(DateTime? date) => date == null ? null : isoDate(date);

/// Removes null values so the JSON matches Swift's `encodeIfPresent`.
Map<String, Object?> _compact(Map<String, Object?> map) =>
    map..removeWhere((_, value) => value == null);

class House {
  House({
    String? exportID,
    required this.name,
    this.address,
    this.notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : exportID = exportID ?? newID(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String exportID;
  String name;
  String? address;
  String? notes;
  final DateTime createdAt;
  DateTime updatedAt;

  factory House.fromJson(Map<String, dynamic> json) => House(
    exportID: json['exportID'],
    name: json['name'],
    address: json['address'],
    notes: json['notes'],
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  Map<String, Object?> toJson() => _compact({
    'exportID': exportID,
    'name': name,
    'address': address,
    'notes': notes,
    'createdAt': isoDate(createdAt),
    'updatedAt': isoDate(updatedAt),
  });
}

class Location {
  Location({
    String? exportID,
    required this.name,
    this.notes,
    this.houseID,
    this.parentLocationID,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : exportID = exportID ?? newID(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String exportID;
  String name;
  String? notes;
  String? houseID;
  String? parentLocationID;
  final DateTime createdAt;
  DateTime updatedAt;

  factory Location.fromJson(Map<String, dynamic> json) => Location(
    exportID: json['exportID'],
    name: json['name'],
    notes: json['notes'],
    houseID: json['houseExportID'],
    parentLocationID: json['parentLocationExportID'],
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  Map<String, Object?> toJson() => _compact({
    'exportID': exportID,
    'name': name,
    'notes': notes,
    'createdAt': isoDate(createdAt),
    'updatedAt': isoDate(updatedAt),
    'houseExportID': houseID,
    'parentLocationExportID': parentLocationID,
  });
}

/// A box, bin, drawer, or anything else that holds items.
/// Named `StorageContainer` to avoid clashing with Flutter's `Container` widget.
class StorageContainer {
  StorageContainer({
    String? exportID,
    required this.name,
    this.containerType,
    this.notes,
    String? identifier,
    this.lastLabelPrintedAt,
    this.parentContainerID,
    this.locationID,
    this.houseID,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : exportID = exportID ?? newID(),
       identifier = identifier ?? IdentifierGenerator.generate(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String exportID;
  String name;
  String? containerType;
  String? notes;
  final String identifier;
  DateTime? lastLabelPrintedAt;
  String? parentContainerID;
  String? locationID;
  String? houseID;
  final DateTime createdAt;
  DateTime updatedAt;

  factory StorageContainer.fromJson(Map<String, dynamic> json) =>
      StorageContainer(
        exportID: json['exportID'],
        name: json['name'],
        containerType: json['containerType'],
        notes: json['notes'],
        identifier: json['identifier'],
        lastLabelPrintedAt: _date(json['lastLabelPrintedAt']),
        parentContainerID: json['parentContainerExportID'],
        locationID: json['locationExportID'],
        houseID: json['houseExportID'],
        createdAt: _date(json['createdAt']),
        updatedAt: _date(json['updatedAt']),
      );

  Map<String, Object?> toJson() => _compact({
    'exportID': exportID,
    'name': name,
    'containerType': containerType,
    'notes': notes,
    'identifier': identifier,
    'createdAt': isoDate(createdAt),
    'updatedAt': isoDate(updatedAt),
    'lastLabelPrintedAt': _isoOrNull(lastLabelPrintedAt),
    'parentContainerExportID': parentContainerID,
    'locationExportID': locationID,
    'houseExportID': houseID,
  });
}

class Item {
  Item({
    String? exportID,
    required this.name,
    this.itemDescription,
    this.quantity = 1,
    this.brand,
    this.model,
    this.condition,
    this.notes,
    String? identifier,
    this.lastLabelPrintedAt,
    this.containerID,
    this.locationID,
    this.houseID,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : exportID = exportID ?? newID(),
       identifier = identifier ?? IdentifierGenerator.generate(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String exportID;
  String name;
  String? itemDescription;
  int quantity;
  String? brand;
  String? model;
  String? condition;
  String? notes;
  final String identifier;
  DateTime? lastLabelPrintedAt;
  String? containerID;
  String? locationID;
  String? houseID;
  final DateTime createdAt;
  DateTime updatedAt;

  /// Reads an item, folding any legacy category, colors, and tags into notes
  /// the same way the iOS app does on import.
  factory Item.fromJson(
    Map<String, dynamic> json,
    Map<String, String> tagNames,
  ) {
    final category = json['category'] as String?;
    final colors =
        (json['colors'] as List?)?.cast<String>() ??
        [if (json['color'] != null) json['color'] as String];
    final tags = ((json['tagExportIDs'] as List?) ?? [])
        .map((id) => tagNames[id])
        .whereType<String>();
    final keywords = [
      if (category != null) _capitalized(category),
      ...colors.map(_capitalized),
      ...tags,
    ];
    return Item(
      exportID: json['exportID'],
      name: json['name'],
      itemDescription: json['itemDescription'],
      quantity: json['quantity'] ?? 1,
      brand: json['brand'],
      model: json['model'],
      condition: json['condition'],
      notes: notesAddingKeywords(json['notes'], keywords),
      identifier: json['identifier'],
      lastLabelPrintedAt: _date(json['lastLabelPrintedAt']),
      containerID: json['containerExportID'],
      locationID: json['locationExportID'],
      houseID: json['houseExportID'],
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  Map<String, Object?> toJson() => _compact({
    'exportID': exportID,
    'name': name,
    'itemDescription': itemDescription,
    'quantity': quantity,
    'brand': brand,
    'model': model,
    'condition': condition,
    'notes': notes,
    'identifier': identifier,
    'createdAt': isoDate(createdAt),
    'updatedAt': isoDate(updatedAt),
    'lastLabelPrintedAt': _isoOrNull(lastLabelPrintedAt),
    'containerExportID': containerID,
    'locationExportID': locationID,
    'houseExportID': houseID,
    'tagExportIDs': <String>[],
  });
}

String _capitalized(String word) => word
    .split(' ')
    .map(
      (w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase(),
    )
    .join(' ');

/// Appends keywords to notes as a comma-separated line, skipping any word the
/// notes already contain. Matches `Item.notes(_:addingKeywords:)` on iOS.
String? notesAddingKeywords(String? notes, List<String> keywords) {
  final existing = notes ?? '';
  final words = <String>[];
  for (final keyword in keywords) {
    if (keyword.isEmpty) continue;
    final present =
        existing.toLowerCase().contains(keyword.toLowerCase()) ||
        words.any((w) => w.toLowerCase() == keyword.toLowerCase());
    if (!present) words.add(keyword);
  }
  if (words.isEmpty) return notes;
  final line = words.join(', ');
  final trimmed = existing.trim();
  return trimmed.isEmpty ? line : '$trimmed\n$line';
}

/// Where an item or container belongs at one house.
class HomeLocation {
  HomeLocation({
    String? exportID,
    required this.houseID,
    this.locationID,
    this.containerID,
    this.itemID,
    this.ownerContainerID,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) : exportID = exportID ?? newID(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  final String exportID;
  String houseID;
  String? locationID;
  String? containerID;
  String? itemID;
  String? ownerContainerID;
  final DateTime createdAt;
  DateTime updatedAt;

  factory HomeLocation.fromJson(Map<String, dynamic> json) => HomeLocation(
    exportID: json['exportID'],
    houseID: json['houseExportID'],
    locationID: json['locationExportID'],
    containerID: json['containerExportID'],
    itemID: json['itemExportID'],
    ownerContainerID: json['ownerContainerExportID'],
    createdAt: _date(json['createdAt']),
    updatedAt: _date(json['updatedAt']),
  );

  Map<String, Object?> toJson() => _compact({
    'exportID': exportID,
    'createdAt': isoDate(createdAt),
    'updatedAt': isoDate(updatedAt),
    'houseExportID': houseID,
    'locationExportID': locationID,
    'containerExportID': containerID,
    'itemExportID': itemID,
    'ownerContainerExportID': ownerContainerID,
  });
}

/// A photo record. The image itself lives in the photos folder as `filename`.
class Photo {
  Photo({
    String? exportID,
    required this.filename,
    this.caption,
    this.sortOrder = 0,
    this.houseID,
    this.locationID,
    this.containerID,
    this.itemID,
    DateTime? createdAt,
  }) : exportID = exportID ?? newID(),
       createdAt = createdAt ?? DateTime.now();

  final String exportID;
  final String filename;
  String? caption;
  int sortOrder;
  String? houseID;
  String? locationID;
  String? containerID;
  String? itemID;
  final DateTime createdAt;

  factory Photo.fromJson(Map<String, dynamic> json) => Photo(
    exportID: json['exportID'],
    filename: json['filename'],
    caption: json['caption'],
    sortOrder: json['sortOrder'] ?? 0,
    houseID: json['houseExportID'],
    locationID: json['locationExportID'],
    containerID: json['containerExportID'],
    itemID: json['itemExportID'],
    createdAt: _date(json['createdAt']),
  );

  Map<String, Object?> toJson() => _compact({
    'exportID': exportID,
    'filename': filename,
    'caption': caption,
    'createdAt': isoDate(createdAt),
    'sortOrder': sortOrder,
    'houseExportID': houseID,
    'locationExportID': locationID,
    'containerExportID': containerID,
    'itemExportID': itemID,
  });
}

/// Memorable two-word identifiers (e.g. "Calm River"), same word lists as iOS.
class IdentifierGenerator {
  static final _random = Random();

  static const adjectives = [
    'Amber',
    'Bold',
    'Bright',
    'Calm',
    'Clear',
    'Coral',
    'Crisp',
    'Dusk',
    'Fern',
    'Frost',
    'Gold',
    'Grand',
    'Green',
    'Iron',
    'Jade',
    'Keen',
    'Lush',
    'Maple',
    'Misty',
    'Noble',
    'Oak',
    'Pearl',
    'Pine',
    'Quiet',
    'Rapid',
    'Reed',
    'Ruby',
    'Sage',
    'Salt',
    'Silver',
    'Slate',
    'Snow',
    'Solar',
    'Stone',
    'Storm',
    'Swift',
    'Teal',
    'Timber',
    'Warm',
    'Wild',
    'Birch',
    'Cloud',
    'Copper',
    'Dawn',
    'Ember',
    'Flint',
    'Glen',
    'Hazel',
    'Ivy',
    'Lake',
    'Lunar',
    'Moss',
    'North',
    'Olive',
    'Onyx',
    'Plum',
    'Rain',
    'Rust',
    'Sandy',
    'Silk',
    'Smoky',
    'Steep',
    'Sunlit',
    'Thistle',
    'Velvet',
    'Violet',
    'Willow',
    'Aspen',
    'Basalt',
    'Blaze',
    'Brisk',
    'Cedar',
    'Clay',
    'Cobalt',
    'Crest',
    'Drift',
    'Dusky',
    'Forge',
    'Gale',
    'Harbor',
    'Linen',
    'Mallow',
    'Mint',
    'Opal',
    'Polar',
    'Pyre',
    'Quartz',
    'Raven',
    'Ridge',
    'Rowan',
    'Scarlet',
    'Spruce',
    'Tide',
    'Umber',
    'Vista',
  ];

  static const nouns = [
    'Arrow',
    'Basin',
    'Bear',
    'Brook',
    'Canyon',
    'Cliff',
    'Cove',
    'Crane',
    'Creek',
    'Crow',
    'Deer',
    'Dove',
    'Dune',
    'Eagle',
    'Elk',
    'Falcon',
    'Field',
    'Finch',
    'Flare',
    'Fox',
    'Grove',
    'Gull',
    'Hawk',
    'Haven',
    'Heron',
    'Hill',
    'Hollow',
    'Inlet',
    'Lark',
    'Ledge',
    'Lodge',
    'Marsh',
    'Mesa',
    'Moth',
    'Nest',
    'Otter',
    'Owl',
    'Pass',
    'Path',
    'Peak',
    'Pike',
    'Pond',
    'Quail',
    'Reef',
    'Ridge',
    'River',
    'Robin',
    'Shore',
    'Spark',
    'Sprout',
    'Stone',
    'Summit',
    'Swallow',
    'Thicket',
    'Trail',
    'Vale',
    'Wren',
    'Arch',
    'Badger',
    'Bluff',
    'Briar',
    'Bridge',
    'Burrow',
    'Cape',
    'Cavern',
    'Cinder',
    'Dale',
    'Den',
    'Drift',
    'Fern',
    'Fjord',
    'Forge',
    'Glade',
    'Gorge',
    'Heath',
    'Hound',
    'Isle',
    'Knoll',
    'Lynx',
    'Meadow',
    'Mink',
    'Moose',
    'Notch',
    'Osprey',
    'Pebble',
    'Perch',
    'Prairie',
    'Quarry',
    'Raven',
    'Shoal',
    'Slope',
    'Spire',
    'Stag',
    'Terrace',
    'Timber',
    'Tower',
    'Tundra',
    'Viper',
    'Wharf',
    'Wolf',
  ];

  static String generate() =>
      '${adjectives[_random.nextInt(adjectives.length)]} ${nouns[_random.nextInt(nouns.length)]}';
}
