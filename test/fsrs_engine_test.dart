import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:lexi_loop/domain/fsrs_engine.dart';

void main() {
  test('FSRS 官方黄金向量保持一致', () {
    final engine = FsrsEngine();
    var now = DateTime.utc(2022, 11, 29, 12, 30);
    var card = engine.newCard(1, now);
    final intervals = <int>[];
    for (final rating in [
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.again,
      fsrs.Rating.again,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
      fsrs.Rating.good,
    ]) {
      card = engine.review(card, rating, now);
      intervals.add(card.due.difference(now).inDays);
      now = card.due;
    }
    // fsrs 2.0.1 官方 test/basic_test.dart 的固定输入输出。
    expect(intervals, [0, 4, 14, 45, 135, 372, 0, 0, 2, 5, 10, 20, 40]);
  });

  test('固定配置含完整 21 参数，预测不修改卡片且可复现', () {
    final engine = FsrsEngine();
    final config = jsonDecode(engine.configurationJson);
    expect(config['parameters'], fsrs.defaultParameters);
    expect(config['parameters'], hasLength(21));
    expect(config['enableFuzzing'], false);
    expect(config['desiredRetention'], .9);
    expect(config['learningSteps'], [60, 600]);
    expect(config['relearningSteps'], [600]);
    expect(config['maximumInterval'], 36500);
    final now = DateTime.utc(2026, 11, 27, 8, 0, 0, 0, 999);
    final card = engine.newCard(1, now);
    final before = engine.encodeCard(card);
    final predictions = engine.predict(card, now);
    expect(predictions[fsrs.Rating.again], const Duration(minutes: 1));
    expect(predictions[fsrs.Rating.hard], const Duration(seconds: 330));
    expect(predictions, engine.predict(card, now));
    expect(engine.encodeCard(card), before);
    final reviewed = engine.review(card, fsrs.Rating.easy, now);
    expect(reviewed.lastReview!.microsecondsSinceEpoch % 1000, 0);
    expect(engine.decodeCard(engine.encodeCard(reviewed)), reviewed);
    expect(engine.retentionAt(reviewed, reviewed.lastReview!), 1);
  });
  test('拒绝比上次评分更早的时间', () {
    final now = DateTime.utc(2026, 11, 27, 8);
    final engine = FsrsEngine();
    final card = engine.review(
      fsrs.Card(cardId: 1, due: now),
      fsrs.Rating.good,
      now,
    );
    expect(
      () => engine.review(
        card,
        fsrs.Rating.good,
        now.subtract(const Duration(milliseconds: 1)),
      ),
      throwsArgumentError,
    );
  });
  test('记忆曲线在日内连续下降，稳定度对应的时刻为 90%', () {
    final now = DateTime.utc(2026, 11, 27, 8);
    final engine = FsrsEngine();
    final card = fsrs.Card(
      cardId: 1,
      state: fsrs.State.review,
      stability: 2,
      difficulty: 5,
      lastReview: now,
      due: now.add(const Duration(days: 2)),
    );
    expect(
      engine.retentionAt(card, now.add(const Duration(hours: 12))),
      lessThan(1),
    );
    expect(
      engine.retentionAt(card, now.add(const Duration(days: 2))),
      closeTo(.9, 1e-12),
    );
  });
  test('首次 Good 进入十分钟学习步骤，原卡片不被修改', () {
    final engine = FsrsEngine();
    final now = DateTime.utc(2026, 11, 27, 8);
    final initial = fsrs.Card(cardId: 1, due: now);
    final reviewed = engine.review(initial, fsrs.Rating.good, now);
    expect(reviewed.due.difference(now), const Duration(minutes: 10));
    expect(reviewed.step, 1);
    expect(initial.lastReview, isNull);
  });
}
