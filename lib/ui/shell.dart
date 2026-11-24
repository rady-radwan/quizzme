import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import 'common/desktop.dart';
import 'common/widgets.dart';

import 'banks/banks_screen.dart';
import 'home/home_screen.dart';
import 'progress/progress_screen.dart';
import 'quiz/quiz_setup_screen.dart';
import 'settings/settings_screen.dart';
import 'settings/sync_screen.dart';

/// Primary navigation: Home | Quiz | Banks | Progress | Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static HomeShellState? of(BuildContext context) => context.findAncestorStateOfType<HomeShellState>();

  @override
  State<HomeShell> createState() => HomeShellState();
}

class HomeShellState extends State<HomeShell> {
  int _index = 0;

  void select(int i) => setState(() => _index = i);

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(icon: Icon(Icons.quiz_outlined), selectedIcon: Icon(Icons.quiz), label: 'Quiz'),
    NavigationDestination(
        icon: Icon(Icons.library_books_outlined), selectedIcon: Icon(Icons.library_books), label: 'Banks'),
    NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Progress'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      const HomeScreen(),
      const QuizSetupScreen(embedded: true),
      const BanksScreen(),
      const ProgressScreen(),
      const SettingsScreen(),
    ];
    final width = MediaQuery.sizeOf(context).width;
    // Windows/desktop: side navigation as soon as the window is not tiny,
    // with text labels beside the icons in large windows.
    final wide = width >= 840 || (isDesktop && width >= 600);
    final body = IndexedStack(index: _index, children: pages);
    return PopScope(
      // Android back: from another tab go to Home first, then leave the app.
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: CallbackShortcuts(
        bindings: {
          for (var i = 0; i < _destinations.length; i++)
            SingleActivator(LogicalKeyboardKey(LogicalKeyboardKey.digit1.keyId + i), control: true): () => select(i),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
        body: wide
            ? Row(children: [
                _Sidebar(
                  index: _index,
                  extended: width >= 1000,
                  onSelect: select,
                  destinations: _destinations,
                ),
                Expanded(child: body),
              ])
            : body,
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: select,
                destinations: _destinations,
              ),
          ),
        ),
      ),
    );
  }
}

/// Desktop/tablet side menu: large, clear labels, a highlighted pill for the
/// current page, the logo on top and the account status at the bottom.
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.index, required this.extended, required this.onSelect, required this.destinations});
  final int index;
  final bool extended;
  final ValueChanged<int> onSelect;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final glass = Theme.of(context).scaffoldBackgroundColor.a < 1;
    return Container(
      width: extended ? 264 : 96,
      decoration: BoxDecoration(
        color: glass ? Colors.white.withValues(alpha: 0.55) : scheme.surfaceContainerLow,
        border: Border(right: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7))),
      ),
      child: SafeArea(
        right: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(extended ? 22 : 0, 22, extended ? 16 : 0, 26),
            child: extended
                ? const Align(alignment: AlignmentDirectional.centerStart, child: AppLogo(size: 44))
                : const Center(child: AppLogo(size: 44, showText: false)),
          ),
          for (var i = 0; i < destinations.length; i++)
            _SidebarItem(
              icon: destinations[i].icon,
              selectedIcon: destinations[i].selectedIcon ?? destinations[i].icon,
              label: destinations[i].label,
              selected: i == index,
              extended: extended,
              shortcut: 'Ctrl+${i + 1}',
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          _AccountChip(extended: extended),
          const SizedBox(height: 14),
        ]),
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.extended,
    required this.shortcut,
    required this.onTap,
  });
  final Widget icon;
  final Widget selectedIcon;
  final String label;
  final bool selected;
  final bool extended;
  final String shortcut;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sel = widget.selected;
    final fg = sel ? scheme.primary : scheme.onSurface.withValues(alpha: 0.82);
    final bg = sel
        ? scheme.primary.withValues(alpha: 0.16)
        : (_hover ? scheme.onSurface.withValues(alpha: 0.06) : Colors.transparent);
    final iconW = IconTheme(
      data: IconThemeData(color: fg, size: 26),
      child: sel ? widget.selectedIcon : widget.icon,
    );
    final content = widget.extended
        ? Row(children: [
            iconW,
            const SizedBox(width: 16),
            Expanded(
              child: Text(widget.label,
                  style: TextStyle(
                      fontSize: 17, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: fg, letterSpacing: 0.1)),
            ),
            if (_hover && !sel)
              Text(widget.shortcut,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant.withValues(alpha: 0.8))),
          ])
        : Column(mainAxisSize: MainAxisSize.min, children: [
            iconW,
            const SizedBox(height: 4),
            Text(widget.label,
                style: TextStyle(fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: fg)),
          ]);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: widget.extended ? 14 : 10, vertical: 3),
      child: Tooltip(
        message: widget.extended ? '' : '${widget.label} (${widget.shortcut})',
        waitDuration: const Duration(milliseconds: 500),
        child: Semantics(
          button: true,
          selected: sel,
          label: widget.label,
          excludeSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: widget.extended ? 54 : 68,
                padding: EdgeInsets.symmetric(horizontal: widget.extended ? 16 : 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: sel ? scheme.primary.withValues(alpha: 0.35) : Colors.transparent),
                ),
                alignment: widget.extended ? AlignmentDirectional.centerStart : Alignment.center,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Signed-in account (or a sign-in prompt) at the bottom of the side menu.
class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final sync = AppServices.I.sync;
    if (sync == null || !sync.available) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final on = sync.enabled;
        final icon = !on
            ? Icons.login
            : sync.busy
                ? Icons.sync
                : (sync.error == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined);
        final color = on && sync.error != null ? scheme.error : scheme.primary;
        final title = on ? (sync.email ?? 'Signed in') : 'Sign in';
        final sub = !on ? 'Sync phone & PC' : (sync.busy ? 'Syncing…' : (sync.error == null ? 'Synced' : 'Sync problem'));
        void open() => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const SyncScreen()));
        if (!extended) {
          return Center(
            child: IconButton(tooltip: '$title — $sub', onPressed: open, icon: Icon(icon, color: color)),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Material(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: open,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(sub, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}
