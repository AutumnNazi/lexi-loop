import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

void main() {
  final capture = Platform.environment['LEXI_CAPTURE'] == '1';
  setUpAll(() async {
    if (!capture) return;
    final font = FontLoader('Microsoft YaHei')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File('C:/Windows/Fonts/msyh.ttc').readAsBytes(),
          ),
        ),
      );
    await font.load();
  });
  for (final config in [
    (390.0, 1.0, false),
    (390.0, 1.5, false),
    (1280.0, 1.0, false),
    (390.0, 1.0, true),
  ]) {
    testWidgets('手账导航、学习与详情 ${config.$1} / ${config.$2} / dark=${config.$3}', (
      tester,
    ) async {
      tester.view.physicalSize = Size(config.$1, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = config.$2;
      tester.platformDispatcher.platformBrightnessTestValue = config.$3
          ? Brightness.dark
          : Brightness.light;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      var now = DateTime.utc(2026, 11, 27, 8);
      final deps = AppDependencies(
        AppDatabase(NativeDatabase.memory()),
        nowUtc: () => now,
      );
      addTearDown(deps.dispose);
      await deps.initialize();
      final first = (await deps.repository.queue()).first;
      final card = await deps.repository.score(
        first,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
      now = card.due;
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: Builder(
            builder: (context) {
              final app =
                  LexiLoopApp(dependencies: deps).build(context) as MaterialApp;
              if (!capture) return app;
              return MaterialApp(
                home: app.home,
                locale: app.locale,
                localizationsDelegates: app.localizationsDelegates,
                supportedLocales: app.supportedLocales,
                debugShowCheckedModeBanner: false,
                theme: journalTheme(
                  Brightness.light,
                  fontFamily: 'Microsoft YaHei',
                ),
                darkTheme: journalTheme(
                  Brightness.dark,
                  fontFamily: 'Microsoft YaHei',
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> inspect(String page) async {
        expect(tester.takeException(), isNull);
        if (!capture) return;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
        });
        await tester.pumpAndSettle();
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/journal-review')
            ..createSync(recursive: true);
          await File(
            '${dir.path}/${config.$1.toInt()}-${config.$2}-${config.$3 ? 'dark' : 'light'}-$page.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      await inspect('today');
      final start = find.text('开始学习');
      if (config.$2 == 1) {
        expect(tester.getBottomRight(start).dy, lessThan(760));
      }
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await inspect('study');
      await tester.tap(find.text('回忆 · 揭晓释义'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Good · 记得'));
      await inspect('answer');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      for (final entry in [
        (Icons.menu_book_outlined, 'library'),
        (Icons.insights_outlined, 'stats'),
        (Icons.tune, 'settings'),
      ]) {
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is JournalIcon && widget.icon == entry.$1,
          ),
        );
        await tester.pumpAndSettle();
        await inspect(entry.$2);
        if (entry.$2 == 'library') {
          await tester.tap(find.text('bloom'));
          await tester.pumpAndSettle();
          await inspect('detail');
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }
}
