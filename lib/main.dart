import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app.dart';
import 'app/services.dart';

// ignore: unused_element
AppLifecycleListener? _lifecycle;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Licences of the bundled Google Fonts (shown in Settings → Licences).
  LicenseRegistry.addLicense(() async* {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final path in manifest.listAssets().where((a) => a.startsWith('assets/font_licenses/'))) {
      final name = path.split('/').last.replaceAll('.txt', '');
      yield LicenseEntryWithLineBreaks(['Font: $name'], await rootBundle.loadString(path));
    }
  });
  try {
    AppServices.I = await AppServices.init();
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(error: '$e'));
    return;
  }
  runApp(const QuizMeApp());
  // Sync with the Quiz me account when the app comes back to the foreground, and
  // push pending changes when it goes to the background.
  _lifecycle = AppLifecycleListener(
    onResume: () => AppServices.I.sync?.appResumed(),
    onPause: () => AppServices.I.sync?.appPaused(),
  );
  // Plan reminders and start sync after the first frame; never blocks start-up.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await AppServices.I.sync?.init();
    } catch (e) {
      debugPrint('Sync start failed: $e');
    }
    await AppServices.I.notifications.init();
    await AppServices.I.refreshReminders();
  });
}
