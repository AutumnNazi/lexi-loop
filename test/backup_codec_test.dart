import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:lexi_loop/core/ids.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/data/backup_codec.dart';
import 'package:lexi_loop/data/study_repository.dart';
import 'package:lexi_loop/domain/fsrs_engine.dart';

void main() {
  late AppDatabase db;
  late StudyRepository repository;
  late BackupCodec codec;
  final now = DateTime.utc(2026, 11, 27, 8, 0, 0, 0, 123);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final engine = FsrsEngine();
    repository = StudyRepository(db, engine, nowUtc: () => now);
    codec = BackupCodec(db, engine, nowUtc: () => now);
    await db.ensureSeeded(
      schedulerVersion: engine.schedulerVersion,
      configurationJson: engine.configurationJson,
    );
  });
  tearDown(() async {
    await repository.dispose();
    await db.close();
  });

  test('恢复写入中途失败时，清空和已插入的内容一起回滚', () async {
    final backup = await codec.export();
    await repository.setDailyGoal(3);
    await repository.score(
      (await repository.queue()).first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final original = await codec.export();
    await db.customStatement(
      "CREATE TRIGGER reject_settings BEFORE INSERT ON app_settings BEGIN SELECT RAISE(ABORT, 'test restore failure'); END",
    );
    await expectLater(codec.restore(backup), throwsA(isA<Exception>()));
    expect(await codec.export(), original);
  });

  test('多步评分历史可以恢复，丢失中间历史则拒绝', () async {
    var instant = now;
    final engine = FsrsEngine();
    final repo = StudyRepository(db, engine, nowUtc: () => instant);
    final lateCodec = BackupCodec(db, engine, nowUtc: () => instant);
    try {
      await repo.setDailyGoal(1);
      for (var i = 0; i < 3; i++) {
        final card = await repo.score(
          (await repo.queue()).first,
          fsrs.Rating.good,
          eventId: newReviewEventId(),
        );
        instant = card.due;
      }
      final original = await lateCodec.export();
      await lateCodec.restore(original);
      final changed = jsonDecode(original);
      changed['reviewEvents'].removeAt(1);
      await expectLater(
        lateCodec.restore(jsonEncode(changed)),
        throwsFormatException,
      );
      expect(await lateCodec.export(), original);
    } finally {
      await repo.dispose();
    }
  });

  final mutations = <String, void Function(Map<String, dynamic>)>{
    '未知备份版本': (root) => root['schemaVersion'] = 2,
    '字段类型错误': (root) => root['words'][0]['id'] = 'one',
    '重复单词': (root) =>
        root['words'][1]['spelling'] = root['words'][0]['spelling'],
    '词义外键不存在': (root) => root['wordSenses'][0]['wordId'] = 999,
    '不支持的用户': (root) => root['memoryStates'][0]['userId'] = 'another-user',
    '不支持的训练模式': (root) => root['memoryStates'][0]['trainingMode'] = 'spelling',
    '非法学习步骤': (root) => root['memoryStates'][0]['step'] = 9,
    '非法难度': (root) => root['memoryStates'][0]['difficulty'] = 11.0,
    '微秒而非毫秒字段': (root) => root['memoryStates'][0]['lastReview'] *= 1000,
    '缺少历史': (root) => root['reviewEvents'] = [],
    '设置不完整': (root) => root['appSettings'] = [],
  };
  for (final mutation in mutations.entries) {
    test('备份校验拒绝${mutation.key}且不动原数据', () async {
      await repository.score(
        (await repository.queue()).first,
        fsrs.Rating.good,
        eventId: newReviewEventId(),
      );
      final original = await codec.export();
      final changed = jsonDecode(original) as Map<String, dynamic>;
      mutation.value(changed);
      await expectLater(
        codec.restore(jsonEncode(changed)),
        throwsFormatException,
      );
      expect(await codec.export(), original);
    });
  }

  test('评分快照被篡改时拒绝恢复，即使 JSON 仍然合法', () async {
    await repository.score(
      (await repository.queue()).first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final original = await codec.export();
    final changed = jsonDecode(original) as Map<String, dynamic>;
    final after = jsonDecode(changed['reviewEvents'][0]['afterJson']);
    after['due'] += 1;
    changed['reviewEvents'][0]['afterJson'] = jsonEncode(after);
    await expectLater(
      codec.restore(jsonEncode(changed)),
      throwsFormatException,
    );
    expect(await codec.export(), original);
  });

  test('调度参数被更改时拒绝恢复并保留原进度', () async {
    await repository.score(
      (await repository.queue()).first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final original = await codec.export();
    final changed = jsonDecode(original) as Map<String, dynamic>;
    final config = jsonDecode(
      changed['memoryStates'][0]['schedulerConfigJson'],
    );
    config['parameters'][0] = 9.0;
    changed['memoryStates'][0]['schedulerConfigJson'] = jsonEncode(config);
    await expectLater(
      codec.restore(jsonEncode(changed)),
      throwsFormatException,
    );
    expect(await codec.export(), original);
  });

  test('完整备份恢复往返保留内容、评分与毫秒时间', () async {
    final item = (await repository.queue()).first;
    await repository.score(item, fsrs.Rating.good, eventId: newReviewEventId());
    final source = await codec.export();
    expect(jsonDecode(source)['format'], 'lexi_loop_backup');
    await repository.setDailyGoal(2);
    await codec.restore(source);
    expect(await repository.dailyGoal(), 10);
    expect(await codec.export(), source);
    final state = (await db.select(db.memoryStates).get()).single;
    expect(state.lastReview, now.millisecondsSinceEpoch);
  });
}
