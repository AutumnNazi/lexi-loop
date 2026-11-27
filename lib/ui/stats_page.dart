import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'memory_curve_chart.dart';
import 'journal_style.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  late final _data = _load();
  int? _selected;
  Future<({StudyStats stats, List<StudyItem> learned})> _load() async => (
    stats: await widget.dependencies.repository.stats(),
    learned: (await widget.dependencies.repository.entries())
        .where((item) => item.memory != null)
        .toList(),
  );
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '记忆正在生长',
    subtitle: '每一次回忆，都有迹可循。',
    children: [
      AsyncContent(
        future: _data,
        builder: (data) {
          final maximum = math.max(1, data.stats.dailyCounts.reduce(math.max));
          final selected =
              _selected ??
              (data.learned.isEmpty ? null : data.learned.first.sense.id);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JournalPanel(
                child: StatStrip(
                  items: [
                    (label: '今日完成', value: '${data.stats.today}'),
                    (label: '累计评分', value: '${data.stats.total}'),
                    (
                      label: '回忆成功率',
                      value: '${(data.stats.successRate * 100).round()}%',
                    ),
                    (label: '连续学习', value: '${data.stats.streak} 天'),
                  ],
                ),
              ),
              const SizedBox(height: 36),
              Text('最近 7 天', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: List.generate(7, (i) {
                  final date = widget.dependencies.repository.calendar.local(
                    widget.dependencies.nowUtc(),
                  );
                  final day = DateTime(date.year, date.month, date.day - 6 + i);
                  final count = data.stats.dailyCounts[i];
                  return Expanded(
                    child: Semantics(
                      label: '${day.month} 月 ${day.day} 日，$count 次评分',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          children: [
                            Text('$count'),
                            const SizedBox(height: 8),
                            SizedBox(
                              height: 120,
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  height: math.max(3, count / maximum * 120),
                                  width: 24,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${day.day}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              const Text('成功率 = Good 与 Easy 的次数 ÷ 全部评分次数。'),
              const SizedBox(height: 36),
              const Divider(),
              const SizedBox(height: 28),
              if (selected == null)
                const MessagePanel(
                  icon: Icons.show_chart,
                  title: '记忆曲线等待你的第一条记录',
                  message: '完成一次词义学习，就能在这里查看遗忘与强化趋势。',
                )
              else ...[
                JournalPanel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selected,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '查看词义的记忆曲线',
                        ),
                        icon: const JournalIcon(Icons.chevron_right, size: 20),
                        items: data.learned
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.sense.id,
                                child: Text(
                                  '${item.word.spelling} · ${item.sense.definition}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => _selected = value),
                      ),
                      const SizedBox(height: 24),
                      AsyncContent(
                        future: widget.dependencies.repository.history(
                          senseId: selected,
                        ),
                        builder: (history) => MemoryCurveChart(
                          history: history,
                          engine: widget.dependencies.engine,
                          nowUtc: widget.dependencies.nowUtc(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ],
  );
}
