import 'dart:math' as math;

/// Result of planning how many questions to take from each bank.
class DistributionPlan {
  const DistributionPlan({
    required this.allocation,
    required this.requested,
    required this.available,
    this.shortages = const {},
  });

  /// bank id -> number of questions to draw.
  final Map<String, int> allocation;
  final int requested;

  /// Total eligible questions across all banks.
  final int available;

  /// Manual mode: bank id -> how many questions are missing in that bank.
  final Map<String, int> shortages;

  int get planned => allocation.values.fold(0, (a, b) => a + b);
  bool get isShort => planned < requested;
}

/// Automatic distribution: draw [requested] questions from the pooled banks.
/// Each bank gets a share proportional to its eligible questions (largest
/// remainder method), so a big bank is not under-represented and a small bank
/// is not exhausted first. Never allocates more than a bank has — questions are
/// never duplicated to fill a quiz.
DistributionPlan planAutomatic(Map<String, int> availableByBank, int requested) {
  final banks = availableByBank.entries.where((e) => e.value > 0).toList();
  final available = banks.fold<int>(0, (a, e) => a + e.value);
  final target = math.min(requested, available);
  final alloc = <String, int>{for (final e in availableByBank.entries) e.key: 0};
  if (target <= 0 || available == 0) {
    return DistributionPlan(
        allocation: alloc, requested: requested, available: available);
  }
  final remainders = <MapEntry<String, double>>[];
  var assigned = 0;
  for (final e in banks) {
    final exact = target * e.value / available;
    final base = exact.floor();
    alloc[e.key] = base;
    assigned += base;
    remainders.add(MapEntry(e.key, exact - base));
  }
  remainders.sort((a, b) => b.value.compareTo(a.value));
  var i = 0;
  while (assigned < target && remainders.isNotEmpty) {
    final key = remainders[i % remainders.length].key;
    if (alloc[key]! < availableByBank[key]!) {
      alloc[key] = alloc[key]! + 1;
      assigned++;
    }
    i++;
    if (i > remainders.length * (target + 1)) break; // safety
  }
  return DistributionPlan(
      allocation: alloc, requested: requested, available: available);
}

/// Manual distribution: the user asked for a fixed count from each bank.
/// Banks that cannot supply their count are reported in [DistributionPlan.shortages].
DistributionPlan planManual(
    Map<String, int> availableByBank, Map<String, int> requestedByBank) {
  final alloc = <String, int>{};
  final shortages = <String, int>{};
  var requested = 0;
  for (final e in requestedByBank.entries) {
    final want = math.max(0, e.value);
    final have = availableByBank[e.key] ?? 0;
    requested += want;
    alloc[e.key] = math.min(want, have);
    if (want > have) shortages[e.key] = want - have;
  }
  final available = availableByBank.values.fold<int>(0, (a, b) => a + b);
  return DistributionPlan(
    allocation: alloc,
    requested: requested,
    available: available,
    shortages: shortages,
  );
}

/// Adaptive difficulty: given recent accuracy (0..1) in the selected topics,
/// returns the preferred difficulty indexes (0 = Easy .. 3 = Expert).
/// * ≥ 85% correct → Hard and Expert first.
/// * 60–85% → Medium and Hard.
/// * < 60% → Easy and Medium, before increasing difficulty again.
/// With no history yet, Easy and Medium.
List<int> adaptiveDifficultyTarget(double? recentAccuracy) {
  if (recentAccuracy == null) return const [0, 1];
  if (recentAccuracy >= 0.85) return const [2, 3];
  if (recentAccuracy >= 0.60) return const [1, 2];
  return const [0, 1];
}
