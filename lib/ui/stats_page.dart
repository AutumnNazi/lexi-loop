import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/app_database.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'journal_style.dart';
import 'memory_curve_chart.dart';

typedef _StatsSnapshot = ({
  StudyStats stats,
  StudyItem? selected,
  int learnedCount,
  int loadId,
  ReviewForecast forecast,
  DateTime asOf,
});

class StatsPage extends StatefulWidget {
  const StatsPage({
    super.key,
    required this.dependencies,
    this.refreshListenable,
    this.historyLoader,
    this.activityLoader,
  });

  final AppDependencies dependencies;
  final Listenable? refreshListenable;
  final Future<List<ReviewEvent>> Function(int senseId)? historyLoader;
  final Future<ReviewActivity> Function(int days, DateTime asOf)?
  activityLoader;

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  _StatsSnapshot? _snapshot;
  bool _loading = true;
  String? _error;
  int _loadRevision = 0;
  StudyItem? _selectedItem;
  int _activityDays = 7;
  ReviewActivity? _activity;
  bool _activityLoading = true;
  String? _activityError;
  int _activityRevision = 0;

  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(_onRefreshSignal);
    _load();
  }

  @override
  void didUpdateWidget(covariant StatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_onRefreshSignal);
      widget.refreshListenable?.addListener(_onRefreshSignal);
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_onRefreshSignal);
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    _load();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    if (_snapshot != null) {
      setState(() {
        _loading = true;
        _error = null;
        _activityRevision++;
        _activity = null;
        _activityLoading = true;
        _activityError = null;
      });
    } else {
      _loading = true;
      _error = null;
      _activityRevision++;
      _activity = null;
      _activityLoading = true;
      _activityError = null;
    }
    final repository = widget.dependencies.repository;
    try {
      final asOf = widget.dependencies.nowUtc();
      final stats = await repository.stats(asOf: asOf);
      final first = (await repository.entries(
        filter: EntryFilter.learned,
        limit: 1,
      )).firstOrNull;
      final learnedCount = await repository.entryCount(
        filter: EntryFilter.learned,
      );
      final forecast = await repository.reviewForecast(asOf: asOf);
      final previous = _selectedItem;
      StudyItem? selected;
      if (previous != null) {
        final current = await repository.learnedEntry(previous.sense.id);
        // 恢复后同一编号可能被复用，必须连同单词和释义一起核对。
        if (current != null &&
            current.word.spelling == previous.word.spelling &&
            current.sense.definition == previous.sense.definition) {
          selected = current;
        }
      }
      selected ??= first;
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _selectedItem = selected;
        _snapshot = (
          stats: stats,
          selected: selected,
          learnedCount: learnedCount,
          loadId: revision,
          forecast: forecast,
          asOf: asOf,
        );
        _loading = false;
        _error = null;
      });
      await _loadActivity(asOf, _activityDays);
    } catch (error) {
      if (!mounted || revision != _loadRevision) return;
      setState(() {
        _snapshot = null;
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _pickSense() async {
    final picked = await showDialog<StudyItem>(
      context: context,
      builder: (_) => _CurveSensePicker(
        repository: widget.dependencies.repository,
        selectedSenseId: _selectedItem?.sense.id,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedItem = picked);
    await _load();
  }

  Future<void> _loadActivity(DateTime asOf, int days) async {
    final revision = ++_activityRevision;
    if (!mounted) return;
    setState(() {
      _activity = null;
      _activityLoading = true;
      _activityError = null;
    });
    try {
      final loader = widget.activityLoader;
      final activity = await (loader != null
          ? loader(days, asOf)
          : widget.dependencies.repository.reviewActivity(
              days: days,
              asOf: asOf,
            ));
      if (!mounted || revision != _activityRevision || days != _activityDays) {
        return;
      }
      setState(() {
        _activity = activity;
        _activityLoading = false;
        _activityError = null;
      });
    } catch (error) {
      if (!mounted || revision != _activityRevision || days != _activityDays) {
        return;
      }
      setState(() {
        _activity = null;
        _activityLoading = false;
        _activityError = '$error';
      });
    }
  }

  void _selectActivityDays(int days) {
    if (days == _activityDays) return;
    setState(() => _activityDays = days);
    final asOf = _snapshot?.asOf;
    if (asOf != null) {
      _loadActivity(asOf, days);
    }
  }

  void _showActivityDay(ReviewActivityDay day) {
    final date = day.localDate;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 360),
        title: Text('${date.year} 年 ${date.month} 月 ${date.day} 日'),
        content: Text('${day.count} 次评分'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return PageFrame(
      title: '记忆正在生长',
      subtitle: '每一次回忆，都有迹可循。',
      children: [
        if (_error != null)
          MessagePanel(
            title: '暂时无法读取数据',
            message: '$_error',
            icon: Icons.error_outline,
            action: OutlinedButton(onPressed: _load, child: const Text('重试')),
          )
        else
          Builder(
            builder: (context) {
              final data = _snapshot;
              if (data == null) {
                return const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final selected = data.selected;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  JournalSurface(
                    padding: const EdgeInsets.all(22),
                    child: StatStrip(
                      accentIndex: data.stats.streak > 0 ? 3 : null,
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
                  const SizedBox(height: 20),
                  if (_loading)
                    JournalSurface(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SectionHeader(title: '未来 7 天复习'),
                          const SizedBox(height: 14),
                          LinearProgressIndicator(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '正在按最新日期刷新复习安排…',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.inkSecondary),
                          ),
                        ],
                      ),
                    )
                  else
                    _buildForecast(context, tokens, data.forecast),
                  const SizedBox(height: 20),
                  _buildActivitySection(context, tokens, data.asOf),
                  const SizedBox(height: 20),
                  if (selected == null)
                    const MessagePanel(
                      icon: Icons.show_chart,
                      title: '记忆曲线等待你的第一条记录',
                      message: '完成一次词义学习，就能在这里查看遗忘与强化趋势。',
                    )
                  else
                    JournalSurface(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '查看词义的记忆曲线',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.inkSecondary),
                          ),
                          const SizedBox(height: 8),
                          Material(
                            color: tokens.surfaceMuted,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: const ValueKey('curve-sense-picker'),
                              onTap: _pickSense,
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 13,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${selected.word.spelling} · ${selected.sense.definition}',
                                            key: const ValueKey(
                                              'curve-sense-selected',
                                            ),
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            '从 ${data.learnedCount} 个已学词义中搜索选择',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: tokens.inkSecondary,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const JournalIcon(
                                      Icons.chevron_right,
                                      size: 18,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          _MemoryCurvePanel(
                            key: ValueKey('memory-curve-${selected.sense.id}'),
                            dependencies: widget.dependencies,
                            senseId: selected.sense.id,
                            nowUtc: data.asOf,
                            loadToken:
                                '${data.loadId}-${selected.memory?.due}-${selected.sense.definition.hashCode}',
                            historyLoader: widget.historyLoader,
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildActivitySection(
    BuildContext context,
    JournalTokens tokens,
    DateTime asOf,
  ) {
    final days = _activityDays;
    final activity = _activity;
    final success = activity?.successRate;
    return JournalSurface(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: days == 7 ? '最近 7 天' : '近 $days 天活动'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in const [7, 30, 90])
                ChoiceChip(
                  key: ValueKey('stats-activity-period-$period'),
                  label: Text('近 $period 天'),
                  selected: days == period,
                  onSelected: (_) => _selectActivityDays(period),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_activityLoading)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LinearProgressIndicator(),
                const SizedBox(height: 10),
                Text(
                  '正在整理近 $days 天记录…',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.inkSecondary),
                ),
              ],
            )
          else if (_activityError != null)
            Container(
              key: const ValueKey('stats-activity-error'),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tokens.again.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.again.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '暂时无法读取活动回看',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: tokens.again.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _activityError!,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.again.foreground),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    key: const ValueKey('stats-activity-retry'),
                    onPressed: () => _loadActivity(asOf, days),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          else if (activity != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ActivityMetric(
                  label: '评分次数',
                  value: '${activity.ratingCount}',
                  valueKey: const ValueKey('stats-activity-rating-count'),
                ),
                _ActivityMetric(
                  label: '学习天数',
                  value: '${activity.activeDays}',
                  valueKey: const ValueKey('stats-activity-active-days'),
                ),
                _ActivityMetric(
                  label: 'Good+Easy 成功率',
                  value: success == null ? '—' : '${(success * 100).round()}%',
                  valueKey: const ValueKey('stats-activity-success-rate'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (days == 7)
              _buildSevenDayActivity(context, tokens, activity)
            else
              _ActivityGrid(activity: activity, onDayTap: _showActivityDay),
            const SizedBox(height: 12),
            Text(
              days == 7
                  ? '成功率 = Good 与 Easy 的次数 ÷ 全部评分次数。'
                  : '成功率 = Good 与 Easy 的次数 ÷ 全部评分次数；最近日期排在最前。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.inkSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSevenDayActivity(
    BuildContext context,
    JournalTokens tokens,
    ReviewActivity activity,
  ) {
    final maximum = math.max(
      1,
      activity.dayCounts.map((day) => day.count).reduce(math.max),
    );
    return Row(
      key: const ValueKey('stats-activity-bars'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(7, (i) {
        final day = activity.dayCounts[i].localDate;
        final count = activity.dayCounts[i].count;
        final isToday = i == 6;
        final barColor = count == 0
            ? tokens.surfaceMuted
            : (isToday
                  ? tokens.primary
                  : tokens.primary.withValues(alpha: .52));
        final barHeight = count == 0
            ? 6.0
            : math.max(10.0, count / maximum * 116);
        return Expanded(
          child: Semantics(
            label: '${day.month} 月 ${day.day} 日，$count 次评分',
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$count',
                    style: JournalTokens.tabular(
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: count == 0 ? tokens.inkMuted : tokens.inkPrimary,
                        fontWeight: count == 0
                            ? FontWeight.w500
                            : FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 116,
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.bottomCenter,
                      children: [
                        Positioned(
                          left: -4,
                          right: -4,
                          top: 58,
                          child: Divider(
                            height: 1,
                            color: tokens.border.withValues(alpha: .55),
                          ),
                        ),
                        Positioned(
                          left: -4,
                          right: -4,
                          bottom: 0,
                          child: Divider(
                            height: 1,
                            color: tokens.border.withValues(alpha: .9),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          height: barHeight,
                          width: 22,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    isToday ? '今' : '${day.day}',
                    textAlign: TextAlign.center,
                    style: JournalTokens.tabular(
                      Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: isToday ? tokens.primary : tokens.inkSecondary,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildForecast(
    BuildContext context,
    JournalTokens tokens,
    ReviewForecast forecast,
  ) {
    const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
    return JournalSurface(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(title: '未来 7 天复习'),
          const SizedBox(height: 8),
          StatusBadge(
            label: '现在待复习 ${forecast.dueNow}',
            tone: forecast.dueNow > 0
                ? StatusBadgeTone.due
                : StatusBadgeTone.neutral,
          ),
          const SizedBox(height: 10),
          Text(
            '今天剩余与之后 6 个本地日；含今日共 ${forecast.sevenDayTotal} 个词义到期。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: forecast.days.indexed.map((entry) {
              final index = entry.$1;
              final day = entry.$2;
              final date = day.localDate;
              final label = index == 0
                  ? '今天'
                  : '${weekdays[date.weekday - 1]} ${date.month}/${date.day}';
              final active = day.count > 0;
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? tokens.heroSurface : tokens.surfaceMuted,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: active
                        ? tokens.primary.withValues(alpha: .45)
                        : tokens.border,
                  ),
                ),
                child: Text(
                  '$label · ${day.count}',
                  style: JournalTokens.tabular(
                    Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: active ? tokens.primary : tokens.inkSecondary,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 10),
          Text(
            '仅统计已学词义的当前安排，复习后会更新。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ActivityMetric extends StatelessWidget {
  const _ActivityMetric({
    required this.label,
    required this.value,
    required this.valueKey,
  });

  final String label;
  final String value;
  final Key valueKey;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 88),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            key: valueKey,
            style: JournalTokens.tabular(
              Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.inkPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityGrid extends StatelessWidget {
  const _ActivityGrid({required this.activity, required this.onDayTap});

  final ReviewActivity activity;
  final ValueChanged<ReviewActivityDay> onDayTap;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 720
            ? 10
            : constraints.maxWidth >= 300
            ? 5
            : 4;
        const spacing = 8.0;
        final cellWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        // 最近日期放最前，长范围在手机上优先看见今天。
        final days = activity.dayCounts.reversed.toList();
        return Wrap(
          key: const ValueKey('stats-activity-grid'),
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final day in days)
              SizedBox(
                width: cellWidth,
                child: Semantics(
                  button: true,
                  label:
                      '${day.localDate.year} 年 ${day.localDate.month} 月 '
                      '${day.localDate.day} 日，${day.count} 次评分',
                  child: InkWell(
                    key: ValueKey(
                      'activity-day-${day.localDate.year}-${day.localDate.month}-${day.localDate.day}',
                    ),
                    onTap: () => onDayTap(day),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: day.count == 0
                            ? tokens.surfaceMuted
                            : tokens.heroSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: day.count == 0
                              ? tokens.border
                              : tokens.primary.withValues(alpha: .42),
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              '${day.localDate.month}/${day.localDate.day}',
                              maxLines: 1,
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(color: tokens.inkSecondary),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${day.count}',
                            style: JournalTokens.tabular(
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: day.count == 0
                                    ? tokens.inkMuted
                                    : tokens.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MemoryCurvePanel extends StatefulWidget {
  const _MemoryCurvePanel({
    super.key,
    required this.dependencies,
    required this.senseId,
    required this.nowUtc,
    required this.loadToken,
    this.historyLoader,
  });
  final AppDependencies dependencies;
  final int senseId;
  final DateTime nowUtc;
  final String loadToken;
  final Future<List<ReviewEvent>> Function(int senseId)? historyLoader;

  @override
  State<_MemoryCurvePanel> createState() => _MemoryCurvePanelState();
}

class _MemoryCurvePanelState extends State<_MemoryCurvePanel> {
  List<ReviewEvent>? _history;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _begin(notify: false);
  }

  @override
  void didUpdateWidget(covariant _MemoryCurvePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.senseId != widget.senseId ||
        oldWidget.loadToken != widget.loadToken) {
      // 选中词义或恢复代次变化时先清空，避免旧曲线配新标题。
      _begin(notify: false);
    }
  }

  void _begin({bool notify = true}) {
    final generation = ++_generation;
    if (notify) {
      setState(() {
        _history = null;
        _error = null;
      });
    } else {
      _history = null;
      _error = null;
    }
    _fetch(generation);
  }

  Future<void> _fetch(int generation) async {
    try {
      final loader =
          widget.historyLoader ??
          (int senseId) => widget.dependencies.repository.history(
            senseId: senseId,
            limit: 6,
          );
      final history = await loader(widget.senseId);
      if (!mounted || generation != _generation) return;
      setState(() => _history = history);
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = '$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return MessagePanel(
        title: '暂时无法读取曲线记录',
        message: '$_error',
        icon: Icons.error_outline,
        action: OutlinedButton(onPressed: _begin, child: const Text('重试')),
      );
    }
    final history = _history;
    if (history == null) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return MemoryCurveChart(
      history: history,
      engine: widget.dependencies.engine,
      nowUtc: widget.nowUtc,
    );
  }
}

class _CurveSensePicker extends StatefulWidget {
  const _CurveSensePicker({
    required this.repository,
    required this.selectedSenseId,
  });
  final StudyRepository repository;
  final int? selectedSenseId;

  @override
  State<_CurveSensePicker> createState() => _CurveSensePickerState();
}

class _CurveSensePickerState extends State<_CurveSensePicker> {
  static const _pageSize = 40;
  final _search = TextEditingController();
  int _offset = 0;
  List<StudyItem> _items = const [];
  int _total = 0;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _begin(notify: false);
  }

  void _begin({bool resetPage = false, bool notify = true}) {
    if (resetPage) _offset = 0;
    final generation = ++_generation;
    void reset() {
      _loading = true;
      _error = null;
      _items = const [];
    }

    if (notify) {
      setState(reset);
    } else {
      reset();
    }
    _fetch(generation);
  }

  Future<void> _fetch(int generation) async {
    final search = _search.text;
    final offset = _offset;
    try {
      final items = await widget.repository.entries(
        filter: EntryFilter.learned,
        search: search,
        offset: offset,
        limit: _pageSize,
      );
      final total = await widget.repository.entryCount(
        filter: EntryFilter.learned,
        search: search,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _total = total;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 600 ? 12 : 40,
        vertical: 24,
      ),
      child: SizedBox(
        width: 680,
        height: math.min(640, MediaQuery.sizeOf(context).height - 48),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '选择已学词义',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const JournalIcon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('curve-sense-search'),
                controller: _search,
                decoration: InputDecoration(
                  labelText: '搜索单词或中文释义',
                  prefixIcon: const Padding(
                    padding: EdgeInsets.all(14),
                    child: JournalIcon(Icons.search, size: 20),
                  ),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () {
                            _search.clear();
                            _begin(resetPage: true);
                          },
                          icon: const JournalIcon(Icons.close, size: 18),
                        ),
                ),
                onChanged: (_) => _begin(resetPage: true),
              ),
              const SizedBox(height: 12),
              Expanded(child: _buildResults(context, tokens)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResults(BuildContext context, JournalTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return SingleChildScrollView(
        child: MessagePanel(
          title: '暂时无法读取已学词义',
          message: '$_error',
          icon: Icons.error_outline,
          action: OutlinedButton(onPressed: _begin, child: const Text('重试')),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Text(
          _search.text.trim().isEmpty ? '还没有已学词义，完成一次学习后再来。' : '没有匹配的已学词义。',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tokens.inkSecondary),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _items.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, color: tokens.border),
            itemBuilder: (context, index) {
              final item = _items[index];
              final selected = item.sense.id == widget.selectedSenseId;
              return ListTile(
                key: ValueKey('curve-sense-${item.sense.id}'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                title: Text(
                  item.word.spelling,
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  item.sense.definition,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: selected
                    ? JournalIcon(
                        Icons.check_circle_outline,
                        size: 20,
                        color: tokens.primary,
                      )
                    : null,
                onTap: () => Navigator.of(context).pop(item),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                '${_offset + 1}–${_offset + _items.length} / $_total',
                style: JournalTokens.tabular(
                  Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.inkSecondary),
                ),
              ),
            ),
            if (_offset > 0)
              TextButton(
                onPressed: () {
                  _offset = math.max(0, _offset - _pageSize);
                  _begin();
                },
                child: const Text('上一页'),
              ),
            if (_offset + _items.length < _total)
              TextButton(
                onPressed: () {
                  _offset += _pageSize;
                  _begin();
                },
                child: const Text('下一页'),
              ),
          ],
        ),
      ],
    );
  }
}
