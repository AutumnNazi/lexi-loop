import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/data/app_database.dart';
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

  Future<void> revealAndRate(
    WidgetTester tester, {
    required String label,
  }) async {
    await tester.tap(find.text('回忆 · 揭晓释义'));
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
}
