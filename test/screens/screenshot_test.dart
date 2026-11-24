// Renders key screens at desktop size and saves PNGs to build/screenshots/
// (published by CI with the reports) so the layout can be reviewed without
// a Windows PC. Also fails on layout overflow errors.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quiz_me/app/app.dart';
import 'package:quiz_me/app/services.dart';
import 'package:quiz_me/data/sample_data.dart';
import 'package:quiz_me/data/settings_repository.dart';

import '../data/database_test.dart' show openServices;

Future<void> _loadFonts() async {
  Future<void> family(String name, List<String> assets) async {
    final loader = FontLoader(name);
    for (final a in assets) {
      loader.addFont(rootBundle.load(a));
    }
    await loader.load();
  }

  await family('Inter', [
    'assets/fonts/Inter/Inter_400Regular.ttf',
    'assets/fonts/Inter/Inter_600SemiBold.ttf',
    'assets/fonts/Inter/Inter_700Bold.ttf',
  ]);
  await family('Cairo', ['assets/fonts/Cairo/Cairo_400Regular.ttf']);
  // Material icons ship with the Flutter SDK.
  final engine = File(Platform.resolvedExecutable).parent; // .../artifacts/engine/<platform>
  final icons = File('${engine.parent.parent.path}/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final loader = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await loader.load();
  }
}

Future<void> _save(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('shot')));
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screenshots/$name.png');
    await f.parent.create(recursive: true);
    await f.writeAsBytes(png!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final theme in [AppTheme.dark, AppTheme.minimal, AppTheme.glassBlue]) {
    testWidgets('desktop screens render without overflow (${theme.key})', (tester) async {
      await tester.runAsync(_loadFonts);
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.reset();
        debugDefaultTargetPlatformOverride = null;
      });

      late AppServices s;
      await tester.runAsync(() async {
        s = await openServices();
        await SampleData.create(s.catalog, s.questions);
        await s.settings.update(s.settings.value.copyWith(theme: theme, font: AppFont.inter));
      });
      AppServices.I = s;

      await tester.pumpWidget(const RepaintBoundary(key: ValueKey('shot'), child: QuizMeApp()));
      await _settle(tester);
      await _save(tester, 'home_${theme.key}');

      await tester.tap(find.text('Settings').first);
      await _settle(tester);
      await _save(tester, 'settings_${theme.key}');
      expect(tester.takeException(), isNull);
    });
  }
}
