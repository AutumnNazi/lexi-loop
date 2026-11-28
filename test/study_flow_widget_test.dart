import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/data/study_repository.dart';
import 'package:lexi_loop/ui/library_page.dart';
import 'package:lexi_loop/ui/spelling_practice_page.dart';
import 'package:lexi_loop/ui/stats_page.dart';
import 'package:lexi_loop/ui/study_page.dart';
import 'package:lexi_loop/ui/today_page.dart';
import 'package:lexi_loop/ui/word_detail_page.dart';
import 'package:lexi_loop/ui/memory_curve_chart.dart';
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:lexi_loop/ui/common.dart';

void main() {
  late AppDependencies dependencies;
  late DateTime now;
  setUp(() async {
    now = DateTime.utc(2026, 11, 27, 8);
    dependencies = AppDependencies(
      AppDatabase(NativeDatabase.memory()),
      nowUtc: () => now,
    );
    await dependencies.initialize();
  });
  tearDown(() => dependencies.dispose());

  Future<void> surface(
    WidgetTester tester, {
    double width = 390,
    double scale = 1.5,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  Future<void> finishNewWordBrowse(WidgetTester tester) async {
    final next = find.byKey(const ValueKey('new-word-browse-next'));
    for (var i = 0; i < 10 && next.evaluate().isNotEmpty; i++) {
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
    }
    expect(next, findsNothing);
  }

  testWidgets('首页固定四级词书后保留选择，开始学习和拼写都使用当前词书', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(2);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('active-wordbook-selector'));
    expect(selector, findsOneWidget);
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('大学英语四级').last);
    await tester.pumpAndSettle();
    expect((await dependencies.repository.activeWordbook())?.id, 'cet4');
    expect(find.textContaining('未能切换词书'), findsNothing);
    expect(find.text('已学 0 / 3849 个单词'), findsOneWidget);
    await tester.ensureVisible(find.text('开始学习'));
    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsOneWidget);
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Good · 记得'));
    await tester.tap(find.text('Good · 记得'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('结束本组新词学习？'), findsOneWidget);
    expect(find.textContaining('1 个词义已保存'), findsOneWidget);
    await tester.tap(find.text('退出并保留已评'));
    await tester.pumpAndSettle();
    expect(find.text('已学 1 / 3849 个单词'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('已学 1 / 3849 个单词'), findsOneWidget);
    await tester.ensureVisible(find.text('拼写练习'));
    await tester.tap(find.text('拼写练习'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<SpellingPracticePage>(find.byType(SpellingPracticePage))
          .wordbookId,
      'cet4',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页学习先复习其他词书到期词，再进入选定词书新词', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final original = (await dependencies.repository.queue(
      wordbookId: 'everyday',
    )).first;
    final card = await dependencies.repository.score(
      original,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = card.due;
    await dependencies.repository.setActiveWordbook('cet4');
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('待复习 1'), findsOneWidget);
    await tester.tap(find.text('开始学习'));
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Good · 记得'));
    await tester.tap(find.text('Good · 记得'));
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页选择长名称自建词书，并可恢复全部词书', (tester) async {
    await surface(tester);
    final item = (await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 1,
    )).single;
    final longName = '本周重点复习的大学英语词汇与容易混淆的单词专用随身学习手账';
    await dependencies.repository.createWordbook(longName, {item.sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(0);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('已学 0 / 1 个单词'), findsOneWidget);
    expect(find.text('等待下一次复习'), findsOneWidget);
    final selector = find.byKey(const ValueKey('active-wordbook-selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部词书').last);
    await tester.pumpAndSettle();
    expect(await dependencies.repository.activeWordbook(), isNull);
    expect(find.text('已学 0 / 13141 个单词'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页空队列显示仅复习、未学词数量和下次复习时间', (tester) async {
    await surface(tester);
    final target = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 1,
    )).single;
    await dependencies.repository.setDailyGoal(10);
    await dependencies.repository.score(
      target,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await dependencies.repository.setDailyGoal(0);
    await dependencies.repository.setActiveWordbook('everyday');
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('今天，只和复习见面'), findsOneWidget);
    expect(find.textContaining('每日新词目标为 0'), findsOneWidget);
    expect(find.textContaining('还有 23 个未学词义'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    expect(find.text('当前任务已完成'), findsNothing);
    expect(find.text('等待下一次复习'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页当前词书没有新词时说明暂无新词并给下次复习', (tester) async {
    await surface(tester);
    final item = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    await dependencies.repository.setDailyGoal(10);
    await dependencies.repository.score(
      item,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await dependencies.repository.createWordbook('单书完成', {item.sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    expect(find.text('当前范围没有新词'), findsOneWidget);
    expect(find.textContaining('单书完成暂无未学词义'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    expect(find.text('当前任务已完成'), findsNothing);
    expect(find.text('已学 1 / 1 个单词'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('学习词书保存失败时保留原选择并允许重试', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    await dependencies.repository.setActiveWordbook('cet4');
    await dependencies.database.customStatement(
      "CREATE TRIGGER reject_active_book BEFORE UPDATE ON app_settings WHEN NEW.key = 'active_wordbook_id' BEGIN SELECT RAISE(ABORT, 'test selection failure'); END",
    );
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('active-wordbook-selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('大学英语六级').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('未能切换词书'), findsOneWidget);
    expect(tester.widget<DropdownButton<String>>(selector).value, 'cet4');
    expect((await dependencies.repository.activeWordbook())?.id, 'cet4');
    await dependencies.database.customStatement(
      'DROP TRIGGER reject_active_book',
    );
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('大学英语六级').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('未能切换词书'), findsNothing);
    expect(find.text('已学 0 / 5407 个单词'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新词浏览完整组后，只有揭晓才能评分并切到下一个测试词', (tester) async {
    await surface(tester);
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-word-browse-progress')),
      findsOneWidget,
    );
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    expect(find.text('开花；绽放'), findsOneWidget);
    expect(find.text('Good · 记得'), findsNothing);
    await finishNewWordBrowse(tester);
    expect(
      find.byKey(const ValueKey('new-word-test-progress')),
      findsOneWidget,
    );
    expect(find.text('开花；绽放'), findsNothing);
    expect(find.text('Good · 记得'), findsNothing);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    expect(find.text('开花；绽放'), findsOneWidget);
    await tester.ensureVisible(find.text('Good · 记得'));
    await tester.tap(find.text('Good · 记得'));
    await tester.pumpAndSettle();
    expect(find.text('wander'), findsOneWidget);
    expect((await dependencies.repository.history()).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final layout in [(390.0, 1.5), (1280.0, 1.0)]) {
    testWidgets('曲线纵轴在 ${layout.$2} 倍字号下与网格线对齐', (tester) async {
      await surface(tester, width: layout.$1, scale: layout.$2);
      await dependencies.repository.score(
        (await dependencies.repository.queue()).first,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
      final history = await dependencies.repository.history();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MemoryCurveChart(
                history: history,
                engine: dependencies.engine,
                nowUtc: now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final plot = tester.getRect(
        find.descendant(
          of: find.byType(MemoryCurveChart),
          matching: find.byType(CustomPaint),
        ),
      );
      expect(tester.getCenter(find.text('100%')).dy, closeTo(plot.top, .5));
      expect(
        tester.getCenter(find.text('50%')).dy,
        closeTo(plot.center.dy, .5),
      );
      expect(tester.getCenter(find.text('0%')).dy, closeTo(plot.bottom, .5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('四个主页面在 ${layout.$1} 宽和 ${layout.$2} 倍字号下不溢出', (tester) async {
      await surface(tester, width: layout.$1, scale: layout.$2);
      await dependencies.repository.score(
        (await dependencies.repository.queue()).first,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
      await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      expect(find.text('每天一点，慢慢记牢。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final icon in [
        Icons.menu_book_outlined,
        Icons.insights_outlined,
        Icons.tune,
      ]) {
        await tester.tap(
          find.byWidgetPredicate(
            (widget) => widget is JournalIcon && widget.icon == icon,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('到期刷新会把刚学完的卡片重新放回队列', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Again · 忘记'));
    await tester.tap(find.text('Again · 忘记'));
    await tester.pumpAndSettle();
    expect(find.text('今天的新词额度已用完'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    now = now.add(const Duration(minutes: 1));
    await tester.pump(const Duration(minutes: 1));
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('学习期间系统时间倒退会提示校时，恢复后可以继续', (tester) async {
    final first = (await dependencies.repository.queue()).first;
    final learnedAt = now;
    final card = await dependencies.repository.score(
      first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = card.due;
    await surface(tester);
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    now = learnedAt.subtract(const Duration(minutes: 1));
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('请检查系统时间'), findsOneWidget);
    expect(find.text('Good · 记得'), findsNothing);
    expect(await dependencies.repository.history(), hasLength(1));
    now = card.due;
    await tester.tap(find.text('刷新学习队列'));
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('跨过本地午夜后，今日页自动恢复新词额度', (tester) async {
    now = DateTime(2026, 11, 27, 23, 59, 59).toUtc();
    await dependencies.repository.setDailyGoal(1);
    await dependencies.repository.score(
      (await dependencies.repository.queue()).first,
      fsrs.Rating.easy,
      eventId: newReviewEventId(),
    );
    await surface(tester);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    expect(find.text('今天的新词，学到这里'), findsOneWidget);
    expect(find.textContaining('今天已完成 1 / 1 个新词义'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    now = now.add(const Duration(seconds: 2));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('留一点时间给记忆'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写判错与统计只影响本轮，不写学习状态或评分', (tester) async {
    await surface(tester);
    await tester.pumpWidget(
      MaterialApp(home: SpellingPracticePage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'definitely-wrong');
    await tester.ensureVisible(find.text('检查答案'));
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    expect(find.textContaining('正确答案：'), findsOneWidget);
    expect(find.textContaining('已答对 0 / 1'), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('背词页浏览阶段 Space 前进，测试阶段 Space 揭晓并可用数字键评分', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    expect(find.text('开花；绽放'), findsOneWidget);

    for (var index = 1; index < 5; index++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
      expect(find.text('新词先看 ${index + 1} / 5'), findsOneWidget);
    }
    expect(await dependencies.repository.history(), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('新词测试 1 / 5'), findsOneWidget);
    expect(find.text('开花；绽放'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('开花；绽放'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(find.text('wander'), findsOneWidget);
    expect((await dependencies.repository.history()).length, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('宽屏词书页采用 Master-Detail 分栏并同步切换右侧详情', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is JournalIcon && widget.icon == Icons.menu_book_outlined,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('学习这个词义'), findsWidgets);
    expect(
      find.text('The small garden begins to bloom in May.'),
      findsOneWidget,
    );

    await tester.tap(find.text('wander'));
    await tester.pumpAndSettle();
    expect(
      find.text('We wander through the quiet town after lunch.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('可从四级词书搜索词条并从词条详情直接学习', (tester) async {
    await surface(tester, width: 390, scale: 1.0);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: LibraryPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '大学英语四级'));
    await tester.pumpAndSettle();
    expect(find.textContaining('共 3849 个词义'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abandon');
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsWidgets);
    await tester.tap(find.text('abandon').last);
    await tester.pumpAndSettle();
    expect(find.text('这份词库没有提供例句。'), findsOneWidget);

    await tester.tap(find.text('学习这个词义'));
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsOneWidget);
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Good · 记得'));
    await tester.tap(find.text('Good · 记得'));
    await tester.pumpAndSettle();
    expect(await dependencies.repository.history(), hasLength(1));
    expect(find.text('当前没有可学词义'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('自建词书可以搜索、跨筛选保留勾选并检查已选词义', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: LibraryPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自建词书'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('wordbook-search'));
    expect(search, findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '词书名称'), '考试随身词');
    await tester.enterText(search, 'abandon');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'abandon'),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'abandon'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(search);
    await tester.enterText(search, 'zoology');
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'zoology'),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'zoology'));
    await tester.pumpAndSettle();
    final selected = find.byKey(const ValueKey('wordbook-selected-only'));
    await tester.ensureVisible(selected);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(
      tester
          .widgetList<CheckboxListTile>(find.byType(CheckboxListTile))
          .every((tile) => tile.value == true),
      isTrue,
    );
    await tester.ensureVisible(
      find.widgetWithText(CheckboxListTile, 'zoology'),
    );
    await tester.tap(find.widgetWithText(CheckboxListTile, 'zoology'));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.text('创建词书（1 个词义）'));
    await tester.pumpAndSettle();
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => book.name == '考试随身词',
    );
    final items = await dependencies.repository.entries(wordbookId: book.id);
    expect(items.single.word.spelling, 'abandon');
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('自建词书按词书分页，切换筛选保留选择并显示空结果', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: LibraryPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自建词书'));
    await tester.pumpAndSettle();
    final source = find.byKey(const ValueKey('wordbook-source'));
    await tester.tap(source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('大学英语四级').last);
    await tester.pumpAndSettle();
    expect(find.text('1–40 / 3849'), findsOneWidget);
    final firstTile = find.byType(CheckboxListTile).first;
    final firstWord =
        (tester.widget<CheckboxListTile>(firstTile).title! as Text).data!;
    await tester.ensureVisible(firstTile);
    await tester.tap(firstTile);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一页'));
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('41–80 / 3849'), findsOneWidget);
    final nextTile = find.byType(CheckboxListTile).first;
    final nextWord =
        (tester.widget<CheckboxListTile>(nextTile).title! as Text).data!;
    expect(nextWord, isNot(firstWord));
    await tester.ensureVisible(nextTile);
    await tester.tap(nextTile);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('上一页'));
    await tester.tap(find.text('上一页'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<CheckboxListTile>(find.byType(CheckboxListTile).first)
          .value,
      isTrue,
    );
    await tester.ensureVisible(source);
    await tester.tap(source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('日常微光').last);
    await tester.pumpAndSettle();
    expect(find.text('1–24 / 24'), findsOneWidget);
    expect(find.text('下一页'), findsNothing);
    final search = find.byKey(const ValueKey('wordbook-search'));
    await tester.ensureVisible(search);
    await tester.enterText(search, 'no-matching-word-xyz');
    await tester.pumpAndSettle();
    expect(find.text('0 个结果'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    final selected = find.byKey(const ValueKey('wordbook-selected-only'));
    await tester.ensureVisible(selected);
    await tester.tap(selected);
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text(firstWord), findsOneWidget);
    expect(find.text(nextWord), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('桌面词书滚动到底后可继续加载下一批词义', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: LibraryPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '大学英语四级'));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    final more = find.text('加载更多（还剩 3809 个词义）');
    await tester.scrollUntilVisible(more, 500, scrollable: scrollable);
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    final next = find.text('加载更多（还剩 3769 个词义）');
    await tester.scrollUntilVisible(next, 500, scrollable: scrollable);
    expect(next, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('选择六级词书后可学习整本词书并写入共享进度', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: LibraryPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '大学英语六级'));
    await tester.pumpAndSettle();
    final start = find.text('学习这本词书');
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(find.text('abandon'), findsOneWidget);
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Good · 记得'));
    await tester.tap(find.text('Good · 记得'));
    await tester.pumpAndSettle();
    final shared = (await dependencies.repository.entries(
      wordbookId: 'cet4',
      search: 'abandon',
    )).singleWhere((item) => item.word.spelling == 'abandon');
    expect(shared.memory, isNotNull);
    expect(await dependencies.repository.history(), hasLength(1));
    expect(find.text('今天的新词额度已用完'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('自建词书可改名和增删词义，删除后首页恢复全部词书', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final items = await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 2,
    );
    await dependencies.repository.createWordbook('待编辑词书', {items[0].sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is JournalIcon && widget.icon == Icons.menu_book_outlined,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '待编辑词书'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-wordbook')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('edit-wordbook')));
    await tester.pumpAndSettle();

    final name = find.byKey(const ValueKey('wordbook-name'));
    expect(tester.widget<TextField>(name).controller!.text, '待编辑词书');
    await tester.enterText(name, '改名后的词书');
    await tester.ensureVisible(
      find.byKey(const ValueKey('wordbook-selected-only')),
    );
    await tester.tap(find.byKey(const ValueKey('wordbook-selected-only')));
    await tester.pumpAndSettle();
    expect(find.byType(CheckboxListTile), findsOneWidget);
    await tester.tap(find.text('查找词义'));
    await tester.pumpAndSettle();
    final search = find.byKey(const ValueKey('wordbook-search'));
    await tester.enterText(search, 'zoology');
    await tester.pumpAndSettle();
    final choice = find.widgetWithText(CheckboxListTile, 'zoology');
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('保存修改'));
    await tester.pumpAndSettle();

    final renamed = (await dependencies.repository.books()).singleWhere(
      (row) => row.id == book.id,
    );
    expect(renamed.name, '改名后的词书');
    expect(await dependencies.repository.senseIdsForWordbook(book.id), {
      items[0].sense.id,
      (await dependencies.repository.entries(search: 'zoology')).first.sense.id,
    });
    expect(find.widgetWithText(ChoiceChip, '改名后的词书'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('export-wordbook')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('export-wordbook-csv')), findsOneWidget);
    expect(find.byKey(const ValueKey('export-wordbook-json')), findsOneWidget);
    expect(find.textContaining('仅导出词条内容'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is JournalIcon && widget.icon == Icons.wb_sunny_outlined,
      ),
    );
    await tester.pumpAndSettle();
    final selector = find.byKey(const ValueKey('active-wordbook-selector'));
    expect(
      find.descendant(of: selector, matching: find.text('改名后的词书')),
      findsOneWidget,
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is JournalIcon && widget.icon == Icons.menu_book_outlined,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('delete-wordbook')));
    await tester.pumpAndSettle();
    expect(find.textContaining('词条、学习状态和评分历史都会保留'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(
      (await dependencies.repository.books()).any((row) => row.id == book.id),
      isTrue,
    );
    expect((await dependencies.repository.activeWordbook())?.id, book.id);

    await tester.tap(find.byKey(const ValueKey('delete-wordbook')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-delete-wordbook')));
    await tester.pumpAndSettle();
    expect(
      (await dependencies.repository.books()).any((row) => row.id == book.id),
      isFalse,
    );
    expect(await dependencies.repository.activeWordbook(), isNull);
    expect(
      find.text('The small garden begins to bloom in May.'),
      findsOneWidget,
    );

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is JournalIcon && widget.icon == Icons.wb_sunny_outlined,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.widget<DropdownButton<String>>(selector).value, '');
    expect(find.text('已学 0 / 13141 个单词'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('恢复后当前词书不存在时，词书页刷新回全部词书', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final item = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 1,
    )).single;
    await dependencies.repository.createWordbook('会被恢复移除', {item.sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: LibraryPage(
            dependencies: dependencies,
            refreshListenable: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '会被恢复移除'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-wordbook')), findsOneWidget);
    expect(find.textContaining('会被恢复移除 · 全部 · 共 1 个词义'), findsOneWidget);

    await (dependencies.database.delete(
      dependencies.database.wordbookEntries,
    )..where((row) => row.wordbookId.equals(book.id))).go();
    await (dependencies.database.delete(
      dependencies.database.wordbooks,
    )..where((row) => row.id.equals(book.id))).go();
    signal.value++;
    await tester.pumpAndSettle();

    expect(find.text('会被恢复移除'), findsNothing);
    expect(find.byKey(const ValueKey('edit-wordbook')), findsNothing);
    expect(find.textContaining('全部词书 · 全部 · 共 13165 个词义'), findsOneWidget);
    expect(find.text('没有找到匹配的词条'), findsNothing);
    expect(find.text('bloom'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑词书预选完成前不能勾选，完成后保留原选择', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final items = await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 2,
    );
    await dependencies.repository.createWordbook('慢加载词书', {items[0].sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    final gate = Completer<List<StudyItem>>();
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordbookEditorPage(
          dependencies: dependencies,
          book: book,
          existingItemsLoader: (_) => gate.future,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final candidate = find.widgetWithText(
      CheckboxListTile,
      items[1].word.spelling,
    );
    expect(candidate, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(candidate).onChanged, isNull);
    expect(find.text('已选 0 个词义'), findsOneWidget);
    await tester.tap(candidate, warnIfMissed: false);
    await tester.pump();
    expect(find.text('已选 0 个词义'), findsOneWidget);

    gate.complete([items[0]]);
    await tester.pumpAndSettle();
    expect(find.text('已选词义（1）'), findsOneWidget);
    expect(find.text('已选 1 个词义'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(candidate).onChanged, isNotNull);
    final selectedTile = find.widgetWithText(
      CheckboxListTile,
      items[0].word.spelling,
    );
    expect(tester.widget<CheckboxListTile>(selectedTile).value, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑词书预选失败时禁用选词和保存并提供重读', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final items = await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 2,
    );
    await dependencies.repository.createWordbook('读取失败词书', {items[0].sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordbookEditorPage(
          dependencies: dependencies,
          book: book,
          existingItemsLoader: (_) async => throw StateError('预选读取失败'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('暂时无法读取词书内容'), findsOneWidget);
    expect(find.text('重新读取词书内容'), findsOneWidget);
    final firstTile = find.byType(CheckboxListTile).first;
    expect(tester.widget<CheckboxListTile>(firstTile).onChanged, isNull);
    final save = find.widgetWithText(FilledButton, '保存修改（0 个词义）');
    expect(save, findsOneWidget);
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('wordbook-search')))
          .enabled,
      isFalse,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词书状态筛选与搜索分页组合，不改变首页学习计划', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await dependencies.repository.setDailyGoal(1);
    final target = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    final card = await dependencies.repository.score(
      target,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = card.due;
    await dependencies.repository.setActiveWordbook('cet4');
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: LibraryPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '日常微光'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('edit-wordbook')), findsNothing);
    expect(find.byKey(const ValueKey('delete-wordbook')), findsNothing);
    expect(find.byKey(const ValueKey('export-wordbook')), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('library-filter-learned')),
    );
    await tester.tap(find.byKey(const ValueKey('library-filter-learned')));
    await tester.pumpAndSettle();
    expect(find.textContaining('已学 · 共 1 个词义'), findsOneWidget);
    expect(find.text('bloom'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('library-filter-due')));
    await tester.pumpAndSettle();
    expect(find.textContaining('待复习 · 共 1 个词义'), findsOneWidget);
    expect(find.text('bloom'), findsWidgets);
    final searchField = find.byType(TextField).first;
    await tester.enterText(searchField, 'wander');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的待复习词义'), findsOneWidget);
    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('library-filter-unlearned')));
    await tester.pumpAndSettle();
    expect(find.textContaining('未学 · 共 23 个词义'), findsOneWidget);
    expect(find.text('bloom'), findsNothing);
    await tester.enterText(searchField, 'bloom');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的未学词义'), findsOneWidget);

    await tester.enterText(searchField, '');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, '全部词书'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('library-filter-all')));
    await tester.pumpAndSettle();
    final more = find.text('加载更多（还剩 13125 个词义）');
    await tester.ensureVisible(more);
    await tester.tap(more);
    await tester.pumpAndSettle();
    expect(find.text('加载更多（还剩 13085 个词义）'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('library-filter-unlearned')),
    );
    await tester.tap(find.byKey(const ValueKey('library-filter-unlearned')));
    await tester.pumpAndSettle();
    expect(find.text('加载更多（还剩 13124 个词义）'), findsOneWidget);
    expect((await dependencies.repository.activeWordbook())?.id, 'cet4');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写完成页列出错词，仅重练错词会清空上一轮状态且不写库', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    final wander = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    );
    await dependencies.repository.createWordbook('错词重练', {
      bloom.first.sense.id,
      wander.first.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: book.id,
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (var answered = 1; answered <= 2; answered++) {
      expect(find.textContaining('第 $answered / 2 题'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'wrong-$answered');
      await tester.ensureVisible(find.text('检查答案'));
      await tester.tap(find.text('检查答案'));
      await tester.pumpAndSettle();
      expect(find.textContaining('正确答案：'), findsOneWidget);
      final advance = answered == 2 ? find.text('查看本轮成绩') : find.text('下一题');
      await tester.ensureVisible(advance);
      await tester.tap(advance);
      await tester.pumpAndSettle();
    }

    expect(find.text('拼写练习完成'), findsOneWidget);
    expect(find.text('本轮错词'), findsOneWidget);
    expect(find.text('bloom'), findsWidgets);
    expect(find.text('wander'), findsWidgets);
    expect(find.text(bloom.first.sense.definition), findsOneWidget);
    expect(find.text(wander.first.sense.definition), findsOneWidget);
    expect(find.text('仅重练错词'), findsOneWidget);
    expect(find.text('重新随机一轮'), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      isEmpty,
    );

    await tester.tap(find.text('仅重练错词'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 / 2 题'), findsOneWidget);
    expect(find.textContaining('已答对 0 / 0'), findsOneWidget);
    final answer = tester.widget<TextField>(find.byType(TextField));
    expect(answer.controller!.text, isEmpty);
    expect(find.textContaining('先写下你的答案'), findsNothing);
    expect(find.text('拼写练习完成'), findsNothing);

    await tester.enterText(find.byType(TextField), 'still-wrong');
    await tester.ensureVisible(find.text('检查答案'));
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一题'));
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    expect(find.textContaining('已答对 0 / 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写全对时不显示重练错词，且可开始新的随机一轮', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    await dependencies.repository.createWordbook('全对练习', {
      bloom.first.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: book.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '  BLOOM ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('答对了！'), findsOneWidget);
    await tester.ensureVisible(find.text('查看本轮成绩'));
    await tester.tap(find.text('查看本轮成绩'));
    await tester.pumpAndSettle();
    expect(find.text('拼写练习完成'), findsOneWidget);
    expect(find.textContaining('答对 1 / 1'), findsOneWidget);
    expect(find.text('仅重练错词'), findsNothing);
    expect(find.text('本轮错词'), findsNothing);
    expect(find.text('重新随机一轮'), findsOneWidget);

    await tester.tap(find.text('重新随机一轮'));
    await tester.tap(find.text('重新随机一轮'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 / 1 题'), findsOneWidget);
    expect(find.textContaining('已答对 0 / 0'), findsOneWidget);
    expect(find.text('拼写练习完成'), findsNothing);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写数据加载失败会给出明确错误并可重试', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await dependencies.database.customStatement(
      'ALTER TABLE wordbook_entries RENAME TO wordbook_entries_hold',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: 'cet4',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取拼写题目'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.textContaining('第 1 /'), findsNothing);

    await dependencies.database.customStatement(
      'ALTER TABLE wordbook_entries_hold RENAME TO wordbook_entries',
    );
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 / 10 题'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写不知道会记入错词一次且不写库，320 宽大字号可用', (tester) async {
    await surface(tester, width: 320, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    await dependencies.repository.createWordbook('不知道练习', {
      bloom.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: book.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('不知道，查看答案'), findsOneWidget);
    await tester.ensureVisible(find.text('不知道，查看答案'));
    await tester.tap(find.text('不知道，查看答案'));
    await tester.pumpAndSettle();
    expect(find.text('答对了！'), findsNothing);
    expect(find.text('正确答案：bloom'), findsOneWidget);
    await tester.ensureVisible(find.text('查看本轮成绩'));
    await tester.tap(find.text('查看本轮成绩'));
    await tester.pumpAndSettle();
    expect(find.text('本轮错词'), findsOneWidget);
    expect(find.text('仅重练错词'), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      isEmpty,
    );
    await tester.tap(find.text('仅重练错词'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 / 1 题'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写草稿与已答返回会确认，取消保留题号答案和错词', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    final wander = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    );
    await dependencies.repository.createWordbook('返回确认', {
      bloom.single.sense.id,
      wander.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SpellingPracticePage(
                      dependencies: dependencies,
                      wordbookId: book.id,
                    ),
                  ),
                ),
                child: const Text('打开拼写练习'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开拼写练习'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.ensureVisible(find.text('检查答案'));
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一题'));
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'draft');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsOneWidget);
    await tester.tap(find.text('继续练习'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'draft',
    );

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsOneWidget);
    await tester.tap(find.text('继续练习'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'draft',
    );

    await tester.enterText(find.byType(TextField), 'wrong-again');
    await tester.ensureVisible(find.text('检查答案'));
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看本轮成绩'));
    await tester.tap(find.text('查看本轮成绩'));
    await tester.pumpAndSettle();
    expect(find.text('本轮错词'), findsOneWidget);
    expect(find.byKey(const ValueKey('retry-wrong-spelling')), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写未开始和完成态返回不弹确认', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    await dependencies.repository.createWordbook('完成返回', {
      bloom.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    Widget host() => MaterialApp(
      theme: journalTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SpellingPracticePage(
                    dependencies: dependencies,
                    wordbookId: book.id,
                  ),
                ),
              ),
              child: const Text('打开拼写练习'),
            ),
          ),
        ),
      ),
    );

    await tester.pumpWidget(host());
    await tester.tap(find.text('打开拼写练习'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsNothing);
    expect(find.text('打开拼写练习'), findsOneWidget);

    await tester.tap(find.text('打开拼写练习'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bloom');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看本轮成绩'));
    await tester.tap(find.text('查看本轮成绩'));
    await tester.pumpAndSettle();
    expect(find.text('拼写练习完成'), findsOneWidget);
    await tester.ensureVisible(find.text('返回'));
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsNothing);
    expect(find.text('打开拼写练习'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写已答一题后下一题空输入返回仍确认', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    final wander = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    );
    await dependencies.repository.createWordbook('已答返回', {
      bloom.single.sense.id,
      wander.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SpellingPracticePage(
                      dependencies: dependencies,
                      wordbookId: book.id,
                    ),
                  ),
                ),
                child: const Text('打开拼写练习'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开拼写练习'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.ensureVisible(find.text('检查答案'));
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('下一题'));
    await tester.tap(find.text('下一题'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsOneWidget);
    await tester.tap(find.text('继续练习'));
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsOneWidget);
    await tester.tap(find.text('放弃并返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开拼写练习'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写 Enter 先检查，检查后进入下一题且不连跳', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    final wander = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    );
    await dependencies.repository.createWordbook('键盘练习', {
      bloom.single.sense.id,
      wander.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: book.id,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'wrong');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 1 / 2 题'), findsOneWidget);
    expect(find.textContaining('正确答案：'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isFalse);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.textContaining('第 2 / 2 题'), findsOneWidget);
    expect(find.text('拼写练习完成'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写调整范围与题量，取消保留，改配置后重开', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final items = await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 2,
    );
    final calls = <({EntryFilter filter, int limit})>[];
    Future<List<StudyItem>> loader(
      String? wordbookId,
      EntryFilter filter,
      int limit,
    ) async {
      calls.add((filter: filter, limit: limit));
      return items;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: 'everyday',
          spellingLoader: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前词书 · 全部 · 每轮 10 词'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'draft');
    final options = find.byKey(const ValueKey('spelling-options'));
    await tester.ensureVisible(options);
    await tester.tap(options);
    await tester.pumpAndSettle();
    expect(find.text('调整拼写练习'), findsOneWidget);
    expect(find.text('保留当前练习'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spelling-options-apply')));
    await tester.pumpAndSettle();
    expect(calls, hasLength(1));
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'draft',
    );

    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spelling-count-5')));
    await tester.pump();
    expect(find.textContaining('应用新选项会放弃当前题号'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spelling-options-cancel')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'draft',
    );
    expect(find.text('当前词书 · 全部 · 每轮 10 词'), findsOneWidget);

    await tester.ensureVisible(options);
    await tester.tap(options);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spelling-filter-learned')));
    await tester.tap(find.byKey(const ValueKey('spelling-count-5')));
    await tester.tap(find.byKey(const ValueKey('spelling-options-apply')));
    await tester.pumpAndSettle();
    expect(calls.last.filter, EntryFilter.learned);
    expect(calls.last.limit, 5);
    expect(find.text('当前词书 · 已学 · 每轮 5 词'), findsOneWidget);
    expect(find.textContaining('第 1 / 2 题'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写读取失败后可调整范围并显示空结果', (tester) async {
    await surface(tester, width: 320, scale: 1.5);
    var fail = true;
    final calls = <({EntryFilter filter, int limit})>[];
    Future<List<StudyItem>> loader(
      String? wordbookId,
      EntryFilter filter,
      int limit,
    ) async {
      calls.add((filter: filter, limit: limit));
      if (fail) throw StateError('拼写抽词失败');
      return const [];
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: SpellingPracticePage(
          dependencies: dependencies,
          wordbookId: 'everyday',
          spellingLoader: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取拼写题目'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('spelling-options-error')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('spelling-filter-due')));
    await tester.tap(find.byKey(const ValueKey('spelling-count-20')));
    fail = false;
    await tester.tap(find.byKey(const ValueKey('spelling-options-apply')));
    await tester.pumpAndSettle();
    expect(calls.last.filter, EntryFilter.due);
    expect(calls.last.limit, 20);
    expect(find.text('当前范围没有可练习的词'), findsOneWidget);
    expect(find.textContaining('暂时没有到期词义'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('spelling-options-empty')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写继续练习同帧重复回调仍保留当前草稿', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    final wander = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    );
    await dependencies.repository.createWordbook('重复继续练习', {
      bloom.single.sense.id,
      wander.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(spellingPracticeHost(dependencies, book.id));
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开拼写练习'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'draft');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本轮拼写练习？'), findsOneWidget);
    final callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '继续练习'))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.text('打开拼写练习'), findsNothing);
    expect(find.textContaining('第 1 / 2 题'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'draft',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('拼写完成态返回同帧重复回调只退一层', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final bloom = await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    );
    await dependencies.repository.createWordbook('完成态单层返回', {
      bloom.single.sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(spellingPracticeHost(dependencies, book.id));
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开拼写练习'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'bloom');
    await tester.tap(find.text('检查答案'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('查看本轮成绩'));
    await tester.tap(find.text('查看本轮成绩'));
    await tester.pumpAndSettle();
    expect(find.text('拼写练习完成'), findsOneWidget);
    final callback = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '返回'))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.text('打开拼写练习'), findsOneWidget);
    expect(find.text('进入二级'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final layout in [
    (width: 320.0, scale: 1.5, brightness: Brightness.light),
    (width: 390.0, scale: 1.5, brightness: Brightness.dark),
    (width: 1280.0, scale: 1.0, brightness: Brightness.light),
  ]) {
    testWidgets(
      '拼写调整弹框在 ${layout.width} 宽 ${layout.scale} 倍字号 ${layout.brightness.name} 下不溢出',
      (tester) async {
        await surface(tester, width: layout.width, scale: layout.scale);
        final items = await dependencies.repository.entries(
          wordbookId: 'everyday',
          limit: 1,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: journalTheme(layout.brightness),
            home: SpellingPracticePage(
              dependencies: dependencies,
              wordbookId: 'everyday',
              spellingLoader: (_, _, _) async => items,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final options = find.byKey(const ValueKey('spelling-options'));
        await tester.ensureVisible(options);
        await tester.tap(options);
        await tester.pumpAndSettle();
        expect(find.text('调整拼写练习'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('spelling-options-cancel')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('spelling-options-cancel')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('目标为零且额度耗尽时说明仅复习，并显示未来复习时间', (tester) async {
    await surface(tester);
    final target = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 1,
    )).single;
    await dependencies.repository.setDailyGoal(10);
    final card = await dependencies.repository.score(
      target,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await dependencies.repository.setDailyGoal(0);
    await dependencies.repository.setActiveWordbook('everyday');
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies, todayPlan: true)),
    );
    await tester.pumpAndSettle();

    expect(find.text('这一轮，完成了'), findsNothing);
    expect(find.text('今天只安排复习'), findsOneWidget);
    expect(find.textContaining('每日新词目标为 0，当前只安排复习'), findsOneWidget);
    expect(find.textContaining('仍有 23 个未学词义'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    expect(find.text('Good · 记得'), findsNothing);
    expect(card.due.isAfter(now), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('当前词书没有未学词时显示暂无未学词与未来复习', (tester) async {
    await surface(tester);
    final item = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    await dependencies.repository.createWordbook('单书复习', {item.sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setDailyGoal(10);
    await dependencies.repository.score(
      item,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await dependencies.repository.setDailyGoal(0);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyPage(dependencies: dependencies, wordbookId: book.id),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('这一轮，完成了'), findsNothing);
    expect(find.text('今天只安排复习'), findsOneWidget);
    expect(find.textContaining('单书复习暂无未学词义'), findsOneWidget);
    expect(find.textContaining('下次复习'), findsOneWidget);
    expect(find.textContaining('每日新词目标为 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('学习队列加载失败显示错误，不伪装成完成并可重试', (tester) async {
    await surface(tester);
    await dependencies.database.customStatement(
      'ALTER TABLE memory_states RENAME TO memory_states_hold',
    );
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取学习队列'), findsOneWidget);
    expect(find.text('这一轮，完成了'), findsNothing);
    expect(find.textContaining('每日新词目标为 0'), findsNothing);

    await dependencies.database.customStatement(
      'ALTER TABLE memory_states_hold RENAME TO memory_states',
    );
    await tester.ensureVisible(find.text('刷新学习队列'));
    await tester.tap(find.text('刷新学习队列'));
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    expect(find.text('暂时无法读取学习队列'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计曲线通过可搜索列表选择已学词义并显示对应曲线', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    final wander = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    )).first;
    for (final item in [bloom, wander]) {
      await dependencies.repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: StatsPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('curve-sense-picker')), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data,
      contains(bloom.word.spelling),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('curve-sense-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('curve-sense-picker')));
    await tester.pumpAndSettle();
    expect(find.text('选择已学词义'), findsOneWidget);
    final search = find.byKey(const ValueKey('curve-sense-search'));
    await tester.enterText(search, 'zoology');
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的已学词义。'), findsOneWidget);

    final definition = wander.sense.definition;
    await tester.enterText(
      search,
      definition.substring(0, definition.length < 3 ? definition.length : 3),
    );
    await tester.pumpAndSettle();
    final choice = find.byKey(ValueKey('curve-sense-${wander.sense.id}'));
    expect(choice, findsOneWidget);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data,
      contains(wander.word.spelling),
    );
    expect(
      find.byKey(ValueKey('memory-curve-${wander.sense.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计曲线候选分页只显示已学词义，刷新后失效选择会回退', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final all = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 45,
    );
    await dependencies.repository.setDailyGoal(1);
    await dependencies.repository.score(
      all.first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final row = await dependencies.database
        .select(dependencies.database.memoryStates)
        .getSingle();
    for (final item in all.skip(1)) {
      await dependencies.database
          .into(dependencies.database.memoryStates)
          .insert(
            MemoryStatesCompanion.insert(
              userId: row.userId,
              wordSenseId: item.sense.id,
              trainingMode: row.trainingMode,
              state: row.state,
              step: Value(row.step),
              stability: row.stability,
              difficulty: row.difficulty,
              due: now.add(const Duration(days: 30)).millisecondsSinceEpoch,
              lastReview: row.lastReview,
              schedulerVersion: row.schedulerVersion,
              schedulerConfigJson: row.schedulerConfigJson,
            ),
          );
    }
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: StatsPage(
            dependencies: dependencies,
            refreshListenable: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('curve-sense-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('curve-sense-picker')));
    await tester.pumpAndSettle();
    expect(find.text('1–40 / 45'), findsOneWidget);
    await tester.tap(find.text('下一页'));
    await tester.pumpAndSettle();
    expect(find.text('41–45 / 45'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(5));

    final search = find.byKey(const ValueKey('curve-sense-search'));
    await tester.enterText(search, all.last.word.spelling);
    await tester.pumpAndSettle();
    final lastChoice = find.byKey(ValueKey('curve-sense-${all.last.sense.id}'));
    expect(lastChoice, findsOneWidget);
    await tester.tap(lastChoice);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data,
      contains(all.last.word.spelling),
    );

    await (dependencies.database.delete(
      dependencies.database.memoryStates,
    )..where((row) => row.wordSenseId.equals(all.last.sense.id))).go();
    signal.value++;
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data,
      contains(all.first.word.spelling),
    );
    expect(
      find.byKey(ValueKey('memory-curve-${all.last.sense.id}')),
      findsNothing,
    );
    expect(
      find.byKey(ValueKey('memory-curve-${all.first.sense.id}')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计曲线选择在词义内容变化后重新校验，不沿用旧曲线', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    final wander = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    )).first;
    for (final item in [bloom, wander]) {
      await dependencies.repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: StatsPage(
            dependencies: dependencies,
            refreshListenable: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('curve-sense-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('curve-sense-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('curve-sense-search')),
      'wander',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('curve-sense-${wander.sense.id}')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data,
      contains('wander'),
    );

    await (dependencies.database.update(dependencies.database.wordSenses)
          ..where((row) => row.id.equals(wander.sense.id)))
        .write(const WordSensesCompanion(definition: Value('恢复后的新释义')));
    signal.value++;
    await tester.pumpAndSettle();
    final selected = tester
        .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
        .data!;
    expect(selected, contains(bloom.word.spelling));
    expect(selected, isNot(contains('wander')));
    expect(
      find.byKey(ValueKey('memory-curve-${bloom.sense.id}')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('memory-curve-${wander.sense.id}')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计曲线切换时历史未到位前不显示旧曲线', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    final wander = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    )).first;
    for (final item in [bloom, wander]) {
      await dependencies.repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    final gates = <int, Completer<List<ReviewEvent>>>{
      bloom.sense.id: Completer<List<ReviewEvent>>(),
      wander.sense.id: Completer<List<ReviewEvent>>(),
    };
    Future<List<ReviewEvent>> loadHistory(int senseId) =>
        gates[senseId]!.future;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: StatsPage(
            dependencies: dependencies,
            historyLoader: loadHistory,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    gates[bloom.sense.id]!.complete(
      await dependencies.repository.history(senseId: bloom.sense.id),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('memory-curve-${bloom.sense.id}')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('curve-sense-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('curve-sense-picker')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('curve-sense-search')),
      'wander',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('curve-sense-${wander.sense.id}')));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      final selected = tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data;
      if (selected?.contains('wander') ?? false) break;
    }
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('curve-sense-selected')))
          .data,
      contains('wander'),
    );
    expect(
      find.byKey(ValueKey('memory-curve-${bloom.sense.id}')),
      findsNothing,
    );
    expect(find.byType(MemoryCurveChart), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gates[wander.sense.id]!.complete(
      await dependencies.repository.history(senseId: wander.sense.id),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('memory-curve-${wander.sense.id}')),
      findsOneWidget,
    );
    expect(find.byType(MemoryCurveChart), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计曲线候选读取失败会显式提示并可重试', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    await dependencies.repository.score(
      bloom,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: StatsPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('curve-sense-picker')),
    );
    await tester.tap(find.byKey(const ValueKey('curve-sense-picker')));
    await tester.pumpAndSettle();

    await dependencies.database.customStatement(
      'ALTER TABLE word_senses RENAME TO word_senses_hold',
    );
    await tester.enterText(
      find.byKey(const ValueKey('curve-sense-search')),
      'bloom',
    );
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取已学词义'), findsOneWidget);
    await dependencies.database.customStatement(
      'ALTER TABLE word_senses_hold RENAME TO word_senses',
    );
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('curve-sense-${bloom.sense.id}')),
      findsOneWidget,
    );
    expect(find.text('暂时无法读取已学词义'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计页刷新失败时显示错误而不是旧缓存，并可重试', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    await dependencies.repository.score(
      bloom,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: StatsPage(
            dependencies: dependencies,
            refreshListenable: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('memory-curve-${bloom.sense.id}')),
      findsOneWidget,
    );

    await dependencies.database.customStatement(
      'ALTER TABLE word_senses RENAME TO word_senses_hold',
    );
    signal.value++;
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取数据'), findsOneWidget);
    expect(find.byType(MemoryCurveChart), findsNothing);
    await dependencies.database.customStatement(
      'ALTER TABLE word_senses_hold RENAME TO word_senses',
    );
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('memory-curve-${bloom.sense.id}')),
      findsOneWidget,
    );
    expect(find.text('暂时无法读取数据'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词义详情到期自动解锁复习，并显示有界最近记录', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    final start = now;
    final card = await dependencies.repository.score(
      bloom,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
      durationMs: 1500,
    );
    final event = (await dependencies.repository.history(
      senseId: bloom.sense.id,
    )).single;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordDetailPage(dependencies: dependencies, wordId: bloom.word.id),
      ),
    );
    await tester.pumpAndSettle();

    final review = find.widgetWithText(FilledButton, '复习这个词义');
    expect(review, findsOneWidget);
    expect(tester.widget<FilledButton>(review).onPressed, isNull);

    now = card.due;
    await tester.pump(card.due.difference(start) + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(review).onPressed, isNotNull);
    expect(find.text('最近 20 条'), findsWidgets);
    expect(find.textContaining('Good · 记得'), findsOneWidget);
    expect(find.textContaining('耗时 1 秒'), findsOneWidget);
    expect(find.textContaining('下次安排'), findsOneWidget);
    expect(
      find.textContaining(
        localDateTimeWithYearLabel(
          DateTime.fromMillisecondsSinceEpoch(event.reviewedAt, isUtc: true),
        ),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词义详情刷新失败可重试且不显示旧记录', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    await dependencies.repository.score(
      bloom,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordDetailPage(dependencies: dependencies, wordId: bloom.word.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Good · 记得'), findsOneWidget);

    await dependencies.database.customStatement(
      'ALTER TABLE review_events RENAME TO review_events_hold',
    );
    addTearDown(() async {
      try {
        await dependencies.database.customStatement(
          'ALTER TABLE review_events_hold RENAME TO review_events',
        );
      } catch (_) {}
    });
    dependencies.repository.refresh();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取数据'), findsOneWidget);
    expect(find.textContaining('Good · 记得'), findsNothing);

    await dependencies.database.customStatement(
      'ALTER TABLE review_events_hold RENAME TO review_events',
    );
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取数据'), findsNothing);
    expect(find.textContaining('Good · 记得'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词义详情切换 wordId 会立即清空旧内容', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    final wander = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'wander',
    )).single;

    Widget page(int wordId) => MaterialApp(
      theme: journalTheme(Brightness.light),
      home: WordDetailPage(dependencies: dependencies, wordId: wordId),
    );

    await tester.pumpWidget(page(bloom.word.id));
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);

    await tester.pumpWidget(page(wander.word.id));
    expect(find.text('bloom'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('wander'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('词义详情应用回前台会刷新并可重试', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    await dependencies.repository.score(
      bloom,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordDetailPage(dependencies: dependencies, wordId: bloom.word.id),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Good · 记得'), findsOneWidget);

    await dependencies.database.customStatement(
      'ALTER TABLE review_events RENAME TO review_events_hold',
    );
    addTearDown(() async {
      try {
        await dependencies.database.customStatement(
          'ALTER TABLE review_events_hold RENAME TO review_events',
        );
      } catch (_) {}
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取数据'), findsOneWidget);
    expect(find.textContaining('Good · 记得'), findsNothing);

    await dependencies.database.customStatement(
      'ALTER TABLE review_events_hold RENAME TO review_events',
    );
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Good · 记得'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('首页词书保存成功但刷新失败会准确提示并可重试', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: TodayPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    await dependencies.database.customStatement(
      'ALTER TABLE memory_states RENAME TO memory_states_hold',
    );
    addTearDown(() async {
      try {
        await dependencies.database.customStatement(
          'ALTER TABLE memory_states_hold RENAME TO memory_states',
        );
      } catch (_) {}
    });

    final selector = find.byKey(const ValueKey('active-wordbook-selector'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('大学英语四级').last);
    await tester.pumpAndSettle();

    expect((await dependencies.repository.activeWordbook())?.id, 'cet4');
    expect(find.text('词书已切换，但刷新失败'), findsOneWidget);
    expect(find.textContaining('词书已切换，但刷新失败：'), findsOneWidget);
    expect(find.textContaining('未能切换词书'), findsNothing);
    expect(find.text('重试'), findsOneWidget);

    await dependencies.database.customStatement(
      'ALTER TABLE memory_states_hold RENAME TO memory_states',
    );
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取数据'), findsNothing);
    expect(find.textContaining('未能切换词书'), findsNothing);
    expect(tester.widget<DropdownButton<String>>(selector).value, 'cet4');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320 大字号详情最近记录标题与条数分行', (tester) async {
    await surface(tester, width: 320, scale: 1.5);
    final bloom = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordDetailPage(dependencies: dependencies, wordId: bloom.word.id),
      ),
    );
    await tester.pumpAndSettle();
    final title = find.text('最近学习记录').first;
    final badge = find.text('最近 20 条').first;
    expect(
      tester.getTopLeft(badge).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(title).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final localHour in [0, 8, 16]) {
    testWidgets('统计活动在本地 $localHour 时可切换 7/30/90 天查看日期与次数', (tester) async {
      now = DateTime(2026, 11, 27, localHour).toUtc();
      await surface(tester, width: 390, scale: 1.5);
      final calendar = dependencies.repository.calendar;
      Future<void> insertReview(DateTime at, String rating) => dependencies
          .database
          .into(dependencies.database.reviewEvents)
          .insert(
            ReviewEventsCompanion.insert(
              id: newReviewEventId(),
              userId: localUserId,
              wordSenseId: 1,
              trainingMode: recognitionMode,
              reviewedAt: at.millisecondsSinceEpoch,
              rating: rating,
              schedulerVersion: dependencies.engine.schedulerVersion,
              beforeJson: '{}',
              afterJson: '{}',
            ),
          );
      for (final day in [
        (0, 'good'),
        (-1, 'hard'),
        (-20, 'easy'),
        (-65, 'good'),
      ]) {
        await insertReview(
          day.$1 == 0
              ? now
              : calendar
                    .midnightUtc(now, daysAhead: day.$1)
                    .add(const Duration(hours: 12)),
          day.$2,
        );
      }
      // 今天的样本必须已发生；未来记录在所有本地时段都不计入活动。
      await insertReview(now.add(const Duration(hours: 1)), 'easy');
      final signal = ValueNotifier<int>(0);
      addTearDown(signal.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(Brightness.light),
          home: Scaffold(
            body: StatsPage(
              dependencies: dependencies,
              refreshListenable: signal,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final seven = find.byKey(const ValueKey('stats-activity-period-7'));
      final thirty = find.byKey(const ValueKey('stats-activity-period-30'));
      final ninety = find.byKey(const ValueKey('stats-activity-period-90'));
      expect(seven, findsOneWidget);
      expect(thirty, findsOneWidget);
      expect(ninety, findsOneWidget);
      expect(tester.widget<ChoiceChip>(seven).selected, isTrue);
      expect(find.byKey(const ValueKey('stats-activity-bars')), findsOneWidget);
      expect(textAtKey(tester, 'stats-activity-rating-count'), '2');
      expect(textAtKey(tester, 'stats-activity-active-days'), '2');
      expect(textAtKey(tester, 'stats-activity-success-rate'), '50%');

      await tester.ensureVisible(thirty);
      await tester.tap(thirty);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(thirty).selected, isTrue);
      expect(find.byKey(const ValueKey('stats-activity-grid')), findsOneWidget);
      expect(textAtKey(tester, 'stats-activity-rating-count'), '3');
      expect(textAtKey(tester, 'stats-activity-active-days'), '3');
      expect(textAtKey(tester, 'stats-activity-success-rate'), '67%');

      signal.value++;
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(thirty).selected, isTrue);
      expect(find.byKey(const ValueKey('stats-activity-grid')), findsOneWidget);

      final twentyDaysAgo = calendar.local(
        calendar.midnightUtc(now, daysAhead: -20),
      );
      final dayCell = find.byKey(
        ValueKey(
          'activity-day-${twentyDaysAgo.year}-${twentyDaysAgo.month}-${twentyDaysAgo.day}',
        ),
      );
      await tester.ensureVisible(dayCell);
      await tester.tap(dayCell);
      await tester.pumpAndSettle();
      expect(
        find.text(
          '${twentyDaysAgo.year} 年 ${twentyDaysAgo.month} 月 ${twentyDaysAgo.day} 日',
        ),
        findsOneWidget,
      );
      expect(find.text('1 次评分'), findsOneWidget);
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(ninety);
      await tester.tap(ninety);
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(ninety).selected, isTrue);
      expect(textAtKey(tester, 'stats-activity-rating-count'), '4');
      expect(textAtKey(tester, 'stats-activity-active-days'), '4');
      expect(textAtKey(tester, 'stats-activity-success-rate'), '75%');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('统计活动零记录时成功率显示破折号', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(body: StatsPage(dependencies: dependencies)),
      ),
    );
    await tester.pumpAndSettle();
    expect(textAtKey(tester, 'stats-activity-rating-count'), '0');
    expect(textAtKey(tester, 'stats-activity-active-days'), '0');
    expect(textAtKey(tester, 'stats-activity-success-rate'), '—');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计活动快速切换时旧异步结果不覆盖新期间', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final thirty = Completer<ReviewActivity>();
    final ninety = Completer<ReviewActivity>();
    Future<ReviewActivity> load(int days, DateTime asOf) {
      if (days == 7) {
        return Future.value(
          activityFixture(7, ratingCount: 7, goodEasyCount: 7),
        );
      }
      return days == 30 ? thirty.future : ninety.future;
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: StatsPage(dependencies: dependencies, activityLoader: load),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final thirtyChip = find.byKey(const ValueKey('stats-activity-period-30'));
    final ninetyChip = find.byKey(const ValueKey('stats-activity-period-90'));
    expect(thirtyChip, findsOneWidget);
    expect(ninetyChip, findsOneWidget);
    await tester.ensureVisible(thirtyChip);
    await tester.tap(thirtyChip);
    await tester.pump();
    await tester.ensureVisible(ninetyChip);
    await tester.tap(ninetyChip);
    await tester.pump();

    ninety.complete(activityFixture(90, ratingCount: 90, goodEasyCount: 90));
    await tester.pumpAndSettle();
    thirty.complete(activityFixture(30, ratingCount: 30, goodEasyCount: 30));
    await tester.pumpAndSettle();

    expect(tester.widget<ChoiceChip>(ninetyChip).selected, isTrue);
    expect(textAtKey(tester, 'stats-activity-rating-count'), '90');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计活动读取失败清空旧数据，重试保留所选期间', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    var fail = false;
    Future<ReviewActivity> load(int days, DateTime asOf) async {
      if (fail) throw StateError('activity failure');
      return activityFixture(days, ratingCount: days, goodEasyCount: days);
    }

    final signal = ValueNotifier<int>(0);
    addTearDown(signal.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: Scaffold(
          body: StatsPage(
            dependencies: dependencies,
            refreshListenable: signal,
            activityLoader: load,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final thirtyChip = find.byKey(const ValueKey('stats-activity-period-30'));
    expect(thirtyChip, findsOneWidget);
    await tester.ensureVisible(thirtyChip);
    await tester.tap(thirtyChip);
    await tester.pumpAndSettle();
    expect(textAtKey(tester, 'stats-activity-rating-count'), '30');

    fail = true;
    signal.value++;
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取活动回看'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('stats-activity-rating-count')),
      findsNothing,
    );
    expect(tester.widget<ChoiceChip>(thirtyChip).selected, isTrue);

    fail = false;
    await tester.ensureVisible(
      find.byKey(const ValueKey('stats-activity-retry')),
    );
    await tester.tap(find.byKey(const ValueKey('stats-activity-retry')));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取活动回看'), findsNothing);
    expect(tester.widget<ChoiceChip>(thirtyChip).selected, isTrue);
    expect(textAtKey(tester, 'stats-activity-rating-count'), '30');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final layout in [
    (width: 320.0, scale: 1.5, brightness: Brightness.light),
    (width: 390.0, scale: 1.5, brightness: Brightness.dark),
    (width: 1280.0, scale: 1.0, brightness: Brightness.light),
  ]) {
    testWidgets(
      '统计活动 90 天在 ${layout.width} 宽、${layout.scale} 倍字号、${layout.brightness.name} 下可用',
      (tester) async {
        await surface(tester, width: layout.width, scale: layout.scale);
        Future<ReviewActivity> load(int days, DateTime asOf) async =>
            activityFixture(days, ratingCount: 90, goodEasyCount: 90);
        await tester.pumpWidget(
          MaterialApp(
            theme: journalTheme(layout.brightness),
            home: Scaffold(
              body: StatsPage(dependencies: dependencies, activityLoader: load),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final ninety = find.byKey(const ValueKey('stats-activity-period-90'));
        expect(ninety, findsOneWidget);
        await tester.ensureVisible(ninety);
        await tester.tap(ninety);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('stats-activity-grid')),
          findsOneWidget,
        );
        final todayCell = find.byKey(const ValueKey('activity-day-2026-11-27'));
        await tester.ensureVisible(todayCell);
        expect(todayCell, findsOneWidget);
        await tester.tap(todayCell);
        await tester.pumpAndSettle();
        expect(find.text('90 次评分'), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets('新建词书未保存变化退出确认，同帧输入与两层路由安全', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await tester.pumpWidget(editorHost(dependencies));
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开编辑'), findsOneWidget);
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    final name = find.byKey(const ValueKey('wordbook-name'));
    await tester.enterText(name, '临时词书名称');
    // 不先 pump，验证输入事件后的同帧返回也按实时 dirty 判断。
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(name).controller!.text, '临时词书名称');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃并返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开编辑'), findsOneWidget);
    expect(find.text('进入二级'), findsNothing);

    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(name, '临时名称');
    await tester.enterText(name, '');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑词书选词改回基线后返回不弹确认', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final items = await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 2,
    );
    await dependencies.repository.createWordbook('基线词书', {items[0].sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await tester.pumpWidget(editorHost(dependencies, book: book));
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
    await tester.tap(find.text('打开编辑'));
    await tester.pumpAndSettle();

    final candidate = find.widgetWithText(
      CheckboxListTile,
      items[1].word.spelling,
    );
    await tester.ensureVisible(candidate);
    await tester.tap(candidate);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(candidate);
    await tester.tap(candidate);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃未保存的修改？'), findsNothing);
    expect(find.text('打开编辑'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('编辑器批量选择只作用于当前页，并在已选末页取消后回落', (tester) async {
    await surface(tester, width: 320, scale: 1.5);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 45,
    );
    await dependencies.repository.createWordbook(
      '批量词书',
      items.map((item) => item.sense.id).toSet(),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordbookEditorPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();

    final source = find.byKey(const ValueKey('wordbook-source'));
    await tester.ensureVisible(source);
    await tester.tap(source);
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量词书').last);
    await tester.pumpAndSettle();

    final selectPage = find.byKey(const ValueKey('wordbook-select-page'));
    await tester.ensureVisible(selectPage);
    expect(tester.widget<TextButton>(selectPage).onPressed, isNotNull);
    await tester.tap(selectPage);
    await tester.pumpAndSettle();
    expect(find.text('已选 40 个词义'), findsOneWidget);

    final next = find.text('下一页');
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    await tester.ensureVisible(selectPage);
    await tester.tap(selectPage);
    await tester.pumpAndSettle();
    expect(find.text('已选 45 个词义'), findsOneWidget);

    final selectedOnly = find.byKey(const ValueKey('wordbook-selected-only'));
    await tester.ensureVisible(selectedOnly);
    await tester.tap(selectedOnly);
    await tester.pumpAndSettle();
    expect(find.text('1–40 / 45'), findsOneWidget);
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('41–45 / 45'), findsOneWidget);

    final clearPage = find.byKey(const ValueKey('wordbook-clear-page'));
    await tester.ensureVisible(clearPage);
    await tester.tap(clearPage);
    await tester.pumpAndSettle();
    expect(find.text('1–40 / 40'), findsOneWidget);
    expect(find.text('已选 40 个词义'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新建词书失败保留草稿，修复后连点只创建一本', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    await dependencies.database.customStatement(
      "CREATE TRIGGER reject_wordbook BEFORE INSERT ON wordbooks "
      "BEGIN SELECT RAISE(ABORT, 'test create failure'); END",
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordbookEditorPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    final name = find.byKey(const ValueKey('wordbook-name'));
    await tester.enterText(name, '失败重试词书');
    final first = find.byType(CheckboxListTile).first;
    await tester.ensureVisible(first);
    await tester.tap(first);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '创建词书（1 个词义）');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.textContaining('test create failure'), findsOneWidget);
    expect(tester.widget<TextField>(name).controller!.text, '失败重试词书');

    await dependencies.database.customStatement('DROP TRIGGER reject_wordbook');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.tap(save, warnIfMissed: false);
    await tester.pumpAndSettle();
    final books = await dependencies.repository.books();
    expect(
      books.where((book) => book.name == '失败重试词书' && !book.isBuiltIn),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}

Widget editorHost(AppDependencies dependencies, {Wordbook? book}) {
  return MaterialApp(
    theme: journalTheme(Brightness.light),
    home: Builder(
      builder: (homeContext) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(homeContext).push(
              MaterialPageRoute<void>(
                builder: (secondContext) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(secondContext).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WordbookEditorPage(
                            dependencies: dependencies,
                            book: book,
                          ),
                        ),
                      ),
                      child: const Text('打开编辑'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('进入二级'),
          ),
        ),
      ),
    ),
  );
}

Widget spellingPracticeHost(AppDependencies dependencies, String wordbookId) {
  return MaterialApp(
    theme: journalTheme(Brightness.light),
    home: Builder(
      builder: (homeContext) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(homeContext).push(
              MaterialPageRoute<void>(
                builder: (secondContext) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => Navigator.of(secondContext).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SpellingPracticePage(
                            dependencies: dependencies,
                            wordbookId: wordbookId,
                          ),
                        ),
                      ),
                      child: const Text('打开拼写练习'),
                    ),
                  ),
                ),
              ),
            ),
            child: const Text('进入二级'),
          ),
        ),
      ),
    ),
  );
}

String? textAtKey(WidgetTester tester, String key) {
  final finder = find.byKey(ValueKey(key));
  expect(finder, findsOneWidget);
  return tester.widget<Text>(finder).data;
}

ReviewActivity activityFixture(
  int days, {
  int ratingCount = 0,
  int goodEasyCount = 0,
}) {
  final last = DateTime.utc(2026, 11, 27);
  return ReviewActivity(
    days: days,
    dayCounts: List.generate(days, (index) {
      final date = last.subtract(Duration(days: days - 1 - index));
      return ReviewActivityDay(
        localDate: DateTime.utc(date.year, date.month, date.day),
        count: index == days - 1 ? ratingCount : 0,
      );
    }),
    ratingCount: ratingCount,
    goodEasyCount: goodEasyCount,
  );
}
