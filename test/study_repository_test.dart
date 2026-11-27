import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/data/study_repository.dart';
import 'package:lexi_loop/domain/fsrs_engine.dart';

void main() {
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
    expect(await db.select(db.words).get(), hasLength(24));
  });
}
