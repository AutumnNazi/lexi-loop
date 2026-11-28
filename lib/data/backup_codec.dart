import 'dart:convert';

import 'package:fsrs/fsrs.dart' as fsrs;

import '../core/clock.dart';
import '../core/ids.dart';
import '../domain/fsrs_engine.dart';
import 'app_database.dart';
import 'seed_catalog.dart';

class BackupCodec {
  BackupCodec(
    this.db,
    this.engine, {
    this.nowUtc = systemUtcNow,
    this.onRestored,
  });
  final AppDatabase db;
  final FsrsEngine engine;
  final UtcClock nowUtc;
  final void Function()? onRestored;

  Future<String> export() => db.transaction(
    () async => jsonEncode({
      'format': 'lexi_loop_backup',
      'schemaVersion': 1,
      'exportedAt': utcMilliseconds(nowUtc()).toIso8601String(),
      'words': (await db.select(db.words).get())
          .map((row) => row.toJson())
          .toList(),
      'wordSenses': (await db.select(db.wordSenses).get())
          .map((row) => row.toJson())
          .toList(),
      'wordbooks': (await db.select(db.wordbooks).get())
          .map((row) => row.toJson())
          .toList(),
      'wordbookEntries': (await db.select(db.wordbookEntries).get())
          .map((row) => row.toJson())
          .toList(),
      'memoryStates': (await db.select(db.memoryStates).get())
          .map((row) => row.toJson())
          .toList(),
      'reviewEvents': (await db.select(db.reviewEvents).get())
          .map((row) => row.toJson())
          .toList(),
      'appSettings': (await db.select(db.appSettings).get())
          .map((row) => row.toJson())
          .toList(),
    }),
  );

  Future<void> restore(String source) async {
    late _Backup data;
    try {
      final root = jsonDecode(
        source.startsWith('\uFEFF') ? source.substring(1) : source,
      );
      if (root is! Map<String, dynamic> ||
          root['format'] != 'lexi_loop_backup' ||
          root['schemaVersion'] != 1 ||
          root['exportedAt'] is! String) {
        throw const FormatException('备份标识、版本或导出时间不正确。');
      }
      final exportedAt = DateTime.parse(root['exportedAt'] as String);
      if (!exportedAt.isUtc || exportedAt.microsecondsSinceEpoch % 1000 != 0) {
        throw const FormatException('导出时间必须为 UTC 毫秒精度。');
      }
      data = _Backup(root);
      _validate(data, exportedAt);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('备份缺少必要字段，或字段类型不正确。');
    }
    await db.transaction(() async {
      await db.delete(db.reviewEvents).go();
      await db.delete(db.memoryStates).go();
      await db.delete(db.wordbookEntries).go();
      await db.delete(db.wordSenses).go();
      await db.delete(db.words).go();
      await db.delete(db.wordbooks).go();
      await db.delete(db.appSettings).go();
      await db.batch((batch) {
        batch.insertAll(db.words, data.words);
        batch.insertAll(db.wordSenses, data.senses);
        batch.insertAll(db.wordbooks, data.books);
        batch.insertAll(db.wordbookEntries, data.entries);
        batch.insertAll(db.memoryStates, data.states);
        batch.insertAll(db.reviewEvents, data.events);
        batch.insertAll(db.appSettings, data.settings);
      });
      // 旧版备份不包含应用自带的考试词书；补齐时仍处于恢复事务内。
      await db.ensureExamWordbooks(reconcile: true);
    });
    onRestored?.call();
  }

  void _validate(_Backup data, DateTime exportedAt) {
    void require(bool condition, String message) {
      if (!condition) throw FormatException(message);
    }

    void unique(Iterable<Object> keys, String table) {
      final list = keys.toList();
      require(list.toSet().length == list.length, '$table 存在重复的主键或唯一键。');
    }

    unique(data.words.map((row) => row.id), '词条');
    unique(data.words.map((row) => row.spelling), '单词');
    unique(data.senses.map((row) => row.id), '词义');
    unique(data.books.map((row) => row.id), '词书');
    unique(
      data.entries.map((row) => jsonEncode([row.wordbookId, row.wordSenseId])),
      '词书关联',
    );
    unique(
      data.states.map(
        (row) => jsonEncode([row.userId, row.wordSenseId, row.trainingMode]),
      ),
      '记忆状态',
    );
    unique(data.events.map((row) => row.id), '评分事件');
    unique(data.settings.map((row) => row.key), '设置');
    final wordIds = data.words.map((row) => row.id).toSet();
    final senseIds = data.senses.map((row) => row.id).toSet();
    final bookIds = data.books.map((row) => row.id).toSet();
    require(data.words.isNotEmpty && data.books.isNotEmpty, '备份必须包含词条与词书。');
    for (final word in data.words) {
      require(word.id > 0 && word.spelling.trim().isNotEmpty, '词条编号或单词不合法。');
    }
    for (final sense in data.senses) {
      require(
        sense.id > 0 &&
            wordIds.contains(sense.wordId) &&
            sense.definition.trim().isNotEmpty,
        '词义引用了不存在的单词，或释义为空。',
      );
    }
    for (final book in data.books) {
      require(book.id.isNotEmpty && book.name.trim().isNotEmpty, '词书编号或名称为空。');
    }
    for (final entry in data.entries) {
      require(
        bookIds.contains(entry.wordbookId) &&
            senseIds.contains(entry.wordSenseId),
        '词书关联引用了不存在的词书或词义。',
      );
    }
    for (final state in data.states) {
      require(senseIds.contains(state.wordSenseId), '记忆状态引用了不存在的词义。');
      require(
        state.userId == localUserId && state.trainingMode == recognitionMode,
        '备份包含不支持的用户或训练方式。',
      );
      require(
        state.schedulerVersion == engine.schedulerVersion &&
            engine.matchesConfiguration(state.schedulerConfigJson),
        '备份的调度版本或完整参数与当前应用不一致。',
      );
      require(
        state.lastReview <= exportedAt.millisecondsSinceEpoch,
        '学习时间晚于备份导出时间。',
      );
      engine.decodeCard(
        jsonEncode({
          'cardId': state.wordSenseId,
          'state': state.state,
          'step': state.step,
          'stability': state.stability,
          'difficulty': state.difficulty,
          'due': state.due,
          'lastReview': state.lastReview,
        }),
        allowNew: false,
      );
    }
    for (final event in data.events) {
      require(
        senseIds.contains(event.wordSenseId) &&
            event.userId == localUserId &&
            event.trainingMode == recognitionMode &&
            event.schedulerVersion == engine.schedulerVersion,
        '评分事件引用无效，或使用了不支持的用户、训练方式、调度版本。',
      );
      require(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(event.id),
        '评分事件编号不是有效的 UUIDv7。',
      );
      require(
        {'again', 'hard', 'good', 'easy'}.contains(event.rating) &&
            event.reviewedAt >= 0 &&
            event.reviewedAt <= exportedAt.millisecondsSinceEpoch &&
            (event.durationMs == null || event.durationMs! >= 0),
        '评分等级、时间或耗时不合法。',
      );
    }
    final latestCards = <int, String>{};
    final ordered = [...data.events]
      ..sort((a, b) => a.reviewedAt.compareTo(b.reviewedAt));
    for (final event in ordered) {
      final before = engine.decodeCard(event.beforeJson);
      final after = engine.decodeCard(event.afterJson, allowNew: false);
      final at = DateTime.fromMillisecondsSinceEpoch(
        event.reviewedAt,
        isUtc: true,
      );
      require(
        before.cardId == event.wordSenseId &&
            after.cardId == event.wordSenseId &&
            after.lastReview == at &&
            !before.due.isAfter(at),
        '评分快照与词义、到期时间或真实评分时间不一致。',
      );
      final previous = latestCards[event.wordSenseId];
      if (previous == null) {
        require(
          before.lastReview == null && before.due == at,
          '首条评分必须从未学习卡片开始。',
        );
      } else {
        require(
          engine.encodeCard(before) == previous &&
              before.lastReview!.isBefore(at),
          '评分历史不连续，或评分时间没有递增。',
        );
      }
      final expected = engine.review(
        before,
        fsrs.Rating.values.byName(event.rating),
        at,
      );
      require(
        engine.encodeCard(expected) == engine.encodeCard(after),
        '评分快照与 FSRS 计算结果不一致。',
      );
      latestCards[event.wordSenseId] = engine.encodeCard(after);
    }
    require(latestCards.length == data.states.length, '学习状态与评分历史的数量不匹配。');
    for (final state in data.states) {
      final card = engine.decodeCard(
        jsonEncode({
          'cardId': state.wordSenseId,
          'state': state.state,
          'step': state.step,
          'stability': state.stability,
          'difficulty': state.difficulty,
          'due': state.due,
          'lastReview': state.lastReview,
        }),
        allowNew: false,
      );
      require(
        latestCards[state.wordSenseId] == engine.encodeCard(card),
        '最新评分快照与当前学习状态不一致。',
      );
    }
    final settings = {for (final row in data.settings) row.key: row.value};
    final activeBookId = settings['active_wordbook_id'];
    // 老备份没有此设置；内置考试词书可以在恢复事务中补齐。
    require(
      activeBookId == null ||
          bookIds.contains(activeBookId) ||
          examWordbooks.containsKey(activeBookId),
      '学习词书引用了不存在的自建词书。',
    );
    final goal = int.tryParse(settings['daily_new_goal'] ?? '');
    require(
      goal != null &&
          goal >= 0 &&
          goal <= 100 &&
          settings['seed_version'] == '1' &&
          double.tryParse(settings['desired_retention'] ?? '') == .9 &&
          settings['scheduler_version'] == engine.schedulerVersion &&
          engine.matchesConfiguration(settings['scheduler_config'] ?? '{}'),
      '备份设置缺失或与当前调度规则不兼容。',
    );
  }
}

class _Backup {
  _Backup(Map<String, dynamic> root)
    : words = _rows(root, 'words', Word.fromJson),
      senses = _rows(root, 'wordSenses', WordSense.fromJson),
      books = _rows(root, 'wordbooks', Wordbook.fromJson),
      entries = _rows(root, 'wordbookEntries', WordbookEntry.fromJson),
      states = _rows(root, 'memoryStates', MemoryStateRow.fromJson),
      events = _rows(root, 'reviewEvents', ReviewEvent.fromJson),
      settings = _rows(root, 'appSettings', AppSetting.fromJson);
  final List<Word> words;
  final List<WordSense> senses;
  final List<Wordbook> books;
  final List<WordbookEntry> entries;
  final List<MemoryStateRow> states;
  final List<ReviewEvent> events;
  final List<AppSetting> settings;

  static List<T> _rows<T>(
    Map<String, dynamic> root,
    String key,
    T Function(Map<String, dynamic>) decode,
  ) {
    final list = root[key];
    if (list is! List) throw FormatException('备份缺少 $key 数据表。');
    return list.map((value) {
      if (value is! Map<String, dynamic>) {
        throw FormatException('$key 包含错误的记录格式。');
      }
      return decode(value);
    }).toList();
  }
}
