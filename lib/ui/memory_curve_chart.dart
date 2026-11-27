import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/app_database.dart';
import '../domain/fsrs_engine.dart';
import 'common.dart';

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
    final points = <Offset>[];
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final until = i + 1 < cards.length ? cards[i + 1].lastReview! : end;
      final duration = until.difference(card.lastReview!).inMilliseconds;
      for (var sample = 0; sample <= 40; sample++) {
        final at = card.lastReview!.add(
          Duration(milliseconds: (duration * sample / 40).round()),
        );
        points.add(Offset(x(at), engine.retentionAt(card, at)));
      }
    }
    final baseline = <Offset>[];
    for (var i = 0; i <= 120; i++) {
      final at = start.add(Duration(milliseconds: (range * i / 120).round()));
      baseline.add(Offset(x(at), engine.retentionAt(cards.first, at)));
    }
    final colors = Theme.of(context).colorScheme;
    final axisLabel = TextPainter(
      text: TextSpan(text: '100%', style: DefaultTextStyle.of(context).style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final axisInset = axisLabel.height / 2;
    final axisWidth = math.max(72.0, axisLabel.width + 16);
    axisLabel.dispose();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('艾宾浩斯记忆曲线', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('展示遗忘与复习强化的趋势。数值由 FSRS 模型估计，不代表实际测量结果。'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('实线：已发生的学习', style: TextStyle(color: colors.primary)),
            Text(
              '虚线：未来估计 / 未再复习参考',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Semantics(
          label:
              '当前估计记忆保持率 ${(engine.retentionAt(last, nowUtc) * 100).round()}%，'
              '图中展示最近 ${cards.length} 次评分，水平参考线为 90%。',
          child: SizedBox(
            height: 220,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: axisWidth,
                  child: const Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [Text('100%'), Text('50%'), Text('0%')],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: axisInset),
                    child: CustomPaint(
                      painter: _CurvePainter(
                        points: points,
                        baseline: baseline,
                        nowX: x(nowUtc).clamp(0, 1),
                        primary: colors.primary,
                        reference: colors.outline,
                        grid: colors.outlineVariant,
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
          runSpacing: 8,
          children: [
            Text(localDateTimeLabel(start)),
            Text(localDateTimeLabel(end)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '当前估计 ${(engine.retentionAt(last, nowUtc) * 100).round()}% · 保持率参考线 90%',
        ),
      ],
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.points,
    required this.baseline,
    required this.nowX,
    required this.primary,
    required this.reference,
    required this.grid,
  });
  final List<Offset> points, baseline;
  final double nowX;
  final Color primary, reference, grid;
  @override
  void paint(Canvas canvas, Size size) {
    Offset at(Offset point) =>
        Offset(point.dx * size.width, (1 - point.dy) * size.height);
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
    final referencePaint = Paint()
      ..color = reference
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 10) {
      canvas.drawLine(
        Offset(x, size.height * .1),
        Offset(math.min(x + 5, size.width), size.height * .1),
        referencePaint,
      );
    }
    final basePaint = Paint()
      ..color = reference
      ..strokeWidth = 1.5;
    for (var i = 1; i < baseline.length; i += 2) {
      canvas.drawLine(at(baseline[i - 1]), at(baseline[i]), basePaint);
    }
    final curvePaint = Paint()
      ..color = primary
      ..strokeWidth = 2.5;
    for (var i = 1; i < points.length; i++) {
      if (points[i].dx <= nowX || i.isEven) {
        canvas.drawLine(at(points[i - 1]), at(points[i]), curvePaint);
      }
    }
    canvas.drawLine(
      Offset(nowX * size.width, 0),
      Offset(nowX * size.width, size.height),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
