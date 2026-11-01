// Imports a real backup into a temporary folder and prints counts only.
// Run with BASELIT_BACKUP=/path/to/backup.zip; skipped otherwise.

import 'dart:io';

import 'package:baselit/store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final path = Platform.environment['BASELIT_BACKUP'];
  test('imports a real backup', () async {
    final temp = await Directory.systemTemp.createTemp('baselit_import');
    addTearDown(() => temp.delete(recursive: true));
    final store = InventoryStore();
    await store.load(folder: temp);
    final summary = await store.importBackup(path!);
    // ignore: avoid_print
    print('Imported: $summary');
    expect(store.items, isNotEmpty);

    // Reload from disk to make sure it saved
    final reloaded = InventoryStore();
    await reloaded.load(folder: temp);
    expect(reloaded.items.length, store.items.length);
    final missingPhotos = reloaded.photos
        .where((p) => !reloaded.photoFile(p).existsSync())
        .length;
    // ignore: avoid_print
    print('Photos missing on disk after import: $missingPhotos');
  }, skip: path == null ? 'Set BASELIT_BACKUP to run' : false);
}
