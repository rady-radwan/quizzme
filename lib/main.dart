import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    AppServices.I = await AppServices.init();
  } catch (e, st) {
    debugPrint('Startup failed: $e\n$st');
    runApp(StartupErrorApp(error: '$e'));
    return;
  }
  runApp(const QuizMeApp());
  // Plan reminders after the first frame; never blocks start-up.
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    await AppServices.I.notifications.init();
    await AppServices.I.refreshReminders();
  });
}
