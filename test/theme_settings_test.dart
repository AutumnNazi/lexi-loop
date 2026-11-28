import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/theme_settings.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/ui/journal_style.dart';

void main() {
  test('四套主题的深浅令牌完整且评分语义色彼此可辨', () {
    for (final theme in JournalThemeId.values) {
      for (final brightness in [Brightness.light, Brightness.dark]) {
        final tokens = JournalTokens.forTheme(theme, brightness);
        expect(tokens.canvas, isNot(tokens.surface));
        expect(tokens.surface, isNot(tokens.surfaceElevated));
        expect(tokens.inkPrimary, isNot(tokens.inkSecondary));
        expect(tokens.primary, isNot(tokens.onPrimary));
        expect({
          tokens.again.foreground,
          tokens.hard.foreground,
          tokens.good.foreground,
          tokens.easy.foreground,
        }, hasLength(4));
      }
    }
  });

  test('主题设置写入 app_settings，关闭数据库后重新打开仍保留', () async {
    final directory = await Directory.systemTemp.createTemp('lexi-theme-');
    final file = File('${directory.path}/theme.sqlite');
    final oldWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    AppDependencies? first;
    AppDependencies? second;
    try {
      first = AppDependencies(AppDatabase(NativeDatabase(file)));
      await first.initialize();
      expect(first.theme.settings, ThemeSettings.defaults);
      await first.theme.save(
        const ThemeSettings(
          themeId: JournalThemeId.seaSalt,
          mode: AppThemeMode.dark,
        ),
      );
      await first.dispose();
      first = null;

      second = AppDependencies(AppDatabase(NativeDatabase(file)));
      await second.initialize();
      expect(second.theme.settings.themeId, JournalThemeId.seaSalt);
      expect(second.theme.settings.mode, AppThemeMode.dark);
    } finally {
      await first?.dispose();
      await second?.dispose();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning;
      await directory.delete(recursive: true);
    }
  });

  test('旧备份缺少主题键恢复默认，含主题键的备份恢复后立即应用', () async {
    final dependencies = AppDependencies(AppDatabase(NativeDatabase.memory()));
    addTearDown(dependencies.dispose);
    await dependencies.initialize();
    await dependencies.theme.save(
      const ThemeSettings(
        themeId: JournalThemeId.warmApricot,
        mode: AppThemeMode.dark,
      ),
    );
    final themed =
        jsonDecode(await dependencies.backup.export()) as Map<String, dynamic>;
    expect(
      (themed['appSettings'] as List).map((row) => row['key']),
      containsAll(['theme_id', 'theme_mode']),
    );

    final old = jsonDecode(jsonEncode(themed)) as Map<String, dynamic>;
    old['appSettings'] = (old['appSettings'] as List)
        .where((row) => row['key'] != 'theme_id' && row['key'] != 'theme_mode')
        .toList();
    await dependencies.backup.restore(jsonEncode(old));
    await dependencies.reloadTheme();
    expect(dependencies.theme.settings, ThemeSettings.defaults);

    await dependencies.theme.save(
      const ThemeSettings(
        themeId: JournalThemeId.emerald,
        mode: AppThemeMode.light,
      ),
    );
    await dependencies.backup.restore(jsonEncode(themed));
    await dependencies.reloadTheme();
    expect(
      dependencies.theme.settings,
      const ThemeSettings(
        themeId: JournalThemeId.warmApricot,
        mode: AppThemeMode.dark,
      ),
    );
  });

  testWidgets('设置页四种主题与三种模式全局生效、持久保存且失败不改主题', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final dependencies = AppDependencies(AppDatabase(NativeDatabase.memory()));
    addTearDown(dependencies.dispose);
    await tester.runAsync(dependencies.initialize);
    await dependencies.repository.setActiveWordbook('cet4');
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is JournalIcon && widget.icon == Icons.tune,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('theme-card-emerald')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-card-sea_salt')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('theme-card-warm_apricot')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('theme-card-graphite')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-system')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-light')), findsOneWidget);
    expect(find.byKey(const ValueKey('theme-mode-dark')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-card-sea_salt')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-card-sea_salt')));
    await tester.pumpAndSettle();
    var app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme!.extension<JournalTokens>()!.primary,
      JournalTokens.seaSaltLight.primary,
    );
    expect(
      (await dependencies.repository.loadThemeSettings()).themeId,
      JournalThemeId.seaSalt,
    );
    expect((await dependencies.repository.activeWordbook())?.id, 'cet4');

    await tester.ensureVisible(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.tap(find.byKey(const ValueKey('theme-mode-dark')));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      (await dependencies.repository.loadThemeSettings()).mode,
      AppThemeMode.dark,
    );

    await dependencies.database.customStatement(
      "CREATE TRIGGER reject_theme_update BEFORE UPDATE ON app_settings "
      "WHEN NEW.key IN ('theme_id','theme_mode') "
      "BEGIN SELECT RAISE(ABORT, 'test theme failure'); END",
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-card-graphite')),
    );
    await tester.tap(find.byKey(const ValueKey('theme-card-graphite')));
    await tester.pumpAndSettle();
    expect(find.textContaining('操作未完成'), findsOneWidget);
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(
      app.theme!.extension<JournalTokens>()!.primary,
      JournalTokens.seaSaltLight.primary,
    );
    expect(dependencies.theme.settings.themeId, JournalThemeId.seaSalt);
    await dependencies.database.customStatement(
      'DROP TRIGGER reject_theme_update',
    );

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      app.theme!.extension<JournalTokens>()!.primary,
      JournalTokens.seaSaltLight.primary,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320 宽大字号下主题色卡可换行且不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final dependencies = AppDependencies(AppDatabase(NativeDatabase.memory()));
    addTearDown(dependencies.dispose);
    await tester.runAsync(dependencies.initialize);
    await tester.pumpWidget(LexiLoopApp(dependencies: dependencies));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is JournalIcon && widget.icon == Icons.tune,
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('theme-card-graphite')),
    );
    expect(find.byKey(const ValueKey('theme-card-graphite')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
