import 'dart:async';

import 'package:drift/drift.dart';
import 'package:fsrs/fsrs.dart' as fsrs;

import '../core/clock.dart';
import '../core/ids.dart';
import '../core/local_calendar.dart';
import '../domain/fsrs_engine.dart';
import 'app_database.dart';

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
  Stream<void> get changes => _changes.stream;
  void refresh() => _changes.add(null);
  Future<void> dispose() => _changes.close();

  Future<List<ReviewEvent>> history({int? senseId}) {
    final query = db.select(db.reviewEvents)
      ..where(
        (row) =>
            row.userId.equals(localUserId) &
            row.trainingMode.equals(recognitionMode),
      );
    if (senseId != null) query.where((row) => row.wordSenseId.equals(senseId));
    query.orderBy([
      (row) => OrderingTerm.asc(row.reviewedAt),
      (row) => OrderingTerm.asc(row.id),
    ]);
    return query.get();
  }

  Future<StudyStats> stats() async {
    final events = await history();
    final allItems = await entries();
    final now = nowUtc();
    final today = calendar.dayKey(now);
    final dates = events
        .map(
          (event) => DateTime.fromMillisecondsSinceEpoch(
            event.reviewedAt,
            isUtc: true,
          ),
        )
        .toList();
    final counts = List<int>.filled(7, 0);
    for (final date in dates) {
      final offset = calendar.dayKey(date) - (today - 6);
      if (offset >= 0 && offset < 7) counts[offset]++;
    }
    double success(Iterable<ReviewEvent> list) {
      final values = list.toList();
      return values.isEmpty
          ? 0
          : values
                    .where(
                      (event) =>
                          event.rating == 'good' || event.rating == 'easy',
                    )
                    .length /
                values.length;
    }

    final recent = events.where(
      (event) =>
          calendar.dayKey(
            DateTime.fromMillisecondsSinceEpoch(event.reviewedAt, isUtc: true),
          ) >=
          today - 6,
    );
    return StudyStats(
      today: counts.last,
      total: events.length,
      successRate: success(events),
      recentSuccessRate: success(recent),
      streak: calendar.streak(dates, now),
      learnedWords: allItems
          .where((item) => item.memory != null)
          .map((item) => item.word.id)
          .toSet()
          .length,
      totalWords: allItems.map((item) => item.word.id).toSet().length,
      dailyCounts: counts,
    );
  }

  Future<DateTime?> nextDue() async {
    final now = nowUtc().millisecondsSinceEpoch;
    final row =
        await (db.select(db.memoryStates)
              ..where(
                (row) =>
                    row.userId.equals(localUserId) &
                    row.trainingMode.equals(recognitionMode) &
                    row.due.isBiggerThanValue(now),
              )
              ..orderBy([(row) => OrderingTerm.asc(row.due)])
              ..limit(1))
            .getSingleOrNull();
    return row == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(row.due, isUtc: true);
  }

  Future<List<Wordbook>> books() => db.select(db.wordbooks).get();

  Future<void> createWordbook(String name, Set<int> senseIds) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 40 || senseIds.isEmpty) {
      throw ArgumentError('请填写 1 到 40 字的词书名称，并选择至少一个词义。');
    }
    await db.transaction(() async {
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

  Future<fsrs.Card> score(
    StudyItem item,
    fsrs.Rating rating, {
    required String eventId,
    int? durationMs,
  }) async {
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
      return after;
    });
    refresh();
    return result;
  }

  Future<List<StudyItem>> entries({
    String? wordbookId,
    String search = '',
  }) async {
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
    final items = (await query.get()).map(
      (row) => StudyItem(
        row.readTable(db.words),
        row.readTable(db.wordSenses),
        row.readTableOrNull(db.memoryStates),
      ),
    );
    final term = search.trim().toLowerCase();
    return items
        .where(
          (item) =>
              term.isEmpty ||
              item.word.spelling.toLowerCase().contains(term) ||
              item.sense.definition.contains(term),
        )
        .toList();
  }

  Future<int> dailyGoal() async {
    final row = await (db.select(
      db.appSettings,
    )..where((row) => row.key.equals('daily_new_goal'))).getSingle();
    return int.parse(row.value);
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

  Future<List<StudyItem>> queue({String? wordbookId}) async {
    final memberships = (await db.select(db.wordbookEntries).get())
        .map((row) => row.wordSenseId)
        .toSet();
    final items = (await entries(wordbookId: wordbookId))
        .where((item) => memberships.contains(item.sense.id))
        .toList();
    final now = nowUtc().millisecondsSinceEpoch;
    final due =
        items
            .where((item) => item.memory != null && item.memory!.due <= now)
            .toList()
          ..sort((a, b) => a.memory!.due.compareTo(b.memory!.due));
    final remaining = ((await dailyGoal()) - (await newLearnedToday())).clamp(
      0,
      100,
    );
    final newItems = items.where((item) => item.memory == null).take(remaining);
    return [...due, ...newItems];
  }
}
