// Syncs the inventory with the NAS through github.com/jos-jason/nas-sync,
// the same way Inkpad does: rows in the shared `sync_items` collection, filed
// under app `baselit`. Each house, location, container, item, photo, and home
// location is one item (kind + lowercase UUID key) whose data is its backup
// JSON; photos also carry their image as the blob. The iOS app follows the
// same rules (Baselit/Services/SyncService.swift).
//
// The store has no per-record change hooks, so before each sync this compares
// every record's JSON with what it was last time and tells the engine about
// whatever changed or vanished.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:nas_sync/nas_sync.dart';

import 'store.dart';

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
  SyncService(this.store, {http.Client? httpClient, String? device})
    : _http = httpClient ?? http.Client(),
      device = device ?? _deviceName();

  /// The app name the server files Baselit's items under.
  static const app = 'baselit';

  final InventoryStore store;
  final http.Client _http;
  final String device;
  late final NasSync _engine = NasSync(
    client: PbClient('http://localhost/', httpClient: _http),
    app: app,
    device: device,
    source: _InventorySource(this),
    storage: _EngineStateFile(this),
  );

  String? serverURL;
  bool syncing = false;
  String? lastError;
  DateTime? lastSynced;

  /// Each record's JSON as of the last sync, and when this device saw it change.
  Map<String, ({String json, int at})> _seen = {};

  bool _again = false;
  bool _commitPending = false;
  bool _committing = false;
  Timer? _debounce;
  Timer? _periodic;
  AppLifecycleListener? _lifecycle;

  bool get signedIn => _engine.client.auth != null;
  String? get email => _engine.client.auth?.email;

  File get _settingsFile => File('${store.appFolder.path}/sync.json');
  File get _engineFile => File('${store.appFolder.path}/sync_state.json');

  static String _deviceName() {
    try {
      return '${Platform.operatingSystem} ${Platform.localHostname}';
    } catch (_) {
      return Platform.operatingSystem;
    }
  }

  // MARK: - Settings

  Future<void> load() async {
    if (await _settingsFile.exists()) {
      final json = jsonDecode(await _settingsFile.readAsString());
      serverURL = json['serverURL'];
      final auth = json['auth'];
      if (serverURL != null && auth is Map) {
        _engine.client = PbClient(
          serverURL!,
          httpClient: _http,
          auth: PbAuth.fromJson(Map<String, dynamic>.from(auth)),
        );
      }
      final last = json['lastSynced'];
      lastSynced = last == null ? null : DateTime.parse(last);
      _seen = {
        for (final MapEntry(:key, :value) in Map<String, dynamic>.from(
          json['seen'] ?? {},
        ).entries)
          key: (json: value[0] as String, at: value[1] as int),
      };
    }
    notifyListeners();
  }

  /// The login is kept in this app's own data folder; the token lasts 90 days
  /// and is refreshed on every start.
  Future<void> _saveSettings() async {
    final temp = File('${_settingsFile.path}.tmp');
    await temp.writeAsString(
      jsonEncode({
        'serverURL': serverURL,
        'auth': _engine.client.auth?.toJson(),
        'lastSynced': lastSynced?.toIso8601String(),
        'seen': {
          for (final MapEntry(:key, :value) in _seen.entries)
            key: [value.json, value.at],
        },
      }),
    );
    await temp.rename(_settingsFile.path);
  }

  /// Restores a saved login, then syncs shortly after each local change,
  /// every five minutes, and when the app comes back (like Inkpad).
  Future<void> start() async {
    store.addListener(_onStoreChanged);
    _periodic = Timer.periodic(const Duration(minutes: 5), (_) => sync());
    _lifecycle = AppLifecycleListener(onResume: sync);
    if (!signedIn) return;
    try {
      await _engine.client.refresh();
      await _saveSettings();
    } on PbException catch (e) {
      if (e.isAuth) return _lostLogin();
    } catch (_) {
      // Offline: keep the saved login and try again on the next sync.
    }
    await sync();
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
    if (_committing || !signedIn) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 5), sync);
  }

  // MARK: - Signing in

  /// Signs in with an account from the NAS admin page and returns whether
  /// this device and the server both already hold a Baselit inventory, in
  /// which case the caller asks which [FirstSync] to use.
  Future<bool> signIn(String url, String email, String password) async {
    final base = url.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw SyncException(
        'Enter the full server address, like https://nas.tailnet.ts.net:8443',
      );
    }
    final client = PbClient(base, httpClient: _http);
    try {
      await client.signIn(email.trim(), password);
    } on PbException catch (e) {
      throw SyncException(e.message);
    } catch (_) {
      throw SyncException('Can\'t reach the server. Is Tailscale on?');
    }
    serverURL = base;
    _engine.client = client;
    lastError = null;
    await _saveSettings();
    notifyListeners();
    return await _serverHasData() && store.syncRecords().isNotEmpty;
  }

  Future<bool> _serverHasData() async {
    final client = _engine.client;
    final url = client.base
        .resolve('api/collections/${PbClient.collection}/records')
        .replace(
          queryParameters: {
            'filter': 'app = "$app" && deleted = false',
            'perPage': '1',
            'skipTotal': '1',
          },
        );
    final response = await _http.get(
      url,
      headers: {'Authorization': client.auth!.token},
    );
    if (response.statusCode != 200) return false;
    return (jsonDecode(response.body)['items'] as List).isNotEmpty;
  }

  /// Runs the first sync after signing in.
  Future<void> firstSync(FirstSync choice) async {
    if (choice == FirstSync.useServer) {
      await store.clearForSync();
      _seen = {};
      await _commit();
    }
    await sync();
  }

  /// Stops syncing on this device. The inventory stays here and on the server.
  Future<void> signOut() async {
    _engine.client.auth = null;
    lastError = null;
    await _saveSettings();
    notifyListeners();
  }

  Future<void> _lostLogin() async {
    await signOut();
    lastError =
        'Your sign-in expired or was removed. Sign in again to keep syncing.';
    notifyListeners();
  }

  // MARK: - Syncing

  Future<void> sync() async {
    if (!signedIn || !store.loaded) return;
    _debounce?.cancel();
    if (syncing) {
      _again = true;
      return;
    }
    syncing = true;
    notifyListeners();
    var lostLogin = false;
    try {
      await _noteLocalChanges();
      final report = await _engine.sync();
      lastSynced = DateTime.now();
      lastError = report.problems.isEmpty
          ? null
          : 'Some changes couldn\'t be sent: ${report.problems.join('; ')}';
    } on PbException catch (e) {
      lostLogin = e.isAuth;
      lastError = e.message;
    } on StateError {
      lastError = null;
    } catch (e) {
      // Socket, TLS and timeout errors: most likely Tailscale is off or the NAS is down.
      lastError = 'Can\'t reach the server. Is Tailscale on?';
    } finally {
      if (_commitPending) await _commit();
      syncing = false;
      await _saveSettings();
      notifyListeners();
    }
    if (lostLogin) {
      await _lostLogin();
    } else if (_again) {
      _again = false;
      await sync();
    }
  }

  /// Tells the engine about every record that changed or vanished since the
  /// last sync, stamped with now so newer edits win.
  Future<void> _noteLocalChanges() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final records = store.syncRecords();
    for (final MapEntry(key: id, value: record) in records.entries) {
      final key = '${record.kind}/$id';
      final json = _canonical(record.data);
      if (_seen[key]?.json == json) continue;
      _seen[key] = (json: json, at: now);
      await _engine.markChanged(record.kind, id, modified: now);
    }
    for (final key in _seen.keys.toList()) {
      final slash = key.indexOf('/');
      final (kind, id) = (key.substring(0, slash), key.substring(slash + 1));
      if (records.containsKey(id)) continue;
      _seen.remove(key);
      await _engine.markChanged(kind, id, deleted: true, modified: now);
    }
    await _saveSettings();
  }

  Future<void> _commit() async {
    _committing = true;
    try {
      await store.commit();
    } finally {
      _committing = false;
      _commitPending = false;
    }
  }

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
}

/// The inventory as the engine sees it.
class _InventorySource extends SyncSource {
  _InventorySource(this.sync);
  final SyncService sync;
  InventoryStore get store => sync.store;

  @override
  Future<SyncItem?> read(String kind, String key) async {
    final data = store.syncRecord(kind, key);
    if (data == null) return null;
    Uint8List? blob;
    if (kind == 'photo') {
      final file = store.photoFileNamed(data['filename'] as String);
      if (await file.exists()) blob = await file.readAsBytes();
    }
    final stamp = DateTime.tryParse(
      (data['updatedAt'] ?? data['createdAt'] ?? '') as String,
    )?.millisecondsSinceEpoch;
    final seen = sync._seen['$kind/$key']?.at ?? 0;
    return SyncItem(
      kind: kind,
      key: key,
      modified: stamp != null && stamp > seen ? stamp : seen,
      data: data.cast<String, dynamic>(),
      blob: blob,
    );
  }

  @override
  Future<void> apply(SyncItem item) async {
    final key = '${item.kind}/${item.key}';
    if (item.deleted || item.data == null) {
      await store.removeSyncRecord(item.kind, item.key);
      sync._seen.remove(key);
    } else {
      final applied = store.applySyncRecord(item.kind, item.data!);
      if (item.kind == 'photo' && item.blob != null) {
        await store
            .photoFileNamed(item.data!['filename'] as String)
            .writeAsBytes(item.blob!);
      }
      sync._seen[key] = (
        json: SyncService._canonical(applied),
        at: item.modified,
      );
    }
    sync._commitPending = true;
  }
}

class _EngineStateFile implements SyncStateStorage {
  _EngineStateFile(this.sync);
  final SyncService sync;

  @override
  Future<String?> read() async {
    final file = sync._engineFile;
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String text) async {
    final temp = File('${sync._engineFile.path}.tmp');
    await temp.writeAsString(text);
    await temp.rename(sync._engineFile.path);
  }
}

/// Makes sync available to every screen and rebuilds them when its status changes.
class SyncScope extends InheritedNotifier<SyncService> {
  const SyncScope({super.key, required SyncService sync, required super.child})
    : super(notifier: sync);

  static SyncService of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SyncScope>()!.notifier!;
}
