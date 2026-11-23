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

/// Brand colours taken from the Quiz me logo.
const Color brandBlue = Color(0xFF1E5BD6);
const Color brandNavy = Color(0xFF0E2A63);
const Color brandOrange = Color(0xFFFF7A00);
const Color brandGold = Color(0xFFFFB300);

const List<int> accentChoices = [
  0xFF1E5BD6, // brand blue
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

/// Colours of a "glassy" theme: a coloured header band, a soft gradient body
/// with glowing blobs, frosted translucent cards and a wave at the bottom.
class GlassPalette {
  const GlassPalette({
    required this.primary,
    required this.onPrimary,
    required this.band,
    required this.onBand,
    required this.bodyTop,
    required this.bodyBottom,
    required this.glowA,
    required this.glowB,
    required this.solid,
    this.dark = false,
  });

  final Color primary;
  final Color onPrimary;

  /// Header band (behind the app bar) and bottom waves.
  final Color band;
  final Color onBand;
  final Color bodyTop;
  final Color bodyBottom;
  final Color glowA;
  final Color glowB;

  /// Opaque colour for dialogs, menus and sheets.
  final Color solid;
  final bool dark;
}

const Map<AppTheme, GlassPalette> glassPalettes = {
  AppTheme.glassBlue: GlassPalette(
    primary: Color(0xFF1E63E9),
    onPrimary: Colors.white,
    band: Color(0xFF2563EB),
    onBand: Colors.white,
    bodyTop: Color(0xFFE3EDFF),
    bodyBottom: Color(0xFFBCD3FB),
    glowA: Color(0xFF7FB2FF),
    glowB: Color(0xFFA9C8FF),
    solid: Color(0xFFEFF5FF),
  ),
  AppTheme.glassTeal: GlassPalette(
    primary: Color(0xFF0B8F9B),
    onPrimary: Colors.white,
    band: Color(0xFF0E9AA7),
    onBand: Colors.white,
    bodyTop: Color(0xFFE2F6F6),
    bodyBottom: Color(0xFFBFE6E8),
    glowA: Color(0xFF7FD8DD),
    glowB: Color(0xFFA6E7E3),
    solid: Color(0xFFEEFAFA),
  ),
  AppTheme.glassYellow: GlassPalette(
    primary: Color(0xFFF2A900),
    onPrimary: Color(0xFF2E2200),
    band: Color(0xFFFFCF3D),
    onBand: Color(0xFF2E2200),
    bodyTop: Color(0xFFFFF7DE),
    bodyBottom: Color(0xFFFFE7A3),
    glowA: Color(0xFFFFDB6E),
    glowB: Color(0xFFFFEAA6),
    solid: Color(0xFFFFFAEC),
  ),
  AppTheme.glassPurple: GlassPalette(
    primary: Color(0xFF7048E8),
    onPrimary: Colors.white,
    band: Color(0xFF7C5CF0),
    onBand: Colors.white,
    bodyTop: Color(0xFFF0EBFF),
    bodyBottom: Color(0xFFD8CCFF),
    glowA: Color(0xFFB9A4FF),
    glowB: Color(0xFFD6C8FF),
    solid: Color(0xFFF6F2FF),
  ),
  AppTheme.glassPink: GlassPalette(
    primary: Color(0xFFD6336C),
    onPrimary: Colors.white,
    band: Color(0xFFE64980),
    onBand: Colors.white,
    bodyTop: Color(0xFFFFEDF3),
    bodyBottom: Color(0xFFF9CADB),
    glowA: Color(0xFFFF9EC0),
    glowB: Color(0xFFFFC2D6),
    solid: Color(0xFFFFF4F8),
  ),
  AppTheme.glassMidnight: GlassPalette(
    primary: Color(0xFF5AA9FF),
    onPrimary: Color(0xFF00213F),
    band: Color(0xFF14245A),
    onBand: Colors.white,
    bodyTop: Color(0xFF0B1433),
    bodyBottom: Color(0xFF101E4A),
    glowA: Color(0xFF2F5BD3),
    glowB: Color(0xFF6B3FD8),
    solid: Color(0xFF16224A),
    dark: true,
  ),
};

/// Marks a theme as glassy; widgets read it to adapt (e.g. solid selections).
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme(this.palette);
  final GlassPalette palette;

  @override
  GlassTheme copyWith({GlassPalette? palette}) => GlassTheme(palette ?? this.palette);

  @override
  GlassTheme lerp(covariant ThemeExtension<GlassTheme>? other, double t) =>
      (t < 0.5 || other is! GlassTheme) ? this : other;
}

/// Paints the glassy background behind every page.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, required this.palette, required this.child});
  final GlassPalette palette;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final bandHeight = MediaQuery.paddingOf(context).top + kToolbarHeight + 18;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.bodyTop, palette.bodyBottom],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        Positioned.fill(
          child: RepaintBoundary(child: CustomPaint(painter: _GlassPainter(palette, bandHeight))),
        ),
        child,
      ]),
    );
  }
}

class _GlassPainter extends CustomPainter {
  _GlassPainter(this.p, this.bandHeight);
  final GlassPalette p;
  final double bandHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    void glow(Offset c, double r, Color color, double alpha) {
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = RadialGradient(colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }

    glow(Offset(w * 0.92, bandHeight + 90), w * 0.62, p.glowA, p.dark ? 0.45 : 0.55);
    glow(Offset(w * 0.05, h * 0.58), w * 0.7, p.glowB, p.dark ? 0.35 : 0.5);

    // Bottom waves.
    final back = Path()
      ..moveTo(0, h * 0.90)
      ..cubicTo(w * 0.30, h * 0.84, w * 0.60, h * 0.95, w, h * 0.87)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(back, Paint()..color = p.band.withValues(alpha: p.dark ? 0.35 : 0.22));
    final front = Path()
      ..moveTo(0, h * 0.95)
      ..cubicTo(w * 0.35, h * 0.90, w * 0.65, h * 0.99, w, h * 0.93)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(front, Paint()..color = p.band.withValues(alpha: p.dark ? 0.5 : 0.35));

    // Header band with a soft wave edge (sits behind the app bar).
    final band = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, bandHeight - 10)
      ..cubicTo(w * 0.70, bandHeight + 10, w * 0.35, bandHeight - 22, 0, bandHeight)
      ..close();
    canvas.drawPath(band, Paint()..color = p.band);
    final shine = Path()
      ..moveTo(w * 0.15, bandHeight - 6)
      ..cubicTo(w * 0.45, bandHeight - 26, w * 0.75, bandHeight - 2, w, bandHeight - 22);
    canvas.drawPath(
      shine,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _GlassPainter old) => old.p != p || old.bandHeight != bandHeight;
}

/// Wraps every page in the glassy background, so pages stay opaque during
/// transitions (no "ghosting" of the page underneath).
class _GlassTransitionsBuilder extends PageTransitionsBuilder {
  const _GlassTransitionsBuilder(this.palette, this.inner);
  final GlassPalette palette;
  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      inner.buildTransitions<T>(
          route, context, animation, secondaryAnimation, GlassBackground(palette: palette, child: child));
}

class AppThemes {
  static bool isGlass(AppTheme t) => glassPalettes.containsKey(t);

  static ThemeMode modeFor(AppTheme t) {
    switch (t) {
      case AppTheme.system:
        return ThemeMode.system;
      case AppTheme.dark:
      case AppTheme.amoled:
      case AppTheme.glassMidnight:
        return ThemeMode.dark;
      case AppTheme.light:
      case AppTheme.minimal:
      case AppTheme.sepia:
      case AppTheme.glassBlue:
      case AppTheme.glassTeal:
      case AppTheme.glassYellow:
      case AppTheme.glassPurple:
      case AppTheme.glassPink:
        return ThemeMode.light;
    }
  }

  static ThemeData light(AppSettings s) {
    final glass = glassPalettes[s.theme];
    if (glass != null && !glass.dark) return _glass(s, glass);
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
    final glass = glassPalettes[s.theme];
    if (glass != null && glass.dark) return _glass(s, glass);
    return _build(s, _scheme(s, Brightness.dark));
  }

  static Color _seed(AppSettings s, Color fallback) =>
      s.useCustomAccent ? Color(s.accentColor) : fallback;

  static ColorScheme _scheme(AppSettings s, Brightness b, {Color? seed}) => ColorScheme.fromSeed(
        seedColor: seed ?? _seed(s, brandBlue),
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

  static ThemeData _glass(AppSettings s, GlassPalette p) {
    final brightness = p.dark ? Brightness.dark : Brightness.light;
    final base = ColorScheme.fromSeed(
      seedColor: s.useCustomAccent ? Color(s.accentColor) : p.primary,
      brightness: brightness,
      contrastLevel: s.highContrast ? 1.0 : 0.0,
    );
    final glass = p.dark ? Colors.white : Colors.white;
    final alphas = p.dark ? [0.05, 0.08, 0.11, 0.15, 0.20] : [0.55, 0.62, 0.70, 0.80, 0.90];
    final scheme = base.copyWith(
      primary: s.useCustomAccent ? null : p.primary,
      onPrimary: s.useCustomAccent ? null : p.onPrimary,
      surface: p.solid,
      surfaceContainerLowest: glass.withValues(alpha: alphas[0]),
      surfaceContainerLow: glass.withValues(alpha: alphas[1]),
      surfaceContainer: glass.withValues(alpha: alphas[2]),
      surfaceContainerHigh: glass.withValues(alpha: alphas[3]),
      surfaceContainerHighest: glass.withValues(alpha: alphas[4]),
      outlineVariant: (p.dark ? Colors.white : Colors.white).withValues(alpha: p.dark ? 0.16 : 0.85),
    );
    final theme = _build(s, scheme, scaffold: Colors.transparent, glass: p);
    final PageTransitionsBuilder inner =
        s.reduceMotion ? const _NoTransitionBuilder() : const ZoomPageTransitionsBuilder();
    final transitions = _GlassTransitionsBuilder(p, inner);
    return theme.copyWith(
      dialogTheme: DialogThemeData(backgroundColor: p.solid),
      bottomSheetTheme: BottomSheetThemeData(backgroundColor: p.solid, modalBackgroundColor: p.solid),
      popupMenuTheme: PopupMenuThemeData(color: p.solid),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: (p.dark ? const Color(0xFF0B1433) : Colors.white).withValues(alpha: 0.78),
        surfaceTintColor: Colors.transparent,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: (p.dark ? const Color(0xFF0B1433) : Colors.white).withValues(alpha: 0.6),
      ),
      pageTransitionsTheme: PageTransitionsTheme(builders: {
        for (final platform in TargetPlatform.values) platform: transitions,
      }),
      extensions: [GlassTheme(p)],
    );
  }

  static ThemeData _build(AppSettings s, ColorScheme scheme,
      {Color? scaffold, bool outlinedCards = false, GlassPalette? glass}) {
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
      side: glass != null
          ? BorderSide(color: Colors.white.withValues(alpha: glass.dark ? 0.14 : 0.9))
          : outlinedCards || s.highContrast
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
        backgroundColor: glass?.band ?? scaffold ?? scheme.surface,
        foregroundColor: glass?.onBand,
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
