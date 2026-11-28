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
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late FsrsEngine engine;
  late StudyRepository repository;
  late BackupCodec codec;
  final now = DateTime.utc(2026, 11, 27, 8, 0, 0, 0, 123);
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    engine = FsrsEngine();
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

  test('备份预检返回已校验摘要，且不写库、不触发恢复回调', () async {
    var restored = 0;
    final previewCodec = BackupCodec(
      db,
      engine,
      nowUtc: () => now,
      onRestored: () => restored++,
    );
    final source = await previewCodec.export();
    final before = await previewCodec.export();
    final root = jsonDecode(source) as Map<String, dynamic>;
    final preview = await previewCodec.preview(source);
    expect(
      preview.exportedAt.millisecondsSinceEpoch,
      now.millisecondsSinceEpoch,
    );
    expect(preview.wordbookCount, (root['wordbooks'] as List).length);
    expect(preview.senseCount, (root['wordSenses'] as List).length);
    expect(preview.learnedSenseCount, 0);
    expect(preview.reviewEventCount, 0);
    expect(preview.dailyGoal, 10);
    expect(restored, 0);
    expect(await previewCodec.export(), before);

    final item = (await repository.queue()).first;
    await repository.setDailyGoal(3);
    await repository.score(item, fsrs.Rating.good, eventId: newReviewEventId());
    final changed = await previewCodec.export();
    final changedPreview = await previewCodec.preview(changed);
    expect(changedPreview.learnedSenseCount, 1);
    expect(changedPreview.reviewEventCount, 1);
    expect(changedPreview.dailyGoal, 3);
    expect(restored, 0);
    expect(await previewCodec.export(), changed);
  });

  test('备份预检不使现有撤销资格失效', () async {
    final item = (await repository.queue()).first;
    final eventId = newReviewEventId();
    await repository.score(item, fsrs.Rating.good, eventId: eventId);
    final previewCodec = BackupCodec(
      db,
      engine,
      nowUtc: () => now,
      onRestored: repository.invalidateUndoEligibility,
    );
    await previewCodec.preview(await previewCodec.export());
    expect(await repository.history(), hasLength(1));
    final result = await repository.undoLastReview(eventId);
    expect(result.firstLearning, isTrue);
    expect(await repository.history(), isEmpty);
  });

  test('备份预检拒绝损坏文件且不改库', () async {
    final before = await codec.export();
    await expectLater(
      codec.preview('{"format":"lexi_loop_backup","schemaVersion":1}'),
      throwsFormatException,
    );
    expect(await codec.export(), before);
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
    '词义外键不存在': (root) => root['wordSenses'][0]['wordId'] = 999999999,
    '不支持的用户': (root) => root['memoryStates'][0]['userId'] = 'another-user',
    '不支持的训练模式': (root) => root['memoryStates'][0]['trainingMode'] = 'spelling',
    '非法学习步骤': (root) => root['memoryStates'][0]['step'] = 9,
    '非法难度': (root) => root['memoryStates'][0]['difficulty'] = 11.0,
    '微秒而非毫秒字段': (root) => root['memoryStates'][0]['lastReview'] *= 1000,
    '缺少历史': (root) => root['reviewEvents'] = [],
    '设置不完整': (root) => root['appSettings'] = [],
    '学习词书不存在': (root) => (root['appSettings'] as List).add({
      'key': 'active_wordbook_id',
      'value': 'missing-custom-book',
    }),
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

  test('旧版备份恢复后补齐考试词书并保留旧词义、目标和评分', () async {
    await repository.score(
      (await repository.queue()).first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    await repository.setDailyGoal(4);
    final original = jsonDecode(await codec.export()) as Map<String, dynamic>;
    original['words'] = (original['words'] as List)
        .where((row) => row['id'] <= 24)
        .toList();
    original['wordSenses'] = (original['wordSenses'] as List)
        .where((row) => row['id'] <= 24)
        .toList();
    original['wordbooks'] = (original['wordbooks'] as List)
        .where((row) => row['id'] == 'everyday')
        .toList();
    original['wordbookEntries'] = (original['wordbookEntries'] as List)
        .where((row) => row['wordbookId'] == 'everyday')
        .toList();
    original['appSettings'] = (original['appSettings'] as List)
        .where((row) => row['key'] != 'exam_catalog_version')
        .toList();
    await repository.setActiveWordbook('cet6');
    await codec.restore(jsonEncode(original));
    expect(await repository.activeWordbook(), isNull);
    expect(await repository.entries(wordbookId: 'cet4'), hasLength(3849));
    expect(await repository.entries(wordbookId: 'cet6'), hasLength(5407));
    expect(await repository.entries(wordbookId: 'tem8'), hasLength(12694));
    expect(await repository.entries(wordbookId: 'ky'), hasLength(4801));
    expect(await repository.dailyGoal(), 4);
    expect(await repository.history(), hasLength(1));
  });

  test('考试词义组成的自建词书恢复后保留共享进度和内容', () async {
    final items = await repository.entries(wordbookId: 'cet4', limit: 2);
    await repository.createWordbook(
      '考试错题本',
      items.map((item) => item.sense.id).toSet(),
    );
    final book = (await repository.books()).singleWhere(
      (book) => !book.isBuiltIn,
    );
    await repository.setActiveWordbook(book.id);
    await repository.score(
      items.first,
      fsrs.Rating.good,
      eventId: newReviewEventId(),
    );
    final source = await codec.export();
    await repository.setDailyGoal(0);
    await codec.restore(source);
    expect((await repository.activeWordbook())?.id, book.id);
    final restored = await repository.entries(wordbookId: book.id);
    expect(
      restored.map((item) => item.sense.id),
      items.map((item) => item.sense.id),
    );
    expect(restored.first.memory, isNotNull);
    expect(
      (await repository.entries(
        wordbookId: 'cet6',
        wordId: items.first.word.id,
      )).single.memory,
      restored.first.memory,
    );
    expect(await codec.export(), source);
  });

  test('恢复遇到考试词书编号冲突时完整回滚且说明冲突', () async {
    final source = await codec.export();
    final changed = jsonDecode(source) as Map<String, dynamic>;
    final cet4 = (changed['wordbooks'] as List).singleWhere(
      (book) => book['id'] == 'cet4',
    );
    cet4['isBuiltIn'] = false;
    cet4['name'] = '自定义四级';
    await expectLater(
      codec.restore(jsonEncode(changed)),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('冲突'),
        ),
      ),
    );
    expect(await codec.export(), source);
  });

  test('恢复文件包含安装标记但遗漏考试词书时仍补齐内置内容', () async {
    await repository.setActiveWordbook('ky');
    final backup = jsonDecode(await codec.export()) as Map<String, dynamic>;
    (backup['wordbooks'] as List).removeWhere((row) => row['id'] == 'ky');
    (backup['wordbookEntries'] as List).removeWhere(
      (row) => row['wordbookId'] == 'ky',
    );
    await codec.restore(jsonEncode(backup));
    expect((await repository.activeWordbook())?.id, 'ky');
    expect(await repository.entries(wordbookId: 'ky'), hasLength(4801));
    expect(await repository.entryCount(), 13165);
  });
}
