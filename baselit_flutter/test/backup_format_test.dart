// Checks that records written by the iOS app read correctly and are written back
// in a form Swift's ISO 8601 decoder accepts.

import 'package:baselit/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads an iOS item and folds legacy category, colors, and tags into notes', () {
    final item = Item.fromJson({
      'exportID': 'A1B2C3D4-0000-0000-0000-000000000001',
      'name': 'Drill',
      'quantity': 1,
      'notes': 'garage',
      'identifier': 'Calm River',
      'createdAt': '2026-06-10T12:00:00Z',
      'updatedAt': '2026-06-11T08:30:15Z',
      'category': 'tools',
      'colors': ['black'],
      'tagExportIDs': ['TAG-1'],
      'locationExportID': 'LOC-1',
    }, {'TAG-1': 'Cordless'});

    expect(item.notes, 'garage\nTools, Black, Cordless');
    expect(item.identifier, 'Calm River');
    expect(item.locationID, 'LOC-1');
    expect(item.updatedAt.toUtc(), DateTime.utc(2026, 6, 11, 8, 30, 15));
  });

  test('writes dates without fractional seconds and leaves out empty fields', () {
    final json = Item(name: 'Hammer', createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5, 678)).toJson();
    expect(json['createdAt'], '2026-01-02T03:04:05Z');
    expect(json.containsKey('brand'), isFalse);
    expect(json['tagExportIDs'], isEmpty);
    expect(RegExp(r'^[0-9A-F-]{36}$').hasMatch(json['exportID'] as String), isTrue);
  });
}
