import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/app_database.dart';
import '../data/study_repository.dart';
import '../domain/fsrs_engine.dart';
import 'common.dart';
import 'journal_style.dart';
import 'memory_curve_chart.dart';
import 'study_page.dart';

class WordDetailPage extends StatelessWidget {
  const WordDetailPage({
    super.key,
    required this.dependencies,
    required this.wordId,
  });

  final AppDependencies dependencies;
  final int wordId;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        leading: journalBackButton(context),
        title: const Text('词条详情'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            width < 600 ? 18 : 36,
            width < 600 ? 8 : 24,
            width < 600 ? 18 : 36,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: WordDetailBody(dependencies: dependencies, wordId: wordId),
            ),
          ),
        ),
      ),
    );
  }
}

class _WordDetailData {
  const _WordDetailData({
    required this.items,
    required this.histories,
    this.error,
  });

  final List<StudyItem> items;
  final Map<int, List<ReviewEvent>> histories;
  final String? error;
}

class _LearningHistorySection extends StatelessWidget {
  const _LearningHistorySection({required this.history, required this.engine});

  final List<ReviewEvent> history;
  final FsrsEngine engine;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    return JournalSurface(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final title = Text(
                '最近学习记录',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              );
              final badge = Text(
                '最近 20 条',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.inkMuted),
              );
              // 窄屏大字号时分开两行，避免标题与条数互相挤压。
              if (constraints.maxWidth < 280) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 4), badge],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  badge,
                ],
              );
            },
          ),
          const SizedBox(height: 6),
          Text(
            '这里最多展示最近 20 条本地记录，不是全部历史。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
          const SizedBox(height: 12),
          if (history.isEmpty) ...[
            Text(
              '还没有学习记录',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '学习或复习这个词义后，这里会出现最近评分。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.inkSecondary),
            ),
          ] else
            for (var index = history.length - 1; index >= 0; index--) ...[
              _LearningHistoryRow(event: history[index], engine: engine),
              if (index > 0) Divider(color: tokens.border, height: 1),
            ],
        ],
      ),
    );
  }
}

class _LearningHistoryRow extends StatelessWidget {
  const _LearningHistoryRow({required this.event, required this.engine});

  final ReviewEvent event;
  final FsrsEngine engine;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final reviewedAt = DateTime.fromMillisecondsSinceEpoch(
      event.reviewedAt,
      isUtc: true,
    );
    final after = engine.decodeCard(event.afterJson, allowNew: false);
    final tone = switch (event.rating) {
      'again' => tokens.again,
      'hard' => tokens.hard,
      'good' => tokens.good,
      'easy' => tokens.easy,
      _ => tokens.again,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                localDateTimeWithYearLabel(reviewedAt),
                style: JournalTokens.tabular(
                  Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.inkSecondary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: tone.background,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tone.border),
                ),
                child: Text(
                  _ratingLabel(event.rating),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tone.foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (event.durationMs != null)
                Text(
                  '耗时 ${intervalLabel(Duration(milliseconds: event.durationMs!))}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.inkMuted),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '下次安排 ${localDateTimeWithYearLabel(after.due)}',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
        ],
      ),
    );
  }
}

String _ratingLabel(String rating) => switch (rating) {
  'again' => 'Again · 忘记',
  'hard' => 'Hard · 困难',
  'good' => 'Good · 记得',
  'easy' => 'Easy · 轻松',
  _ => rating,
};

class WordDetailBody extends StatefulWidget {
  const WordDetailBody({
    super.key,
    required this.dependencies,
    required this.wordId,
    this.embedded = false,
    this.onChanged,
  });

  final AppDependencies dependencies;
  final int wordId;
  final bool embedded;
  final VoidCallback? onChanged;

  @override
  State<WordDetailBody> createState() => _WordDetailBodyState();
}

class _WordDetailBodyState extends State<WordDetailBody>
    with WidgetsBindingObserver {
  static const _historyLimit = 20;

  late Future<_WordDetailData> _detail;
  StreamSubscription<void>? _subscription;
  Timer? _dueTimer;
  int _revision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
    _detail = _load(++_revision);
  }

  @override
  void didUpdateWidget(covariant WordDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dependencies != widget.dependencies) {
      _listen();
    }
    if (oldWidget.wordId != widget.wordId ||
        oldWidget.dependencies != widget.dependencies) {
      _reload();
    }
  }

  void _listen() {
    _subscription?.cancel();
    _subscription = widget.dependencies.repository.changes.listen(
      (_) => _reload(),
    );
  }

  void _reload() {
    if (!mounted) return;
    final revision = ++_revision;
    _dueTimer?.cancel();
    setState(() {
      _detail = _load(revision);
    });
  }

  Future<_WordDetailData> _load(int revision) async {
    try {
      final wordId = widget.wordId;
      final items = await widget.dependencies.repository.entries(
        wordId: wordId,
      );
      final histories = <int, List<ReviewEvent>>{};
      for (final item in items) {
        histories[item.sense.id] = await widget.dependencies.repository.history(
          senseId: item.sense.id,
          limit: _historyLimit,
        );
      }
      if (mounted && revision == _revision) {
        _scheduleDue(items);
      }
      return _WordDetailData(
        items: List<StudyItem>.unmodifiable(items),
        histories: Map<int, List<ReviewEvent>>.unmodifiable(histories),
      );
    } catch (error) {
      return _WordDetailData(
        items: const [],
        histories: const {},
        error: '$error',
      );
    }
  }

  void _scheduleDue(List<StudyItem> items) {
    _dueTimer?.cancel();
    final now = widget.dependencies.nowUtc();
    DateTime? next;
    for (final item in items) {
      final memory = item.memory;
      if (memory == null) continue;
      final due = DateTime.fromMillisecondsSinceEpoch(memory.due, isUtc: true);
      if (due.isAfter(now) && (next == null || due.isBefore(next))) {
        next = due;
      }
    }
    if (next == null) return;
    final delay = next.difference(now) + const Duration(milliseconds: 1);
    _dueTimer = Timer(delay, _reload);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subscription?.cancel();
    _dueTimer?.cancel();
    super.dispose();
  }

  Future<void> _openStudy(int senseId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudyPage(dependencies: widget.dependencies, senseId: senseId),
      ),
    );
    if (mounted) {
      _reload();
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final nowUtc = widget.dependencies.nowUtc();

    return AsyncContent<_WordDetailData>(
      key: ValueKey(_revision),
      future: _detail,
      retry: _reload,
      builder: (detail) {
        if (detail.error != null) {
          return MessagePanel(
            title: '暂时无法读取数据',
            message: detail.error!,
            icon: Icons.error_outline,
            action: OutlinedButton(onPressed: _reload, child: const Text('重试')),
          );
        }
        final items = detail.items;
        if (items.isEmpty) {
          return const MessagePanel(
            title: '词条不存在',
            message: '备份恢复后内容可能已变化，请返回词书刷新。',
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!widget.embedded) ...[
              Text(
                items.first.word.spelling,
                style: Theme.of(context).textTheme.displayMedium
                    ?.copyWith(fontSize: 36, height: 1.15),
              ),
              const SizedBox(height: 6),
              Text(
                '每个词义独立记忆，跨词书共享学习进度。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.inkSecondary),
              ),
              const SizedBox(height: 20),
            ],
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final memory = item.memory;
              final due = memory == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      memory.due,
                      isUtc: true,
                    );
              final stage = memoryStageInfo(memory, nowUtc);
              final locked = due != null && due.isAfter(nowUtc);
              final history =
                  detail.histories[item.sense.id] ?? const <ReviewEvent>[];

              return Padding(
                padding: EdgeInsets.only(
                  bottom: index + 1 == items.length ? 0 : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    JournalSurface(
                      variant: JournalSurfaceVariant.elevated,
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (widget.embedded && index == 0) ...[
                                      Text(
                                        item.word.spelling,
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineMedium
                                            ?.copyWith(fontSize: 30),
                                      ),
                                      const SizedBox(height: 6),
                                    ],
                                    Text(
                                      item.sense.definition,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge,
                                    ),
                                    if (item.sense.phonetics != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        item.sense.phonetics!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(color: tokens.inkMuted),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              StatusBadge(label: stage.label, tone: stage.tone),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceMuted,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              item.sense.example.isEmpty
                                  ? '这份词库没有提供例句。'
                                  : item.sense.example,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(color: tokens.inkSecondary),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              Text(
                                due == null
                                    ? '尚未建立复习计划'
                                    : '下次复习 ${localDateTimeWithYearLabel(due)}',
                                style: JournalTokens.tabular(
                                  Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: tokens.inkSecondary),
                                ),
                              ),
                              FilledButton(
                                onPressed: locked
                                    ? null
                                    : () => _openStudy(item.sense.id),
                                child: Text(
                                  memory == null ? '学习这个词义' : '复习这个词义',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    _LearningHistorySection(
                      history: history,
                      engine: widget.dependencies.engine,
                    ),
                    const SizedBox(height: 18),
                    JournalSurface(
                      padding: const EdgeInsets.all(22),
                      child: MemoryCurveChart(
                        history: history,
                        engine: widget.dependencies.engine,
                        nowUtc: widget.dependencies.nowUtc(),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }
}
