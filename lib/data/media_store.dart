import 'dart:io';

import 'package:path/path.dart' as p;

import '../core/ids.dart';

/// Stores imported images and audio inside the app's private storage, so
/// questions keep their media even after the original files are deleted.
/// Questions reference media by a path relative to [root].
class MediaStore {
  MediaStore(this.root);
  final Directory root;

  static const imageExtensions = {'.png', '.jpg', '.jpeg', '.gif', '.webp', '.bmp'};
  static const audioExtensions = {'.mp3', '.m4a', '.aac', '.wav', '.ogg', '.oga', '.flac'};
  static const maxFileBytes = 50 * 1024 * 1024;

  static bool isImage(String name) => imageExtensions.contains(p.extension(name).toLowerCase());
  static bool isAudio(String name) => audioExtensions.contains(p.extension(name).toLowerCase());

  Future<void> ensure() async {
    if (!await root.exists()) await root.create(recursive: true);
  }

  /// Absolute path for a stored relative path, or null when it is missing or
  /// tries to escape the media folder.
  File? resolve(String? relative) {
    if (relative == null || relative.isEmpty) return null;
    final full = p.normalize(p.join(root.path, relative));
    if (!p.isWithin(root.path, full)) return null;
    return File(full);
  }

  /// Saves [bytes] under a new unique name keeping the original extension.
  /// Returns the relative path to store on the question.
  Future<String> save(List<int> bytes, String originalName) async {
    await ensure();
    if (bytes.length > maxFileBytes) {
      throw ArgumentError('"$originalName" is larger than 50 MB.');
    }
    final ext = p.extension(originalName).toLowerCase();
    if (!isImage(originalName) && !isAudio(originalName)) {
      throw ArgumentError('"$originalName" is not a supported image or audio file.');
    }
    final name = '${newId()}$ext';
    await File(p.join(root.path, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<String> copyFile(File source) async => save(await source.readAsBytes(), source.path);

  Future<void> delete(String? relative) async {
    final f = resolve(relative);
    if (f != null && await f.exists()) await f.delete();
  }

  /// All stored media files (relative name -> file).
  Future<Map<String, File>> all() async {
    await ensure();
    final out = <String, File>{};
    await for (final e in root.list()) {
      if (e is File) out[p.basename(e.path)] = e;
    }
    return out;
  }
}
