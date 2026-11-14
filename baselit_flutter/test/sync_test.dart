// Syncs two devices through a stand-in for the NAS's PocketBase `sync_items`
// collection and checks that adds, edits, photos, deletions, and conflicts
// reach the other device.

import 'dart:convert';
import 'dart:io';

import 'package:baselit/models.dart';
import 'package:baselit/store.dart';
import 'package:baselit/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Just enough of PocketBase and the `sync_items` collection
/// (github.com/jos-jason/nas-sync) for Baselit sync.
class FakeNas {
  final rows = <String, Map<String, dynamic>>{};
  final files = <String, List<int>>{};
  var _clock = 0;
  var _ids = 0;

  String _now() =>
      '2026-01-01 00:00:${(_clock++).toString().padLeft(6, '0')}.000Z';

  Iterable<Map<String, dynamic>> baselit(String kind) =>
      rows.values.where((r) => r['app'] == 'baselit' && r['kind'] == kind);

  Map<String, dynamic>? byKey(String key) =>
      rows.values.where((r) => r['item_key'] == key).firstOrNull;

  late final client = MockClient((request) async {
    final path = request.url.path;
    http.Response json(Object value, [int status = 200]) =>
        http.Response(jsonEncode(value), status);
    final authorized = request.headers['Authorization'] == 'token-u1';
    const user = {'id': 'u1', 'email': 'me@example.com'};

    if (path == '/api/collections/users/auth-with-password') {
      final body = jsonDecode(request.body);
      return body['password'] == 'secret'
          ? json({'token': 'token-u1', 'record': user})
          : json({'message': 'Failed to authenticate.'}, 400);
    }
    if (path.startsWith('/api/files/sync_items/')) {
      final id = request.url.pathSegments[3];
      return request.url.queryParameters['token'] == 'ft' && files[id] != null
          ? http.Response.bytes(files[id]!, 200)
          : json({'message': 'Not found'}, 404);
    }
    if (!authorized) return json({'message': 'Unauthorized'}, 401);
    if (path == '/api/collections/users/auth-refresh') {
      return json({'token': 'token-u1', 'record': user});
    }
    if (path == '/api/files/token') return json({'token': 'ft'});

    const records = '/api/collections/sync_items/records';
    if (path == records && request.method == 'GET') {
      final filter = request.url.queryParameters['filter'] ?? '';
      final app = RegExp(r'app = "([^"]+)"').firstMatch(filter)?.group(1);
      final since = RegExp(r'updated >= "([^"]+)"')
          .firstMatch(filter)
          ?.group(1);
      var list = rows.values.where((r) => r['app'] == app).toList()
        ..sort(
          (a, b) => '${a['updated']}${a['id']}'.compareTo(
            '${b['updated']}${b['id']}',
          ),
        );
      if (since != null) {
        list = list
            .where((r) => (r['updated'] as String).compareTo(since) >= 0)
            .toList();
      }
      if (filter.contains('deleted = false')) {
        list = list.where((r) => r['deleted'] != true).toList();
      }
      final perPage = int.parse(request.url.queryParameters['perPage']!);
      final page = int.parse(request.url.queryParameters['page'] ?? '1');
      return json({
        'items': list.skip((page - 1) * perPage).take(perPage).toList(),
      });
    }
    if (path.startsWith('$records/') && request.method == 'GET') {
      final row = rows[request.url.pathSegments.last];
      return row == null ? json({'message': 'Not found'}, 404) : json(row);
    }
    if (path.startsWith(records) &&
        (request.method == 'POST' || request.method == 'PATCH')) {
      final (fields, blob) = _fields(request);
      final Map<String, dynamic> row;
      if (request.method == 'POST') {
        if (fields['owner'] != 'u1') {
          return json({'message': 'Failed to create record.'}, 400);
        }
        final taken = rows.values.any(
          (r) =>
              r['owner'] == 'u1' &&
              r['app'] == fields['app'] &&
              r['kind'] == fields['kind'] &&
              r['item_key'] == fields['item_key'],
        );
        if (taken) {
          return json({
            'message': 'Failed to create record.',
            'data': {
              'item_key': {
                'code': 'validation_not_unique',
                'message': 'Value must be unique.',
              },
            },
          }, 400);
        }
        final id = 'r${(_ids++).toString().padLeft(14, '0')}';
        row = rows[id] = {'id': id, 'blob': ''};
      } else {
        final existing = rows[request.url.pathSegments.last];
        if (existing == null) return json({'message': 'Not found'}, 404);
        row = existing;
      }
      final clearsBlob = fields.containsKey('blob');
      fields.remove('blob');
      row.addAll(fields);
      if (blob != null) {
        files[row['id']] = blob;
        row['blob'] = 'item_abc.bin';
      } else if (clearsBlob) {
        files.remove(row['id']);
        row['blob'] = '';
      }
      row['updated'] = _now();
      return json(row);
    }
    return json({'message': 'Unexpected ${request.method} $path'}, 500);
  });

  /// JSON bodies as they are; multipart text fields decoded like PocketBase does.
  static (Map<String, dynamic>, List<int>?) _fields(http.Request request) {
    if (!request.headers['content-type']!.startsWith('multipart')) {
      return (Map<String, dynamic>.from(jsonDecode(request.body)), null);
    }
    final boundary = request.headers['content-type']!.split('boundary=').last;
    final text = latin1.decode(request.bodyBytes);
    final fields = <String, dynamic>{};
    List<int>? blob;
    for (final part in text.split('--$boundary')) {
      final split = part.indexOf('\r\n\r\n');
      if (split < 0) continue;
      final head = part.substring(0, split);
      final value = part.substring(split + 4, part.length - 2);
      final name = RegExp(r'name="([^"]+)"').firstMatch(head)!.group(1)!;
      if (name == 'blob') {
        blob = latin1.encode(value);
        continue;
      }
      final string = utf8.decode(latin1.encode(value));
      fields[name] = switch (name) {
        'modified' => int.parse(string),
        'deleted' => string == 'true',
        'data' => jsonDecode(string),
        _ => string,
      };
    }
    return (fields, blob);
  }
}

Future<(InventoryStore, SyncService)> _device(
  FakeNas server,
  String name,
) async {
  final dir = Directory.systemTemp.createTempSync('baselit_sync');
  addTearDown(() => dir.deleteSync(recursive: true));
  final store = InventoryStore();
  await store.load(folder: Directory('${dir.path}/inventory'));
  final sync = SyncService(store, httpClient: server.client, device: name);
  await sync.load();
  return (store, sync);
}

void main() {
  test('two devices stay in sync', () async {
    final server = FakeNas();
    final (phone, phoneSync) = await _device(server, 'phone');
    final (laptop, laptopSync) = await _device(server, 'laptop');

    // The phone has an inventory with a photo and signs in first
    final house = House(name: 'Lake House');
    final garage = Location(name: 'Garage', houseID: house.exportID);
    final drill = Item(name: 'Drill', locationID: garage.exportID);
    phone
      ..houses = [house]
      ..locations = [garage]
      ..items = [drill];
    final photo = Photo(filename: 'drill.jpg', itemID: drill.exportID);
    phone.photos = [photo];
    await phone.photoFile(photo).writeAsBytes([1, 2, 3, 250]);
    await phone.commit();

    expect(
      await phoneSync.signIn('http://nas.test/', 'me@example.com', 'secret'),
      isFalse,
    );
    await phoneSync.firstSync(FirstSync.merge);
    expect(phoneSync.lastError, isNull);
    expect(server.rows.length, 4);
    final row = server.byKey(drill.exportID.toLowerCase())!;
    expect(
      [row['app'], row['kind'], row['device'], row['deleted']],
      ['baselit', 'item', 'phone', false],
    );
    expect(row['data']['name'], 'Drill');
    expect(row['modified'], isA<int>());
    expect(server.files.values.single, [1, 2, 3, 250]);

    // The empty laptop signs in and gets everything, photo file included
    expect(
      await laptopSync.signIn('http://nas.test', 'me@example.com', 'secret'),
      isFalse,
    );
    await laptopSync.firstSync(FirstSync.merge);
    expect(laptop.items.single.name, 'Drill');
    expect(laptop.itemPath(laptop.items.single), ['Lake House', 'Garage']);
    expect(await laptop.photoFile(laptop.photos.single).readAsBytes(), [
      1,
      2,
      3,
      250,
    ]);

    // An edit on the laptop reaches the phone
    laptop.items.single.brand = 'Milwaukee';
    await laptop.commit();
    await laptopSync.sync();
    await phoneSync.sync();
    expect(phone.items.single.brand, 'Milwaukee');

    // A deletion on the phone reaches the laptop, photo file and all
    final laptopPhoto = laptop.photoFile(laptop.photos.single);
    await phone.deleteItem(phone.items.single);
    await phoneSync.sync();
    await laptopSync.sync();
    expect(laptop.items, isEmpty);
    expect(laptop.photos, isEmpty);
    expect(await laptopPhoto.exists(), isFalse);
    expect(server.byKey(drill.exportID.toLowerCase())!['deleted'], isTrue);

    // Both rename the garage before syncing; the later edit wins on both devices
    phone.locations.single.name = 'Shop';
    await phone.commit();
    await phoneSync.sync();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    laptop.locations.single.name = 'Workshop';
    await laptop.commit();
    // The laptop hadn't seen the phone's rename yet, so this is a conflict
    await laptopSync.sync();
    await phoneSync.sync();
    expect(phone.locations.single.name, 'Workshop');
    expect(laptop.locations.single.name, 'Workshop');

    // Syncing again with nothing changed sends no writes
    final before = server.rows.values.map((r) => r['updated']).toList();
    await phoneSync.sync();
    await laptopSync.sync();
    expect(server.rows.values.map((r) => r['updated']).toList(), before);
  });

  test('a device can replace its inventory with the server\'s', () async {
    final server = FakeNas();
    final (phone, phoneSync) = await _device(server, 'phone');
    final (tablet, tabletSync) = await _device(server, 'tablet');
    phone.houses = [House(name: 'Home')];
    await phone.commit();
    await phoneSync.signIn('http://nas.test', 'me@example.com', 'secret');
    await phoneSync.firstSync(FirstSync.merge);

    tablet.houses = [House(name: 'Old Copy')];
    await tablet.commit();
    expect(
      await tabletSync.signIn('http://nas.test', 'me@example.com', 'secret'),
      isTrue,
    );
    await tabletSync.firstSync(FirstSync.useServer);
    expect(tablet.houses.map((h) => h.name), ['Home']);
    // The replaced house never reaches the server or the phone
    await phoneSync.sync();
    expect(phone.houses.map((h) => h.name), ['Home']);
    expect(server.rows.length, 1);
  });

  test('other apps\' rows are left alone', () async {
    final server = FakeNas();
    server.rows['inkpad1'] = {
      'id': 'inkpad1',
      'owner': 'u1',
      'app': 'inkpad',
      'kind': 'drawing',
      'item_key': 'd1',
      'modified': 1,
      'deleted': false,
      'data': {'name': 'Sketch'},
      'blob': '',
      'updated': '2026-01-01 00:00:000000.000Z',
    };
    final (store, sync) = await _device(server, 'phone');
    store.houses = [House(name: 'Home')];
    await store.commit();
    await sync.signIn('http://nas.test', 'me@example.com', 'secret');
    await sync.firstSync(FirstSync.merge);
    expect(store.houses.length, 1);
    expect(server.rows['inkpad1']!['updated'], '2026-01-01 00:00:000000.000Z');
    expect(server.baselit('house').length, 1);
  });

  test(
    'records written by iOS settle without echoing or coming back',
    () async {
      final server = FakeNas();
      final (laptop, sync) = await _device(server, 'laptop');
      await sync.signIn('http://nas.test', 'me@example.com', 'secret');
      await sync.firstSync(FirstSync.merge);

      // iOS writes every key, including an empty tag list Flutter leaves out
      const key = '0f8fad5b-d9cb-469f-a165-70867728950e';
      server.rows['ios1'] = {
        'id': 'ios1',
        'owner': 'u1',
        'app': 'baselit',
        'kind': 'item',
        'item_key': key,
        'modified': 1762000000000,
        'deleted': false,
        'device': 'iPhone',
        'blob': '',
        'data': {
          'exportID': key.toUpperCase(),
          'name': 'Lantern',
          'quantity': 1,
          'identifier': 'Calm Otter',
          'createdAt': '2026-11-01T10:00:00Z',
          'updatedAt': '2026-11-01T10:00:00Z',
          'tagExportIDs': <String>[],
        },
        'updated': '2026-01-01 00:00:000500.000Z',
      };
      await sync.sync();
      expect(laptop.items.single.name, 'Lantern');
      await sync.sync();
      expect(server.rows['ios1']!['updated'], '2026-01-01 00:00:000500.000Z');

      await laptop.deleteItem(laptop.items.single);
      await sync.sync();
      await sync.sync();
      expect(laptop.items, isEmpty);
      expect(server.rows['ios1']!['deleted'], isTrue);
    },
  );

  test('a wrong password shows the server\'s message', () async {
    final (_, sync) = await _device(FakeNas(), 'phone');
    await expectLater(
      sync.signIn('http://nas.test', 'me@example.com', 'nope'),
      throwsA(predicate((e) => '$e' == 'Failed to authenticate.')),
    );
    expect(sync.signedIn, isFalse);
  });
}
