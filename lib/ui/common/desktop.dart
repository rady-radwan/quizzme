import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// True on Windows, macOS and Linux (keyboard + mouse, resizable window).
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Whether the keyboard focus is inside a text field. Single-key shortcuts
/// are ignored then, so typing an answer never triggers them.
bool get isEditingText {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  if (ctx.widget is EditableText) return true;
  return ctx.findAncestorStateOfType<EditableTextState>() != null;
}

/// Index 0–9 for the keys 1–9/0 and A–J (top row and numpad), else null.
int? optionIndexForKey(LogicalKeyboardKey key) {
  const digits = [
    LogicalKeyboardKey.digit1, LogicalKeyboardKey.digit2, LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4, LogicalKeyboardKey.digit5, LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7, LogicalKeyboardKey.digit8, LogicalKeyboardKey.digit9,
  ];
  const numpad = [
    LogicalKeyboardKey.numpad1, LogicalKeyboardKey.numpad2, LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4, LogicalKeyboardKey.numpad5, LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7, LogicalKeyboardKey.numpad8, LogicalKeyboardKey.numpad9,
  ];
  const letters = [
    LogicalKeyboardKey.keyA, LogicalKeyboardKey.keyB, LogicalKeyboardKey.keyC,
    LogicalKeyboardKey.keyD, LogicalKeyboardKey.keyE, LogicalKeyboardKey.keyF,
    LogicalKeyboardKey.keyG, LogicalKeyboardKey.keyH, LogicalKeyboardKey.keyI,
    LogicalKeyboardKey.keyJ,
  ];
  var i = digits.indexOf(key);
  if (i >= 0) return i;
  i = numpad.indexOf(key);
  if (i >= 0) return i;
  i = letters.indexOf(key);
  return i >= 0 ? i : null;
}

bool isEnterKey(LogicalKeyboardKey k) => k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter;

/// No Ctrl/Alt/Meta held (Shift is allowed).
bool get noCommandModifier {
  final k = HardwareKeyboard.instance;
  return !k.isControlPressed && !k.isAltPressed && !k.isMetaPressed;
}

/// A dialog listing keyboard shortcuts as `keys → action` rows.
Future<void> showShortcutsDialog(BuildContext context, String title, List<(String, String)> rows) {
  return showDialog<void>(
    context: context,
    builder: (c) {
      final scheme = Theme.of(c).colorScheme;
      return AlertDialog(
        icon: const Icon(Icons.keyboard_outlined),
        title: Text(title),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (keys, action) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    SizedBox(
                      width: 150,
                      child: Wrap(spacing: 4, runSpacing: 4, children: [
                        for (final k in keys.split(' '))
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: scheme.outlineVariant),
                            ),
                            child: Text(k, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(action)),
                  ]),
                ),
            ]),
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
      );
    },
  );
}

const quizShortcuts = <(String, String)>[
  ('1–9 A–J', 'Choose an answer option'),
  ('Enter', 'Check answer / next question'),
  ('→', 'Next question'),
  ('←', 'Previous question'),
  ('H', 'Show the hint (option keys take priority when a question has 8+ options)'),
  ('Ctrl+B', 'Bookmark the question'),
  ('Ctrl+G', 'All questions'),
  ('Ctrl+R', 'Read aloud'),
  ('Esc', 'Leave the quiz'),
  ('F1', 'Show this list'),
];

const flashcardShortcuts = <(String, String)>[
  ('Space Enter', 'Reveal the answer / next card'),
  ('1 2 3 4', 'Rate: Forgot … Easy'),
  ('→', 'Next card'),
  ('←', 'Previous card'),
  ('Esc', 'Leave'),
  ('F1', 'Show this list'),
];
