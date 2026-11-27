import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/ui/spelling_practice_page.dart';
import 'package:lexi_loop/ui/study_page.dart';
import 'package:lexi_loop/ui/memory_curve_chart.dart';
import 'package:lexi_loop/ui/journal_style.dart';

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

  testWidgets('只有揭晓后才能评分，评分后自动切到下一个新词', (tester) async {
    await surface(tester);
    await tester.pumpWidget(
      MaterialApp(home: StudyPage(dependencies: dependencies)),
    );
    await tester.pumpAndSettle();
    expect(find.text('bloom'), findsOneWidget);
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
    await tester.tap(find.text('回忆 · 揭晓释义'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Again · 忘记'));
    await tester.tap(find.text('Again · 忘记'));
    await tester.pumpAndSettle();
    expect(find.text('这一轮，完成了'), findsOneWidget);
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
    expect(find.text('当前任务已完成'), findsOneWidget);
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
}
