import 'package:drift/drift.dart';

import 'seed_catalog.dart';

part 'app_database.g.dart';

class Words extends Table {
  IntColumn get id => integer()();
  TextColumn get spelling => text().named('text').unique()();
  @override
  Set<Column> get primaryKey => {id};
}

class WordSenses extends Table {
  IntColumn get id => integer()();
  IntColumn get wordId => integer().references(Words, #id)();
  TextColumn get definition => text()();
  TextColumn get example => text()();
  TextColumn get phonetics => text().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class Wordbooks extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  BoolColumn get isBuiltIn => boolean().withDefault(const Constant(false))();
  @override
  Set<Column> get primaryKey => {id};
}

class WordbookEntries extends Table {
  TextColumn get wordbookId => text().references(Wordbooks, #id)();
  IntColumn get wordSenseId => integer().references(WordSenses, #id)();
  @override
  Set<Column> get primaryKey => {wordbookId, wordSenseId};
}

@DataClassName('MemoryStateRow')
class MemoryStates extends Table {
  TextColumn get userId => text()();
  IntColumn get wordSenseId => integer().references(WordSenses, #id)();
  TextColumn get trainingMode => text()();
  IntColumn get state => integer()();
  IntColumn get step => integer().nullable()();
  RealColumn get stability => real()();
  RealColumn get difficulty => real()();
  IntColumn get due => integer()();
  IntColumn get lastReview => integer()();
  TextColumn get schedulerVersion => text()();
  TextColumn get schedulerConfigJson => text()();
  @override
  Set<Column> get primaryKey => {userId, wordSenseId, trainingMode};
}

class ReviewEvents extends Table {
  TextColumn get id => text()();
  TextColumn get userId => text()();
  IntColumn get wordSenseId => integer().references(WordSenses, #id)();
  TextColumn get trainingMode => text()();
  IntColumn get reviewedAt => integer()();
  TextColumn get rating => text()();
  TextColumn get schedulerVersion => text()();
  TextColumn get beforeJson => text()();
  TextColumn get afterJson => text()();
  IntColumn get durationMs => integer().nullable()();
  @override
  Set<Column> get primaryKey => {id};
}

class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(
  tables: [
    Words,
    WordSenses,
    Wordbooks,
    WordbookEntries,
    MemoryStates,
    ReviewEvents,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) => migrator.createAll(),
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> ensureSeeded({
    required String schedulerVersion,
    required String configurationJson,
  }) => transaction(() async {
    // 恢复后的词书也可能含有自己的 ID；完成首次初始化后不重写内容。
    final seeded = await (select(
      appSettings,
    )..where((row) => row.key.equals('seed_version'))).getSingleOrNull();
    if (seeded == null) {
      await into(wordbooks).insert(
        const WordbooksCompanion(
          id: Value('everyday'),
          name: Value('日常微光'),
          isBuiltIn: Value(true),
        ),
      );
      for (var i = 0; i < seedCatalog.length; i++) {
        final word = seedCatalog[i];
        await into(
          words,
        ).insert(WordsCompanion.insert(id: Value(i + 1), spelling: word.text));
        await into(wordSenses).insert(
          WordSensesCompanion.insert(
            id: Value(i + 1),
            wordId: i + 1,
            definition: word.definition,
            example: word.example,
          ),
        );
        await into(wordbookEntries).insert(
          WordbookEntriesCompanion.insert(
            wordbookId: 'everyday',
            wordSenseId: i + 1,
          ),
        );
      }
    }
    for (final entry in {
      'seed_version': '1',
      'daily_new_goal': '10',
      'desired_retention': '0.9',
      'scheduler_version': schedulerVersion,
      'scheduler_config': configurationJson,
    }.entries) {
      await into(appSettings).insert(
        AppSettingsCompanion.insert(key: entry.key, value: entry.value),
        mode: InsertMode.insertOrIgnore,
      );
    }
  });
}
