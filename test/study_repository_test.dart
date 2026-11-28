import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/core/local_calendar.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/data/backup_codec.dart';
import 'package:lexi_loop/data/study_repository.dart';
import 'package:lexi_loop/data/wordbook_exchange.dart';
import 'package:lexi_loop/domain/fsrs_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FsrsEngine engine;
  late StudyRepository repository;
  late DateTime now;
  setUp(() async {
    now = DateTime.utc(2026, 11, 27, 8);
    db = AppDatabase(NativeDatabase.memory());
    engine = FsrsEngine();
    repository = StudyRepository(db, engine, nowUtc: () => now);
    await db.ensureSeeded(
      schedulerVersion: engine.schedulerVersion,
      configurationJson: engine.configurationJson,
    );
  });
  tearDown(() async {
    await repository.dispose();
    await db.close();
  });

  test('学习词书选择持久保存、可清除，拒绝不存在的词书', () async {
    expect(await repository.activeWordbook(), isNull);
    await repository.setActiveWordbook('cet4');
    expect((await repository.activeWordbook())?.id, 'cet4');
    final reopened = StudyRepository(db, engine, nowUtc: () => now);
    addTearDown(reopened.dispose);
    expect((await reopened.activeWordbook())?.id, 'cet4');
    await expectLater(
      repository.setActiveWordbook('missing'),
      throwsArgumentError,
    );
    expect((await repository.activeWordbook())?.id, 'cet4');
    final item = (await repository.queue()).first;
    await repository.createWordbook('每日精选', {item.sense.id});
    final custom = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await repository.setActiveWordbook(custom.id);
    expect((await reopened.activeWordbook())?.name, '每日精选');
    await repository.setActiveWordbook(null);
    expect(await reopened.activeWordbook(), isNull);
    expect(await repository.history(), isEmpty);
  });

  test('首页只加入选定词书新词，保留其他词书到期复习与全局每日额度', () async {
    final original = (await repository.queue(wordbookId: 'everyday')).first;
    final scheduled = await repository.score(
      original,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = scheduled.due;
    await repository.setDailyGoal(3);
    await repository.setActiveWordbook('cet4');
    final cet4 = (await repository.entries(wordbookId: 'cet4'))
        .map((item) => item.sense.id)
        .toSet();
    final today = await repository.todayQueue();
    expect(today, hasLength(3));
    expect(today.first.sense.id, original.sense.id);
    expect(today.skip(1).every((item) => cet4.contains(item.sense.id)), isTrue);
    expect(today.map((item) => item.sense.id).toSet(), hasLength(today.length));
    expect(
      (await repository.queue(wordbookId: 'cet4'))
          .every((item) => cet4.contains(item.sense.id)),
      isTrue,
    );
    await repository.score(
      today[1],
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await repository.setActiveWordbook('cet6');
    expect(
      (await repository.todayQueue()).where((item) => item.memory == null),
      hasLength(1),
    );
    await repository.setDailyGoal(0);
    expect((await repository.todayQueue()).map((item) => item.sense.id), [
      original.sense.id,
    ]);
    await repository.setDailyGoal(3);
    await repository.createWordbook('只复习已学词', {original.sense.id});
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await repository.setActiveWordbook(book.id);
    expect((await repository.todayQueue()).map((item) => item.sense.id), [
      original.sense.id,
    ]);
  });

  test('词书进度按本书词义关联去重，跨书共享但不同词义不冒充已学', () async {
    final example = (await repository.entries(
      wordbookId: 'everyday',
      search: 'bloom',
    )).single;
    final exam = (await repository.entries(
      wordbookId: 'cet4',
      search: 'bloom',
    )).single;
    await repository.score(
      example,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    expect(await repository.wordProgress(wordbookId: 'cet4'), (
      learned: 0,
      total: 3849,
    ));
    expect(await repository.wordProgress(wordbookId: 'everyday'), (
      learned: 1,
      total: 24,
    ));
    await repository.score(exam, fsrs.Rating.good, eventId: newReviewEventId());
    expect(await repository.wordProgress(wordbookId: 'cet4'), (
      learned: 1,
      total: 3849,
    ));
    expect(await repository.wordProgress(wordbookId: 'cet6'), (
      learned: 1,
      total: 5407,
    ));
    expect(await repository.wordProgress(), (learned: 1, total: 13141));
    expect(await repository.wordProgress(wordbookId: 'missing'), (
      learned: 0,
      total: 0,
    ));
  });

  test('关闭数据库再打开仍沿用学习词书与新词计划', () async {
    final directory = await Directory.systemTemp.createTemp('lexi-plan-test-');
    final file = File('${directory.path}/study.sqlite');
    // 此用例另外打开独立文件库，不与 setUp 的内存库共享连接。
    final oldWarning = driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    AppDatabase? diskDb;
    StudyRepository? diskRepo;
    try {
      diskDb = AppDatabase(NativeDatabase(file));
      diskRepo = StudyRepository(diskDb, engine, nowUtc: () => now);
      await diskDb.ensureSeeded(
        schedulerVersion: engine.schedulerVersion,
        configurationJson: engine.configurationJson,
      );
      await diskRepo.setActiveWordbook('cet6');
      await diskRepo.setDailyGoal(2);
      await diskRepo.dispose();
      diskRepo = null;
      await diskDb.close();
      diskDb = AppDatabase(NativeDatabase(file));
      diskRepo = StudyRepository(diskDb, engine, nowUtc: () => now);
      await diskDb.ensureSeeded(
        schedulerVersion: engine.schedulerVersion,
        configurationJson: engine.configurationJson,
      );
      expect((await diskRepo.activeWordbook())?.id, 'cet6');
      expect(await diskRepo.todayQueue(), hasLength(2));
      expect((await diskRepo.todayQueue()).first.word.spelling, 'abandon');
    } finally {
      await diskRepo?.dispose();
      await diskDb?.close();
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = oldWarning;
      await directory.delete(recursive: true);
    }
  });

  test('评分记录写入失败会回滚已经更新的记忆状态', () async {
    await db.customStatement(
      "CREATE TRIGGER reject_review BEFORE INSERT ON review_events BEGIN SELECT RAISE(ABORT, 'test write failure'); END",
    );
    final item = (await repository.queue()).first;
    await expectLater(
      repository.score(item, fsrs.Rating.good, eventId: newReviewEventId()),
      throwsA(isA<Exception>()),
    );
    expect(await db.select(db.memoryStates).get(), isEmpty);
    expect(await repository.history(), isEmpty);
  });

  test('同一词义跨自建词书共享进度，并发重试只写一次', () async {
    final item = (await repository.queue()).first;
    await repository.createWordbook('随身词书', {item.sense.id});
    final book = (await repository.books()).firstWhere(
      (book) => !book.isBuiltIn,
    );
    final id = newReviewEventId();
    await Future.wait([
      repository.score(item, fsrs.Rating.good, eventId: id),
      repository.score(item, fsrs.Rating.good, eventId: id),
    ]);
    expect(await repository.history(), hasLength(1));
    expect(
      (await repository.entries(wordbookId: book.id)).single.memory,
      isNotNull,
    );
    expect(await repository.queue(wordbookId: book.id), isEmpty);
  });

  test('统计按真实评分计算成功率，Hard 不计为成功', () async {
    final items = await repository.queue();
    await repository.score(
      items[0],
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await repository.score(
      items[1],
      fsrs.Rating.hard,
      eventId: newReviewEventId(),
    );
    final stats = await repository.stats();
    expect(stats.today, 2);
    expect(stats.total, 2);
    expect(stats.successRate, .5);
    expect(stats.streak, 1);
    expect(stats.dailyCounts.last, 2);
    expect(stats.learnedWords, 2);
  });

  test('新词额度按当天首次学习扣减，跨日恢复且到期复习优先', () async {
    final item = (await repository.queue()).first;
    await repository.score(item, fsrs.Rating.good, eventId: newReviewEventId());
    expect(await repository.queue(), hasLength(9));
    now = now.add(const Duration(days: 1));
    final queue = await repository.queue();
    expect(queue, hasLength(11));
    expect(queue.first.sense.id, item.sense.id);
  });

  test('其他页面提交过的旧卡片不能再推进状态', () async {
    final item = (await repository.queue()).first;
    await repository.score(item, fsrs.Rating.good, eventId: newReviewEventId());
    await expectLater(
      repository.score(item, fsrs.Rating.easy, eventId: newReviewEventId()),
      throwsStateError,
    );
    expect(await db.select(db.reviewEvents).get(), hasLength(1));
  });

  test('评分写入历史和状态，同一事件重试只推进一次', () async {
    final item = (await repository.queue()).first;
    final eventId = newReviewEventId();
    final first = await repository.score(
      item,
      fsrs.Rating.good,
      eventId: eventId,
    );
    final retry = await repository.score(
      item,
      fsrs.Rating.good,
      eventId: eventId,
    );
    expect(await db.select(db.reviewEvents).get(), hasLength(1));
    expect(await db.select(db.memoryStates).get(), hasLength(1));
    expect(engine.encodeCard(retry), engine.encodeCard(first));
  });

  test('初次队列按目标返回十个新词，重复初始化不增加词条', () async {
    await db.ensureSeeded(
      schedulerVersion: engine.schedulerVersion,
      configurationJson: engine.configurationJson,
    );
    expect(await repository.queue(), hasLength(10));
    expect(await db.select(db.words).get(), hasLength(13141));
  });

  test('初始化导入四六级、专八与考研词书而不覆盖原有学习进度', () async {
    await repository.setDailyGoal(3);
    final original = (await repository.queue()).first;
    await repository.score(
      original,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    // 模拟仅安装原创词库的旧版本，保留已经产生的真实评分和设置。
    await db.transaction(() async {
      await (db.delete(
        db.wordbookEntries,
      )..where((row) => row.wordbookId.equals('everyday').not())).go();
      await (db.delete(
        db.wordbooks,
      )..where((row) => row.id.equals('everyday').not())).go();
      await (db.delete(
        db.wordSenses,
      )..where((row) => row.id.isBiggerThanValue(24))).go();
      await (db.delete(
        db.words,
      )..where((row) => row.id.isBiggerThanValue(24))).go();
      await (db.delete(
        db.appSettings,
      )..where((row) => row.key.equals('exam_catalog_version'))).go();
    });

    await db.ensureSeeded(
      schedulerVersion: engine.schedulerVersion,
      configurationJson: engine.configurationJson,
    );

    final books = await repository.books();
    expect(
      books.map((book) => book.id),
      containsAll(['cet4', 'cet6', 'tem8', 'ky']),
    );
    expect(await repository.entries(wordbookId: 'cet4'), hasLength(3849));
    expect(await repository.entries(wordbookId: 'cet6'), hasLength(5407));
    expect(await repository.entries(wordbookId: 'tem8'), hasLength(12694));
    expect(await repository.entries(wordbookId: 'ky'), hasLength(4801));
    expect(await repository.entries(), hasLength(13165));
    expect(
      (await repository.entries())
          .singleWhere((item) => item.sense.id == original.sense.id)
          .memory,
      isNotNull,
    );
    expect(await repository.dailyGoal(), 3);
    expect(await repository.history(), hasLength(1));
  });

  test('考试词库写入失败会整体回滚，允许修复原因后重新安装', () async {
    await (db.delete(
      db.appSettings,
    )..where((row) => row.key.equals('exam_catalog_version'))).go();
    await (db.delete(
      db.wordbookEntries,
    )..where((row) => row.wordbookId.equals('cet6'))).go();
    await (db.delete(db.wordbooks)..where((row) => row.id.equals('cet6'))).go();
    final before = await repository.entryCount();
    await db.customStatement(
      "CREATE TRIGGER reject_exam BEFORE INSERT ON wordbook_entries WHEN NEW.wordbook_id = 'cet6' BEGIN SELECT RAISE(ABORT, 'test exam failure'); END",
    );
    await expectLater(db.ensureExamWordbooks(), throwsA(isA<Exception>()));
    expect(
      (await repository.books()).any((book) => book.id == 'cet6'),
      isFalse,
    );
    expect(await repository.entryCount(), before);
    expect(
      await (db.select(db.appSettings)
            ..where((row) => row.key.equals('exam_catalog_version')))
          .getSingleOrNull(),
      isNull,
    );
    await db.customStatement('DROP TRIGGER reject_exam');
    await db.ensureExamWordbooks();
    expect(await repository.entryCount(wordbookId: 'cet6'), 5407);
  });

  test('考试词书相同词义共享进度，指定词义不受今日默认队列截断', () async {
    final target = (await repository.entries(
      wordbookId: 'cet6',
      search: 'abandon',
    )).singleWhere((item) => item.word.spelling == 'abandon');
    final cet4 = (await repository.entries(
      wordbookId: 'cet4',
      search: 'abandon',
    )).singleWhere((item) => item.word.spelling == 'abandon');
    expect(cet4.sense.id, target.sense.id);
    final selected = await repository.queue(senseId: target.sense.id);
    expect(selected.map((item) => item.sense.id), [target.sense.id]);
    await repository.score(
      selected.single,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    expect(
      (await repository.entries(
        wordbookId: 'cet4',
        search: 'abandon',
      )).singleWhere((item) => item.word.spelling == 'abandon').memory,
      isNotNull,
    );
    expect(await repository.queue(senseId: target.sense.id), isEmpty);
    await repository.setDailyGoal(1);
    final other = (await repository.entries(wordbookId: 'ky'))
        .firstWhere((item) => item.memory == null);
    expect(await repository.queue(senseId: other.sense.id), isEmpty);
    expect(await repository.queue(), isEmpty);
    await expectLater(
      repository.score(other, fsrs.Rating.good, eventId: newReviewEventId()),
      throwsStateError,
    );
    now = now.add(const Duration(days: 1));
    expect(await repository.queue(senseId: other.sense.id), hasLength(1));
  });

  test('词书搜索和分页在数据库中裁剪后按稳定顺序返回', () async {
    expect(await repository.entryCount(wordbookId: 'cet4'), 3849);
    expect(
      await repository.entries(wordbookId: 'cet4', search: 'abandon', limit: 2),
      hasLength(1),
    );
    final first = await repository.entries(wordbookId: 'tem8', limit: 2);
    final second = await repository.entries(
      wordbookId: 'tem8',
      offset: 2,
      limit: 2,
    );
    expect(first, hasLength(2));
    expect(second, hasLength(2));
    expect(first.last.sense.id, lessThan(second.first.sense.id));
    expect(
      (await repository.entries(wordbookId: 'tem8', offset: 2)).first.sense.id,
      second.first.sense.id,
    );
    expect(await repository.entries(limit: 0), isEmpty);
    expect(await repository.entries(search: '_'), isEmpty);
    final expected = (await repository.entries(
      wordbookId: 'cet4',
      search: 'ability',
    ));
    expect(
      await repository.entryCount(wordbookId: 'cet4', search: 'ability'),
      expected.length,
    );
  });

  test('统计按去重单词计数，曲线候选只读取已学词义', () async {
    final first = (await repository.entries(search: 'bloom')).first;
    final senses = await repository.entries(wordId: first.word.id);
    for (final item in senses) {
      await repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    final learned = await repository.entries(learnedOnly: true);
    expect(
      learned.map((item) => item.sense.id).toSet(),
      senses.map((item) => item.sense.id).toSet(),
    );
    expect(learned.every((item) => item.memory != null), isTrue);
    final stats = await repository.stats();
    expect(stats.learnedWords, 1);
    expect(stats.totalWords, 13141);
    expect(stats.total, senses.length);
    expect(
      await repository.entries(learnedOnly: true, search: 'zoology'),
      isEmpty,
    );
    final located = await repository.learnedEntry(first.sense.id);
    expect(located?.sense.id, first.sense.id);
    expect(located?.memory, isNotNull);
    final unlearned = (await repository.entries(
      filter: EntryFilter.unlearned,
      wordbookId: 'everyday',
      limit: 1,
    )).single;
    expect(await repository.learnedEntry(unlearned.sense.id), isNull);
  });

  test('拼写抽词限制数量、按单词去重并限定词书，不写入学习记录', () async {
    final first = (await repository.entries(search: 'bloom')).first;
    final senses = await repository.entries(wordId: first.word.id);
    expect(senses.length, greaterThan(1));
    await repository.createWordbook(
      '多义词练习',
      senses.map((item) => item.sense.id).toSet(),
    );
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    final sample = await repository.spellingSample(wordbookId: book.id);
    expect(sample, hasLength(1));
    expect(sample.single.word.spelling, 'bloom');
    expect(
      senses.map((item) => item.sense.id),
      contains(sample.single.sense.id),
    );
    final exam = await repository.spellingSample(wordbookId: 'tem8');
    expect(exam, hasLength(10));
    expect(exam.map((item) => item.word.id).toSet(), hasLength(10));
    final eligible = (await repository.entries(wordbookId: 'tem8'))
        .map((item) => item.sense.id)
        .toSet();
    expect(exam.every((item) => eligible.contains(item.sense.id)), isTrue);
    expect(await repository.spellingSample(wordbookId: 'missing'), isEmpty);
    expect(await repository.spellingSample(limit: 0), isEmpty);
    await expectLater(
      repository.spellingSample(limit: -1),
      throwsArgumentError,
    );
    expect(await repository.history(), isEmpty);
    expect(await db.select(db.memoryStates).get(), isEmpty);
  });

  test('拼写按范围先筛选再按单词去重，多义词不会漏掉高 ID 到期释义', () async {
    const wordId = 900001;
    const otherWordId = 900010;
    const lowSense = 900001;
    const highSense = 900002;
    const otherSense = 900003;
    await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            id: const Value(wordId),
            spelling: 'boundary-word',
          ),
        );
    for (final sense in [
      (id: lowSense, definition: '低 ID 未学释义'),
      (id: highSense, definition: '高 ID 到期释义'),
    ]) {
      await db
          .into(db.wordSenses)
          .insert(
            WordSensesCompanion.insert(
              id: Value(sense.id),
              wordId: wordId,
              definition: sense.definition,
              example: '',
            ),
          );
    }
    await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            id: const Value(otherWordId),
            spelling: 'other-user-word',
          ),
        );
    await db
        .into(db.wordSenses)
        .insert(
          WordSensesCompanion.insert(
            id: const Value(otherSense),
            wordId: otherWordId,
            definition: '其他用户释义',
            example: '',
          ),
        );
    final nowMs = now.millisecondsSinceEpoch;
    MemoryStatesCompanion state(int senseId, String userId, String mode) =>
        MemoryStatesCompanion.insert(
          userId: userId,
          wordSenseId: senseId,
          trainingMode: mode,
          state: 1,
          step: const Value(0),
          stability: 1,
          difficulty: 5,
          due: nowMs,
          lastReview: nowMs - 1000,
          schedulerVersion: engine.schedulerVersion,
          schedulerConfigJson: engine.configurationJson,
        );
    await db
        .into(db.memoryStates)
        .insert(state(highSense, localUserId, recognitionMode));
    await db
        .into(db.memoryStates)
        .insert(state(otherSense, 'other-user', recognitionMode));
    await db
        .into(db.memoryStates)
        .insert(state(otherSense, localUserId, 'spelling'));
    await repository.createWordbook('拼写边界', {lowSense, highSense, otherSense});
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );

    final learned = await repository.spellingSample(
      wordbookId: book.id,
      filter: EntryFilter.learned,
      nowMilliseconds: nowMs,
    );
    expect(learned, hasLength(1));
    expect(learned.single.sense.id, highSense);
    expect(learned.single.sense.definition, '高 ID 到期释义');

    final dueAtBoundary = await repository.spellingSample(
      wordbookId: book.id,
      filter: EntryFilter.due,
      nowMilliseconds: nowMs,
    );
    expect(dueAtBoundary.single.sense.id, highSense);
    expect(
      await repository.spellingSample(
        wordbookId: book.id,
        filter: EntryFilter.due,
        nowMilliseconds: nowMs - 1,
      ),
      isEmpty,
    );

    final unlearned = await repository.spellingSample(
      wordbookId: book.id,
      filter: EntryFilter.unlearned,
      limit: 10,
      nowMilliseconds: nowMs,
    );
    expect(unlearned.map((item) => item.sense.id), contains(lowSense));
    expect(unlearned.map((item) => item.sense.id), isNot(contains(highSense)));
    expect(await repository.history(), isEmpty);
  });

  test('默认队列覆盖考试词书，到期卡跨词书去重且不扣减新词额度', () async {
    final original = (await repository.queue(wordbookId: 'cet4')).first;
    final card = await repository.score(
      original,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = card.due;
    await repository.setDailyGoal(0);
    expect((await repository.queue()).map((item) => item.sense.id), [
      original.sense.id,
    ]);
    expect(
      (await repository.queue(wordbookId: 'cet6')).single.sense.id,
      original.sense.id,
    );
    expect(await repository.queue(wordbookId: 'everyday'), isEmpty);
    await repository.setDailyGoal(2);
    final queue = await repository.queue();
    expect(queue, hasLength(2));
    expect(queue.first.sense.id, original.sense.id);
    expect(queue.last.memory, isNull);
  });

  test('自建词书可编辑名称与词义，内置词书和非法内容被拒绝', () async {
    final items = await repository.entries(wordbookId: 'everyday', limit: 3);
    await repository.createWordbook('初始词书', {
      items[0].sense.id,
      items[1].sense.id,
    });
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );

    await repository.updateWordbook(book.id, '  周末复习  ', {
      items[1].sense.id,
      items[2].sense.id,
    });

    final updated = (await repository.books()).singleWhere(
      (row) => row.id == book.id,
    );
    expect(updated.name, '周末复习');
    expect(await repository.senseIdsForWordbook(book.id), {
      items[1].sense.id,
      items[2].sense.id,
    });
    expect(
      (await repository.entries(wordbookId: book.id))
          .map((item) => item.sense.id)
          .toSet(),
      {items[1].sense.id, items[2].sense.id},
    );

    await expectLater(
      repository.updateWordbook('everyday', '改名', {items[0].sense.id}),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.deleteWordbook('everyday'),
      throwsA(isA<StateError>()),
    );
    await expectLater(
      repository.updateWordbook(book.id, '   ', {items[0].sense.id}),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateWordbook(book.id, '合法名称', {}),
      throwsArgumentError,
    );
    await expectLater(
      repository.updateWordbook(book.id, '合法名称', {999999999}),
      throwsArgumentError,
    );
    expect(
      (await repository.books()).singleWhere((row) => row.id == book.id).name,
      '周末复习',
    );
    expect(await repository.senseIdsForWordbook(book.id), {
      items[1].sense.id,
      items[2].sense.id,
    });
  });

  test('编辑自建词书写入失败会回滚名称和词义关联', () async {
    final items = await repository.entries(wordbookId: 'everyday', limit: 2);
    await repository.createWordbook('原始名称', {items[0].sense.id});
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );

    await db.customStatement(
      "CREATE TRIGGER reject_book_update BEFORE UPDATE ON wordbooks "
      "WHEN NEW.id = '${book.id}' "
      "BEGIN SELECT RAISE(ABORT, 'test book update failure'); END",
    );
    await expectLater(
      repository.updateWordbook(book.id, '新名称', {
        items[0].sense.id,
        items[1].sense.id,
      }),
      throwsA(isA<Exception>()),
    );
    expect(
      (await repository.books()).singleWhere((row) => row.id == book.id).name,
      '原始名称',
    );
    expect(await repository.senseIdsForWordbook(book.id), {items[0].sense.id});
    await db.customStatement('DROP TRIGGER reject_book_update');

    await db.customStatement(
      "CREATE TRIGGER reject_book_entry BEFORE INSERT ON wordbook_entries "
      "WHEN NEW.wordbook_id = '${book.id}' "
      "BEGIN SELECT RAISE(ABORT, 'test entry failure'); END",
    );
    await expectLater(
      repository.updateWordbook(book.id, '新名称', {
        items[0].sense.id,
        items[1].sense.id,
      }),
      throwsA(isA<Exception>()),
    );
    expect(
      (await repository.books()).singleWhere((row) => row.id == book.id).name,
      '原始名称',
    );
    expect(await repository.senseIdsForWordbook(book.id), {items[0].sense.id});
    await db.customStatement('DROP TRIGGER reject_book_entry');
  });

  test('删除当前自建词书清除学习选择，孤立已学词仍进入首页复习', () async {
    await db
        .into(db.words)
        .insert(
          WordsCompanion.insert(
            id: const Value(900001),
            spelling: 'orphanword',
          ),
        );
    await db
        .into(db.wordSenses)
        .insert(
          WordSensesCompanion.insert(
            id: const Value(900001),
            wordId: 900001,
            definition: '失去所有词书归属的词义',
            example: '',
          ),
        );
    await repository.createWordbook('孤立词书', {900001});
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    final item = (await repository.queue(wordbookId: book.id)).single;
    final card = await repository.score(
      item,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    now = card.due;
    await repository.setActiveWordbook(book.id);
    expect((await repository.activeWordbook())?.id, book.id);

    await repository.deleteWordbook(book.id);

    expect((await repository.books()).any((row) => row.id == book.id), isFalse);
    expect(await repository.activeWordbook(), isNull);
    expect(await repository.entries(search: 'orphanword'), hasLength(1));
    expect(await repository.history(), hasLength(1));
    expect(await db.select(db.memoryStates).get(), hasLength(1));

    final today = await repository.todayQueue();
    expect(today.map((item) => item.sense.id), contains(900001));
    expect(
      (await repository.queue(wordbookId: 'cet4')).map((item) => item.sense.id),
      isNot(contains(900001)),
    );
  });

  test('删除词书时清除学习选择的写入失败会整体回滚', () async {
    final items = await repository.entries(wordbookId: 'everyday', limit: 1);
    await repository.createWordbook('不可删除测试', {items.single.sense.id});
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await repository.setActiveWordbook(book.id);
    await db.customStatement(
      "CREATE TRIGGER reject_setting_delete BEFORE DELETE ON app_settings "
      "WHEN OLD.key = 'active_wordbook_id' "
      "BEGIN SELECT RAISE(ABORT, 'test setting failure'); END",
    );

    await expectLater(
      repository.deleteWordbook(book.id),
      throwsA(isA<Exception>()),
    );

    expect((await repository.books()).any((row) => row.id == book.id), isTrue);
    expect(await repository.senseIdsForWordbook(book.id), {
      items.single.sense.id,
    });
    expect((await repository.activeWordbook())?.id, book.id);
    await db.customStatement('DROP TRIGGER reject_setting_delete');
  });

  test('状态筛选在 SQLite 内完成并与条数、分页使用同一到期边界', () async {
    final items = await repository.entries(wordbookId: 'everyday', limit: 4);
    final futureItem = items[0];
    final dueItem = items[1];
    final unlearnedItem = items[2];
    final otherUserItem = items[3];

    await repository.score(
      futureItem,
      fsrs.Rating.easy,
      eventId: newReviewEventId(),
    );
    final dueCard = await repository.score(
      dueItem,
      fsrs.Rating.again,
      eventId: newReviewEventId(),
    );
    now = dueCard.due;

    final dueRow =
        await (db.select(db.memoryStates)..where(
              (row) =>
                  row.userId.equals(localUserId) &
                  row.wordSenseId.equals(dueItem.sense.id) &
                  row.trainingMode.equals(recognitionMode),
            ))
            .getSingle();
    await db
        .into(db.memoryStates)
        .insert(
          MemoryStatesCompanion.insert(
            userId: 'another-user',
            wordSenseId: otherUserItem.sense.id,
            trainingMode: recognitionMode,
            state: dueRow.state,
            step: Value(dueRow.step),
            stability: dueRow.stability,
            difficulty: dueRow.difficulty,
            due: dueRow.due,
            lastReview: dueRow.lastReview,
            schedulerVersion: dueRow.schedulerVersion,
            schedulerConfigJson: dueRow.schedulerConfigJson,
          ),
        );

    final all = await repository.entries(
      wordbookId: 'everyday',
      limit: 10,
      offset: 10,
    );
    final allCount = await repository.entryCount(wordbookId: 'everyday');
    final unlearned = await repository.entries(
      wordbookId: 'everyday',
      filter: EntryFilter.unlearned,
      limit: 10,
      offset: 10,
    );
    final unlearnedCount = await repository.entryCount(
      wordbookId: 'everyday',
      filter: EntryFilter.unlearned,
    );
    final learned = await repository.entries(
      wordbookId: 'everyday',
      filter: EntryFilter.learned,
      limit: 10,
    );
    final learnedCount = await repository.entryCount(
      wordbookId: 'everyday',
      filter: EntryFilter.learned,
    );
    final due = await repository.entries(
      wordbookId: 'everyday',
      filter: EntryFilter.due,
    );
    final dueCount = await repository.entryCount(
      wordbookId: 'everyday',
      filter: EntryFilter.due,
    );

    expect(allCount, 24);
    expect(all, hasLength(10));
    expect(unlearnedCount, allCount - 2);
    expect(unlearned, hasLength(10));
    expect(unlearned.every((item) => item.memory == null), isTrue);
    expect(learnedCount, 2);
    expect(learned, hasLength(2));
    expect(learned.every((item) => item.memory != null), isTrue);
    expect(dueCount, 1);
    expect(due.single.sense.id, dueItem.sense.id);
    expect(due.single.memory!.due, now.millisecondsSinceEpoch);
    expect(due.any((item) => item.sense.id == otherUserItem.sense.id), isFalse);
    expect(
      await repository.entries(
        filter: EntryFilter.unlearned,
        search: unlearnedItem.word.spelling,
      ),
      contains(
        isA<StudyItem>().having(
          (item) => item.sense.id,
          'sense id',
          unlearnedItem.sense.id,
        ),
      ),
    );
    expect(
      await repository.entryCount(
        filter: EntryFilter.due,
        wordbookId: 'everyday',
      ),
      1,
    );
    expect(
      await repository.entryCount(filter: EntryFilter.due, wordbookId: 'cet4'),
      0,
    );

    final firstPage = await repository.entries(
      filter: EntryFilter.unlearned,
      limit: 3,
    );
    final secondPage = await repository.entries(
      filter: EntryFilter.unlearned,
      offset: 3,
      limit: 3,
    );
    expect(
      firstPage
          .map((item) => item.sense.id)
          .toSet()
          .intersection(secondPage.map((item) => item.sense.id).toSet()),
      isEmpty,
    );
    expect(
      await repository.entryCount(
        filter: EntryFilter.unlearned,
        search: unlearnedItem.word.spelling,
      ),
      (await repository.entries(
        filter: EntryFilter.unlearned,
        search: unlearnedItem.word.spelling,
      )).length,
    );
    expect(
      await repository.entryCount(
        filter: EntryFilter.learned,
        search: 'zoology',
      ),
      await repository
          .entries(filter: EntryFilter.learned, search: 'zoology')
          .then((items) => items.length),
    );
  });

  test('队列状态按入口范围给出最近复习，并区分额度耗尽与未学词', () async {
    final everyday = (await repository.entries(
      wordbookId: 'everyday',
      limit: 1,
    )).single;
    await repository.setActiveWordbook('everyday');
    await repository.setDailyGoal(10);
    final card = await repository.score(
      everyday,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await repository.setDailyGoal(0);

    final home = await repository.queueStatus(todayPlan: true);
    expect(home.items, isEmpty);
    expect(home.dailyGoal, 0);
    expect(home.unlearnedCount, 23);
    expect(home.quotaExhausted, isTrue);
    expect(home.nextDue, card.due);
    expect(home.scopeLabel, '日常微光');

    final everydayBook = await repository.queueStatus(wordbookId: 'everyday');
    expect(everydayBook.items, isEmpty);
    expect(everydayBook.unlearnedCount, 23);
    expect(everydayBook.quotaExhausted, isTrue);
    expect(everydayBook.nextDue, card.due);

    final cet4 = await repository.queueStatus(wordbookId: 'cet4');
    expect(cet4.items, isEmpty);
    expect(cet4.unlearnedCount, 3849);
    expect(cet4.quotaExhausted, isTrue);
    expect(cet4.nextDue, isNull);

    final sense = await repository.queueStatus(senseId: everyday.sense.id);
    expect(sense.items, isEmpty);
    expect(sense.unlearnedCount, 0);
    expect(sense.quotaExhausted, isFalse);
    expect(sense.nextDue, card.due);

    await repository.createWordbook('已学单书', {everyday.sense.id});
    final custom = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    final customStatus = await repository.queueStatus(wordbookId: custom.id);
    expect(customStatus.items, isEmpty);
    expect(customStatus.unlearnedCount, 0);
    expect(customStatus.quotaExhausted, isFalse);
    expect(customStatus.nextDue, card.due);
  });

  test('新词额度未耗尽时队列状态保留新词，达到目标后明确标记耗尽', () async {
    await repository.setActiveWordbook('everyday');
    await repository.setDailyGoal(2);

    final initial = await repository.queueStatus(todayPlan: true);
    expect(initial.items, hasLength(2));
    expect(initial.unlearnedCount, 24);
    expect(initial.quotaExhausted, isFalse);
    expect(initial.dailyGoal, 2);
    expect(initial.learnedToday, 0);

    for (final item in initial.items) {
      await repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    final exhausted = await repository.queueStatus(todayPlan: true);
    expect(exhausted.items, isEmpty);
    expect(exhausted.unlearnedCount, 22);
    expect(exhausted.quotaExhausted, isTrue);
    expect(exhausted.dailyGoal, 2);
    expect(exhausted.learnedToday, 2);
  });

  test('导入词书复用精确词形与词义，保留原有进度和元数据', () async {
    final bloomSenses = await repository.entries(search: 'bloom');
    expect(bloomSenses.length, greaterThan(1));
    final existing = bloomSenses.first;
    await repository.score(
      existing,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final beforeMemory = await db.select(db.memoryStates).getSingle();
    final beforeWords = await db.select(db.words).get();
    final beforeSenses = await db.select(db.wordSenses).get();

    final result = await repository.importWordbook(
      name: '导入测试词书',
      entries: [
        WordbookEntryDraft(
          word: existing.word.spelling,
          definition: existing.sense.definition,
          phonetic: '/changed/',
          example: '不应覆盖已有例句',
        ),
        const WordbookEntryDraft(
          word: 'Bloom',
          definition: '新的大小写词形',
          phonetic: '/bluːm/',
        ),
        WordbookEntryDraft(
          word: existing.word.spelling,
          definition: '同一词形的第二个新释义',
        ),
        WordbookEntryDraft(
          word: existing.word.spelling,
          definition: existing.sense.definition,
        ),
      ],
    );

    expect(result.bookName, '导入测试词书');
    expect(result.importedEntries, 3);
    expect(result.newWords, 1);
    expect(result.newSenses, 2);
    expect(result.reusedSenses, 1);
    final book = (await repository.books()).singleWhere(
      (row) => row.id == result.bookId,
    );
    expect(book.isBuiltIn, isFalse);
    expect(await repository.senseIdsForWordbook(book.id), hasLength(3));
    final shared = await (db.select(
      db.wordSenses,
    )..where((row) => row.id.equals(existing.sense.id))).getSingle();
    expect(shared.example, existing.sense.example);
    expect(shared.phonetics, existing.sense.phonetics);
    expect(await db.select(db.memoryStates).getSingle(), beforeMemory);
    expect(await db.select(db.words).get(), hasLength(beforeWords.length + 1));
    expect(
      await db.select(db.wordSenses).get(),
      hasLength(beforeSenses.length + 2),
    );
    expect(
      (await (db.select(
        db.words,
      )..where((row) => row.spelling.equals('Bloom'))).getSingle()).id,
      isNot(existing.word.id),
    );
    expect(await repository.history(), hasLength(1));
  });

  test('导入任意写入失败会整体回滚词书、词条与关联', () async {
    final beforeBooks = (await db.select(db.wordbooks).get()).length;
    final beforeWords = (await db.select(db.words).get()).length;
    final beforeSenses = (await db.select(db.wordSenses).get()).length;
    await db.customStatement(
      "CREATE TRIGGER reject_import_entry BEFORE INSERT ON wordbook_entries "
      "BEGIN SELECT RAISE(ABORT, 'test import failure'); END",
    );
    await expectLater(
      repository.importWordbook(
        name: '失败词书',
        entries: const [
          WordbookEntryDraft(word: 'rollbackword', definition: '回滚释义'),
        ],
      ),
      throwsA(isA<Exception>()),
    );
    expect((await db.select(db.wordbooks).get()).length, beforeBooks);
    expect((await db.select(db.words).get()).length, beforeWords);
    expect((await db.select(db.wordSenses).get()).length, beforeSenses);
    expect(
      (await repository.books()).any((book) => book.name == '失败词书'),
      isFalse,
    );
    await db.customStatement('DROP TRIGGER reject_import_entry');
  });

  test('纯单词列表补全本地全部词义，缺失单词明确报错', () async {
    final bloomSenses = await repository.entries(search: 'bloom');
    final resolution = await repository.resolveWordOnlyEntries([
      const WordOnlyEntry(word: 'bloom', line: 1),
      const WordOnlyEntry(word: 'missing-local-word', line: 2),
    ]);
    expect(resolution.entries, hasLength(bloomSenses.length));
    expect(
      resolution.entries.map((entry) => entry.definition).toSet(),
      bloomSenses.map((item) => item.sense.definition).toSet(),
    );
    expect(resolution.errorRows, 1);
    expect(resolution.issues.single.line, 2);
    expect(resolution.issues.single.message, contains('本地词库没有'));
    expect(
      resolution.entries.any((entry) => entry.word == 'missing-local-word'),
      isFalse,
    );
  });

  test('单本词书导出只含词条内容，导出再导入不重复写入', () async {
    final source = (await repository.entries(search: 'bloom')).take(2).toList();
    final first = await repository.importWordbook(
      name: '导出源',
      entries: source
          .map(
            (item) => WordbookEntryDraft(
              word: item.word.spelling,
              definition: item.sense.definition,
              phonetic: item.sense.phonetics,
              example: item.sense.example,
            ),
          )
          .toList(),
    );
    final exported = await repository.exportWordbookEntries(first.bookId);
    expect(exported, hasLength(source.length));
    final csv = exportWordbookCsv('导出源', exported);
    final parsed = parseWordbookBytes(
      Uint8List.fromList(utf8.encode(csv)),
      fileName: '导出源.csv',
    );
    expect(parsed.errorRows, 0);
    final wordsBefore = (await db.select(db.words).get()).length;
    final sensesBefore = (await db.select(db.wordSenses).get()).length;
    final second = await repository.importWordbook(
      name: '导出回读',
      entries: parsed.entries,
    );
    expect(second.newWords, 0);
    expect(second.newSenses, 0);
    expect(second.reusedSenses, source.length);
    expect((await db.select(db.words).get()).length, wordsBefore);
    expect((await db.select(db.wordSenses).get()).length, sensesBefore);
    expect(
      await repository.senseIdsForWordbook(second.bookId),
      hasLength(source.length),
    );
  });

  test('撤销首学删除记忆状态后可用新事件重新学习', () async {
    final item = (await repository.queue()).first;
    final wordsBefore = (await db.select(db.words).get()).length;
    final sensesBefore = (await db.select(db.wordSenses).get()).length;
    final firstEvent = newReviewEventId();
    await repository.score(item, fsrs.Rating.good, eventId: firstEvent);
    final afterUndo = await repository.undoLastReview(firstEvent);
    expect(afterUndo.firstLearning, isTrue);
    expect(await repository.history(), isEmpty);
    expect(
      await (db.select(db.memoryStates)
            ..where((row) => row.wordSenseId.equals(item.sense.id)))
          .getSingleOrNull(),
      isNull,
    );
    expect((await db.select(db.words).get()).length, wordsBefore);
    expect((await db.select(db.wordSenses).get()).length, sensesBefore);

    final restored = await repository.itemBySenseId(item.sense.id);
    expect(restored?.memory, isNull);
    final retryEvent = newReviewEventId();
    await repository.score(restored!, fsrs.Rating.good, eventId: retryEvent);
    expect(await repository.history(), hasLength(1));
    expect((await repository.history()).single.id, retryEvent);
    await expectLater(
      repository.undoLastReview(firstEvent),
      throwsA(isA<UndoUnavailable>()),
    );
  });

  test('撤销复习恢复 before 状态，且无法再撤销更早评分', () async {
    final item = (await repository.queue()).first;
    final firstEvent = newReviewEventId();
    final firstCard = await repository.score(
      item,
      fsrs.Rating.good,
      eventId: firstEvent,
    );
    now = firstCard.due;
    final beforeSecond = await repository.itemBySenseId(item.sense.id);
    final secondEvent = newReviewEventId();
    await repository.score(
      beforeSecond!,
      fsrs.Rating.easy,
      eventId: secondEvent,
    );
    final secondRow = await (db.select(
      db.memoryStates,
    )..where((row) => row.wordSenseId.equals(item.sense.id))).getSingle();
    final result = await repository.undoLastReview(secondEvent);
    expect(result.firstLearning, isFalse);
    final restored = await (db.select(
      db.memoryStates,
    )..where((row) => row.wordSenseId.equals(item.sense.id))).getSingle();
    expect(restored.due, beforeSecond.memory!.due);
    expect(restored.stability, beforeSecond.memory!.stability);
    expect(restored.difficulty, beforeSecond.memory!.difficulty);
    expect(restored.state, beforeSecond.memory!.state);
    expect(restored.step, beforeSecond.memory!.step);
    expect(restored.lastReview, beforeSecond.memory!.lastReview);
    expect(mapHistoryIds(await repository.history()), [firstEvent]);
    expect(secondRow.due, isNot(restored.due));
    await expectLater(
      repository.undoLastReview(firstEvent),
      throwsA(isA<UndoUnavailable>()),
    );
  });

  test('同毫秒跨词评分只允许撤销实际最新提交，单级撤销后旧请求不复活', () async {
    final items = await repository.queue();
    final eventA = newReviewEventId();
    final eventB = newReviewEventId();
    await repository.score(items[0], fsrs.Rating.good, eventId: eventA);
    await repository.score(items[1], fsrs.Rating.good, eventId: eventB);
    await expectLater(
      repository.undoLastReview(eventA),
      throwsA(isA<UndoUnavailable>()),
    );
    expect(await repository.history(), hasLength(2));

    await repository.undoLastReview(eventB);
    expect(await repository.history(), hasLength(1));
    expect((await repository.history()).single.id, eventA);
    await expectLater(
      repository.undoLastReview(eventA),
      throwsA(isA<UndoUnavailable>()),
    );
    await expectLater(
      repository.undoLastReview(eventB),
      throwsA(isA<UndoUnavailable>()),
    );
    expect(await repository.history(), hasLength(1));
  });

  test('撤销事务失败整体回滚，修复后可重试', () async {
    final item = (await repository.queue()).first;
    final eventId = newReviewEventId();
    await repository.score(item, fsrs.Rating.good, eventId: eventId);
    await db.customStatement(
      "CREATE TRIGGER reject_undo_event BEFORE DELETE ON review_events "
      "BEGIN SELECT RAISE(ABORT, 'test undo failure'); END",
    );
    await expectLater(
      repository.undoLastReview(eventId),
      throwsA(isA<Exception>()),
    );
    expect(await repository.history(), hasLength(1));
    expect(
      await (db.select(db.memoryStates)
            ..where((row) => row.wordSenseId.equals(item.sense.id)))
          .getSingleOrNull(),
      isNotNull,
    );
    await db.customStatement('DROP TRIGGER reject_undo_event');
    final result = await repository.undoLastReview(eventId);
    expect(result.firstLearning, isTrue);
    expect(await repository.history(), isEmpty);
  });

  test('原样恢复备份会使恢复前的撤销资格失效', () async {
    final item = (await repository.queue()).first;
    final eventId = newReviewEventId();
    await repository.score(item, fsrs.Rating.good, eventId: eventId);
    final codec = BackupCodec(
      db,
      engine,
      nowUtc: () => now,
      onRestored: repository.invalidateUndoEligibility,
    );
    final backup = await codec.export();
    await codec.restore(backup);
    expect(await repository.history(), hasLength(1));
    await expectLater(
      repository.undoLastReview(eventId),
      throwsA(isA<UndoUnavailable>()),
    );
    expect(await repository.history(), hasLength(1));
  });

  test('撤销后的状态仍能通过完整备份导出与语义恢复', () async {
    final item = (await repository.queue()).first;
    final eventId = newReviewEventId();
    await repository.score(item, fsrs.Rating.good, eventId: eventId);
    await repository.undoLastReview(eventId);
    final codec = BackupCodec(db, engine, nowUtc: () => now);
    final backup = await codec.export();
    await codec.restore(backup);
    expect(await repository.history(), isEmpty);
    expect(
      await (db.select(db.memoryStates)
            ..where((row) => row.wordSenseId.equals(item.sense.id)))
          .getSingleOrNull(),
      isNull,
    );
  });

  test('本轮小结只统计真实存在且未撤销的评分', () async {
    final items = await repository.queue();
    final event1 = newReviewEventId();
    final event2 = newReviewEventId();
    final event3 = newReviewEventId();
    await repository.score(items[0], fsrs.Rating.good, eventId: event1);
    final firstCard = await repository.itemBySenseId(items[0].sense.id);
    now = DateTime.fromMillisecondsSinceEpoch(
      firstCard!.memory!.due,
      isUtc: true,
    );
    await repository.score(firstCard, fsrs.Rating.hard, eventId: event2);
    await repository.score(items[1], fsrs.Rating.easy, eventId: event3);
    var summary = await repository.sessionSummary([event1, event2, event3]);
    expect(summary.ratingCount, 3);
    expect(summary.firstLearnedSenses, 2);
    expect(summary.reviewCount, 1);
    expect(summary.goodEasyCount, 2);
    expect(summary.successRate, closeTo(2 / 3, 1e-9));

    await repository.undoLastReview(event3);
    summary = await repository.sessionSummary([event1, event2, event3]);
    expect(summary.ratingCount, 2);
    expect(summary.firstLearnedSenses, 1);
    expect(summary.reviewCount, 1);
    expect(summary.goodEasyCount, 1);
    expect(
      await repository
          .sessionSummary(const [])
          .then((value) => value.successRate),
      isNull,
    );
  });

  test('未来 7 天预测按本地固定 offset 分桶，包含孤立词且不重复', () async {
    final calendar = LocalCalendar(fixedOffset: const Duration(hours: 8));
    final forecastRepo = StudyRepository(
      db,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(forecastRepo.dispose);
    now = DateTime.utc(2026, 11, 27, 12);
    await repository.setDailyGoal(100);
    final items = await repository.entries(wordbookId: 'everyday', limit: 6);
    for (final item in items) {
      await repository.score(
        item,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
    }
    final nextMidnight = calendar.nextMidnightUtc(now);
    final day7Start = calendar.midnightUtc(now, daysAhead: 7);
    final dues = [
      now.subtract(const Duration(minutes: 1)),
      now,
      now.add(const Duration(minutes: 1)),
      nextMidnight,
      nextMidnight.add(const Duration(hours: 1)),
      day7Start,
    ];
    for (var i = 0; i < items.length; i++) {
      await (db.update(
        db.memoryStates,
      )..where((row) => row.wordSenseId.equals(items[i].sense.id))).write(
        MemoryStatesCompanion(due: Value(dues[i].millisecondsSinceEpoch)),
      );
    }
    // 删除一个词的词书关联，验证孤立已学词仍进入预测。
    await (db.delete(
      db.wordbookEntries,
    )..where((row) => row.wordSenseId.equals(items[3].sense.id))).go();
    final forecast = await forecastRepo.reviewForecast();
    expect(forecast.dueNow, 2);
    expect(forecast.days, hasLength(7));
    expect(forecast.days[0].count, 1);
    expect(forecast.days[1].count, 2);
    expect(forecast.sevenDayTotal, 3);
    expect(forecast.days.last.count, 0);
  });

  test('history 的 limit 取最新 N 条并按时间升序，默认仍返回全量', () async {
    final first = (await repository.queue(wordbookId: 'everyday')).first;
    var current = first;
    for (var i = 0; i < 25; i++) {
      final card = await repository.score(
        current,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
      now = card.due;
      current = (await repository.itemBySenseId(first.sense.id))!;
    }

    final all = await repository.history(senseId: first.sense.id);
    expect(all, hasLength(25));
    final limited = await repository.history(
      senseId: first.sense.id,
      limit: 20,
    );
    expect(limited, hasLength(20));
    expect(mapHistoryIds(limited), mapHistoryIds(all.skip(5).toList()));
    for (var i = 0; i < limited.length - 1; i++) {
      expect(
        limited[i].reviewedAt,
        lessThanOrEqualTo(limited[i + 1].reviewedAt),
      );
    }
    expect((await repository.stats(asOf: now)).total, 25);
  });

  test('活动摘要按本地日历窗口聚合评分、学习天数与成功率', () async {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: 8));
    now = DateTime.utc(2026, 1, 1, 15, 59, 59, 999);
    final activityRepo = StudyRepository(
      db,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(activityRepo.dispose);
    final start = calendar.midnightUtc(now, daysAhead: -6);
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: start.subtract(const Duration(milliseconds: 1)),
      rating: 'easy',
    );
    await insertReviewRecord(db, engine, reviewedAt: start, rating: 'good');
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: start.add(const Duration(hours: 1)),
      rating: 'hard',
    );
    await insertReviewRecord(db, engine, reviewedAt: now, rating: 'easy');
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: now.add(const Duration(milliseconds: 1)),
      rating: 'good',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: now,
      rating: 'good',
      userId: 'other-user',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: now,
      rating: 'good',
      trainingMode: 'spelling',
    );

    final activity = await activityRepo.reviewActivity(days: 7, asOf: now);
    expect(activity.ratingCount, 3);
    expect(activity.goodEasyCount, 2);
    expect(activity.activeDays, 2);
    expect(activity.successRate, closeTo(2 / 3, 1e-9));
    expect(activity.dayCounts, hasLength(7));
    expect(activity.dayCounts.first.localDate, DateTime.utc(2025, 12, 26));
    expect(activity.dayCounts.first.count, 2);
    expect(activity.dayCounts[1].count, 0);
    expect(activity.dayCounts.last.localDate, DateTime.utc(2026, 1, 1));
    expect(activity.dayCounts.last.count, 1);

    final stats = await activityRepo.stats(asOf: now);
    expect(stats.today, 1);
    // 累计数保留未来异常记录；近期活动与连击只使用截至 asOf 的窗口。
    expect(stats.total, 5);
    expect(stats.successRate, closeTo(4 / 5, 1e-9));
    expect(stats.dailyCounts.first, 2);
    expect(stats.dailyCounts.last, 1);
    expect(stats.recentSuccessRate, closeTo(2 / 3, 1e-9));
    expect(stats.streak, 1);
  });

  test('空白活动返回零值与空成功率', () async {
    final activity = await repository.reviewActivity(days: 30, asOf: now);
    expect(activity.ratingCount, 0);
    expect(activity.goodEasyCount, 0);
    expect(activity.activeDays, 0);
    expect(activity.successRate, isNull);
    expect(activity.dayCounts, hasLength(30));
    expect(activity.dayCounts.every((day) => day.count == 0), isTrue);

    final stats = await repository.stats(asOf: now);
    expect(stats.total, 0);
    expect(stats.today, 0);
    expect(stats.successRate, 0);
    expect(stats.recentSuccessRate, 0);
    expect(stats.streak, 0);
    expect(stats.dailyCounts, List<int>.filled(7, 0));
  });

  test('近 90 天窗口跨月跨年并支持负本地 offset', () async {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: -5));
    now = DateTime.utc(2026, 1, 1, 6);
    final activityRepo = StudyRepository(
      db,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(activityRepo.dispose);
    final start = calendar.midnightUtc(now, daysAhead: -89);
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: start.subtract(const Duration(milliseconds: 1)),
      rating: 'good',
    );
    await insertReviewRecord(db, engine, reviewedAt: start, rating: 'good');
    await insertReviewRecord(db, engine, reviewedAt: now, rating: 'hard');

    final activity = await activityRepo.reviewActivity(days: 90, asOf: now);
    expect(activity.ratingCount, 2);
    expect(activity.goodEasyCount, 1);
    expect(activity.activeDays, 2);
    expect(activity.dayCounts, hasLength(90));
    expect(activity.dayCounts.first.localDate, DateTime.utc(2025, 10, 4));
    expect(activity.dayCounts.first.count, 1);
    expect(activity.dayCounts.last.localDate, DateTime.utc(2026, 1, 1));
    expect(activity.dayCounts.last.count, 1);
  });

  test('连续学习按精简时间戳扫描，跨月重复与未来记录不影响', () async {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: 8));
    now = DateTime.utc(2026, 1, 1, 4);
    final streakRepo = StudyRepository(
      db,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(streakRepo.dispose);
    for (var i = 0; i < 300; i++) {
      final reviewedAt = calendar
          .midnightUtc(now, daysAhead: -i)
          .add(const Duration(hours: 10));
      await insertReviewRecord(
        db,
        engine,
        reviewedAt: reviewedAt,
        rating: 'good',
      );
    }
    await insertReviewRecord(db, engine, reviewedAt: now, rating: 'easy');
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: calendar
          .midnightUtc(now, daysAhead: 1)
          .add(const Duration(hours: 10)),
      rating: 'good',
    );

    final stats = await streakRepo.stats(asOf: now);
    expect(stats.streak, 300);
  });

  test('连续学习支持昨天延续，遇断档停止并忽略同日重复', () async {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: 8));
    now = DateTime.utc(2026, 1, 1, 4);
    final streakRepo = StudyRepository(
      db,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(streakRepo.dispose);
    final yesterday = calendar.midnightUtc(now, daysAhead: -1);
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: yesterday.add(const Duration(hours: 9)),
      rating: 'good',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: yesterday.add(const Duration(hours: 10)),
      rating: 'easy',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: calendar
          .midnightUtc(now, daysAhead: -2)
          .add(const Duration(hours: 10)),
      rating: 'good',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: calendar
          .midnightUtc(now, daysAhead: -4)
          .add(const Duration(hours: 10)),
      rating: 'good',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: calendar
          .midnightUtc(now, daysAhead: 1)
          .add(const Duration(hours: 9)),
      rating: 'good',
    );

    final stats = await streakRepo.stats(asOf: now);
    expect(stats.streak, 2);
  });

  test('统计过滤其他用户和训练方式，撤销后活动与连击归零', () async {
    final item = (await repository.queue()).first;
    final eventId = newReviewEventId();
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: now,
      rating: 'good',
      userId: 'other-user',
    );
    await insertReviewRecord(
      db,
      engine,
      reviewedAt: now,
      rating: 'good',
      trainingMode: 'spelling',
    );
    await repository.score(item, fsrs.Rating.good, eventId: eventId);
    var stats = await repository.stats(asOf: now);
    expect(stats.total, 1);
    expect(stats.today, 1);
    expect(stats.streak, 1);
    var activity = await repository.reviewActivity(days: 7, asOf: now);
    expect(activity.ratingCount, 1);
    expect(activity.activeDays, 1);
    expect(activity.successRate, 1);

    await repository.undoLastReview(eventId);
    stats = await repository.stats(asOf: now);
    activity = await repository.reviewActivity(days: 7, asOf: now);
    expect(stats.total, 0);
    expect(stats.today, 0);
    expect(stats.streak, 0);
    expect(activity.ratingCount, 0);
    expect(activity.activeDays, 0);
    expect(activity.successRate, isNull);
  });

  test('并发写入时活动汇总与每日合计保持一致', () async {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: 8));
    now = DateTime.utc(2026, 1, 1, 4);
    final activityRepo = StudyRepository(
      db,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(activityRepo.dispose);
    final writes = [
      for (var i = 0; i < 40; i++)
        insertReviewRecord(
          db,
          engine,
          reviewedAt: calendar
              .midnightUtc(now, daysAhead: -(i % 20))
              .add(Duration(hours: 10 + i % 3)),
          rating: i % 3 == 0 ? 'hard' : 'good',
        ),
    ];
    final reads = [
      for (var i = 0; i < 8; i++)
        activityRepo.reviewActivity(days: 30, asOf: now),
    ];
    await Future.wait(writes);
    for (final activity in await Future.wait(reads)) {
      expect(
        activity.ratingCount,
        activity.dayCounts.fold<int>(0, (sum, day) => sum + day.count),
      );
      expect(activity.goodEasyCount, lessThanOrEqualTo(activity.ratingCount));
    }
  });

  test('活动汇总在单次事务快照中保持一致', () async {
    const calendar = LocalCalendar(fixedOffset: Duration(hours: 8));
    now = DateTime.utc(2026, 1, 1, 4);
    final interceptor = _ActivitySnapshotInterceptor();
    final snapshotDb = AppDatabase(
      NativeDatabase.memory().interceptWith(interceptor),
    );
    await snapshotDb.ensureSeeded(
      schedulerVersion: engine.schedulerVersion,
      configurationJson: engine.configurationJson,
    );
    final snapshotRepo = StudyRepository(
      snapshotDb,
      engine,
      nowUtc: () => now,
      calendar: calendar,
    );
    addTearDown(() async {
      await snapshotRepo.dispose();
      await snapshotDb.close();
    });

    final read = snapshotRepo.reviewActivity(days: 30, asOf: now);
    await interceptor.firstSelectReturned.future;
    final insert = insertReviewRecord(
      snapshotDb,
      engine,
      reviewedAt: now,
      rating: 'good',
    );
    await Future<void>.delayed(Duration.zero);
    interceptor.release.complete();
    final activity = await read;
    await insert;

    expect(activity.ratingCount, 0);
    expect(activity.dayCounts.fold<int>(0, (sum, day) => sum + day.count), 0);
    expect(
      (await snapshotRepo.reviewActivity(days: 30, asOf: now)).ratingCount,
      1,
    );
  });
}

Future<void> insertReviewRecord(
  AppDatabase db,
  FsrsEngine engine, {
  required DateTime reviewedAt,
  required String rating,
  String userId = localUserId,
  String trainingMode = recognitionMode,
}) => db
    .into(db.reviewEvents)
    .insert(
      ReviewEventsCompanion.insert(
        id: newReviewEventId(),
        userId: userId,
        wordSenseId: 1,
        trainingMode: trainingMode,
        reviewedAt: reviewedAt.millisecondsSinceEpoch,
        rating: rating,
        schedulerVersion: engine.schedulerVersion,
        beforeJson: '{}',
        afterJson: '{}',
      ),
    );

class _ActivitySnapshotInterceptor extends QueryInterceptor {
  final firstSelectReturned = Completer<void>();
  final release = Completer<void>();
  bool _paused = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!_paused &&
        statement.contains('COUNT(*) AS ratings') &&
        statement.contains('review_events')) {
      _paused = true;
      firstSelectReturned.complete();
      await release.future;
    }
    return result;
  }
}

List<String> mapHistoryIds(List<ReviewEvent> events) =>
    events.map((event) => event.id).toList();
