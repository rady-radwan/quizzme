import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'firebase_auth.dart';
import 'firebase_config.dart';

/// The shared copy's header: which version is current and in how many parts
/// it is stored.
class RemoteManifest {
  RemoteManifest({
    required this.version,
    required this.generation,
    required this.chunks,
    required this.updateTime,
    this.upload = '',
    this.device = '',
  });
  final int version;
  final String generation;
  final int chunks;

  /// Firestore update time, used as a precondition so two devices can never
  /// overwrite each other's upload unnoticed.
  final String updateTime;

  /// Id of the upload that wrote the parts (unique, so two devices
  /// uploading at the same moment never mix their parts).
  final String upload;
  final String device;

  String part(int i) => upload.isEmpty ? 'v$version-$i' : 'v$version-$upload-$i';
}

class CloudException implements Exception {
  CloudException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Stores each user's data in Cloud Firestore (REST API) under
/// `users/{uid}/…`. Security rules allow a signed-in user to read and write
/// only their own folder.
///
/// * `users/{uid}/sync/manifest` — version, generation, number of parts
/// * `users/{uid}/chunks/v{version}-{i}` — the gzip'd snapshot, ≤ 900 KB per part
/// * `users/{uid}/media/{name}` + `users/{uid}/mediaChunks/{name}-{i}` — question images/audio
class FirestoreBackend {
  FirestoreBackend(this.auth, {http.Client? client}) : _http = client ?? http.Client();
  final FirebaseAuthClient auth;
  final http.Client _http;

  static const chunkBytes = 900 * 1024;

  /// Larger media files are not synced (Firestore is not meant for big files).
  static const maxMediaBytes = 15 * 1024 * 1024;

  String get _root => 'projects/${FirebaseConfig.projectId}/databases/(default)/documents';
  String get _base => 'https://firestore.googleapis.com/v1/$_root';
  String get _user => 'users/${auth.uid}';

  Future<Map<String, String>> _headers() async =>
      {'Authorization': 'Bearer ${await auth.idToken()}', 'Content-Type': 'application/json'};

  Future<http.Response> _send(Future<http.Response> Function(Map<String, String> h) f) async {
    try {
      return await f(await _headers());
    } on SocketException {
      throw CloudException('No internet connection. Your changes are kept and will sync later.');
    }
  }

  Never _fail(http.Response r, String what) {
    var msg = '$what failed (HTTP ${r.statusCode}).';
    try {
      final e = (jsonDecode(r.body) as Map)['error'];
      if (e is Map && e['message'] != null) msg = '$what failed: ${e['message']}';
    } catch (_) {}
    if (r.statusCode == 401) throw const SignInRequired();
    throw CloudException(msg, status: r.statusCode);
  }

  // ---------------- Snapshot ----------------

  Future<RemoteManifest?> manifest() async {
    final r = await _send((h) => _http.get(Uri.parse('$_base/$_user/sync/manifest'), headers: h));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _fail(r, 'Reading your cloud data');
    final j = jsonDecode(r.body) as Map<String, Object?>;
    final f = (j['fields'] as Map?) ?? const {};
    int intField(String k) => int.tryParse('${(f[k] as Map?)?['integerValue'] ?? 0}') ?? 0;
    String strField(String k) => '${(f[k] as Map?)?['stringValue'] ?? ''}';
    return RemoteManifest(
      version: intField('version'),
      generation: strField('generation'),
      chunks: intField('chunks'),
      device: strField('device'),
      upload: strField('upload'),
      updateTime: j['updateTime'] as String? ?? '',
    );
  }

  Future<List<int>> download(RemoteManifest m) async {
    final out = <int>[];
    for (var i = 0; i < m.chunks; i++) {
      out.addAll(await _readBytes('$_user/chunks/${m.part(i)}'));
    }
    return out;
  }

  /// Uploads a new version. Returns false (and cleans up) when another
  /// device uploaded first — the caller then merges that copy and retries.
  Future<bool> upload(List<int> bytes,
      {required int version, required String generation, required String device, RemoteManifest? expected}) async {
    final parts = <List<int>>[];
    for (var i = 0; i < bytes.length; i += chunkBytes) {
      parts.add(bytes.sublist(i, i + chunkBytes > bytes.length ? bytes.length : i + chunkBytes));
    }
    final mine = RemoteManifest(
      version: version,
      generation: generation,
      chunks: parts.length,
      updateTime: '',
      upload: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
    );
    for (var i = 0; i < parts.length; i++) {
      await _writeBytes('$_user/chunks/${mine.part(i)}', parts[i]);
    }
    final write = <String, Object?>{
      'update': {
        'name': '$_root/$_user/sync/manifest',
        'fields': {
          'version': {'integerValue': '$version'},
          'generation': {'stringValue': generation},
          'chunks': {'integerValue': '${parts.length}'},
          'size': {'integerValue': '${bytes.length}'},
          'device': {'stringValue': device},
          'upload': {'stringValue': mine.upload},
          'updatedAt': {'timestampValue': DateTime.now().toUtc().toIso8601String()},
        },
      },
      'currentDocument': expected == null ? {'exists': false} : {'updateTime': expected.updateTime},
    };
    final r = await _send((h) => _http.post(Uri.parse('$_base:commit'), headers: h, body: jsonEncode({'writes': [write]})));
    if (r.statusCode != 200) {
      // Precondition failed: someone else uploaded. Remove our parts.
      for (var i = 0; i < parts.length; i++) {
        await _delete('$_user/chunks/${mine.part(i)}');
      }
      if (r.statusCode == 400 || r.statusCode == 409 || r.body.contains('FAILED_PRECONDITION')) return false;
      _fail(r, 'Uploading your data');
    }
    // The previous version's parts are no longer needed.
    if (expected != null) {
      for (var i = 0; i < expected.chunks; i++) {
        await _delete('$_user/chunks/${expected.part(i)}');
      }
    }
    return true;
  }

  // ---------------- Media ----------------

  Future<Set<String>> mediaNames() => _listIds('$_user/media');

  Future<void> uploadMedia(String name, List<int> bytes) async {
    if (bytes.length > maxMediaBytes) return;
    var parts = 0;
    for (var i = 0; i < bytes.length; i += chunkBytes, parts++) {
      final end = i + chunkBytes > bytes.length ? bytes.length : i + chunkBytes;
      await _writeBytes('$_user/mediaChunks/$name-$parts', bytes.sublist(i, end));
    }
    await _writeFields('$_user/media/$name', {
      'chunks': {'integerValue': '$parts'},
      'size': {'integerValue': '${bytes.length}'},
    });
  }

  Future<List<int>?> downloadMedia(String name) async {
    final r = await _send((h) => _http.get(Uri.parse('$_base/$_user/media/$name'), headers: h));
    if (r.statusCode == 404) return null;
    if (r.statusCode != 200) _fail(r, 'Downloading media');
    final f = ((jsonDecode(r.body) as Map)['fields'] as Map?) ?? const {};
    final chunks = int.tryParse('${(f['chunks'] as Map?)?['integerValue'] ?? 0}') ?? 0;
    final out = <int>[];
    for (var i = 0; i < chunks; i++) {
      out.addAll(await _readBytes('$_user/mediaChunks/$name-$i'));
    }
    return out;
  }

  /// Deletes everything stored for this user.
  Future<void> deleteAll() async {
    for (final c in ['chunks', 'media', 'mediaChunks', 'sync']) {
      for (final id in await _listIds('$_user/$c')) {
        await _delete('$_user/$c/$id');
      }
    }
  }

  // ---------------- Helpers ----------------

  Future<List<int>> _readBytes(String path) async {
    final r = await _send((h) => _http.get(Uri.parse('$_base/$path'), headers: h));
    if (r.statusCode != 200) _fail(r, 'Downloading your data');
    final f = ((jsonDecode(r.body) as Map)['fields'] as Map?) ?? const {};
    final b64 = (f['data'] as Map?)?['bytesValue'] as String? ?? '';
    return base64.decode(b64);
  }

  Future<void> _writeBytes(String path, List<int> bytes) => _writeFields(path, {
        'data': {'bytesValue': base64.encode(bytes)},
      });

  Future<void> _writeFields(String path, Map<String, Object?> fields) async {
    final r = await _send(
        (h) => _http.patch(Uri.parse('$_base/$path'), headers: h, body: jsonEncode({'fields': fields})));
    if (r.statusCode != 200) _fail(r, 'Uploading your data');
  }

  Future<void> _delete(String path) async {
    final r = await _send((h) => _http.delete(Uri.parse('$_base/$path'), headers: h));
    if (r.statusCode != 200 && r.statusCode != 404) _fail(r, 'Deleting cloud data');
  }

  /// Ids of the documents in a collection (names only, no content).
  Future<Set<String>> _listIds(String collection) async {
    final ids = <String>{};
    String? page;
    do {
      final uri = Uri.parse('$_base/$collection').replace(queryParameters: {
        'pageSize': '300',
        'mask.fieldPaths': 'chunks',
        if (page != null) 'pageToken': page,
      });
      final r = await _send((h) => _http.get(uri, headers: h));
      if (r.statusCode == 404) break;
      if (r.statusCode != 200) _fail(r, 'Reading your cloud data');
      final j = jsonDecode(r.body) as Map<String, Object?>;
      for (final d in (j['documents'] as List? ?? const [])) {
        final name = (d as Map)['name'] as String;
        ids.add(name.substring(name.lastIndexOf('/') + 1));
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return ids;
  }
}
