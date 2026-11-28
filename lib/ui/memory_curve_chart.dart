import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/app_database.dart';
import '../domain/fsrs_engine.dart';
import 'common.dart';
import 'journal_style.dart';

class MemoryCurveChart extends StatelessWidget {
  const MemoryCurveChart({
    super.key,
    required this.history,
    required this.engine,
    required this.nowUtc,
  });
  final List<ReviewEvent> history;
  final FsrsEngine engine;
  final DateTime nowUtc;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const MessagePanel(
        icon: Icons.show_chart,
        title: '第一条曲线，从一次回忆开始',
        message: '学习这个词义后，这里会展示遗忘趋势与复习带来的变化。',
      );
    }
    final tokens = JournalTokens.of(context);
    final recent = history.length > 6
        ? history.sublist(history.length - 6)
        : history;
    final cards = recent
        .map((event) => engine.decodeCard(event.afterJson, allowNew: false))
        .toList();
    final start = cards.first.lastReview!;
    final last = cards.last;
    final span = math.max(
      const Duration(days: 1).inMilliseconds,
      math.max(last.due.millisecondsSinceEpoch, nowUtc.millisecondsSinceEpoch) -
          start.millisecondsSinceEpoch,
    );
    final end = start.add(Duration(milliseconds: (span * 1.15).round()));
    final range = end.difference(start).inMilliseconds;
    double x(DateTime at) => at.difference(start).inMilliseconds / range;

    final segments = <List<Offset>>[];
    final reviewPoints = <Offset>[];
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final until = i + 1 < cards.length ? cards[i + 1].lastReview! : end;
      final duration = until.difference(card.lastReview!).inMilliseconds;
      final seg = <Offset>[];
      for (var sample = 0; sample <= 40; sample++) {
        final at = card.lastReview!.add(
          Duration(milliseconds: (duration * sample / 40).round()),
        );
        final pt = Offset(x(at), engine.retentionAt(card, at));
        seg.add(pt);
        if (sample == 0) reviewPoints.add(pt);
      }
      segments.add(seg);
    }

    final baseline = <Offset>[];
    for (var i = 0; i <= 120; i++) {
      final at = start.add(Duration(milliseconds: (range * i / 120).round()));
      baseline.add(Offset(x(at), engine.retentionAt(cards.first, at)));
    }

    final nowX = x(nowUtc).clamp(0.0, 1.0);
    final currentRetention = engine.retentionAt(last, nowUtc);
    final nowPoint = Offset(nowX, currentRetention);

    final axisStyle = JournalTokens.tabular(
      Theme.of(context).textTheme.labelSmall?.copyWith(color: tokens.inkMuted),
    );
    final axisLabel = TextPainter(
      text: TextSpan(
        text: '100%',
        style: axisStyle ?? DefaultTextStyle.of(context).style,
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final axisInset = axisLabel.height / 2;
    final axisWidth = math.max(60.0, axisLabel.width + 14);
    axisLabel.dispose();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '艾宾浩斯记忆曲线'),
        const SizedBox(height: 8),
        StatusBadge(
          label: '当前估计 ${(currentRetention * 100).round()}%',
          tone: currentRetention >= .9
              ? StatusBadgeTone.review
              : StatusBadgeTone.accent,
        ),
        const SizedBox(height: 6),
        Text(
          '展示遗忘与复习强化的趋势。数值由 FSRS 模型估计，不代表实际测量结果。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.inkSecondary),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _LegendSwatch(
              color: tokens.primary,
              dashed: false,
              label: '已发生的学习',
            ),
            _LegendSwatch(
              color: tokens.inkMuted,
              dashed: true,
              label: '未来估计 / 未再复习参考',
            ),
            _LegendSwatch(
              color: tokens.accent,
              dashed: true,
              label: '90% 保持率参考线',
            ),
          ],
        ),
        const SizedBox(height: 18),
        Semantics(
          label:
              '当前估计记忆保持率 ${(currentRetention * 100).round()}%，'
              '图中展示最近 ${cards.length} 次评分，水平参考线为 90%。',
          child: SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: axisWidth,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('100%', style: axisStyle),
                      Text('50%', style: axisStyle),
                      Text('0%', style: axisStyle),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: axisInset),
                    child: CustomPaint(
                      painter: _CurvePainter(
                        segments: segments,
                        reviewPoints: reviewPoints,
                        baseline: baseline,
                        nowPoint: nowPoint,
                        primary: tokens.primary,
                        surface: tokens.surface,
                        accent: tokens.accent,
                        reference: tokens.inkMuted.withValues(alpha: .72),
                        grid: tokens.border.withValues(alpha: .8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 16,
          runSpacing: 6,
          children: [
            Text(
              localDateTimeLabel(start),
              style: JournalTokens.tabular(
                Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.inkMuted),
              ),
            ),
            Text(
              localDateTimeLabel(end),
              style: JournalTokens.tabular(
                Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.inkMuted),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: tokens.surfaceMuted,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '当前估计 ${(currentRetention * 100).round()}% · 保持率参考线 90% · 展示最近 ${cards.length} 次评分',
            style: JournalTokens.tabular(
              Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.inkSecondary),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.dashed,
    required this.label,
  });

  final Color color;
  final bool dashed;
  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!dashed)
          Container(
            width: 16,
            height: 2.5,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          )
        else
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 2, color: color),
              const SizedBox(width: 3),
              Container(width: 6, height: 2, color: color),
            ],
          ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.segments,
    required this.reviewPoints,
    required this.baseline,
    required this.nowPoint,
    required this.primary,
    required this.surface,
    required this.accent,
    required this.reference,
    required this.grid,
  });

  final List<List<Offset>> segments;
  final List<Offset> reviewPoints, baseline;
  final Offset nowPoint;
  final Color primary, surface, accent, reference, grid;

  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset point) => Offset(
      point.dx * size.width,
      (1 - point.dy.clamp(0.0, 1.0)) * size.height,
    );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final y in [0.0, .5, 1.0]) {
      canvas.drawLine(
        Offset(0, y * size.height),
        Offset(size.width, y * size.height),
        gridPaint,
      );
    }

    // 90% 目标保持率水平参考线（琥珀虚线）
    final targetPaint = Paint()
      ..color = accent.withValues(alpha: .85)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, size.height * .1),
        Offset(math.min(x + 5, size.width), size.height * .1),
        targetPaint,
      );
    }

    // 未再复习基线虚线
    final basePaint = Paint()
      ..color = reference
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < baseline.length; i += 2) {
      canvas.drawLine(at(baseline[i - 1]), at(baseline[i]), basePaint);
    }

    // 已发生阶段柔光填充
    final pastPoints = <Offset>[];
    for (final seg in segments) {
      for (final p in seg) {
        if (p.dx <= nowPoint.dx) pastPoints.add(p);
      }
    }
    if (pastPoints.length >= 2) {
      final fillPath = Path()
        ..moveTo(at(pastPoints.first).dx, size.height)
        ..lineTo(at(pastPoints.first).dx, at(pastPoints.first).dy);
      for (var i = 1; i < pastPoints.length; i++) {
        final pos = at(pastPoints[i]);
        fillPath.lineTo(pos.dx, pos.dy);
      }
      fillPath
        ..lineTo(at(pastPoints.last).dx, size.height)
        ..close();
      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            primary.withValues(alpha: .16),
            primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(fillPath, fillPaint);
    }

    // 主记忆曲线：过去用连续实线，未来用虚线
    final solidPaint = Paint()
      ..color = primary
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final futurePaint = Paint()
      ..color = primary.withValues(alpha: .7)
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;

    for (final seg in segments) {
      final solidPath = Path();
      var started = false;
      for (var i = 0; i < seg.length; i++) {
        final p = seg[i];
        final pos = at(p);
        if (p.dx <= nowPoint.dx) {
          if (!started) {
            solidPath.moveTo(pos.dx, pos.dy);
            started = true;
          } else {
            solidPath.lineTo(pos.dx, pos.dy);
          }
        } else if (i > 0 && i.isOdd) {
          canvas.drawLine(at(seg[i - 1]), pos, futurePaint);
        }
      }
      if (started) {
        canvas.drawPath(solidPath, solidPaint);
      }
    }

    // 当前时刻竖线与锚点
    final nowXPos = nowPoint.dx * size.width;
    canvas.drawLine(
      Offset(nowXPos, 0),
      Offset(nowXPos, size.height),
      Paint()
        ..color = primary.withValues(alpha: .35)
        ..strokeWidth = 1.2,
    );

    // 历史评分强化节点
    final nodeFill = Paint()..color = primary;
    final nodeRing = Paint()
      ..color = surface
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (final p in reviewPoints) {
      final pos = at(p);
      canvas.drawCircle(pos, 4, nodeFill);
      canvas.drawCircle(pos, 4, nodeRing);
    }

    final nowPos = at(nowPoint);
    canvas.drawCircle(nowPos, 5, Paint()..color = accent);
    canvas.drawCircle(nowPos, 5, nodeRing);
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
