import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/core/theme_settings.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/ui/app_shell.dart';
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:lexi_loop/ui/study_page.dart';
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
      // 大词库由后台 isolate 解码，初始化需在测试的真实异步环境中完成。
      await tester.runAsync(() async {
        await deps.initialize();
        final first = (await deps.repository.queue()).first;
        final card = await deps.repository.score(
          first,
          fsrs.Rating.good,
          eventId: newReviewEventId(),
        );
        now = card.due;
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: Builder(
            builder: (context) {
              if (!capture) return LexiLoopApp(dependencies: deps);
              return MaterialApp(
                home: AppShell(dependencies: deps),
                locale: const Locale('zh', 'CN'),
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                supportedLocales: const [Locale('zh', 'CN')],
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
      final bookSelector = find.byKey(
        const ValueKey('active-wordbook-selector'),
      );
      await tester.ensureVisible(bookSelector);
      await tester.tap(bookSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('大学英语四级').last);
      await tester.pumpAndSettle();
      await inspect('today-selected-book');
      await tester.tap(bookSelector);
      await tester.pumpAndSettle();
      await tester.tap(find.text('全部词书').last);
      await tester.pumpAndSettle();
      final start = find.text('开始学习');
      if (config.$2 == 1) {
        expect(tester.getBottomRight(start).dy, lessThan(760));
      }
      await tester.ensureVisible(start);
      await tester.tap(start);
      await tester.pumpAndSettle();
      await inspect('study');
      await tester.ensureVisible(find.text('回忆 · 揭晓释义'));
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
        if (entry.$2 == 'settings') {
          final pronunciation = find.byKey(const ValueKey('pronounce-hello'));
          await tester.ensureVisible(pronunciation);
          await tester.pumpAndSettle();
          expect(pronunciation, findsOneWidget);
          await inspect('settings-pronunciation');
        }
        if (entry.$2 == 'library') {
          await tester.tap(find.text('自建词书'));
          await tester.pumpAndSettle();
          await inspect('create-book');
          await tester.enterText(
            find.byKey(const ValueKey('wordbook-search')),
            'abandon',
          );
          await tester.pumpAndSettle();
          final choice = find.widgetWithText(CheckboxListTile, 'abandon');
          await tester.ensureVisible(choice);
          await tester.tap(choice);
          await tester.pumpAndSettle();
          await inspect('create-book-results');
          await tester.tap(find.byTooltip('返回'));
          await tester.pumpAndSettle();
          expect(find.text('放弃未保存的修改？'), findsOneWidget);
          await tester.tap(find.text('放弃并返回'));
          await tester.pumpAndSettle();
          final bloom = find.text('bloom').first;
          await tester.ensureVisible(bloom);
          await tester.tap(bloom);
          await tester.pumpAndSettle();
          if (config.$1 >= 920) {
            expect(find.text('艾宾浩斯记忆曲线'), findsOneWidget);
          } else {
            await inspect('detail');
            await tester.tap(find.byTooltip('返回'));
            await tester.pumpAndSettle();
          }
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final config in [
    (390.0, 1.5, false),
    (1280.0, 1.0, false),
    (390.0, 1.0, true),
  ]) {
    testWidgets('新增页面状态截图 ${config.$1} / ${config.$2}', (tester) async {
      tester.view.physicalSize = Size(config.$1, 844);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = config.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final baseNow = DateTime.utc(2026, 11, 27, 8);
      var now = baseNow;
      final deps = AppDependencies(
        AppDatabase(NativeDatabase.memory()),
        nowUtc: () => now,
      );
      addTearDown(deps.dispose);
      late fsrs.Card bloomCard;
      await tester.runAsync(() async {
        await deps.initialize();
        final bloom = (await deps.repository.entries(
          wordbookId: 'everyday',
          search: 'bloom',
        )).first;
        final wander = (await deps.repository.entries(
          wordbookId: 'everyday',
          search: 'wander',
        )).first;
        await deps.repository.setDailyGoal(100);
        bloomCard = await deps.repository.score(
          bloom,
          fsrs.Rating.good,
          eventId: newReviewEventId(),
        );
        await deps.repository.score(
          wander,
          fsrs.Rating.good,
          eventId: newReviewEventId(),
        );
        await deps.repository.setDailyGoal(0);
        await deps.repository.setActiveWordbook('everyday');
        await deps.repository.createWordbook('手账练习', {bloom.sense.id});
      });

      Future<void> shot(GlobalKey key, String name) async {
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
            '${dir.path}/${config.$1.toInt()}-${config.$2}-${config.$3 ? 'dark' : 'light'}-feature-$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<GlobalKey> show(Widget home) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: journalTheme(
                Brightness.light,
                fontFamily: 'Microsoft YaHei',
              ),
              darkTheme: journalTheme(
                Brightness.dark,
                fontFamily: 'Microsoft YaHei',
              ),
              themeMode: config.$3 ? ThemeMode.dark : ThemeMode.light,
              home: home,
            ),
          ),
        );
        await tester.pumpAndSettle();
        return key;
      }

      final appKey = await show(AppShell(dependencies: deps));
      await shot(appKey, 'today-goal-zero');

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is JournalIcon && widget.icon == Icons.menu_book_outlined,
        ),
      );
      await tester.pumpAndSettle();
      await shot(appKey, 'library');
      final customChip = find.widgetWithText(ChoiceChip, '手账练习');
      await tester.ensureVisible(customChip);
      await tester.tap(customChip);
      await tester.pumpAndSettle();
      await shot(appKey, 'library-manage');

      await tester.tap(find.byKey(const ValueKey('edit-wordbook')));
      await tester.pumpAndSettle();
      await shot(appKey, 'library-edit');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-wordbook')));
      await tester.pumpAndSettle();
      await shot(appKey, 'library-delete-confirm');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      final everydayChip = find.widgetWithText(ChoiceChip, '日常微光');
      await tester.ensureVisible(everydayChip);
      await tester.tap(everydayChip);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('library-filter-learned')));
      await tester.pumpAndSettle();
      await shot(appKey, 'library-filter-learned');
      now = bloomCard.due;
      await tester.tap(find.byKey(const ValueKey('library-filter-due')));
      await tester.pumpAndSettle();
      await shot(appKey, 'library-filter-due');

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is JournalIcon && widget.icon == Icons.insights_outlined,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('curve-sense-picker')),
      );
      await tester.tap(find.byKey(const ValueKey('curve-sense-picker')));
      await tester.pumpAndSettle();
      await shot(appKey, 'stats-picker');
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byWidgetPredicate(
          (widget) =>
              widget is JournalIcon && widget.icon == Icons.menu_book_outlined,
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(customChip);
      await tester.tap(customChip);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('拼写练习'));
      await tester.tap(find.text('拼写练习'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-the-word');
      await tester.ensureVisible(find.text('检查答案'));
      await tester.tap(find.text('检查答案'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('查看本轮成绩'));
      await tester.tap(find.text('查看本轮成绩'));
      await tester.pumpAndSettle();
      await shot(appKey, 'spelling-complete');
      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();

      now = baseNow;
      await tester.runAsync(
        () => deps.repository.setActiveWordbook('everyday'),
      );
      final studyKey = await show(
        StudyPage(dependencies: deps, todayPlan: true),
      );
      await shot(studyKey, 'study-empty-goal-zero');
      await tester.pumpWidget(const SizedBox());
    }, skip: !capture);
  }

  for (final config in [
    (320.0, 1.5, false),
    (390.0, 1.0, true),
    (1280.0, 1.0, false),
  ]) {
    testWidgets('新词先学后测与读音布局 ${config.$1}', (tester) async {
      tester.view.physicalSize = Size(config.$1, 900);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = config.$2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final deps = AppDependencies(AppDatabase(NativeDatabase.memory()));
      addTearDown(deps.dispose);
      const channel = MethodChannel('flutter_tts');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getVoices') {
              return [
                {'name': 'English', 'locale': 'en-US'},
              ];
            }
            return 1;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.runAsync(() async {
        await deps.initialize();
        await deps.repository.setActiveWordbook('everyday');
        await deps.repository.setDailyGoal(2);
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('zh', 'CN'),
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            supportedLocales: const [Locale('zh', 'CN')],
            theme: journalTheme(
              config.$3 ? Brightness.dark : Brightness.light,
              fontFamily: capture ? 'Microsoft YaHei' : null,
            ),
            home: StudyPage(dependencies: deps, todayPlan: true),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> inspect(String state) async {
        expect(tester.takeException(), isNull);
        if (!capture) return;
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/learning-pronunciation-review')
            ..createSync(recursive: true);
          await File('${dir.path}/${config.$1.toInt()}-$state.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.text('新词先看 1 / 2'), findsOneWidget);
      await inspect('browse');
      await tester.ensureVisible(find.text('听读音'));
      await tester.tap(find.text('听读音'));
      await tester.pumpAndSettle();
      expect(find.text('停止'), findsOneWidget);
      await inspect('pronunciation');
      await tester.tap(find.text('语速 · 标准'));
      await tester.pumpAndSettle();
      await inspect('rate-menu');
      await tester.tap(find.text('慢速').last);
      await tester.pumpAndSettle();
      final next = find.byKey(const ValueKey('new-word-browse-next'));
      await tester.ensureVisible(next);
      await inspect('browse-action');
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('新词先看 2 / 2'), findsOneWidget);
      expect(deps.pronunciation.playing, isFalse);
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('新词测试 1 / 2'), findsOneWidget);
      expect(find.text('开花；逐渐发展成熟'), findsNothing);
      await tester.ensureVisible(find.text('新词测试 1 / 2'));
      await inspect('test');
      final reveal = find.text('回忆 · 揭晓释义');
      await tester.ensureVisible(reveal);
      await tester.tap(reveal);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Good · 记得'));
      await inspect('rating');
      expect(await deps.repository.history(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
  }

  testWidgets('四套主题多尺寸截图', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = AppDependencies(AppDatabase(NativeDatabase.memory()));
    addTearDown(dependencies.dispose);
    await tester.runAsync(dependencies.initialize);
    for (final theme in JournalThemeId.values) {
      for (final config in [
        (width: 390.0, scale: 1.5, dark: false),
        (width: 390.0, scale: 1.0, dark: true),
        (width: 1280.0, scale: 1.0, dark: false),
      ]) {
        tester.view.physicalSize = Size(config.width, 844);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = config.scale;
        final key = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN')],
              localizationsDelegates: GlobalMaterialLocalizations.delegates,
              theme: journalTheme(
                Brightness.light,
                themeId: theme,
                fontFamily: 'Microsoft YaHei',
              ),
              darkTheme: journalTheme(
                Brightness.dark,
                themeId: theme,
                fontFamily: 'Microsoft YaHei',
              ),
              themeMode: config.dark ? ThemeMode.dark : ThemeMode.light,
              home: AppShell(dependencies: dependencies),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final dir = Directory('build/theme-review')
            ..createSync(recursive: true);
          await File(
            '${dir.path}/${theme.storageValue}-${config.width.toInt()}-${config.scale}-${config.dark ? 'dark' : 'light'}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }
    await tester.pumpWidget(const SizedBox());
  }, skip: !capture);
}
