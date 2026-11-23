import 'dart:math';

final Random _secure = Random.secure();

/// Returns a random RFC 4122 version-4 UUID. Used as the stable identifier
/// for every row (categories, banks, questions, answer options, sessions...).
String newId() {
  final b = List<int>.generate(16, (_) => _secure.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}
