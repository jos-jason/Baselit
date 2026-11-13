// Syncs two devices through a stand-in PocketBase server and checks that
// adds, edits, photos, deletions, and conflicts reach the other device.

import 'dart:convert';
import 'dart:io';

import 'package:baselit/models.dart';
import 'package:baselit/store.dart';
import 'package:baselit/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Just enough of PocketBase's records API for Baselit sync.
class FakePocketBase {
  final rows = <String, Map<String, dynamic>>{};
  final files = <String, List<int>>{};
  var _clock = 0;

  String _now() =>
      '2026-01-01 00:00:${(_clock++).toString().padLeft(6, '0')}.000Z';

  late final client = MockClient((request) async {
    final path = request.url.path;
    Map<String, dynamic> body() => jsonDecode(request.body);
    http.Response json(Object value, [int status = 200]) =>
        http.Response(jsonEncode(value), status);
    final authorized = request.headers['Authorization'] == 'token-u1';

    if (path == '/api/collections/users/auth-with-password') {
      return body()['password'] == 'secret'
          ? json({
              'token': 'token-u1',
              'record': {'id': 'u1'},
            })
          : json({'message': 'Failed to authenticate.'}, 400);
    }
    // Protected files take a file token in the URL instead of the auth header
    if (path.startsWith('/api/files/baselit_records/')) {
      final id = request.url.pathSegments[3];
      return request.url.queryParameters['token'] == 'ft' && files[id] != null
          ? http.Response.bytes(files[id]!, 200)
          : json({'message': 'Not found'}, 404);
    }
    if (!authorized) return json({'message': 'Unauthorized'}, 401);
    if (path == '/api/collections/users/auth-refresh') {
      return json({
        'token': 'token-u1',
        'record': {'id': 'u1'},
      });
    }
    if (path == '/api/files/token') return json({'token': 'ft'});

    const records = '/api/collections/baselit_records/records';
    if (path == records && request.method == 'GET') {
      final filter = request.url.queryParameters['filter'] ?? '';
      final since = RegExp(r'updated >= "(.+)"').firstMatch(filter)?.group(1);
      var list = rows.values.toList()
        ..sort((a, b) => (a['updated'] as String).compareTo(b['updated']));
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
    if (path == records && request.method == 'POST') {
      final fields = request.headers['content-type']!.startsWith('multipart')
          ? _multipart(request)
          : body();
      final id = fields['id'] as String;
      if (rows.containsKey(id)) return json({'message': 'id taken'}, 400);
      if (fields['owner'] != 'u1') return json({'message': 'bad owner'}, 400);
      rows[id] = {
        'id': id,
        'kind': fields['kind'],
        'data': fields['data'] is String
            ? jsonDecode(fields['data'])
            : fields['data'],
        'deleted': fields['deleted'] == true || fields['deleted'] == 'true',
        'photo': files.containsKey(id) ? 'photo_abc.jpg' : '',
        'updated': _now(),
      };
      return json(rows[id]!);
    }
    if (path.startsWith('$records/') && request.method == 'PATCH') {
      final row = rows[request.url.pathSegments.last];
      if (row == null) return json({'message': 'Not found'}, 404);
      row.addAll(body());
      row['updated'] = _now();
      return json(row);
    }
    return json({'message': 'Unexpected ${request.method} $path'}, 500);
  });

  /// Crude multipart reader: text fields, plus the photo bytes under its row ID.
  Map<String, dynamic> _multipart(http.Request request) {
    final boundary = request.headers['content-type']!.split('boundary=').last;
    final text = latin1.decode(request.bodyBytes);
    final fields = <String, dynamic>{};
    List<int>? photo;
    for (final part in text.split('--$boundary')) {
      final split = part.indexOf('\r\n\r\n');
      if (split < 0) continue;
      final head = part.substring(0, split);
      final value = part.substring(split + 4, part.length - 2);
      final name = RegExp(r'name="([^"]+)"').firstMatch(head)!.group(1)!;
      if (name == 'photo') {
        photo = latin1.encode(value);
      } else {
        fields[name] = utf8.decode(latin1.encode(value));
      }
    }
    if (photo != null) files[fields['id']] = photo;
    return fields;
  }
}

Future<(InventoryStore, SyncService)> _device(FakePocketBase server) async {
  final dir = Directory.systemTemp.createTempSync('baselit_sync');
  addTearDown(() => dir.deleteSync(recursive: true));
  final store = InventoryStore();
  await store.load(folder: Directory('${dir.path}/inventory'));
  final sync = SyncService(store, client: server.client);
  await sync.load();
  return (store, sync);
}

void main() {
  test('two devices stay in sync', () async {
    final server = FakePocketBase();
    final (phone, phoneSync) = await _device(server);
    final (laptop, laptopSync) = await _device(server);

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
      await phoneSync.signIn('http://pb.test/', 'me@example.com', 'secret'),
      isFalse,
    );
    await phoneSync.firstSync(FirstSync.merge);
    expect(phoneSync.lastError, isNull);
    expect(server.rows.length, 4);
    expect(server.rows[drill.exportID.toLowerCase()]!['kind'], 'item');

    // The empty laptop signs in and gets everything, photo file included
    expect(
      await laptopSync.signIn('http://pb.test', 'me@example.com', 'secret'),
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
    laptop.items.single
      ..brand = 'Milwaukee'
      ..updatedAt = DateTime.now().add(const Duration(seconds: 5));
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
    expect(server.rows[drill.exportID.toLowerCase()]!['deleted'], isTrue);

    // Both rename the garage; the later edit wins on both devices
    final soon = DateTime.now().add(const Duration(minutes: 1));
    phone.locations.single
      ..name = 'Shop'
      ..updatedAt = soon;
    laptop.locations.single
      ..name = 'Workshop'
      ..updatedAt = soon.add(const Duration(minutes: 1));
    await phone.commit();
    await laptop.commit();
    await phoneSync.sync();
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
    final server = FakePocketBase();
    final (phone, phoneSync) = await _device(server);
    final (tablet, tabletSync) = await _device(server);
    phone.houses = [House(name: 'Home')];
    await phone.commit();
    await phoneSync.signIn('http://pb.test', 'me@example.com', 'secret');
    await phoneSync.firstSync(FirstSync.merge);

    tablet.houses = [House(name: 'Old Copy')];
    await tablet.commit();
    expect(
      await tabletSync.signIn('http://pb.test', 'me@example.com', 'secret'),
      isTrue,
    );
    await tabletSync.firstSync(FirstSync.useServer);
    expect(tablet.houses.map((h) => h.name), ['Home']);
    // The replaced house isn't deleted from the server or the phone
    await phoneSync.sync();
    expect(phone.houses.map((h) => h.name), ['Home']);
    expect(server.rows.length, 1);
  });

  test(
    'records written by iOS settle without echoing or coming back',
    () async {
      final server = FakePocketBase();
      final (laptop, sync) = await _device(server);
      await sync.signIn('http://pb.test', 'me@example.com', 'secret');
      await sync.firstSync(FirstSync.merge);

      // iOS writes every key, including an empty tag list Flutter leaves out
      const id = '0f8fad5b-d9cb-469f-a165-70867728950e';
      server.rows[id] = {
        'id': id,
        'kind': 'item',
        'data': {
          'exportID': id.toUpperCase(),
          'name': 'Lantern',
          'quantity': 1,
          'identifier': 'Calm Otter',
          'createdAt': '2026-11-01T10:00:00Z',
          'updatedAt': '2026-11-01T10:00:00Z',
          'tagExportIDs': <String>[],
        },
        'deleted': false,
        'photo': '',
        'updated': '2026-01-01 00:00:000500.000Z',
      };
      await sync.sync();
      expect(laptop.items.single.name, 'Lantern');
      await sync.sync();
      expect(server.rows[id]!['updated'], '2026-01-01 00:00:000500.000Z');

      await laptop.deleteItem(laptop.items.single);
      await sync.sync();
      await sync.sync();
      expect(laptop.items, isEmpty);
      expect(server.rows[id]!['deleted'], isTrue);
    },
  );

  test('a wrong password shows the server\'s message', () async {
    final (_, sync) = await _device(FakePocketBase());
    await expectLater(
      sync.signIn('http://pb.test', 'me@example.com', 'nope'),
      throwsA(predicate((e) => '$e' == 'Failed to authenticate.')),
    );
    expect(sync.signedIn, isFalse);
  });
}
