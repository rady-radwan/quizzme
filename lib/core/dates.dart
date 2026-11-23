/// Calendar helpers. All "day" logic uses the device's local calendar so that
/// "due today" means today on the user's clock, and adding days is safe across
/// daylight-saving changes (DateTime(y, m, d + n) normalises correctly).
library;

DateTime startOfDay(DateTime t) {
  final l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

DateTime addDays(DateTime day, int days) {
  final l = day.toLocal();
  return DateTime(l.year, l.month, l.day + days);
}

/// The last millisecond of the local day containing [t].
DateTime endOfDay(DateTime t) =>
    addDays(startOfDay(t), 1).subtract(const Duration(milliseconds: 1));

/// Whole calendar days from [from] to [to] (local), negative if [to] is earlier.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = startOfDay(from);
  final b = startOfDay(to);
  // Use UTC dates to avoid DST hour differences.
  final ua = DateTime.utc(a.year, a.month, a.day);
  final ub = DateTime.utc(b.year, b.month, b.day);
  return ub.difference(ua).inDays;
}

/// yyyy-MM-dd key of the local day containing [t].
String dayKey(DateTime t) {
  final l = t.toLocal();
  final m = l.month.toString().padLeft(2, '0');
  final d = l.day.toString().padLeft(2, '0');
  return '${l.year}-$m-$d';
}

DateTime parseDayKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Monday of the week containing [t] (local).
DateTime startOfWeek(DateTime t) {
  final d = startOfDay(t);
  return addDays(d, -(d.weekday - DateTime.monday));
}

int toMs(DateTime t) => t.millisecondsSinceEpoch;

DateTime? fromMs(Object? v) {
  if (v == null) return null;
  final n = v is int ? v : int.tryParse(v.toString());
  return n == null ? null : DateTime.fromMillisecondsSinceEpoch(n);
}

String formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = d.inSeconds % 60;
  if (h > 0) return '${h}h ${m}m';
  if (m > 0) return '${m}m ${s.toString().padLeft(2, '0')}s';
  return '${s}s';
}
