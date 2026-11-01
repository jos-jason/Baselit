// Renders key screens to PNGs for a visual check: flutter test --update-goldens test/preview_test.dart
// Uses the Mac's SF font as a stand-in for Inter, so it only runs on macOS.

import 'dart:io';

import 'package:baselit/main.dart';
import 'package:baselit/models.dart';
import 'package:baselit/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _loadFont(String family, String path) async {
  final loader = FontLoader(family)..addFont(Future.value(ByteData.sublistView(File(path).readAsBytesSync())));
  await loader.load();
}

InventoryStore _sampleStore() {
  final store = InventoryStore()..loaded = true;
  final lake = House(name: 'Lake House');
  final home = House(name: 'Home', address: '12 Birch Lane');
  final garage = Location(name: 'Garage', houseID: lake.exportID);
  final kitchen = Location(name: 'Kitchen', houseID: lake.exportID);
  final office = Location(name: 'Office', houseID: home.exportID);
  final bin = StorageContainer(name: 'Tool Bin', containerType: 'Bin', locationID: garage.exportID);
  final drawer = StorageContainer(name: 'Junk Drawer', locationID: kitchen.exportID);
  final drill = Item(
    name: 'Drill',
    itemDescription: 'Cordless, red battery pack',
    brand: 'Milwaukee',
    notes: 'Tools, Black\ngarage',
    locationID: kitchen.exportID,
  );
  store
    ..houses = [lake, home]
    ..locations = [garage, kitchen, office]
    ..containers = [bin, drawer]
    ..items = [
      drill,
      Item(name: 'Hammer', containerID: bin.exportID),
      Item(name: 'Tape Measure', containerID: bin.exportID),
      Item(name: 'Batteries', quantity: 12, containerID: drawer.exportID),
      Item(name: 'Laptop Charger', locationID: office.exportID),
      Item(name: 'Camping Lantern'),
    ]
    ..homeLocations = [HomeLocation(houseID: lake.exportID, locationID: garage.exportID, itemID: drill.exportID)];
  return store;
}

void main() {
  setUpAll(() async {
    await _loadFont('SF', '/System/Library/Fonts/SFNS.ttf');
    final home = Platform.environment['HOME'];
    await _loadFont('packages/cupertino_icons/CupertinoIcons', '$home/.pub-cache/hosted/pub.dev/cupertino_icons-2.0.0/assets/CupertinoIcons.ttf');
  });

  for (final brightness in Brightness.values) {
    testWidgets('screens in ${brightness.name} mode', (tester) async {
      tester.view.physicalSize = const Size(1206, 2622);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      debugDisableShadows = false;

      await tester.pumpWidget(BaselitApp(store: _sampleStore(), fontFamily: 'SF'));
      await tester.pumpAndSettle();
      final name = brightness.name;

      Future<void> snap(String screen) async {
        await tester.pumpAndSettle();
        await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/${name}_$screen.png'));
      }

      await snap('1_search');
      await tester.tap(find.text('Places'));
      await snap('2_places');
      await tester.tap(find.text('Lake House'));
      await snap('3_house');
      await tester.tap(find.text('Items').last);
      await snap('4_items');
      await tester.tap(find.text('Drill'));
      await snap('5_item_detail');
      debugDisableShadows = true;
    });
  }
}
