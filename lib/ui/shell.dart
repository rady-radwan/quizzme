import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common/desktop.dart';
import 'common/widgets.dart';

import 'banks/banks_screen.dart';
import 'home/home_screen.dart';
import 'progress/progress_screen.dart';
import 'quiz/quiz_setup_screen.dart';
import 'settings/settings_screen.dart';

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
    final extended = isDesktop && width >= 1180;
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
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: select,
                  extended: extended,
                  minExtendedWidth: 210,
                  labelType: extended ? NavigationRailLabelType.none : NavigationRailLabelType.all,
                  leading: isDesktop
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
                          child: AppLogo(size: extended ? 40 : 36, showText: extended),
                        )
                      : null,
                  destinations: [
                    for (final d in _destinations)
                      NavigationRailDestination(icon: d.icon, selectedIcon: d.selectedIcon, label: Text(d.label)),
                  ],
                ),
                const VerticalDivider(width: 1),
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
