import 'package:flutter/material.dart';

import '../core/models.dart';
import '../data/settings_repository.dart';

/// Design system: one place for colours, shapes, spacing and typography.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double radius = 16;
}

const List<int> accentChoices = [
  0xFF3F51B5, // indigo
  0xFF1E88E5, // blue
  0xFF00897B, // teal
  0xFF43A047, // green
  0xFFF4511E, // deep orange
  0xFF8E24AA, // purple
  0xFFD81B60, // pink
  0xFF6D4C41, // brown
  0xFF546E7A, // blue grey
];

class AppThemes {
  static ThemeMode modeFor(AppTheme t) {
    switch (t) {
      case AppTheme.system:
        return ThemeMode.system;
      case AppTheme.dark:
      case AppTheme.amoled:
        return ThemeMode.dark;
      case AppTheme.light:
      case AppTheme.minimal:
      case AppTheme.sepia:
        return ThemeMode.light;
    }
  }

  static ThemeData light(AppSettings s) {
    switch (s.theme) {
      case AppTheme.minimal:
        return _minimal(s);
      case AppTheme.sepia:
        return _sepia(s);
      default:
        return _build(s, _scheme(s, Brightness.light));
    }
  }

  static ThemeData dark(AppSettings s) {
    if (s.theme == AppTheme.amoled) return _amoled(s);
    return _build(s, _scheme(s, Brightness.dark));
  }

  static Color _seed(AppSettings s, Color fallback) =>
      s.useCustomAccent ? Color(s.accentColor) : fallback;

  static ColorScheme _scheme(AppSettings s, Brightness b, {Color? seed}) => ColorScheme.fromSeed(
        seedColor: seed ?? _seed(s, const Color(0xFF3F51B5)),
        brightness: b,
        contrastLevel: s.highContrast ? 1.0 : 0.0,
      );

  static ThemeData _amoled(AppSettings s) {
    final base = _scheme(s, Brightness.dark);
    final scheme = base.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: const Color(0xFF0B0B0B),
      surfaceContainer: const Color(0xFF111111),
      surfaceContainerHigh: const Color(0xFF181818),
      surfaceContainerHighest: const Color(0xFF202020),
    );
    return _build(s, scheme, scaffold: Colors.black);
  }

  static ThemeData _minimal(AppSettings s) {
    final base = _scheme(s, Brightness.light, seed: _seed(s, const Color(0xFF455A64)));
    final scheme = base.copyWith(
      surface: Colors.white,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: const Color(0xFFFAFAFA),
      surfaceContainer: const Color(0xFFF5F5F5),
      surfaceContainerHigh: const Color(0xFFF0F0F0),
      surfaceContainerHighest: const Color(0xFFEAEAEA),
      onSurface: const Color(0xFF111111),
    );
    return _build(s, scheme, scaffold: Colors.white, outlinedCards: true);
  }

  static ThemeData _sepia(AppSettings s) {
    final base = _scheme(s, Brightness.light, seed: _seed(s, const Color(0xFF8B5E34)));
    final scheme = base.copyWith(
      surface: const Color(0xFFF5EDDC),
      surfaceContainerLowest: const Color(0xFFFBF5E8),
      surfaceContainerLow: const Color(0xFFF1E7D2),
      surfaceContainer: const Color(0xFFECE0C8),
      surfaceContainerHigh: const Color(0xFFE6D8BD),
      surfaceContainerHighest: const Color(0xFFE0D0B2),
      onSurface: const Color(0xFF3B2E1E),
      onSurfaceVariant: const Color(0xFF5A4A36),
    );
    return _build(s, scheme, scaffold: const Color(0xFFF5EDDC));
  }

  static ThemeData _build(AppSettings s, ColorScheme scheme,
      {Color? scaffold, bool outlinedCards = false}) {
    final family = s.font.family;
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: family,
      scaffoldBackgroundColor: scaffold ?? scheme.surface,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final text = base.textTheme.copyWith(
      bodyLarge: base.textTheme.bodyLarge?.copyWith(height: s.lineHeight),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: s.lineHeight),
      titleMedium: base.textTheme.titleMedium?.copyWith(height: s.lineHeight * 0.95),
    );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      side: outlinedCards || s.highContrast
          ? BorderSide(color: scheme.outlineVariant)
          : BorderSide.none,
    );
    return base.copyWith(
      textTheme: text,
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: shape,
        clipBehavior: Clip.antiAlias,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold ?? scheme.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      listTileTheme: const ListTileThemeData(minVerticalPadding: 10),
      pageTransitionsTheme: s.reduceMotion
          ? const PageTransitionsTheme(builders: {
              TargetPlatform.android: _NoTransitionBuilder(),
              TargetPlatform.iOS: _NoTransitionBuilder(),
              TargetPlatform.windows: _NoTransitionBuilder(),
              TargetPlatform.linux: _NoTransitionBuilder(),
              TargetPlatform.macOS: _NoTransitionBuilder(),
            })
          : null,
      focusColor: scheme.primary.withValues(alpha: 0.24),
    );
  }
}

class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
          Animation<double> animation, Animation<double> secondaryAnimation, Widget child) =>
      child;
}

/// Mastery colours. Always shown together with a label/icon so colour is
/// never the only signal.
Color masteryColor(MasteryLevel m, ColorScheme scheme) {
  final dark = scheme.brightness == Brightness.dark;
  switch (m) {
    case MasteryLevel.notLearned:
      return dark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828);
    case MasteryLevel.learning:
      return dark ? const Color(0xFFFFB74D) : const Color(0xFFE65100);
    case MasteryLevel.needsPractice:
      return dark ? const Color(0xFFFFE082) : const Color(0xFFB28704);
    case MasteryLevel.wellLearned:
      return dark ? const Color(0xFFA5D6A7) : const Color(0xFF2E7D32);
    case MasteryLevel.mastered:
      return dark ? const Color(0xFF90CAF9) : const Color(0xFF1565C0);
  }
}

IconData masteryIcon(MasteryLevel m) {
  switch (m) {
    case MasteryLevel.notLearned:
      return Icons.radio_button_unchecked;
    case MasteryLevel.learning:
      return Icons.timelapse;
    case MasteryLevel.needsPractice:
      return Icons.replay;
    case MasteryLevel.wellLearned:
      return Icons.check_circle_outline;
    case MasteryLevel.mastered:
      return Icons.workspace_premium;
  }
}

Color correctColor(ColorScheme s) =>
    s.brightness == Brightness.dark ? const Color(0xFF81C784) : const Color(0xFF2E7D32);
Color incorrectColor(ColorScheme s) =>
    s.brightness == Brightness.dark ? const Color(0xFFE57373) : const Color(0xFFC62828);

/// Icons offered for subjects and banks (stored by key).
const Map<String, IconData> appIcons = {
  'book': Icons.menu_book,
  'language': Icons.translate,
  'grammar': Icons.spellcheck,
  'chat': Icons.chat_bubble_outline,
  'headphones': Icons.headphones,
  'engineering': Icons.engineering,
  'construction': Icons.construction,
  'architecture': Icons.architecture,
  'drone': Icons.flight,
  'weather': Icons.cloud_outlined,
  'map': Icons.map_outlined,
  'science': Icons.science_outlined,
  'history': Icons.history_edu,
  'globe': Icons.public,
  'calculate': Icons.calculate_outlined,
  'computer': Icons.computer,
  'lightbulb': Icons.lightbulb_outline,
  'star': Icons.star_outline,
  'folder': Icons.folder_outlined,
  'quiz': Icons.quiz_outlined,
};

IconData iconFor(String? key, {IconData fallback = Icons.folder_outlined}) =>
    appIcons[key] ?? fallback;
