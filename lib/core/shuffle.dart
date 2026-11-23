import 'dart:math';

import 'models.dart';

final RegExp _fixedPositionOption = RegExp(
  r'^(all|none|both|neither) (of the above|of these|a and b|of them)\b|^all of the above|^none of the above',
  caseSensitive: false,
);

/// Whether the options of [q] may be reordered. True/false questions and
/// questions containing "All of the above"-style options keep their order;
/// so do questions whose author disabled shuffling.
bool canShuffleOptions(Question q) {
  if (!q.shuffleOptions) return false;
  if (q.type == QuestionType.trueFalse) return false;
  if (!q.type.usesChoices && q.type != QuestionType.matching) return false;
  return !q.options.any((o) => _fixedPositionOption.hasMatch(o.text.trim()));
}

/// Display order (list of option ids) for one presentation of [q].
///
/// The returned value is a permutation of option *ids*, stored with the quiz
/// session. The correct answer is a property of the option id, so shuffling can
/// never change which answer is correct. For matching questions this is the
/// order of the right-hand column; the left column keeps its authored order.
List<String> displayOrder(Question q, {required bool shuffle, Random? random}) {
  final sorted = [...q.options]..sort((a, b) => a.position.compareTo(b.position));
  final ids = sorted.map((o) => o.id).toList();
  if (!shuffle || !canShuffleOptions(q) || ids.length < 2) return ids;
  final rnd = random ?? Random();
  final original = List<String>.of(ids);
  ids.shuffle(rnd);
  // Avoid presenting the authored order when a different one exists, so a
  // shuffled quiz genuinely looks shuffled (only matters for 2+ options).
  if (ids.length > 2 && _sameOrder(ids, original)) ids.shuffle(rnd);
  return ids;
}

bool _sameOrder(List<String> a, List<String> b) {
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Letter label for display position [i] (A, B, C ... Z, AA ...).
String optionLetter(int i) {
  var n = i;
  var s = '';
  do {
    s = String.fromCharCode(65 + n % 26) + s;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return s;
}
