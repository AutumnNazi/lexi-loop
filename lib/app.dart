import 'package:material_ui/material_ui.dart';

import 'core/clock.dart';
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
    return AppDependencies._(
      database,
      engine,
      StudyRepository(database, engine, nowUtc: nowUtc),
      BackupCodec(database, engine, nowUtc: nowUtc),
      nowUtc,
    );
  }
  AppDependencies._(
    this.database,
    this.engine,
    this.repository,
    this.backup,
    this.nowUtc,
  );
  final AppDatabase database;
  final FsrsEngine engine;
  final StudyRepository repository;
  final BackupCodec backup;
  final UtcClock nowUtc;

  Future<void> initialize() => database.ensureSeeded(
    schedulerVersion: engine.schedulerVersion,
    configurationJson: engine.configurationJson,
  );
  Future<void> dispose() async {
    await repository.dispose();
    await database.close();
  }
}

class LexiLoopApp extends StatelessWidget {
  const LexiLoopApp({super.key, required this.dependencies});
  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lexi Loop',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: journalTheme(Brightness.light),
    darkTheme: journalTheme(Brightness.dark),
    home: AppShell(dependencies: dependencies),
  );
}
