import 'dart:convert';
import 'dart:math' as math;

import 'package:fsrs/fsrs.dart' as fsrs;

import '../core/clock.dart';

class FsrsEngine {
  final _scheduler = fsrs.Scheduler(enableFuzzing: false);

  String get schedulerVersion => 'fsrs-6/2.0.1/retention-0.90/fuzz-off';
  String get configurationJson => jsonEncode(_scheduler.toMap());
  bool matchesConfiguration(String source) {
    Object? ordered(Object? value) {
      if (value is Map<String, dynamic>) {
        final keys = value.keys.toList()..sort();
        return {for (final key in keys) key: ordered(value[key])};
      }
      if (value is List) return value.map(ordered).toList();
      return value;
    }

    return jsonEncode(ordered(jsonDecode(source))) ==
        jsonEncode(ordered(jsonDecode(configurationJson)));
  }

  List<Duration> get learningSteps =>
      List.unmodifiable(_scheduler.learningSteps);
  List<fsrs.Rating> get ratings => fsrs.Rating.values;

  fsrs.Card newCard(int senseId, DateTime nowUtc) =>
      fsrs.Card(cardId: senseId, due: utcMilliseconds(nowUtc));

  double retentionAt(fsrs.Card card, DateTime atUtc) {
    if (card.lastReview == null || card.stability == null) return 0;
    final elapsedDays = math.max(
      0,
      atUtc.difference(card.lastReview!).inMilliseconds /
          Duration.millisecondsPerDay,
    );
    final decay = -_scheduler.parameters[20];
    final factor = math.pow(.9, 1 / decay) - 1;
    // 连续时间仅用于绘图；实际复习日期仍由原包的 reviewCard 决定。
    return math
        .pow(1 + factor * elapsedDays / card.stability!, decay)
        .toDouble();
  }

  fsrs.Card review(fsrs.Card card, fsrs.Rating rating, DateTime nowUtc) {
    final now = utcMilliseconds(nowUtc);
    if (card.lastReview != null && now.isBefore(card.lastReview!)) {
      throw ArgumentError('评分时间早于上次学习，请检查系统时间。');
    }
    final result = _scheduler
        .reviewCard(card, rating, reviewDateTime: now)
        .card;
    result.due = utcMilliseconds(result.due);
    result.lastReview = utcMilliseconds(result.lastReview!);
    return result;
  }

  Map<fsrs.Rating, Duration> predict(fsrs.Card card, DateTime nowUtc) => {
    for (final rating in ratings)
      rating: review(
        card,
        rating,
        nowUtc,
      ).due.difference(utcMilliseconds(nowUtc)),
  };

  Map<String, Object?> snapshot(fsrs.Card card) => {
    'cardId': card.cardId,
    'state': card.state.value,
    'step': card.step,
    'stability': card.stability,
    'difficulty': card.difficulty,
    'due': card.due.millisecondsSinceEpoch,
    'lastReview': card.lastReview?.millisecondsSinceEpoch,
  };

  String encodeCard(fsrs.Card card) => jsonEncode(snapshot(card));

  fsrs.Card decodeCard(String source, {bool allowNew = true}) {
    final value = jsonDecode(source);
    if (value is! Map<String, dynamic> ||
        value.length != 7 ||
        !value.keys.toSet().containsAll({
          'cardId',
          'state',
          'step',
          'stability',
          'difficulty',
          'due',
          'lastReview',
        })) {
      throw const FormatException('卡片快照格式不正确。');
    }
    final id = value['cardId'];
    final state = value['state'];
    final step = value['step'];
    final stability = value['stability'];
    final difficulty = value['difficulty'];
    final due = value['due'];
    final last = value['lastReview'];
    if (id is! int ||
        id <= 0 ||
        state is! int ||
        state < 1 ||
        state > 3 ||
        due is! int ||
        due < 0 ||
        due > 8640000000000000 ||
        (last != null && (last is! int || last < 0 || last > due))) {
      throw const FormatException('卡片编号、阶段或时间不合法。');
    }
    if (last == null) {
      if (!allowNew ||
          state != 1 ||
          step != 0 ||
          stability != null ||
          difficulty != null) {
        throw const FormatException('未学习卡片的状态不合法。');
      }
    } else if (stability is! num ||
        !stability.isFinite ||
        stability <= 0 ||
        difficulty is! num ||
        !difficulty.isFinite ||
        difficulty < 1 ||
        difficulty > 10 ||
        (state == 2
            ? step != null
            : step is! int || step < 0 || step >= (state == 1 ? 2 : 1))) {
      throw const FormatException('记忆强度、难度或学习步骤不合法。');
    }
    return fsrs.Card(
      cardId: id,
      state: fsrs.State.fromValue(state),
      step: step as int?,
      stability: (stability as num?)?.toDouble(),
      difficulty: (difficulty as num?)?.toDouble(),
      due: DateTime.fromMillisecondsSinceEpoch(due, isUtc: true),
      lastReview: last == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(last as int, isUtc: true),
    );
  }
}
