// Syncs the inventory with the user's PocketBase server, the same way the iOS
// app does. Every record lives in one `baselit_records` collection as its
// backup JSON (see pocketbase/pb_migrations). Each sync pulls rows changed
// since the last pull, then pushes local records whose JSON differs from what
// was last synced. Records that vanished locally become `deleted` rows. When
// both sides changed the same record, the newer `updatedAt` wins.
//
// For each record, a device remembers its own JSON and the server's `updated`
// time as of the last sync. Comparing server times (not JSON) tells whether
// the server changed, since iOS and Flutter write slightly different JSON.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'store.dart';

const _collection = 'baselit_records';

/// What to do the first time a device with its own inventory signs in to a
/// server that already has one.
enum FirstSync { useServer, merge }

class SyncException implements Exception {
  SyncException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SyncService extends ChangeNotifier {
  SyncService(this.store, {http.Client? client})
    : _http = client ?? http.Client();

  final InventoryStore store;
  final http.Client _http;

  String? serverURL;
  String? email;
  String? _token;
  String? _userID;
  String? _lastPull;

  /// Each record's canonical local JSON and server `updated` time as of the
  /// last sync, keyed by row ID.
  Map<String, ({String local, String server})> _known = {};

  bool syncing = false;
  String? lastError;
  DateTime? lastSynced;

  bool _again = false;
  bool _applying = false;
  Timer? _debounce;
  Timer? _periodic;
  AppLifecycleListener? _lifecycle;

  bool get signedIn => _token != null;

  File get _stateFile => File('${store.appFolder.path}/sync.json');

  // MARK: - State

  Future<void> load() async {
    if (await _stateFile.exists()) {
      final json = jsonDecode(await _stateFile.readAsString());
      serverURL = json['serverURL'];
      email = json['email'];
      _token = json['token'];
      _userID = json['userID'];
      _lastPull = json['lastPull'];
      _known = {
        for (final MapEntry(:key, :value) in Map<String, dynamic>.from(
          json['known'] ?? {},
        ).entries)
          key: (local: value[0] as String, server: value[1] as String),
      };
      final last = json['lastSynced'];
      lastSynced = last == null ? null : DateTime.parse(last);
    }
    notifyListeners();
  }

  Future<void> _saveState() async {
    final temp = File('${_stateFile.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'serverURL': serverURL,
        'email': email,
        'token': _token,
        'userID': _userID,
        'lastPull': _lastPull,
        'lastSynced': lastSynced?.toIso8601String(),
        'known': {
          for (final MapEntry(:key, :value) in _known.entries)
            key: [value.local, value.server],
        },
      }),
    );
    await temp.rename(_stateFile.path);
  }

  /// Syncs shortly after each local change, every minute, and when the app comes back.
  void start() {
    store.addListener(_onStoreChanged);
    _periodic = Timer.periodic(const Duration(minutes: 1), (_) => sync());
    _lifecycle = AppLifecycleListener(onResume: sync);
    sync();
  }

  @override
  void dispose() {
    store.removeListener(_onStoreChanged);
    _debounce?.cancel();
    _periodic?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (_applying || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), sync);
  }

  // MARK: - Signing in

  /// Signs in and returns whether this device and the server both already
  /// hold an inventory, in which case the caller asks which [FirstSync] to use.
  Future<bool> signIn(String url, String email, String password) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw SyncException(
        'Enter the full server address, like https://pb.example.com',
      );
    }
    final response = await _send(
      'POST',
      '/api/collections/users/auth-with-password',
      base: base,
      body: {'identity': email.trim(), 'password': password},
      authorized: false,
    );
    serverURL = base;
    this.email = email.trim();
    _token = response['token'];
    _userID = response['record']['id'];
    _lastPull = null;
    _known = {};
    lastError = null;
    await _saveState();
    notifyListeners();

    final remote = await _send(
      'GET',
      '/api/collections/$_collection/records?perPage=1&skipTotal=1&filter=${Uri.encodeQueryComponent('deleted = false')}',
    );
    final serverHasData = (remote['items'] as List).isNotEmpty;
    return serverHasData && store.syncRecords().isNotEmpty;
  }

  /// Runs the first sync after signing in.
  Future<void> firstSync(FirstSync choice) async {
    if (choice == FirstSync.useServer) {
      _applying = true;
      await store.clearForSync();
      await store.commit();
      _applying = false;
    }
    await sync();
  }

  Future<void> signOut() async {
    _token = null;
    _userID = null;
    _lastPull = null;
    _known = {};
    lastSynced = null;
    lastError = null;
    await _saveState();
    notifyListeners();
  }

  // MARK: - Syncing

  Future<void> sync() async {
    if (!signedIn) return;
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    notifyListeners();
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
      lastError = null;
      lastSynced = DateTime.now();
    } on SocketException {
      lastError = 'Can\'t reach the server.';
    } on http.ClientException {
      lastError = 'Can\'t reach the server.';
    } catch (error) {
      lastError = error.toString();
    } finally {
      syncing = false;
      _applying = false;
      await _saveState();
      notifyListeners();
    }
  }

  Future<void> _syncOnce() async {
    await _refreshToken();
    final local = store.syncRecords();
    var newestPull = _lastPull;
    var changedLocally = false;
    _applying = true;

    for (final row in await _pullChanges()) {
      final id = row['id'] as String;
      final kind = row['kind'] as String;
      final updated = row['updated'] as String;
      if (newestPull == null || updated.compareTo(newestPull) > 0) {
        newestPull = updated;
      }
      final known = _known[id];
      // Unchanged on the server since this device last synced it (often our own push)
      if (known != null && known.server == updated) continue;

      final mine = local[id];
      final remoteData = row['data'] is Map
          ? Map<String, dynamic>.from(row['data'])
          : null;
      final localChanged = mine == null
          ? known != null
          : _canonical(mine.data) != known?.local;
      final localWins =
          mine != null &&
          localChanged &&
          remoteData != null &&
          _stamp(mine.data).compareTo(_stamp(remoteData)) > 0;

      if (localWins) {
        // Keep this device's version; it's pushed below over the server's
        _known[id] = (local: known?.local ?? '', server: updated);
        continue;
      }
      if (row['deleted'] == true || remoteData == null) {
        if (mine != null) {
          await store.removeSyncRecord(kind, id);
          local.remove(id);
          changedLocally = true;
        }
        _known.remove(id);
        continue;
      }

      if (kind == 'photo') await _downloadPhoto(row, remoteData);
      final applied = store.applySyncRecord(kind, remoteData);
      local[id] = (kind: kind, data: applied);
      _known[id] = (local: _canonical(applied), server: updated);
      changedLocally = true;
    }

    if (changedLocally) await store.commit();
    _applying = false;
    _lastPull = newestPull;
    await _saveState();

    for (final MapEntry(key: id, value: record) in local.entries) {
      final json = _canonical(record.data);
      final known = _known[id];
      if (known?.local == json) continue;
      final server = await _push(
        id,
        record.kind,
        record.data,
        isNew: known == null,
      );
      _known[id] = (local: json, server: server);
    }
    for (final id
        in _known.keys.where((id) => !local.containsKey(id)).toList()) {
      await _markDeleted(id);
      _known.remove(id);
    }
  }

  /// The sortable time a record last changed, for settling conflicts.
  static String _stamp(Map<String, dynamic> data) =>
      (data['updatedAt'] ?? data['createdAt'] ?? '') as String;

  /// JSON with sorted keys, so the same record always gives the same text.
  static String _canonical(Object? value) {
    Object? sort(Object? v) => switch (v) {
      Map m => {
        for (final key in (m.keys.map((k) => '$k').toList()..sort()))
          key: sort(m[key]),
      },
      List l => l.map(sort).toList(),
      _ => v,
    };
    return jsonEncode(sort(value));
  }

  Future<List<Map<String, dynamic>>> _pullChanges() async {
    final rows = <Map<String, dynamic>>[];
    for (var page = 1; ; page++) {
      final filter = _lastPull == null ? '' : 'updated >= "$_lastPull"';
      final response = await _send(
        'GET',
        '/api/collections/$_collection/records?page=$page&perPage=500&skipTotal=1'
            '&sort=updated,id&fields=id,kind,data,deleted,photo,updated'
            '${filter.isEmpty ? '' : '&filter=${Uri.encodeQueryComponent(filter)}'}',
      );
      final items = (response['items'] as List).cast<Map<String, dynamic>>();
      rows.addAll(items);
      if (items.length < 500) return rows;
    }
  }

  Future<void> _downloadPhoto(
    Map<String, dynamic> row,
    Map<String, dynamic> data,
  ) async {
    final remoteName = row['photo'] as String?;
    final file = store.photoFileNamed(data['filename'] as String);
    if (remoteName == null || remoteName.isEmpty || await file.exists()) return;
    final fileToken = (await _send('POST', '/api/files/token'))['token'];
    final response = await _http.get(
      Uri.parse(
        '$serverURL/api/files/$_collection/${row['id']}/$remoteName?token=$fileToken',
      ),
    );
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
    } else if (response.statusCode != 404) {
      // Stop before this pull is recorded, so the photo is fetched again next time
      throw SyncException(
        'Couldn\'t download a photo (${response.statusCode}).',
      );
    }
  }

  /// Creates or updates the row and returns the server's new `updated` time.
  Future<String> _push(
    String id,
    String kind,
    Map<String, Object?> data, {
    required bool isNew,
  }) async {
    final fields = {'kind': kind, 'data': data, 'deleted': false};
    final photo = kind == 'photo'
        ? store.photoFileNamed(data['filename'] as String)
        : null;
    final upload = isNew && photo != null && await photo.exists();

    if (!isNew) {
      final updated = await _sendOrNull(
        'PATCH',
        '/api/collections/$_collection/records/$id',
        body: fields,
      );
      if (updated != null) return updated['updated'];
    }
    final create = {'id': id, 'owner': _userID, ...fields};
    if (upload) {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverURL/api/collections/$_collection/records'),
      )..headers['Authorization'] = _token!;
      for (final MapEntry(:key, :value) in create.entries) {
        request.fields[key] = value is String ? value : jsonEncode(value);
      }
      request.files.add(await http.MultipartFile.fromPath('photo', photo.path));
      final response = await http.Response.fromStream(
        await _http.send(request),
      );
      _check(response);
      return jsonDecode(response.body)['updated'];
    }
    final created = await _sendOrNull(
      'POST',
      '/api/collections/$_collection/records',
      body: create,
    );
    // Already on the server (synced from elsewhere before this device knew it)
    return (created ??
        await _send(
          'PATCH',
          '/api/collections/$_collection/records/$id',
          body: fields,
        ))['updated'];
  }

  Future<void> _markDeleted(String id) => _sendOrNull(
    'PATCH',
    '/api/collections/$_collection/records/$id',
    body: {'deleted': true},
  );

  Future<void> _refreshToken() async {
    final response = await _sendOrNull(
      'POST',
      '/api/collections/users/auth-refresh',
    );
    if (response == null) {
      await signOut();
      throw SyncException(
        'Signed out. Sign in to your server again to keep syncing.',
      );
    }
    _token = response['token'];
  }

  // MARK: - HTTP

  /// Sends a request and returns the JSON body, or null for 400 and 404
  /// (a row that doesn't exist yet, or one that already does).
  Future<Map<String, dynamic>?> _sendOrNull(
    String method,
    String path, {
    Map<String, Object?>? body,
  }) async {
    try {
      return await _send(method, path, body: body);
    } on _StatusException catch (e) {
      if (e.status == 400 || e.status == 401 || e.status == 404) return null;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    String? base,
    Map<String, Object?>? body,
    bool authorized = true,
  }) async {
    final request = http.Request(
      method,
      Uri.parse('${base ?? serverURL}$path'),
    );
    if (authorized && _token != null) {
      request.headers['Authorization'] = _token!;
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(await _http.send(request));
    _check(response);
    return response.body.isEmpty
        ? {}
        : Map<String, dynamic>.from(jsonDecode(response.body));
  }

  static void _check(http.Response response) {
    if (response.statusCode < 300) return;
    String message = 'Server error ${response.statusCode}';
    try {
      final json = jsonDecode(response.body);
      if (json['message'] is String) message = json['message'];
    } catch (_) {}
    throw _StatusException(response.statusCode, message);
  }
}

class _StatusException extends SyncException {
  _StatusException(this.status, super.message);
  final int status;
}

/// Makes sync available to every screen and rebuilds them when its status changes.
class SyncScope extends InheritedNotifier<SyncService> {
  const SyncScope({super.key, required SyncService sync, required super.child})
    : super(notifier: sync);

  static SyncService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()!.notifier!;
}
