import 'dart:async';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../core/clock.dart';
import '../core/ids.dart';
import '../core/local_calendar.dart';
import '../core/theme_settings.dart';
import '../domain/fsrs_engine.dart';
import 'app_database.dart';
import 'wordbook_exchange.dart';

enum EntryFilter { all, unlearned, learned, due }

class StudyItem {
  const StudyItem(this.word, this.sense, this.memory);
  final Word word;
  final WordSense sense;
  final MemoryStateRow? memory;

  fsrs.Card card(FsrsEngine engine, DateTime nowUtc) {
    final row = memory;
    if (row == null) return engine.newCard(sense.id, nowUtc);
    return fsrs.Card(
      cardId: sense.id,
      state: fsrs.State.fromValue(row.state),
      step: row.step,
      stability: row.stability,
      difficulty: row.difficulty,
      due: DateTime.fromMillisecondsSinceEpoch(row.due, isUtc: true),
      lastReview: DateTime.fromMillisecondsSinceEpoch(
        row.lastReview,
        isUtc: true,
      ),
    );
  }
}

class StudyStats {
  const StudyStats({
    required this.today,
    required this.total,
    required this.successRate,
    required this.recentSuccessRate,
    required this.streak,
    required this.learnedWords,
    required this.totalWords,
    required this.dailyCounts,
  });
  final int today, total, streak, learnedWords, totalWords;
  final double successRate, recentSuccessRate;
  final List<int> dailyCounts;
}

class ReviewActivityDay {
  const ReviewActivityDay({required this.localDate, required this.count});
  final DateTime localDate;
  final int count;
}

class ReviewActivity {
  const ReviewActivity({
    required this.days,
    required this.dayCounts,
    required this.ratingCount,
    required this.goodEasyCount,
  });
  final int days;
  final List<ReviewActivityDay> dayCounts;
  final int ratingCount;
  final int goodEasyCount;

  int get activeDays => dayCounts.where((day) => day.count > 0).length;
  double? get successRate =>
      ratingCount == 0 ? null : goodEasyCount / ratingCount;
}

class StudyQueueStatus {
  const StudyQueueStatus({
    required this.items,
    required this.nextDue,
    required this.unlearnedCount,
    required this.dailyGoal,
    required this.learnedToday,
    required this.quotaExhausted,
    required this.scopeLabel,
  });
  final List<StudyItem> items;
  final DateTime? nextDue;
  final int unlearnedCount;
  final int dailyGoal;
  final int learnedToday;
  final bool quotaExhausted;
  final String scopeLabel;

  bool get hasUnlearned => unlearnedCount > 0;
}

class StudySessionSummary {
  const StudySessionSummary({
    required this.ratingCount,
    required this.firstLearnedSenses,
    required this.reviewCount,
    required this.goodEasyCount,
  });

  const StudySessionSummary.empty()
    : ratingCount = 0,
      firstLearnedSenses = 0,
      reviewCount = 0,
      goodEasyCount = 0;

  final int ratingCount;
  final int firstLearnedSenses;
  final int reviewCount;
  final int goodEasyCount;

  double? get successRate =>
      ratingCount == 0 ? null : goodEasyCount / ratingCount;
}

class ReviewForecastDay {
  const ReviewForecastDay({required this.localDate, required this.count});
  final DateTime localDate;
  final int count;
}

class ReviewForecast {
  const ReviewForecast({required this.dueNow, required this.days});
  final int dueNow;
  final List<ReviewForecastDay> days;

  int get sevenDayTotal => days.fold(0, (sum, day) => sum + day.count);
}

class StudyUndoResult {
  const StudyUndoResult({
    required this.wordSenseId,
    required this.firstLearning,
  });
  final int wordSenseId;
  final bool firstLearning;
}

class UndoUnavailable implements Exception {
  const UndoUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

class StudyRepository {
  StudyRepository(
    this.db,
    this.engine, {
    this.nowUtc = systemUtcNow,
    this.calendar = const LocalCalendar(),
  });
  final AppDatabase db;
  final FsrsEngine engine;
  final UtcClock nowUtc;
  final LocalCalendar calendar;
  final _changes = StreamController<void>.broadcast();
  String? _undoEventId;
  Stream<void> get changes => _changes.stream;
  void refresh() => _changes.add(null);
  Future<void> dispose() => _changes.close();

  void invalidateUndoEligibility() {
    _undoEventId = null;
  }

  Future<List<ReviewEvent>> history({int? senseId, int? limit}) async {
    if (limit != null && limit < 0) {
      throw ArgumentError('历史记录数量不能为负数。');
    }
    final query = db.select(db.reviewEvents)
      ..where(
        (row) =>
            row.userId.equals(localUserId) &
            row.trainingMode.equals(recognitionMode),
      );
    if (senseId != null) query.where((row) => row.wordSenseId.equals(senseId));
    if (limit != null) {
      query
        ..orderBy([
          (row) => OrderingTerm.desc(row.reviewedAt),
          (row) => OrderingTerm.desc(row.id),
        ])
        ..limit(limit);
      final latest = await query.get();
      return latest.reversed.toList();
    }
    query.orderBy([
      (row) => OrderingTerm.asc(row.reviewedAt),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query.get();
  }

  Future<StudyStats> stats({DateTime? asOf}) async {
    final now = asOf ?? nowUtc();
    return db.transaction(() async {
      // 累计数保留全部记录；近期与连击以 asOf 为上限，避免未来异常记录污染。
      final totals = await _ratingTotals();
      final activity = await _reviewActivityData(days: 7, now: now);
      final streak = await _streakAt(now);
      final wordCounts = await wordProgress();
      final counts = activity.dayCounts.map((day) => day.count).toList();
      return StudyStats(
        today: counts.last,
        total: totals.ratings,
        successRate: totals.ratings == 0 ? 0 : totals.goodEasy / totals.ratings,
        recentSuccessRate: activity.ratingCount == 0
            ? 0
            : activity.goodEasyCount / activity.ratingCount,
        streak: streak,
        learnedWords: wordCounts.learned,
        totalWords: wordCounts.total,
        dailyCounts: counts,
      );
    });
  }

  Future<ReviewActivity> reviewActivity({
    required int days,
    DateTime? asOf,
  }) async {
    if (days < 1 || days > 90) {
      throw ArgumentError('活动回看只支持 1 到 90 个本地日。');
    }
    final now = asOf ?? nowUtc();
    return db.transaction(() => _reviewActivityData(days: days, now: now));
  }

  Future<ReviewActivity> _reviewActivityData({
    required int days,
    required DateTime now,
  }) async {
    final start = calendar.midnightUtc(now, daysAhead: -(days - 1));
    final startMs = start.millisecondsSinceEpoch;
    // 累计数保留未来异常记录；近期活动窗口只统计到当前时刻。
    final endMs = utcMilliseconds(now).millisecondsSinceEpoch + 1;
    final totals = await _ratingTotals(startMs: startMs, endMs: endMs);
    final timestamps = await _reviewTimestamps(startMs: startMs, endMs: endMs);
    final startDay = calendar.dayKey(start);
    final counts = List<int>.filled(days, 0);
    for (final timestamp in timestamps) {
      final offset =
          calendar.dayKey(
            DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true),
          ) -
          startDay;
      if (offset >= 0 && offset < days) counts[offset]++;
    }
    return ReviewActivity(
      days: days,
      dayCounts: List.generate(days, (index) {
        final local = calendar.local(
          calendar.midnightUtc(now, daysAhead: -(days - 1) + index),
        );
        return ReviewActivityDay(
          localDate: DateTime.utc(local.year, local.month, local.day),
          count: counts[index],
        );
      }),
      ratingCount: totals.ratings,
      goodEasyCount: totals.goodEasy,
    );
  }

  Future<({int ratings, int goodEasy})> _ratingTotals({
    int? startMs,
    int? endMs,
  }) async {
    final conditions = <String>['user_id = ?', 'training_mode = ?'];
    final variables = <Variable<Object>>[
      Variable(localUserId),
      Variable(recognitionMode),
    ];
    if (startMs != null) {
      conditions.add('reviewed_at >= ?');
      variables.add(Variable(startMs));
    }
    if (endMs != null) {
      conditions.add('reviewed_at < ?');
      variables.add(Variable(endMs));
    }
    final row = await db.customSelect('''
      SELECT COUNT(*) AS ratings,
             COALESCE(SUM(CASE WHEN rating IN ('good', 'easy')
                               THEN 1 ELSE 0 END), 0) AS good_easy
      FROM review_events
      WHERE ${conditions.join(' AND ')}
    ''', variables: variables).getSingle();
    return (
      ratings: row.read<int>('ratings'),
      goodEasy: row.read<int>('good_easy'),
    );
  }

  Future<List<int>> _reviewTimestamps({
    required int startMs,
    required int endMs,
  }) async {
    final rows = await db
        .customSelect(
          '''
      SELECT reviewed_at
      FROM review_events
      WHERE user_id = ? AND training_mode = ?
        AND reviewed_at >= ? AND reviewed_at < ?
    ''',
          variables: [
            Variable(localUserId),
            Variable(recognitionMode),
            Variable(startMs),
            Variable(endMs),
          ],
        )
        .get();
    return rows.map((row) => row.read<int>('reviewed_at')).toList();
  }

  Future<int> _streakAt(DateTime now) async {
    final today = calendar.dayKey(now);
    final nowMs = utcMilliseconds(now).millisecondsSinceEpoch;
    // 没有 reviewed_at 索引时，单次精简时间戳扫描比小批量反复排序整表更稳。
    final rows = await db
        .customSelect(
          '''
      SELECT reviewed_at
      FROM review_events
      WHERE user_id = ? AND training_mode = ? AND reviewed_at <= ?
      ORDER BY reviewed_at DESC
    ''',
          variables: [
            Variable(localUserId),
            Variable(recognitionMode),
            Variable(nowMs),
          ],
        )
        .get();
    var expected = today;
    var count = 0;
    var started = false;
    for (final row in rows) {
      final day = calendar.dayKey(
        DateTime.fromMillisecondsSinceEpoch(
          row.read<int>('reviewed_at'),
          isUtc: true,
        ),
      );
      if (day > today) continue;
      if (!started) {
        if (day < today - 1) break;
        started = true;
        expected = day;
      }
      if (day == expected) {
        count++;
        expected--;
      } else if (day < expected) {
        break;
      }
    }
    return count;
  }

  Future<DateTime?> nextDue() async {
    final now = nowUtc().millisecondsSinceEpoch;
    return _nextDueAfter(now);
  }

  Future<DateTime?> _nextDueAfter(
    int now, {
    String? wordbookId,
    int? senseId,
  }) async {
    final row = await db
        .customSelect(
          '''
      SELECT MIN(m.due) AS next_due
      FROM memory_states m
      WHERE m.user_id = ? AND m.training_mode = ? AND m.due > ?
      ${senseId == null ? '' : 'AND m.word_sense_id = ?'}
      ${wordbookId == null ? '' : 'AND EXISTS (SELECT 1 FROM wordbook_entries e WHERE e.word_sense_id = m.word_sense_id AND e.wordbook_id = ?)'}
    ''',
          variables: [
            Variable(localUserId),
            Variable(recognitionMode),
            Variable(now),
            if (senseId != null) Variable(senseId),
            if (wordbookId != null) Variable(wordbookId),
          ],
        )
        .getSingle();
    final value = row.readNullable<int>('next_due');
    return value == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }

  Future<List<Wordbook>> books() => db.select(db.wordbooks).get();

  Future<({int learned, int total})> wordProgress({String? wordbookId}) async {
    // 按当前词书收录的词义统计，避免同拼写的其他词义被当作本书已学。
    final counts = await db
        .customSelect(
          '''
      SELECT COUNT(DISTINCT s.word_id) AS total,
             COUNT(DISTINCT CASE WHEN m.word_sense_id IS NOT NULL
                                THEN s.word_id END) AS learned
      FROM word_senses s
      LEFT JOIN memory_states m ON m.word_sense_id = s.id
        AND m.user_id = ? AND m.training_mode = ?
      ${wordbookId == null ? '' : 'WHERE EXISTS (SELECT 1 FROM wordbook_entries e WHERE e.word_sense_id = s.id AND e.wordbook_id = ?)'}
    ''',
          variables: [
            Variable(localUserId),
            Variable(recognitionMode),
            if (wordbookId != null) Variable(wordbookId),
          ],
        )
        .getSingle();
    return (
      learned: counts.read<int>('learned'),
      total: counts.read<int>('total'),
    );
  }

  Future<Wordbook?> activeWordbook() async {
    final setting = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('active_wordbook_id'))).getSingleOrNull();
    if (setting == null) return null;
    final book = await (db.select(
      db.wordbooks,
    )..where((row) => row.id.equals(setting.value))).getSingleOrNull();
    if (book == null) throw StateError('学习词书已不存在，请重新选择。');
    return book;
  }

  Future<void> setActiveWordbook(String? wordbookId) async {
    await db.transaction(() async {
      if (wordbookId == null) {
        await (db.delete(
          db.appSettings,
        )..where((row) => row.key.equals('active_wordbook_id'))).go();
        return;
      }
      final book = await (db.select(
        db.wordbooks,
      )..where((row) => row.id.equals(wordbookId))).getSingleOrNull();
      if (book == null) throw ArgumentError('所选词书不存在，请刷新后重试。');
      await db
          .into(db.appSettings)
          .insertOnConflictUpdate(
            AppSettingsCompanion.insert(
              key: 'active_wordbook_id',
              value: wordbookId,
            ),
          );
    });
    refresh();
  }

  Future<void> createWordbook(String name, Set<int> senseIds) async {
    final cleanName = _cleanWordbookName(name);
    _ensureWordbookSenses(senseIds);
    await db.transaction(() async {
      await _ensureWordbookSensesExist(senseIds);
      final id = newReviewEventId();
      await db
          .into(db.wordbooks)
          .insert(WordbooksCompanion.insert(id: id, name: cleanName));
      for (final senseId in senseIds) {
        await db
            .into(db.wordbookEntries)
            .insert(
              WordbookEntriesCompanion.insert(
                wordbookId: id,
                wordSenseId: senseId,
              ),
            );
      }
    });
    refresh();
  }

  Future<WordbookImportResult> importWordbook({
    required String name,
    required List<WordbookEntryDraft> entries,
  }) async {
    final cleanName = _cleanWordbookName(name);
    if (entries.isEmpty) throw ArgumentError('请至少导入一个词条。');
    if (entries.length > WordbookFormatLimits.maxEntries) {
      throw ArgumentError('单个词书最多导入 ${WordbookFormatLimits.maxEntries} 个词条。');
    }
    final unique = <WordbookEntryDraft>[];
    final seen = <String>{};
    for (final raw in entries) {
      final word = raw.word.trim();
      final definition = raw.definition.trim();
      if (word.isEmpty || definition.isEmpty) {
        throw ArgumentError('词条单词和释义不能为空。');
      }
      if (hasInvalidControlCharacters(word) ||
          hasInvalidControlCharacters(definition) ||
          hasInvalidControlCharacters(raw.phonetic ?? '') ||
          hasInvalidControlCharacters(raw.example ?? '')) {
        throw ArgumentError('词条包含不支持的控制字符。');
      }
      if (word.runes.length > WordbookFormatLimits.maxWordRunes ||
          definition.runes.length > WordbookFormatLimits.maxDefinitionRunes ||
          (raw.phonetic?.runes.length ?? 0) >
              WordbookFormatLimits.maxPhoneticRunes ||
          (raw.example?.runes.length ?? 0) >
              WordbookFormatLimits.maxExampleRunes) {
        throw ArgumentError('词条字段超过长度限制。');
      }
      final entry = raw.copyWith(word: word, definition: definition);
      if (seen.add(entry.key)) unique.add(entry);
    }
    if (unique.isEmpty) throw ArgumentError('请至少导入一个词条。');

    late WordbookImportResult result;
    await db.transaction(() async {
      final existingWords = await db.select(db.words).get();
      final existingSenses = await db.select(db.wordSenses).get();
      final wordIds = {
        for (final word in existingWords) word.spelling: word.id,
      };
      final senseIds = {
        for (final sense in existingSenses)
          _senseKey(sense.wordId, sense.definition): sense.id,
      };
      var nextWordId = existingWords.fold<int>(
        0,
        (max, word) => word.id > max ? word.id : max,
      );
      var nextSenseId = existingSenses.fold<int>(
        0,
        (max, sense) => sense.id > max ? sense.id : max,
      );
      final newWords = <WordsCompanion>[];
      final newSenses = <WordSensesCompanion>[];
      final linkedSenseIds = <int>{};
      var newSenseCount = 0;
      for (final entry in unique) {
        final wordId = wordIds.putIfAbsent(entry.word, () {
          final id = ++nextWordId;
          newWords.add(
            WordsCompanion.insert(id: Value(id), spelling: entry.word),
          );
          return id;
        });
        final key = _senseKey(wordId, entry.definition);
        final senseId = senseIds.putIfAbsent(key, () {
          final id = ++nextSenseId;
          newSenseCount++;
          newSenses.add(
            WordSensesCompanion.insert(
              id: Value(id),
              wordId: wordId,
              definition: entry.definition,
              example: entry.example ?? '',
              phonetics: Value(entry.phonetic),
            ),
          );
          return id;
        });
        if (!linkedSenseIds.add(senseId)) continue;
      }
      final bookId = newReviewEventId();
      await db.batch((batch) {
        batch.insert(
          db.wordbooks,
          WordbooksCompanion.insert(
            id: bookId,
            name: cleanName,
            isBuiltIn: const Value(false),
          ),
        );
        batch.insertAll(db.words, newWords);
        batch.insertAll(db.wordSenses, newSenses);
        batch.insertAll(
          db.wordbookEntries,
          linkedSenseIds
              .map(
                (senseId) => WordbookEntriesCompanion.insert(
                  wordbookId: bookId,
                  wordSenseId: senseId,
                ),
              )
              .toList(),
        );
      });
      // 词形与释义完全相同的已有词义共享进度，只新增本次词书的关联。
      final newSenseIds = newSenses.map((sense) => sense.id.value).toSet();
      final reusedSenseCount = linkedSenseIds.length - newSenseIds.length;
      result = WordbookImportResult(
        bookId: bookId,
        bookName: cleanName,
        importedEntries: linkedSenseIds.length,
        newWords: newWords.length,
        newSenses: newSenseCount,
        reusedSenses: reusedSenseCount,
      );
    });
    refresh();
    return result;
  }

  Future<List<WordbookEntryDraft>> exportWordbookEntries(
    String wordbookId,
  ) async {
    final query = db.select(db.wordSenses).join([
      innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      innerJoin(
        db.wordbookEntries,
        db.wordbookEntries.wordSenseId.equalsExp(db.wordSenses.id) &
            db.wordbookEntries.wordbookId.equals(wordbookId),
      ),
    ])..orderBy([OrderingTerm.asc(db.wordSenses.id)]);
    return (await query.get())
        .map(
          (row) => WordbookEntryDraft(
            word: row.readTable(db.words).spelling,
            definition: row.readTable(db.wordSenses).definition,
            phonetic: row.readTable(db.wordSenses).phonetics,
            example: row.readTable(db.wordSenses).example,
          ),
        )
        .toList();
  }

  Future<WordListResolution> resolveWordOnlyEntries(
    List<WordOnlyEntry> words,
  ) async {
    final entries = <WordbookEntryDraft>[];
    final issues = <WordbookParseIssue>[];
    final seen = <String>{};
    var duplicates = 0;
    var errorRows = 0;
    for (var start = 0; start < words.length; start += 400) {
      final chunk = words.skip(start).take(400).toList();
      final spellings = chunk.map((word) => word.word).toList();
      final foundWords = await (db.select(
        db.words,
      )..where((row) => row.spelling.isIn(spellings))).get();
      final bySpelling = {for (final word in foundWords) word.spelling: word};
      final wordIds = foundWords.map((word) => word.id).toList();
      final senses = wordIds.isEmpty
          ? <WordSense>[]
          : await (db.select(db.wordSenses)
                  ..where((row) => row.wordId.isIn(wordIds))
                  ..orderBy([(row) => OrderingTerm.asc(row.id)]))
                .get();
      final byWord = <int, List<WordSense>>{};
      for (final sense in senses) {
        byWord.putIfAbsent(sense.wordId, () => []).add(sense);
      }
      for (final source in chunk) {
        final word = bySpelling[source.word];
        final wordSenses = word == null ? null : byWord[word.id];
        if (word == null || wordSenses == null || wordSenses.isEmpty) {
          errorRows++;
          if (issues.length < WordbookFormatLimits.maxIssues) {
            issues.add(
              WordbookParseIssue(
                line: source.line,
                message: '本地词库没有“${source.word}”的释义，请补充释义后重新导入。',
                sample: source.word,
              ),
            );
          }
          continue;
        }
        for (final sense in wordSenses) {
          final entry = WordbookEntryDraft(
            word: word.spelling,
            definition: sense.definition,
            phonetic: sense.phonetics,
            example: sense.example,
            line: source.line,
          );
          if (!seen.add(entry.key)) {
            duplicates++;
            continue;
          }
          entries.add(entry);
        }
      }
    }
    return WordListResolution(
      entries: entries,
      issues: issues,
      duplicateRows: duplicates,
      errorRows: errorRows,
    );
  }

  static String _senseKey(int wordId, String definition) =>
      '$wordId\u0000$definition';

  Future<fsrs.Card> score(
    StudyItem item,
    fsrs.Rating rating, {
    required String eventId,
    int? durationMs,
  }) async {
    var createdEvent = false;
    final result = await db.transaction(() async {
      final prior = await (db.select(
        db.reviewEvents,
      )..where((row) => row.id.equals(eventId))).getSingleOrNull();
      if (prior != null) {
        if (prior.wordSenseId != item.sense.id || prior.rating != rating.name) {
          throw ArgumentError('评分事件编号已经用于另一条评分。');
        }
        return engine.decodeCard(prior.afterJson, allowNew: false);
      }
      if (!RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ).hasMatch(eventId) ||
          (durationMs != null && durationMs < 0)) {
        throw ArgumentError('评分事件编号或作答耗时不合法。');
      }
      final now = utcMilliseconds(nowUtc());
      final current =
          await (db.select(db.memoryStates)..where(
                (row) =>
                    row.userId.equals(localUserId) &
                    row.wordSenseId.equals(item.sense.id) &
                    row.trainingMode.equals(recognitionMode),
              ))
              .getSingleOrNull();
      if (current != item.memory ||
          (current != null && current.due > now.millisecondsSinceEpoch)) {
        throw StateError('这张卡片的进度已变化或尚未到期，请刷新后继续。');
      }
      if (current == null && await newLearnedToday() >= await dailyGoal()) {
        throw StateError('今日新词目标已完成，可以在设置中调整目标。');
      }
      final before = item.card(engine, now);
      final after = engine.review(before, rating, now);
      await db
          .into(db.memoryStates)
          .insertOnConflictUpdate(
            MemoryStatesCompanion.insert(
              userId: localUserId,
              wordSenseId: item.sense.id,
              trainingMode: recognitionMode,
              state: after.state.value,
              step: Value(after.step),
              stability: after.stability!,
              difficulty: after.difficulty!,
              due: after.due.millisecondsSinceEpoch,
              lastReview: after.lastReview!.millisecondsSinceEpoch,
              schedulerVersion: engine.schedulerVersion,
              schedulerConfigJson: engine.configurationJson,
            ),
          );
      await db
          .into(db.reviewEvents)
          .insert(
            ReviewEventsCompanion.insert(
              id: eventId,
              userId: localUserId,
              wordSenseId: item.sense.id,
              trainingMode: recognitionMode,
              reviewedAt: now.millisecondsSinceEpoch,
              rating: rating.name,
              schedulerVersion: engine.schedulerVersion,
              beforeJson: engine.encodeCard(before),
              afterJson: engine.encodeCard(after),
              durationMs: Value(durationMs),
            ),
          );
      createdEvent = true;
      return after;
    });
    if (createdEvent) _undoEventId = eventId;
    refresh();
    return result;
  }

  Future<StudyUndoResult> undoLastReview(String eventId) async {
    late StudyUndoResult result;
    await db.transaction(() async {
      if (_undoEventId != eventId) {
        throw const UndoUnavailable('这次评分已不再是当前可撤销记录。');
      }
      final event =
          await (db.select(db.reviewEvents)..where(
                (row) =>
                    row.id.equals(eventId) &
                    row.userId.equals(localUserId) &
                    row.trainingMode.equals(recognitionMode),
              ))
              .getSingleOrNull();
      if (event == null) {
        throw const UndoUnavailable('这次评分已经不存在，可能已被恢复或其他页面更新。');
      }
      // 事件 ID 是 UUIDv7，但同一毫秒内仍不能用字符串顺序代表提交顺序；
      // SQLite rowid 才是插入提交顺序。
      final latest = await db
          .customSelect(
            '''
        SELECT id FROM review_events
        WHERE user_id = ? AND training_mode = ?
        ORDER BY rowid DESC LIMIT 1
      ''',
            variables: [Variable(localUserId), Variable(recognitionMode)],
          )
          .getSingleOrNull();
      if (latest == null || latest.read<String>('id') != eventId) {
        throw const UndoUnavailable('已有更新的评分记录，本次撤销已失效。');
      }
      final current =
          await (db.select(db.memoryStates)..where(
                (row) =>
                    row.userId.equals(localUserId) &
                    row.wordSenseId.equals(event.wordSenseId) &
                    row.trainingMode.equals(recognitionMode),
              ))
              .getSingleOrNull();
      if (current == null ||
          engine.encodeCard(_cardFromRow(current)) != event.afterJson) {
        throw const UndoUnavailable('当前记忆状态已变化，不能撤销这次评分。');
      }
      final before = engine.decodeCard(event.beforeJson);
      final after = engine.decodeCard(event.afterJson, allowNew: false);
      if (before.cardId != event.wordSenseId ||
          after.cardId != event.wordSenseId) {
        throw const UndoUnavailable('评分快照与词义不一致，不能撤销。');
      }
      if (before.lastReview == null) {
        await (db.delete(db.memoryStates)..where(
              (row) =>
                  row.userId.equals(localUserId) &
                  row.wordSenseId.equals(event.wordSenseId) &
                  row.trainingMode.equals(recognitionMode),
            ))
            .go();
      } else {
        await (db.update(db.memoryStates)..where(
              (row) =>
                  row.userId.equals(localUserId) &
                  row.wordSenseId.equals(event.wordSenseId) &
                  row.trainingMode.equals(recognitionMode),
            ))
            .write(
              MemoryStatesCompanion(
                state: Value(before.state.value),
                step: Value(before.step),
                stability: Value(before.stability!),
                difficulty: Value(before.difficulty!),
                due: Value(before.due.millisecondsSinceEpoch),
                lastReview: Value(before.lastReview!.millisecondsSinceEpoch),
                schedulerVersion: Value(engine.schedulerVersion),
                schedulerConfigJson: Value(engine.configurationJson),
              ),
            );
      }
      await (db.delete(
        db.reviewEvents,
      )..where((row) => row.id.equals(eventId))).go();
      result = StudyUndoResult(
        wordSenseId: event.wordSenseId,
        firstLearning: before.lastReview == null,
      );
    });
    if (_undoEventId == eventId) _undoEventId = null;
    refresh();
    return result;
  }

  fsrs.Card _cardFromRow(MemoryStateRow row) => fsrs.Card(
    cardId: row.wordSenseId,
    state: fsrs.State.fromValue(row.state),
    step: row.step,
    stability: row.stability,
    difficulty: row.difficulty,
    due: DateTime.fromMillisecondsSinceEpoch(row.due, isUtc: true),
    lastReview: DateTime.fromMillisecondsSinceEpoch(
      row.lastReview,
      isUtc: true,
    ),
  );

  Future<StudySessionSummary> sessionSummary(Iterable<String> eventIds) async {
    final ids = eventIds.toSet();
    if (ids.isEmpty) return const StudySessionSummary.empty();
    var ratings = 0;
    var reviews = 0;
    var goodEasy = 0;
    final firstLearned = <int>{};
    final list = ids.toList();
    for (var start = 0; start < list.length; start += 400) {
      final chunk = list.skip(start).take(400).toList();
      final events =
          await (db.select(db.reviewEvents)..where(
                (row) =>
                    row.id.isIn(chunk) &
                    row.userId.equals(localUserId) &
                    row.trainingMode.equals(recognitionMode),
              ))
              .get();
      for (final event in events) {
        ratings++;
        if (event.rating == 'good' || event.rating == 'easy') goodEasy++;
        final before = engine.decodeCard(event.beforeJson);
        if (before.lastReview == null) {
          firstLearned.add(event.wordSenseId);
        } else {
          reviews++;
        }
      }
    }
    return StudySessionSummary(
      ratingCount: ratings,
      firstLearnedSenses: firstLearned.length,
      reviewCount: reviews,
      goodEasyCount: goodEasy,
    );
  }

  Future<ReviewForecast> reviewForecast({DateTime? asOf}) async {
    final now = asOf ?? nowUtc();
    final nowMs = now.millisecondsSinceEpoch;
    final midnight = calendar.nextMidnightUtc(now);
    final day0End = midnight.millisecondsSinceEpoch;
    final starts = <int>[];
    final ends = <int>[];
    for (var day = 1; day < 7; day++) {
      starts.add(
        calendar.midnightUtc(now, daysAhead: day).millisecondsSinceEpoch,
      );
      ends.add(
        calendar.midnightUtc(now, daysAhead: day + 1).millisecondsSinceEpoch,
      );
    }
    final columns = <String>[
      'COALESCE(SUM(CASE WHEN due <= ? THEN 1 ELSE 0 END), 0) AS due_now',
      'COALESCE(SUM(CASE WHEN due > ? AND due < ? THEN 1 ELSE 0 END), 0) AS day0',
      for (var index = 0; index < starts.length; index++)
        'COALESCE(SUM(CASE WHEN due >= ? AND due < ? THEN 1 ELSE 0 END), 0) AS day${index + 1}',
    ];
    final variables = <Variable<Object>>[
      Variable(nowMs),
      Variable(nowMs),
      Variable(day0End),
      for (var index = 0; index < starts.length; index++) ...[
        Variable(starts[index]),
        Variable(ends[index]),
      ],
      Variable(localUserId),
      Variable(recognitionMode),
    ];
    final row = await db.customSelect('''
      SELECT ${columns.join(', ')}
      FROM memory_states
      WHERE user_id = ? AND training_mode = ?
    ''', variables: variables).getSingle();
    final days = <ReviewForecastDay>[
      ReviewForecastDay(
        localDate: calendar.local(calendar.midnightUtc(now)),
        count: row.read<int>('day0'),
      ),
      for (var index = 0; index < starts.length; index++)
        ReviewForecastDay(
          localDate: calendar.local(
            calendar.midnightUtc(now, daysAhead: index + 1),
          ),
          count: row.read<int>('day${index + 1}'),
        ),
    ];
    return ReviewForecast(dueNow: row.read<int>('due_now'), days: days);
  }

  Future<StudyItem?> itemBySenseId(int senseId) async {
    final row = await (db.select(db.wordSenses).join([
      innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      leftOuterJoin(
        db.memoryStates,
        db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
            db.memoryStates.userId.equals(localUserId) &
            db.memoryStates.trainingMode.equals(recognitionMode),
      ),
    ])..where(db.wordSenses.id.equals(senseId))).getSingleOrNull();
    if (row == null) return null;
    return StudyItem(
      row.readTable(db.words),
      row.readTable(db.wordSenses),
      row.readTableOrNull(db.memoryStates),
    );
  }

  Future<List<StudyItem>> entries({
    String? wordbookId,
    String search = '',
    int offset = 0,
    int? limit,
    int? wordId,
    bool learnedOnly = false,
    EntryFilter filter = EntryFilter.all,
    int? nowMilliseconds,
  }) async {
    if (offset < 0 || (limit != null && limit < 0)) {
      throw ArgumentError('分页位置和数量不能为负数。');
    }
    final effectiveFilter = learnedOnly ? EntryFilter.learned : filter;
    final query = db.select(db.wordSenses).join([
      innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      leftOuterJoin(
        db.memoryStates,
        db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
            db.memoryStates.userId.equals(localUserId) &
            db.memoryStates.trainingMode.equals(recognitionMode),
      ),
      if (wordbookId != null)
        innerJoin(
          db.wordbookEntries,
          db.wordbookEntries.wordSenseId.equalsExp(db.wordSenses.id) &
              db.wordbookEntries.wordbookId.equals(wordbookId),
        ),
    ])..orderBy([OrderingTerm.asc(db.wordSenses.id)]);
    if (wordbookId != null) {
      query.where(db.wordbookEntries.wordbookId.equals(wordbookId));
    }
    if (search.trim().isNotEmpty) {
      final term = search
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      query.where(
        db.words.spelling.like('%$term%', escapeChar: '\\') |
            db.wordSenses.definition.like('%$term%', escapeChar: '\\'),
      );
    }
    if (wordId != null) query.where(db.words.id.equals(wordId));
    switch (effectiveFilter) {
      case EntryFilter.all:
        break;
      case EntryFilter.unlearned:
        query.where(db.memoryStates.wordSenseId.isNull());
        break;
      case EntryFilter.learned:
        query.where(db.memoryStates.wordSenseId.isNotNull());
        break;
      case EntryFilter.due:
        query.where(
          db.memoryStates.wordSenseId.isNotNull() &
              db.memoryStates.due.isSmallerOrEqualValue(
                nowMilliseconds ?? nowUtc().millisecondsSinceEpoch,
              ),
        );
        break;
    }
    if (limit != null || offset > 0) query.limit(limit ?? -1, offset: offset);
    final items = (await query.get()).map(
      (row) => StudyItem(
        row.readTable(db.words),
        row.readTable(db.wordSenses),
        row.readTableOrNull(db.memoryStates),
      ),
    );
    return items.toList();
  }

  Future<int> entryCount({
    String? wordbookId,
    String search = '',
    EntryFilter filter = EntryFilter.all,
    bool learnedOnly = false,
    int? nowMilliseconds,
  }) async {
    final effectiveFilter = learnedOnly ? EntryFilter.learned : filter;
    final count = db.wordSenses.id.count();
    final query = db.selectOnly(db.wordSenses).join([
      innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      leftOuterJoin(
        db.memoryStates,
        db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
            db.memoryStates.userId.equals(localUserId) &
            db.memoryStates.trainingMode.equals(recognitionMode),
      ),
      if (wordbookId != null)
        innerJoin(
          db.wordbookEntries,
          db.wordbookEntries.wordSenseId.equalsExp(db.wordSenses.id) &
              db.wordbookEntries.wordbookId.equals(wordbookId),
        ),
    ])..addColumns([count]);
    if (wordbookId != null) {
      query.where(db.wordbookEntries.wordbookId.equals(wordbookId));
    }
    if (search.trim().isNotEmpty) {
      final term = search
          .trim()
          .replaceAll('\\', '\\\\')
          .replaceAll('%', '\\%')
          .replaceAll('_', '\\_');
      query.where(
        db.words.spelling.like('%$term%', escapeChar: '\\') |
            db.wordSenses.definition.like('%$term%', escapeChar: '\\'),
      );
    }
    switch (effectiveFilter) {
      case EntryFilter.all:
        break;
      case EntryFilter.unlearned:
        query.where(db.memoryStates.wordSenseId.isNull());
        break;
      case EntryFilter.learned:
        query.where(db.memoryStates.wordSenseId.isNotNull());
        break;
      case EntryFilter.due:
        query.where(
          db.memoryStates.wordSenseId.isNotNull() &
              db.memoryStates.due.isSmallerOrEqualValue(
                nowMilliseconds ?? nowUtc().millisecondsSinceEpoch,
              ),
        );
        break;
    }
    final row = await query.getSingle();
    return row.read(count)!;
  }

  Future<Set<int>> senseIdsForWordbook(String wordbookId) async {
    final rows =
        await (db.selectOnly(db.wordbookEntries)
              ..addColumns([db.wordbookEntries.wordSenseId])
              ..where(db.wordbookEntries.wordbookId.equals(wordbookId)))
            .get();
    return rows.map((row) => row.read(db.wordbookEntries.wordSenseId)!).toSet();
  }

  Future<List<StudyItem>> itemsForSenses(Set<int> senseIds) async {
    if (senseIds.isEmpty) return [];
    final query =
        db.select(db.wordSenses).join([
            innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
            leftOuterJoin(
              db.memoryStates,
              db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
                  db.memoryStates.userId.equals(localUserId) &
                  db.memoryStates.trainingMode.equals(recognitionMode),
            ),
          ])
          ..where(db.wordSenses.id.isIn(senseIds))
          ..orderBy([OrderingTerm.asc(db.wordSenses.id)]);
    return (await query.get())
        .map(
          (row) => StudyItem(
            row.readTable(db.words),
            row.readTable(db.wordSenses),
            row.readTableOrNull(db.memoryStates),
          ),
        )
        .toList();
  }

  Future<StudyItem?> learnedEntry(int senseId) async {
    final query = db.select(db.wordSenses).join([
      innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      innerJoin(
        db.memoryStates,
        db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
            db.memoryStates.userId.equals(localUserId) &
            db.memoryStates.trainingMode.equals(recognitionMode),
      ),
    ])..where(db.wordSenses.id.equals(senseId));
    final row = await query.getSingleOrNull();
    if (row == null) return null;
    return StudyItem(
      row.readTable(db.words),
      row.readTable(db.wordSenses),
      row.readTable(db.memoryStates),
    );
  }

  Future<void> updateWordbook(
    String wordbookId,
    String name,
    Set<int> senseIds,
  ) async {
    final cleanName = _cleanWordbookName(name);
    _ensureWordbookSenses(senseIds);
    await db.transaction(() async {
      final book = await (db.select(
        db.wordbooks,
      )..where((row) => row.id.equals(wordbookId))).getSingleOrNull();
      if (book == null) throw ArgumentError('词书不存在，请刷新后重试。');
      if (book.isBuiltIn) throw StateError('内置词书不能编辑。');
      await _ensureWordbookSensesExist(senseIds);
      final existing = await senseIdsForWordbook(wordbookId);
      final removed = existing.difference(senseIds);
      final added = senseIds.difference(existing);
      await (db.update(db.wordbooks)..where((row) => row.id.equals(wordbookId)))
          .write(WordbooksCompanion(name: Value(cleanName)));
      if (removed.isNotEmpty) {
        await (db.delete(db.wordbookEntries)..where(
              (row) =>
                  row.wordbookId.equals(wordbookId) &
                  row.wordSenseId.isIn(removed),
            ))
            .go();
      }
      if (added.isNotEmpty) {
        await db.batch((batch) {
          batch.insertAll(
            db.wordbookEntries,
            added
                .map(
                  (senseId) => WordbookEntriesCompanion.insert(
                    wordbookId: wordbookId,
                    wordSenseId: senseId,
                  ),
                )
                .toList(),
            mode: InsertMode.insertOrIgnore,
          );
        });
      }
    });
    refresh();
  }

  Future<void> deleteWordbook(String wordbookId) async {
    await db.transaction(() async {
      final book = await (db.select(
        db.wordbooks,
      )..where((row) => row.id.equals(wordbookId))).getSingleOrNull();
      if (book == null) throw ArgumentError('词书不存在，请刷新后重试。');
      if (book.isBuiltIn) throw StateError('内置词书不能删除。');
      await (db.delete(
        db.wordbookEntries,
      )..where((row) => row.wordbookId.equals(wordbookId))).go();
      await (db.delete(
        db.wordbooks,
      )..where((row) => row.id.equals(wordbookId))).go();
      await (db.delete(db.appSettings)..where(
            (row) =>
                row.key.equals('active_wordbook_id') &
                row.value.equals(wordbookId),
          ))
          .go();
    });
    refresh();
  }

  String _cleanWordbookName(String name) {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 40) {
      throw ArgumentError('请填写 1 到 40 字的词书名称。');
    }
    return clean;
  }

  void _ensureWordbookSenses(Set<int> senseIds) {
    if (senseIds.isEmpty) throw ArgumentError('请选择至少一个词义。');
  }

  Future<void> _ensureWordbookSensesExist(Set<int> senseIds) async {
    final rows =
        await (db.selectOnly(db.wordSenses)
              ..addColumns([db.wordSenses.id])
              ..where(db.wordSenses.id.isIn(senseIds)))
            .get();
    if (rows.length != senseIds.length) {
      throw ArgumentError('所选词义已不存在，请刷新后重试。');
    }
  }

  Future<List<StudyItem>> spellingSample({
    String? wordbookId,
    int limit = 10,
    EntryFilter filter = EntryFilter.all,
    int? nowMilliseconds,
  }) async {
    if (limit < 0) throw ArgumentError('抽词数量不能为负数。');
    if (limit == 0) return [];
    final now = nowMilliseconds ?? nowUtc().millisecondsSinceEpoch;
    // 先在词书与筛选条件内按单词去重，再抽取符合条件的代表词义。
    final selected = db.selectOnly(db.wordSenses)
      ..addColumns([db.wordSenses.id.min()]);
    selected.join([
      if (wordbookId != null)
        innerJoin(
          db.wordbookEntries,
          db.wordbookEntries.wordSenseId.equalsExp(db.wordSenses.id),
        ),
      leftOuterJoin(
        db.memoryStates,
        db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
            db.memoryStates.userId.equals(localUserId) &
            db.memoryStates.trainingMode.equals(recognitionMode),
      ),
    ]);
    if (wordbookId != null) {
      selected.where(db.wordbookEntries.wordbookId.equals(wordbookId));
    }
    switch (filter) {
      case EntryFilter.all:
        break;
      case EntryFilter.unlearned:
        selected.where(db.memoryStates.wordSenseId.isNull());
        break;
      case EntryFilter.learned:
        selected.where(db.memoryStates.wordSenseId.isNotNull());
        break;
      case EntryFilter.due:
        selected.where(
          db.memoryStates.wordSenseId.isNotNull() &
              db.memoryStates.due.isSmallerOrEqualValue(now),
        );
        break;
    }
    selected
      ..groupBy([db.wordSenses.wordId])
      ..orderBy([OrderingTerm.random()])
      ..limit(limit);
    final query =
        db.select(db.wordSenses).join([
            innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
            leftOuterJoin(
              db.memoryStates,
              db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
                  db.memoryStates.userId.equals(localUserId) &
                  db.memoryStates.trainingMode.equals(recognitionMode),
            ),
          ])
          ..where(db.wordSenses.id.isInQuery(selected))
          ..limit(limit)
          ..orderBy([OrderingTerm.random()]);
    return (await query.get())
        .map(
          (row) => StudyItem(
            row.readTable(db.words),
            row.readTable(db.wordSenses),
            row.readTableOrNull(db.memoryStates),
          ),
        )
        .toList();
  }

  Future<int> dailyGoal() async {
    final row = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('daily_new_goal'))).getSingle();
    return int.parse(row.value);
  }

  Future<ThemeSettings> loadThemeSettings() async {
    final rows = await (db.select(
      db.appSettings,
    )..where((row) => row.key.isIn(const ['theme_id', 'theme_mode']))).get();
    final values = {for (final row in rows) row.key: row.value};
    return ThemeSettings(
      themeId: JournalThemeId.fromStorage(values['theme_id']),
      mode: AppThemeMode.fromStorage(values['theme_mode']),
    );
  }

  Future<double> pronunciationRate() async {
    final setting = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('pronunciation_rate'))).getSingleOrNull();
    final value = double.tryParse(setting?.value ?? '');
    return const [.35, .5, .65].contains(value) ? value! : .5;
  }

  Future<void> setPronunciationRate(double value) async {
    if (!const [.35, .5, .65].contains(value)) {
      throw ArgumentError('请选择慢速、标准或稍快语速。');
    }
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: 'pronunciation_rate',
            value: '$value',
          ),
        );
  }

  Future<void> saveThemeSettings(ThemeSettings settings) async {
    await db.transaction(() async {
      for (final entry in {
        'theme_id': settings.themeId.storageValue,
        'theme_mode': settings.mode.storageValue,
      }.entries) {
        await db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(key: entry.key, value: entry.value),
            );
      }
    });
  }

  Future<int> newLearnedToday() async {
    final now = nowUtc();
    final start = calendar.midnightUtc(now).millisecondsSinceEpoch;
    final end = calendar.nextMidnightUtc(now).millisecondsSinceEpoch;
    final events =
        await (db.select(db.reviewEvents)..where(
              (row) =>
                  row.userId.equals(localUserId) &
                  row.trainingMode.equals(recognitionMode) &
                  row.reviewedAt.isBiggerOrEqualValue(start) &
                  row.reviewedAt.isSmallerThanValue(end),
            ))
            .get();
    return events
        .where(
          (event) => engine.decodeCard(event.beforeJson).lastReview == null,
        )
        .map((event) => event.wordSenseId)
        .toSet()
        .length;
  }

  Future<void> setDailyGoal(int goal) async {
    if (goal < 0 || goal > 100) throw ArgumentError('每日新词目标需在 0 到 100 之间。');
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: 'daily_new_goal', value: '$goal'),
        );
    refresh();
  }

  Future<List<StudyItem>> todayQueue() async =>
      (await queueStatus(todayPlan: true)).items;

  Future<List<StudyItem>> queue({String? wordbookId, int? senseId}) =>
      queueStatus(
        wordbookId: wordbookId,
        senseId: senseId,
      ).then((status) => status.items);

  Future<StudyQueueStatus> queueStatus({
    String? wordbookId,
    int? senseId,
    bool todayPlan = false,
  }) async {
    final active = todayPlan ? await activeWordbook() : null;
    return _queueStatus(
      wordbookId: wordbookId,
      senseId: senseId,
      newWordbookId: active?.id,
      activeBook: active,
      todayPlan: todayPlan,
    );
  }

  Future<StudyQueueStatus> activeBookQueueStatus(Wordbook? activeBook) =>
      _queueStatus(
        newWordbookId: activeBook?.id,
        activeBook: activeBook,
        todayPlan: true,
      );

  Future<StudyQueueStatus> _queueStatus({
    String? wordbookId,
    int? senseId,
    String? newWordbookId,
    Wordbook? activeBook,
    bool todayPlan = false,
  }) async {
    final now = utcMilliseconds(nowUtc()).millisecondsSinceEpoch;
    final memberships = db.selectOnly(db.wordbookEntries)
      ..addColumns([db.wordbookEntries.wordSenseId]);
    if (wordbookId != null) {
      memberships.where(db.wordbookEntries.wordbookId.equals(wordbookId));
    }
    if (newWordbookId != null) {
      memberships.where(db.wordbookEntries.wordbookId.equals(newWordbookId));
    }
    final newScope = db.selectOnly(db.wordSenses)
      ..addColumns([db.wordSenses.id])
      ..where(db.wordSenses.id.isInQuery(memberships));
    if (senseId != null) newScope.where(db.wordSenses.id.equals(senseId));
    final BaseSelectStatement<dynamic>? dueScope;
    if (wordbookId != null) {
      dueScope = newScope;
    } else if (senseId != null) {
      dueScope = db.selectOnly(db.wordSenses)
        ..addColumns([db.wordSenses.id])
        ..where(db.wordSenses.id.equals(senseId));
    } else {
      dueScope = null;
    }

    final dueQuery = db.select(db.wordSenses).join([
      innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      innerJoin(
        db.memoryStates,
        db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
            db.memoryStates.userId.equals(localUserId) &
            db.memoryStates.trainingMode.equals(recognitionMode) &
            db.memoryStates.due.isSmallerOrEqualValue(now),
      ),
    ])..orderBy([OrderingTerm.asc(db.memoryStates.due)]);
    // 首页到期复习按全部已学词处理，词义脱离所有词书也不能漏掉。
    if (dueScope != null) dueQuery.where(db.wordSenses.id.isInQuery(dueScope));
    final due = (await dueQuery.get())
        .map(
          (row) => StudyItem(
            row.readTable(db.words),
            row.readTable(db.wordSenses),
            row.readTable(db.memoryStates),
          ),
        )
        .toList();
    final goal = await dailyGoal();
    final learnedToday = await newLearnedToday();
    final remaining = (goal - learnedToday).clamp(0, 100);
    final newItems = <StudyItem>[];
    if (remaining > 0) {
      final newQuery =
          db.select(db.wordSenses).join([
              innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
              leftOuterJoin(
                db.memoryStates,
                db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
                    db.memoryStates.userId.equals(localUserId) &
                    db.memoryStates.trainingMode.equals(recognitionMode),
              ),
            ])
            ..orderBy([OrderingTerm.asc(db.wordSenses.id)])
            ..where(db.memoryStates.wordSenseId.isNull())
            ..where(db.wordSenses.id.isInQuery(newScope))
            ..limit(remaining);
      newItems.addAll(
        (await newQuery.get()).map(
          (row) => StudyItem(
            row.readTable(db.words),
            row.readTable(db.wordSenses),
            row.readTableOrNull(db.memoryStates),
          ),
        ),
      );
    }
    final unlearnedCount = db.wordSenses.id.count();
    final unlearnedQuery =
        db.selectOnly(db.wordSenses).join([
            leftOuterJoin(
              db.memoryStates,
              db.memoryStates.wordSenseId.equalsExp(db.wordSenses.id) &
                  db.memoryStates.userId.equals(localUserId) &
                  db.memoryStates.trainingMode.equals(recognitionMode),
            ),
          ])
          ..addColumns([unlearnedCount])
          ..where(db.memoryStates.wordSenseId.isNull())
          ..where(db.wordSenses.id.isInQuery(newScope));
    final unlearned = (await unlearnedQuery.getSingle()).read(unlearnedCount)!;
    final scopeLabel = await _queueScopeLabel(
      wordbookId: wordbookId,
      senseId: senseId,
      activeBook: activeBook,
    );
    // 首页固定词书只约束新词；已经学过的其他词书仍按原计划复习。
    return StudyQueueStatus(
      items: [...due, ...newItems],
      nextDue: await _nextDueAfter(
        now,
        wordbookId: todayPlan ? null : wordbookId,
        senseId: senseId,
      ),
      unlearnedCount: unlearned,
      dailyGoal: goal,
      learnedToday: learnedToday,
      quotaExhausted: remaining == 0 && unlearned > 0,
      scopeLabel: scopeLabel,
    );
  }

  Future<String> _queueScopeLabel({
    String? wordbookId,
    int? senseId,
    Wordbook? activeBook,
  }) async {
    if (senseId != null) {
      final row = await (db.select(db.wordSenses).join([
        innerJoin(db.words, db.words.id.equalsExp(db.wordSenses.wordId)),
      ])..where(db.wordSenses.id.equals(senseId))).getSingleOrNull();
      final spelling = row?.readTable(db.words).spelling;
      return spelling == null ? '当前词义' : '“$spelling”这个词义';
    }
    if (activeBook != null) return activeBook.name;
    if (wordbookId != null) {
      final book = await (db.select(
        db.wordbooks,
      )..where((row) => row.id.equals(wordbookId))).getSingleOrNull();
      return book?.name ?? '当前词书';
    }
    return '全部词书';
  }
}
