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
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:lexi_loop/ui/stats_page.dart';
import 'package:lexi_loop/ui/study_page.dart';

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

  Future<void> revealAndRate(
    WidgetTester tester, {
    required String label,
  }) async {
    await finishNewWordBrowse(tester);
    final reveal = find.text('回忆 · 揭晓释义');
    await tester.ensureVisible(reveal);
    await tester.tap(reveal);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('首学撤销回到待揭晓，小结归零，再用新事件重新评分', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    await revealAndRate(tester, label: 'Good · 记得');
    expect(await dependencies.repository.history(), hasLength(1));
    expect(find.text('1 次'), findsOneWidget);
    expect(find.text('1 个词义'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);

    final undo = find.byKey(const ValueKey('undo-last-score'));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    expect(find.text('回忆 · 揭晓释义'), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      isEmpty,
    );
    await tester.tap(find.byTooltip('本轮小结'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-no-ratings')), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    await tester.tap(find.text('继续学习'));
    await tester.pumpAndSettle();

    await revealAndRate(tester, label: 'Good · 记得');
    expect(await dependencies.repository.history(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('撤销复习后从当前范围回到原词并恢复 before 状态', (tester) async {
    await surface(tester);
    final item = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).first;
    await dependencies.repository.createWordbook('单书撤销', {item.sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(10);
    final first = await dependencies.repository.score(
      item,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = first.due;
    final before = await dependencies.repository.itemBySenseId(item.sense.id);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    await revealAndRate(tester, label: 'Easy · 轻松');
    await tester.ensureVisible(find.byKey(const ValueKey('undo-last-score')));
    await tester.tap(find.byKey(const ValueKey('undo-last-score')));
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    expect(find.text('回忆 · 揭晓释义'), findsOneWidget);
    final restored = await dependencies.repository.itemBySenseId(item.sense.id);
    expect(restored!.memory!.due, before!.memory!.due);
    expect(restored.memory!.stability, before.memory!.stability);
    expect(await dependencies.repository.history(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('modifier 不评分，Ctrl+Z 只在无弹层时撤销', (tester) async {
    await surface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(await dependencies.repository.history(), isEmpty);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();
    expect(await dependencies.repository.history(), isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(await dependencies.repository.history(), hasLength(1));
    expect(find.text('wander'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(await dependencies.repository.history(), hasLength(1));

    await tester.tap(find.byTooltip('本轮小结'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(await dependencies.repository.history(), hasLength(1));
    await tester.tap(find.text('继续学习'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(await dependencies.repository.history(), isEmpty);
    expect(find.text('bloom'), findsOneWidget);
    expect(find.text('回忆 · 揭晓释义'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('空队列小结显示 0 次与无虚假成功率', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(0);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('session-no-ratings')), findsOneWidget);
    expect(find.text('100%'), findsNothing);
    expect(find.text('今天只安排复习'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('小结弹窗统计失败可原地重试并刷新自身', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    await revealAndRate(tester, label: 'Good · 记得');
    await dependencies.database.customStatement(
      'ALTER TABLE review_events RENAME TO review_events_hold',
    );
    await tester.tap(find.byTooltip('本轮小结'));
    await tester.pumpAndSettle();
    final dialogError = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining('本轮统计暂时无法读取'),
    );
    expect(dialogError, findsOneWidget);
    await dependencies.database.customStatement(
      'ALTER TABLE review_events_hold RENAME TO review_events',
    );
    final retry = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('重试统计'),
    );
    await tester.ensureVisible(retry);
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(dialogError, findsNothing);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('本轮评分'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(AlertDialog), matching: find.text('1 次')),
      findsOneWidget,
    );
    await tester.tap(find.text('继续学习'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('外部恢复使旧撤销资格失效时显示可读反馈', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    await revealAndRate(tester, label: 'Good · 记得');
    dependencies.repository.invalidateUndoEligibility();
    final undo = find.byKey(const ValueKey('undo-last-score'));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(find.textContaining('不再是当前可撤销记录'), findsOneWidget);
    expect(find.byKey(const ValueKey('undo-last-score')), findsNothing);
    expect(await dependencies.repository.history(), hasLength(1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('统计页在 390 大字号下显示本地未来 7 天复习', (tester) async {
    await surface(tester);
    final item = (await dependencies.repository.queue()).first;
    await dependencies.repository.score(
      item,
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
    expect(find.text('未来 7 天复习'), findsOneWidget);
    expect(find.textContaining('现在待复习'), findsOneWidget);
    expect(find.textContaining('今天 ·'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('刷新保留仍在队列中的当前卡，不用排序把用户正在看的词换掉', (tester) async {
    await surface(tester, width: 1280, scale: 1);
    final items = await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 2,
    );
    await dependencies.repository.createWordbook('双到期卡', {
      items[0].sense.id,
      items[1].sense.id,
    });
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(10);
    for (final item in items) {
      await dependencies.repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    await dependencies.repository.setDailyGoal(0);
    Future<void> setDue(int senseId, DateTime due) =>
        (dependencies.database.update(
          dependencies.database.memoryStates,
        )..where((row) => row.wordSenseId.equals(senseId))).write(
          MemoryStatesCompanion(due: Value(due.millisecondsSinceEpoch)),
        );
    await setDue(items[0].sense.id, now.subtract(const Duration(minutes: 1)));
    await setDue(items[1].sense.id, now.add(const Duration(hours: 1)));

    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    final current = items[0];
    expect(find.text(current.word.spelling), findsOneWidget);
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    expect(find.text(current.sense.definition), findsOneWidget);

    await setDue(items[1].sense.id, now.subtract(const Duration(minutes: 2)));
    dependencies.repository.refresh();
    await tester.pumpAndSettle();
    expect(find.text(current.word.spelling), findsOneWidget);
    expect(find.text(current.sense.definition), findsOneWidget);
    expect(find.textContaining('当前待学 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('刷新替换同一 sense 的内容时重置揭晓状态和计时身份', (tester) async {
    await surface(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    expect(find.text('开花；绽放'), findsOneWidget);

    final sense = (await dependencies.repository.entries(search: 'bloom'))
        .first;
    await (dependencies.database.update(
      dependencies.database.wordSenses,
    )..where((row) => row.id.equals(sense.sense.id))).write(
      const WordSensesCompanion(
        definition: Value('刷新后的新释义'),
        example: Value('刷新后的新例句'),
        phonetics: Value('/new/'),
      ),
    );
    dependencies.repository.refresh();
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    expect(find.text('刷新后的新释义'), findsOneWidget);
    expect(find.text('开花；绽放'), findsNothing);
    expect(find.text('回忆 · 揭晓释义'), findsNothing);
    await finishNewWordBrowse(tester);
    expect(find.text('新词测试 1 / 5'), findsOneWidget);
    expect(find.text('刷新后的新释义'), findsNothing);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    expect(find.text('刷新后的新释义'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('撤销写入成功但原词读取失败时按真实状态反馈', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(
          dependencies: dependencies,
          itemLoader: (_) async => throw StateError('read failure after undo'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await revealAndRate(tester, label: 'Good · 记得');
    await dependencies.repository.setDailyGoal(0);
    await tester.pumpAndSettle();
    final undo = find.byKey(const ValueKey('undo-last-score'));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    await tester.pumpAndSettle();
    expect(find.textContaining('评分已撤销，但读取原词失败'), findsOneWidget);
    expect(find.textContaining('记忆状态未变'), findsNothing);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('旧异步队列加载不会在新评分过程中覆盖当前卡', (tester) async {
    await surface(tester, width: 1280, scale: 1);
    final initialStatus = await dependencies.repository.queueStatus();
    final staleGate = Completer<StudyQueueStatus>();
    final summaryGate = Completer<StudySessionSummary>();
    var loadCalls = 0;
    var summaryCalled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(
          dependencies: dependencies,
          queueStatusLoader: () {
            loadCalls++;
            if (loadCalls == 2) return staleGate.future;
            return dependencies.repository.queueStatus();
          },
          sessionSummaryLoader: (ids) {
            if (ids.isEmpty) {
              return dependencies.repository.sessionSummary(ids);
            }
            summaryCalled = true;
            return summaryGate.future;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(initialStatus.items.first.word.spelling), findsOneWidget);
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();

    dependencies.repository.refresh();
    await tester.pump();
    expect(loadCalls, 2);
    await tester.tap(find.text('Good · 记得'));
    for (var i = 0; i < 20 && !summaryCalled; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(summaryCalled, isTrue);

    staleGate.complete(await dependencies.repository.queueStatus());
    await tester.pump();
    expect(find.text('wander'), findsNothing);
    summaryGate.complete(const StudySessionSummary.empty());
    await tester.pumpAndSettle();
    expect(find.text('wander'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('小结弹窗连点只打开一个，等待期间评分被阻止', (tester) async {
    await surface(tester);
    final summaryGate = Completer<StudySessionSummary>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(
          dependencies: dependencies,
          sessionSummaryLoader: (ids) {
            calls++;
            if (calls <= 2) return summaryGate.future;
            return dependencies.repository.sessionSummary(ids);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('本轮小结'));
    await tester.tap(find.byTooltip('本轮小结'), warnIfMissed: false);
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    final good = find.text('Good · 记得');
    await tester.ensureVisible(good);
    await tester.tap(good);
    await tester.pump();
    expect(await dependencies.repository.history(), isEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(await dependencies.repository.history(), isEmpty);
    summaryGate.complete(const StudySessionSummary.empty());
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('继续学习'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('小结继续和结束重复回调不会多退外层页面', (tester) async {
    await surface(tester);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: journalTheme(Brightness.light),
        home: const Scaffold(body: Text('根页面')),
      ),
    );
    final navigator = navigatorKey.currentState!;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('学习入口')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => StudyPage(dependencies: dependencies),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('本轮小结'));
    await tester.pumpAndSettle();
    final keep = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '继续学习'))
        .onPressed!;
    keep();
    keep();
    await tester.pumpAndSettle();
    expect(find.byType(StudyPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('本轮小结'));
    await tester.pumpAndSettle();
    final finish = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '结束本轮并返回'))
        .onPressed!;
    finish();
    finish();
    await tester.pumpAndSettle();
    expect(find.text('学习入口'), findsOneWidget);
    expect(navigator.canPop(), isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('撤销写入期间离开页面，完成摘要后不更新已销毁页面', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(1);
    final summaryGate = Completer<StudySessionSummary>();
    var gateEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(
          dependencies: dependencies,
          sessionSummaryLoader: (ids) {
            if (gateEnabled) return summaryGate.future;
            return dependencies.repository.sessionSummary(ids);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await revealAndRate(tester, label: 'Good · 记得');
    gateEnabled = true;
    final undo = find.byKey(const ValueKey('undo-last-score'));
    await tester.ensureVisible(undo);
    await tester.tap(undo);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if ((await dependencies.repository.history()).isEmpty) break;
    }
    expect(await dependencies.repository.history(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    summaryGate.complete(const StudySessionSummary.empty());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final layout in [(320.0, 1.5), (1280.0, 1.0)]) {
    testWidgets('学习小结与未来预测在 ${layout.$1} 宽 ${layout.$2} 倍字号下不溢出', (
      tester,
    ) async {
      await surface(tester, width: layout.$1, scale: layout.$2);
      await dependencies.repository.setDailyGoal(1);
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(Brightness.light),
          home: StudyPage(dependencies: dependencies),
        ),
      );
      await tester.pumpAndSettle();
      await revealAndRate(tester, label: 'Good · 记得');
      await tester.tap(find.byTooltip('本轮小结'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('继续学习'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(Brightness.light),
          home: Scaffold(body: StatsPage(dependencies: dependencies)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未来 7 天复习'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('新词先浏览完整一组五词，再进入隐藏释义测试并取下一组', (tester) async {
    await surface(tester);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 6,
    );
    await dependencies.repository.createWordbook(
      '新词组',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(6);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('new-word-browse-progress')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('new-word-browse-next')), findsOneWidget);
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    expect(find.text(items[0].sense.definition), findsOneWidget);
    expect(find.text('回忆 · 揭晓释义'), findsNothing);
    expect(await dependencies.repository.history(), isEmpty);
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      isEmpty,
    );

    final next = find.byKey(const ValueKey('new-word-browse-next'));
    for (var index = 1; index < 5; index++) {
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('新词先看 ${index + 1} / 5'), findsOneWidget);
      expect(find.text(items[index].sense.definition), findsOneWidget);
    }
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('new-word-test-progress')),
      findsOneWidget,
    );
    expect(find.text('新词测试 1 / 5'), findsOneWidget);
    expect(find.text(items[0].sense.definition), findsNothing);
    expect(await dependencies.repository.history(), isEmpty);

    for (var index = 0; index < 5; index++) {
      await revealAndRate(tester, label: 'Good · 记得');
      if (index == 0) {
        expect(find.textContaining('本轮已评 1 次 · 当前待学 5'), findsOneWidget);
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 1'), findsOneWidget);
    expect(find.text(items[5].sense.definition), findsOneWidget);
    expect(await dependencies.repository.history(), hasLength(5));
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      hasLength(5),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('到期回顾优先，完成后才进入新词浏览组', (tester) async {
    await surface(tester);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 6,
    );
    await dependencies.repository.createWordbook(
      '到期后新词',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(6);
    final card = await dependencies.repository.score(
      items[0],
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = card.due;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('回忆 · 揭晓释义'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-word-browse-progress')),
      findsNothing,
    );
    await revealAndRate(tester, label: 'Good · 记得');
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('new-word-browse-progress')),
      findsOneWidget,
    );
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    expect(find.text('回忆 · 揭晓释义'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新词测试首学撤销回到已浏览待测状态', (tester) async {
    await surface(tester);
    final item = (await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 1,
    )).single;
    await dependencies.repository.createWordbook('撤销浏览', {item.sense.id});
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(1);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 1'), findsOneWidget);
    final next = find.byKey(const ValueKey('new-word-browse-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('新词测试 1 / 1'), findsOneWidget);
    await revealAndRate(tester, label: 'Good · 记得');
    await tester.ensureVisible(find.byKey(const ValueKey('undo-last-score')));
    await tester.tap(find.byKey(const ValueKey('undo-last-score')));
    await tester.pumpAndSettle();
    expect(find.text('新词测试 1 / 1'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-word-browse-next')), findsNothing);
    expect(find.text(item.sense.definition), findsNothing);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新词浏览刷新保持阶段，内容变化后旧组失效', (tester) async {
    await surface(tester);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 5,
    );
    await dependencies.repository.createWordbook(
      '刷新浏览',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    final next = find.byKey(const ValueKey('new-word-browse-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('新词先看 2 / 5'), findsOneWidget);
    dependencies.repository.refresh();
    await tester.pumpAndSettle();
    expect(find.text('新词先看 2 / 5'), findsOneWidget);
    expect(find.text(items[1].sense.definition), findsOneWidget);

    await (dependencies.database.update(dependencies.database.wordSenses)
          ..where((row) => row.id.equals(items[1].sense.id)))
        .write(const WordSensesCompanion(definition: Value('刷新后的新释义')));
    dependencies.repository.refresh();
    await tester.pumpAndSettle();
    expect(find.text('刷新后的新释义'), findsOneWidget);
    expect(find.text(items[1].sense.definition), findsNothing);
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

  testWidgets('新词浏览 Space 前进而不写库', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 2,
    );
    await dependencies.repository.createWordbook(
      '快捷键浏览',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(2);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 2'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('新词先看 2 / 2'), findsOneWidget);
    expect(find.text(items[1].sense.definition), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新词浏览按钮同帧连点只前进一个词', (tester) async {
    await surface(tester);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 5,
    );
    await dependencies.repository.createWordbook(
      '连点浏览',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.byKey(const ValueKey('new-word-browse-next')),
    );
    button.onPressed!();
    button.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('新词先看 2 / 5'), findsOneWidget);
    expect(find.text(items[1].sense.definition), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('浏览中外部把每日新词目标改为 0，旧新词组安全失效', (tester) async {
    await surface(tester);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 5,
    );
    await dependencies.repository.createWordbook(
      '目标归零',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    await dependencies.repository.setDailyGoal(0);
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 5'), findsNothing);
    expect(find.text('今天只安排复习'), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('浏览中切换学习词书，旧组失效并按新范围重新取词', (tester) async {
    await surface(tester);
    final ces = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 5,
    );
    await dependencies.repository.createWordbook(
      '切书前',
      ces.map((item) => item.sense.id).toSet(),
    );
    final firstBook = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    final next = (await dependencies.repository.entries(
      wordbookId: 'everyday',
      limit: 1,
    )).single;
    await dependencies.repository.createWordbook('切书后', {next.sense.id});
    final secondBook = (await dependencies.repository.books()).singleWhere(
      (book) => book.name == '切书后',
    );
    await dependencies.repository.setActiveWordbook(firstBook.id);
    await dependencies.repository.setDailyGoal(5);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(dependencies: dependencies, todayPlan: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 5'), findsOneWidget);
    await dependencies.repository.setActiveWordbook(secondBook.id);
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 1'), findsOneWidget);
    expect(find.text(next.sense.definition), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('新词评分写入后离开页面，不更新已销毁页面', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(2);
    final summaryGate = Completer<StudySessionSummary>();
    var gateEnabled = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(
          dependencies: dependencies,
          sessionSummaryLoader: (ids) {
            if (gateEnabled) return summaryGate.future;
            return dependencies.repository.sessionSummary(ids);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    gateEnabled = true;
    await tester.tap(find.text('Good · 记得'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if ((await dependencies.repository.history()).isNotEmpty) break;
    }
    expect(await dependencies.repository.history(), hasLength(1));
    await tester.pumpWidget(const SizedBox());
    summaryGate.complete(const StudySessionSummary.empty());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('新词浏览中途返回提示不记为已学，已评部分保留', (tester) async {
    await surface(tester);
    await dependencies.repository.setDailyGoal(2);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        theme: journalTheme(Brightness.light),
        home: const Scaffold(body: Text('学习入口')),
      ),
    );
    final navigator = navigatorKey.currentState!;
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => StudyPage(dependencies: dependencies),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 2'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('结束本组新词学习？'), findsOneWidget);
    expect(find.textContaining('离开不会记为已学'), findsOneWidget);
    final keep = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '继续学习'))
        .onPressed!;
    keep();
    keep();
    await tester.pumpAndSettle();
    expect(find.text('新词先看 1 / 2'), findsOneWidget);
    expect(await dependencies.repository.history(), isEmpty);

    await finishNewWordBrowse(tester);
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Good · 记得'));
    await tester.pumpAndSettle();
    expect(await dependencies.repository.history(), hasLength(1));

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('结束本组新词学习？'), findsOneWidget);
    expect(find.textContaining('1 个词义已保存'), findsOneWidget);
    final leave = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '退出并保留已评'))
        .onPressed!;
    leave();
    leave();
    await tester.pumpAndSettle();
    expect(find.text('学习入口'), findsOneWidget);
    expect(await dependencies.repository.history(), hasLength(1));
    expect(
      await dependencies.database
          .select(dependencies.database.memoryStates)
          .get(),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('浏览时队列读取失败，重试后恢复当前新词与进度', (tester) async {
    await surface(tester);
    final items = await dependencies.repository.entries(
      wordbookId: 'cet4',
      limit: 5,
    );
    await dependencies.repository.createWordbook(
      '读取重试',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await dependencies.repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await dependencies.repository.setActiveWordbook(book.id);
    await dependencies.repository.setDailyGoal(5);
    var calls = 0;
    var failNext = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: StudyPage(
          dependencies: dependencies,
          todayPlan: true,
          queueStatusLoader: () async {
            calls++;
            if (failNext) {
              failNext = false;
              throw StateError('temporary queue failure');
            }
            return dependencies.repository.queueStatus(todayPlan: true);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    final next = find.byKey(const ValueKey('new-word-browse-next'));
    await tester.ensureVisible(next);
    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(find.text('新词先看 2 / 5'), findsOneWidget);

    failNext = true;
    dependencies.repository.refresh();
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('暂时无法读取学习队列'), findsOneWidget);

    await tester.tap(find.text('刷新学习队列'));
    await tester.pumpAndSettle();
    expect(calls, 3);
    expect(find.text('新词先看 2 / 5'), findsOneWidget);
    expect(find.text(items[1].sense.definition), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
