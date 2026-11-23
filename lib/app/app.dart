import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../data/settings_repository.dart';
import '../ui/shell.dart';
import 'services.dart';
import 'theme.dart';

class QuizMeApp extends StatelessWidget {
  const QuizMeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AppServices.I.settings;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.value;
        Locale? locale;
        if (s.layoutDirection == LayoutDirectionPref.rtl) locale = const Locale('ar');
        if (s.layoutDirection == LayoutDirectionPref.ltr) locale = const Locale('en');
        return MaterialApp(
          title: 'Quiz me',
          debugShowCheckedModeBanner: false,
          theme: AppThemes.light(s),
          darkTheme: AppThemes.dark(s),
          themeMode: AppThemes.modeFor(s.theme),
          locale: locale,
          supportedLocales: const [Locale('en'), Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final system = mq.textScaler.scale(1.0);
            final factor = (system * s.textScale).clamp(0.8, 2.6).toDouble();
            return MediaQuery(
              data: mq.copyWith(
                textScaler: TextScaler.linear(factor),
                disableAnimations: mq.disableAnimations || s.reduceMotion,
                highContrast: mq.highContrast || s.highContrast,
              ),
              child: child ?? const SizedBox.shrink(),
            );
          },
          home: const HomeShell(),
        );
      },
    );
  }
}

/// Shown only if the database cannot be opened at start-up.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.error});
  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text('Quiz me could not start',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                const Text('Your data has not been changed. Please close and reopen the app. '
                    'Avoid uninstalling: that would delete your local questions and history.'),
                const SizedBox(height: 16),
                SelectableText(error, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
