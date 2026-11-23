import 'dart:convert';

import 'package:http/http.dart' as http;

/// A file in the app's private Google Drive folder ("appDataFolder"). Only
/// Quiz me can see these files; they don't appear in the user's Drive list.
class DriveFile {
  DriveFile({required this.id, required this.name, required this.version, this.size});
  final String id;
  final String name;
  final String version;
  final int? size;

  factory DriveFile.fromJson(Map<String, Object?> j) => DriveFile(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        version: '${j['version'] ?? ''}',
        size: int.tryParse('${j['size'] ?? ''}'),
      );
}

class DriveException implements Exception {
  DriveException(this.message, {this.status});
  final String message;
  final int? status;
  bool get unauthorized => status == 401 || status == 403;
  @override
  String toString() => message;
}

/// Minimal Google Drive v3 REST client for the appDataFolder space.
class DriveClient {
  DriveClient(this._token, {http.Client? client}) : _http = client ?? http.Client();

  /// Returns a valid OAuth access token with the drive.appdata scope.
  final Future<String> Function() _token;
  final http.Client _http;

  static const _api = 'https://www.googleapis.com/drive/v3';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3';
  static const _fields = 'id,name,version,size';

  Future<Map<String, String>> _headers([Map<String, String>? extra]) async =>
      {'Authorization': 'Bearer ${await _token()}', ...?extra};

  Never _fail(http.Response r, String what) {
    var msg = '$what failed (HTTP ${r.statusCode}).';
    try {
      final e = (jsonDecode(r.body) as Map)['error'];
      if (e is Map && e['message'] != null) msg = '$what failed: ${e['message']}';
    } catch (_) {}
    throw DriveException(msg, status: r.statusCode);
  }

  /// All files whose name starts with [prefix] (all files when empty).
  Future<List<DriveFile>> list({String prefix = ''}) async {
    final out = <DriveFile>[];
    String? page;
    do {
      final q = prefix.isEmpty ? null : "name contains '${prefix.replaceAll("'", "\\'")}'";
      final uri = Uri.parse('$_api/files').replace(queryParameters: {
        'spaces': 'appDataFolder',
        'fields': 'nextPageToken,files($_fields)',
        'pageSize': '1000',
        if (q != null) 'q': q,
        if (page != null) 'pageToken': page,
      });
      final r = await _http.get(uri, headers: await _headers());
      if (r.statusCode != 200) _fail(r, 'Listing Google Drive files');
      final j = jsonDecode(r.body) as Map<String, Object?>;
      for (final f in (j['files'] as List? ?? const [])) {
        final file = DriveFile.fromJson(Map<String, Object?>.from(f as Map));
        if (file.name.startsWith(prefix)) out.add(file);
      }
      page = j['nextPageToken'] as String?;
    } while (page != null);
    return out;
  }

  Future<DriveFile?> find(String name) async {
    final files = (await list(prefix: name)).where((f) => f.name == name).toList();
    return files.isEmpty ? null : files.first;
  }

  Future<DriveFile> metadata(String id) async {
    final r = await _http.get(Uri.parse('$_api/files/$id?fields=$_fields'), headers: await _headers());
    if (r.statusCode != 200) _fail(r, 'Reading Google Drive file details');
    return DriveFile.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<List<int>> download(String id) async {
    final r = await _http.get(Uri.parse('$_api/files/$id?alt=media'), headers: await _headers());
    if (r.statusCode != 200) _fail(r, 'Downloading from Google Drive');
    return r.bodyBytes;
  }

  /// Creates a new file in the app folder.
  Future<DriveFile> create(String name, List<int> bytes, {String mime = 'application/octet-stream'}) async {
    const boundary = 'quizme-boundary-7d1f';
    final meta = jsonEncode({'name': name, 'parents': ['appDataFolder']});
    final body = <int>[
      ...utf8.encode('--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'),
      ...utf8.encode('--$boundary\r\nContent-Type: $mime\r\n\r\n'),
      ...bytes,
      ...utf8.encode('\r\n--$boundary--\r\n'),
    ];
    final r = await _http.post(
      Uri.parse('$_upload/files?uploadType=multipart&fields=$_fields'),
      headers: await _headers({'Content-Type': 'multipart/related; boundary=$boundary'}),
      body: body,
    );
    if (r.statusCode != 200) _fail(r, 'Uploading to Google Drive');
    return DriveFile.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  /// Replaces the content of an existing file.
  Future<DriveFile> update(String id, List<int> bytes, {String mime = 'application/octet-stream'}) async {
    final r = await _http.patch(
      Uri.parse('$_upload/files/$id?uploadType=media&fields=$_fields'),
      headers: await _headers({'Content-Type': mime}),
      body: bytes,
    );
    if (r.statusCode != 200) _fail(r, 'Uploading to Google Drive');
    return DriveFile.fromJson(jsonDecode(r.body) as Map<String, Object?>);
  }

  Future<void> delete(String id) async {
    final r = await _http.delete(Uri.parse('$_api/files/$id'), headers: await _headers());
    if (r.statusCode != 204 && r.statusCode != 404) _fail(r, 'Deleting from Google Drive');
  }
}
