import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/services.dart';

import 'seed_catalog.dart';

part 'app_database.g.dart';

typedef _ExamWord = ({String spelling, String definition, String? phonetics});

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
    await ensureExamWordbooks();
    for (final entry in {
      'seed_version': '1',
      'daily_new_goal': '10',
      'theme_id': 'emerald',
      'theme_mode': 'system',
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

  // 包内词表只解析一次；每个数据库仍在自己的事务中导入。
  static Future<Map<String, List<_ExamWord>>>? _examCatalog;

  Future<void> ensureExamWordbooks({
    bool reconcile = false,
  }) => transaction(() async {
    final installed =
        await (select(appSettings)
              ..where((row) => row.key.equals('exam_catalog_version')))
            .getSingleOrNull();
    if (installed?.value == '1' && !reconcile) return;
    final catalog = await (_examCatalog ??= _loadExamCatalog());
    final existingWords = await select(words).get();
    final existingSenses = await select(wordSenses).get();
    final existingBooks = {
      for (final book in await select(wordbooks).get()) book.id: book,
    };
    final wordIds = {for (final word in existingWords) word.spelling: word.id};
    final senseIds = {
      for (final sense in existingSenses)
        (sense.wordId, sense.definition): sense.id,
    };
    var nextWordId = existingWords.fold<int>(
      0,
      (id, word) => word.id > id ? word.id : id,
    );
    var nextSenseId = existingSenses.fold<int>(
      0,
      (id, sense) => sense.id > id ? sense.id : id,
    );
    final newWords = <WordsCompanion>[];
    final newSenses = <WordSensesCompanion>[];
    final newBooks = <WordbooksCompanion>[];
    final entries = <WordbookEntriesCompanion>[];
    for (final book in examWordbooks.entries) {
      final existing = existingBooks[book.key];
      if (existing != null && !existing.isBuiltIn) {
        throw StateError('词书编号 ${book.key} 与自建词书冲突，无法导入考试词库。');
      }
      if (existing == null) {
        newBooks.add(
          WordbooksCompanion.insert(
            id: book.key,
            name: book.value.title,
            isBuiltIn: const Value(true),
          ),
        );
      }
      for (final term in catalog[book.key]!) {
        final wordId = wordIds.putIfAbsent(term.spelling, () {
          final id = ++nextWordId;
          newWords.add(
            WordsCompanion.insert(id: Value(id), spelling: term.spelling),
          );
          return id;
        });
        // 完全相同的词义跨考试词书共享进度，保留已有的原创词义和评分。
        final senseId = senseIds.putIfAbsent((wordId, term.definition), () {
          final id = ++nextSenseId;
          newSenses.add(
            WordSensesCompanion.insert(
              id: Value(id),
              wordId: wordId,
              definition: term.definition,
              example: '',
              phonetics: Value(term.phonetics),
            ),
          );
          return id;
        });
        entries.add(
          WordbookEntriesCompanion.insert(
            wordbookId: book.key,
            wordSenseId: senseId,
          ),
        );
      }
    }
    await batch((batch) {
      batch.insertAll(words, newWords);
      batch.insertAll(wordSenses, newSenses);
      batch.insertAll(wordbooks, newBooks);
      batch.insertAll(
        wordbookEntries,
        entries,
        mode: InsertMode.insertOrIgnore,
      );
      if (installed?.value != '1') {
        batch.insert(
          appSettings,
          AppSettingsCompanion.insert(key: 'exam_catalog_version', value: '1'),
          onConflict: DoUpdate(
            (_) => const AppSettingsCompanion(value: Value('1')),
          ),
        );
      }
    });
  });

  static Future<Map<String, List<_ExamWord>>> _loadExamCatalog() async {
    final catalog = <String, List<_ExamWord>>{};
    for (final book in examWordbooks.entries) {
      final source = await rootBundle.loadString(
        'assets/wordbooks/${book.key}.jsonl',
      );
      final terms = <_ExamWord>[];
      final spellings = <String>{};
      for (final line in LineSplitter.split(source)) {
        final record = jsonDecode(line) as Map<String, dynamic>;
        final spelling = record['word'] as String;
        final definition = (record['meaning'] as String)
            .replaceAll(r'\r', '')
            .trim();
        final phonetics = record['phonetic'] as String?;
        if (spelling.trim().isEmpty ||
            definition.isEmpty ||
            !spellings.add(spelling.toLowerCase())) {
          throw FormatException('${book.value.title} 包含空词条或重复单词。');
        }
        terms.add((
          spelling: spelling,
          definition: definition,
          phonetics: phonetics == null || phonetics.trim().isEmpty
              ? null
              : phonetics,
        ));
      }
      if (terms.length != book.value.count) {
        throw FormatException('${book.value.title} 的词条数量不正确。');
      }
      catalog[book.key] = terms;
    }
    return catalog;
  }
}
