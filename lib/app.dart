import 'package:material_ui/material_ui.dart';

import 'core/clock.dart';
import 'core/pronunciation.dart';
import 'core/theme_settings.dart';
import 'data/app_database.dart';
import 'data/backup_codec.dart';
import 'data/study_repository.dart';
import 'domain/fsrs_engine.dart';
import 'ui/app_shell.dart';
import 'ui/journal_style.dart';

class AppDependencies {
  factory AppDependencies(
    AppDatabase database, {
    UtcClock nowUtc = systemUtcNow,
  }) {
    final engine = FsrsEngine();
    final repository = StudyRepository(database, engine, nowUtc: nowUtc);
    return AppDependencies._(
      database,
      engine,
      repository,
      BackupCodec(
        database,
        engine,
        nowUtc: nowUtc,
        onRestored: repository.invalidateUndoEligibility,
      ),
      ThemeController(repository),
      PronunciationController(
        loadRate: repository.pronunciationRate,
        saveRate: repository.setPronunciationRate,
      ),
      nowUtc,
    );
  }
  AppDependencies._(
    this.database,
    this.engine,
    this.repository,
    this.backup,
    this.theme,
    this.pronunciation,
    this.nowUtc,
  );
  final AppDatabase database;
  final FsrsEngine engine;
  final StudyRepository repository;
  final BackupCodec backup;
  final ThemeController theme;
  final PronunciationController pronunciation;
  final UtcClock nowUtc;

  Future<void> initialize() async {
    await database.ensureSeeded(
      schedulerVersion: engine.schedulerVersion,
      configurationJson: engine.configurationJson,
    );
    await theme.load();
    await pronunciation.reloadSettings();
  }

  Future<void> reloadTheme() async {
    await pronunciation.stop();
    await theme.load();
    await pronunciation.reloadSettings();
  }

  Future<void> dispose() async {
    await pronunciation.stop();
    pronunciation.dispose();
    theme.dispose();
    await repository.dispose();
    await database.close();
  }
}

class ThemeController extends ChangeNotifier {
  ThemeController(this.repository);

  final StudyRepository repository;
  ThemeSettings _settings = ThemeSettings.defaults;

  ThemeSettings get settings => _settings;

  Future<void> load() async {
    final loaded = await repository.loadThemeSettings();
    if (_settings == loaded) return;
    _settings = loaded;
    notifyListeners();
  }

  Future<void> save(ThemeSettings settings) async {
    await repository.saveThemeSettings(settings);
    if (_settings == settings) return;
    _settings = settings;
    notifyListeners();
  }
}

class LexiLoopApp extends StatelessWidget {
  const LexiLoopApp({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: dependencies.theme,
    builder: (context, _) {
      final settings = dependencies.theme.settings;
      return MaterialApp(
        title: 'Lexi Loop',
        debugShowCheckedModeBanner: false,
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: journalTheme(Brightness.light, themeId: settings.themeId),
        darkTheme: journalTheme(Brightness.dark, themeId: settings.themeId),
        themeMode: switch (settings.mode) {
          AppThemeMode.system => ThemeMode.system,
          AppThemeMode.light => ThemeMode.light,
          AppThemeMode.dark => ThemeMode.dark,
        },
        home: AppShell(dependencies: dependencies),
      );
    },
  );
}
