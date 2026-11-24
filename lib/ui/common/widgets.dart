import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/models.dart';

final RegExp _rtlChar = RegExp(r'[֐-ࣿיִ-﷿ﹰ-﻿]');
final RegExp _ltrChar = RegExp(r'[A-Za-zÀ-ɏͰ-ϿЀ-ӿ]');

/// Direction of user content from its first strong character, so Arabic
/// questions render right-to-left even inside an English interface.
TextDirection? contentDirection(String text) {
  for (final ch in text.runes) {
    final c = String.fromCharCode(ch);
    if (_rtlChar.hasMatch(c)) return TextDirection.rtl;
    if (_ltrChar.hasMatch(c)) return TextDirection.ltr;
  }
  return null;
}

/// Text that picks its direction from its own content.
class ContentText extends StatelessWidget {
  const ContentText(this.text, {super.key, this.style, this.maxLines, this.overflow});
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    final dir = contentDirection(text);
    return Text(
      text,
      style: style,
      maxLines: maxLines,
      overflow: overflow ?? (maxLines != null ? TextOverflow.ellipsis : null),
      textDirection: dir,
      textAlign: TextAlign.start,
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.action, this.padding});
  final String title;
  final Widget? action;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(2, 24, 2, 10),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.8)!],
              ),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700, fontSize: 18, letterSpacing: -0.1)),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A rounded, softly tinted square holding an icon (used for visual accents).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, required this.color, this.size = 44, this.filled = false});
  final IconData icon;
  final Color color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: filled
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color, Color.lerp(color, Colors.black, 0.18)!],
              )
            : null,
        color: filled ? null : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.52, color: filled ? Colors.white : color),
    );
  }
}

/// A compact number + label tile used in statistics grids.
class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, this.icon, this.color, this.onTap});
  final String label;
  final String value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) IconBadge(icon: icon!, color: c, size: 36),
              if (icon != null) const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: color)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Responsive grid of [StatTile]s (2 columns on phones, more on wide screens).
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children, this.minTileWidth = 150});
  final List<Widget> children;
  final double minTileWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / minTileWidth).floor().clamp(2, 6);
      final w = (c.maxWidth - (cols - 1) * AppSpacing.sm) / cols;
      return Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [for (final ch in children) SizedBox(width: w, child: ch)],
      );
    });
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.actions = const []});
  final IconData icon;
  final String title;
  final String? message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 20),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class MasteryChip extends StatelessWidget {
  const MasteryChip(this.level, {super.key, this.dense = false});
  final MasteryLevel level;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = masteryColor(level, Theme.of(context).colorScheme);
    return Semantics(
      label: 'Mastery: ${level.label}',
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: dense ? 2 : 4),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(masteryIcon(level), size: dense ? 12 : 14, color: c),
            const SizedBox(width: 4),
            Text(level.label,
                style: TextStyle(fontSize: dense ? 11 : 12, color: c, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Horizontal stacked bar of mastery levels.
class MasteryBar extends StatelessWidget {
  const MasteryBar({super.key, required this.byLevel, this.height = 12});
  final Map<MasteryLevel, int> byLevel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = byLevel.values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return Container(
        height: height,
        decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(height)),
      );
    }
    return Semantics(
      label: byLevel.entries.map((e) => '${e.key.label} ${e.value}').join(', '),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              for (final l in MasteryLevel.values)
                if ((byLevel[l] ?? 0) > 0)
                  Expanded(flex: byLevel[l]!, child: Container(color: masteryColor(l, scheme))),
            ],
          ),
        ),
      ),
    );
  }
}

class MasteryLegend extends StatelessWidget {
  const MasteryLegend({super.key, required this.byLevel});
  final Map<MasteryLevel, int> byLevel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        for (final l in MasteryLevel.values)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(masteryIcon(l), size: 14, color: masteryColor(l, scheme)),
            const SizedBox(width: 4),
            Text('${l.label} ${byLevel[l] ?? 0}', style: Theme.of(context).textTheme.bodySmall),
          ]),
      ],
    );
  }
}

/// Labeled linear progress bar.
class LabeledProgress extends StatelessWidget {
  const LabeledProgress({super.key, required this.label, required this.value, this.trailing, this.color});
  final String label;
  final double value;
  final String? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(trailing ?? '${(value * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            semanticsLabel: label,
            semanticsValue: '${(value * 100).round()}',
          ),
        ),
      ],
    );
  }
}

String percent(double? v) => v == null ? '—' : '${(v * 100).round()}%';

// ---------------------------------------------------------------------------
// Dialog helpers
// ---------------------------------------------------------------------------

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r == true;
}

/// Asks the user to type a confirmation word before a destructive action.
Future<bool> confirmTyped(BuildContext context,
    {required String title, required String message, String word = 'DELETE'}) async {
  final ctrl = TextEditingController();
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(message),
            const SizedBox(height: 12),
            Text('Type $word to confirm.'),
            const SizedBox(height: 8),
            TextField(controller: ctrl, autofocus: true, onChanged: (_) => setState(() {})),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(c).colorScheme.error,
                foregroundColor: Theme.of(c).colorScheme.onError),
            onPressed: ctrl.text.trim().toUpperCase() == word ? () => Navigator.pop(c, true) : null,
            child: const Text('Delete'),
          ),
        ],
      ),
    ),
  );
  ctrl.dispose();
  return r == true;
}

Future<String?> promptText(
  BuildContext context, {
  required String title,
  String? initial,
  String? hint,
  String confirmLabel = 'Save',
  int maxLines = 1,
  bool allowEmpty = false,
}) async {
  final ctrl = TextEditingController(text: initial);
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        maxLines: maxLines,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
        textCapitalization: TextCapitalization.sentences,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final v = ctrl.text.trim();
            if (v.isEmpty && !allowEmpty) return;
            Navigator.pop(c, v);
          },
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  ctrl.dispose();
  return r;
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
}

Future<void> showErrorDialog(BuildContext context, String title, String message) => showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );

/// A colored circular avatar showing a subject/bank icon.
class NodeAvatar extends StatelessWidget {
  const NodeAvatar({super.key, this.iconKey, this.color, this.fallback = Icons.folder_outlined, this.size = 40});
  final String? iconKey;
  final int? color;
  final IconData fallback;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color != null ? Color(color!) : scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(12)),
      child: Icon(iconFor(iconKey, fallback: fallback), color: c, size: size * 0.55),
    );
  }
}

/// Wraps a page body with a max width so content stays readable on tablets
/// and desktop windows.
class Readable extends StatelessWidget {
  const Readable({super.key, required this.child, this.maxWidth = 760});
  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}


/// The Quiz me logo: graduation-cap emblem with "Quiz" + orange "me".
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 32, this.showText = true, this.useAmbientColor = false});
  final double size;
  final bool showText;

  /// Use the surrounding text colour for "Quiz" (e.g. white on a coloured
  /// app bar). Otherwise navy on light backgrounds and white on dark ones.
  final bool useAmbientColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    return Semantics(
      label: 'Quiz me',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Image.asset('assets/branding/emblem.png', width: size, height: size, filterQuality: FilterQuality.medium),
          if (showText) ...[
            SizedBox(width: size * 0.22),
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: 'Quiz ',
                    style: TextStyle(
                        color: useAmbientColor
                            ? (DefaultTextStyle.of(context).style.color ?? (dark ? Colors.white : brandNavy))
                            : (dark ? Colors.white : brandNavy))),
                const TextSpan(text: 'me', style: TextStyle(color: brandOrange)),
              ]),
              style: TextStyle(fontSize: size * 0.72, fontWeight: FontWeight.w800, letterSpacing: -0.3),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Large primary action with the app's gradient (primary -> tertiary).
class GradientButton extends StatelessWidget {
  const GradientButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 56});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final colors = enabled
        ? [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.75)!]
        : [scheme.onSurface.withValues(alpha: 0.12), scheme.onSurface.withValues(alpha: 0.12)];
    final fg = enabled ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.38);
    return Semantics(
      button: true,
      enabled: enabled,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(18),
          boxShadow: enabled
              ? [BoxShadow(color: scheme.primary.withValues(alpha: 0.30), blurRadius: 16, offset: const Offset(0, 6))]
              : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onPressed,
            child: Center(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, color: fg), const SizedBox(width: 10)],
                Text(label, style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Thin rounded progress bar filled with the app gradient.
class GradientProgressBar extends StatelessWidget {
  const GradientProgressBar({super.key, required this.value, this.height = 8});
  final double value;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Container(
        height: height,
        color: scheme.surfaceContainerHighest,
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: value.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Color.lerp(scheme.primary, scheme.tertiary, 0.75)!, scheme.primary]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular ring with a label inside (progress percentage or countdown).
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, required this.label, this.size = 64, this.color, this.semanticLabel});
  final double value;
  final String label;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel ?? label,
      child: ExcludeSemantics(
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: value.clamp(0.0, 1.0),
                strokeWidth: size * 0.09,
                strokeCap: StrokeCap.round,
                backgroundColor: scheme.surfaceContainerHighest,
                color: color ?? scheme.primary,
              ),
            ),
            Text(label, style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}
