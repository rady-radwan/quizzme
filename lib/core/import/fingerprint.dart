import 'dart:convert';

import '../models.dart';

/// Normalises text for duplicate detection: lower-case, punctuation removed,
/// whitespace collapsed. Letters of any script (e.g. Arabic) are kept.
String normalizeForFingerprint(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[\p{P}\p{S}]', unicode: true), ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// A stable fingerprint of a question's content (type + text + option texts,
/// order-independent). Two questions with the same fingerprint are treated as
/// duplicates. 64-bit FNV-1a over the normalised UTF-8 bytes, as hex.
String questionFingerprint(Question q) {
  final opts = q.options
      .map((o) => normalizeForFingerprint('${o.text}${o.matchText == null ? '' : '=${o.matchText}'}'))
      .toList()
    ..sort();
  final key = '${q.type.key}|${normalizeForFingerprint(q.text)}|${opts.join('|')}';
  return fnv1a64(key);
}

String fnv1a64(String input) {
  // 64-bit FNV-1a. Dart VM ints are 64-bit two's complement and wrap on
  // overflow, which is exactly the modular arithmetic FNV needs.
  var hash = -3750763034362895579; // 0xcbf29ce484222325
  const prime = 1099511628211; // 0x100000001b3
  for (final b in utf8.encode(input)) {
    hash ^= b;
    hash *= prime;
  }
  final high = (hash >> 32) & 0xffffffff;
  final low = hash & 0xffffffff;
  return high.toRadixString(16).padLeft(8, '0') + low.toRadixString(16).padLeft(8, '0');
}
