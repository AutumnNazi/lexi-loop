import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/app_database.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'journal_style.dart';
import 'spelling_practice_page.dart';
import 'study_page.dart';

typedef _TodaySnapshot = ({
  StudyStats stats,
  StudyQueueStatus status,
  List<Wordbook> books,
  Wordbook? activeBook,
  ({int learned, int total}) progress,
});

class TodayPage extends StatefulWidget {
  const TodayPage({
    super.key,
    required this.dependencies,
    this.refreshListenable,
  });

  final AppDependencies dependencies;
  final Listenable? refreshListenable;

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<_TodaySnapshot> _data;
  _TodaySnapshot? _cached;
  int _loadRevision = 0;
  bool _savingBook = false;
  String? _bookError;

  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(_onRefreshSignal);
    _data = _load();
  }

  @override
  void didUpdateWidget(covariant TodayPage oldWidget) {
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
    setState(() {
      _data = _load();
    });
  }

  Future<_TodaySnapshot> _load() async {
    final revision = ++_loadRevision;
    final repo = widget.dependencies.repository;
    final activeBook = await repo.activeWordbook();
    final snapshot = (
      stats: await repo.stats(),
      status: await repo.activeBookQueueStatus(activeBook),
      books: await repo.books(),
      activeBook: activeBook,
      progress: await repo.wordProgress(wordbookId: activeBook?.id),
    );
    if (mounted && revision == _loadRevision) {
      _cached = snapshot;
    }
    return snapshot;
  }

  Future<void> _openStudy() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudyPage(dependencies: widget.dependencies, todayPlan: true),
      ),
    );
    if (mounted) {
      setState(() {
        _data = _load();
      });
    }
  }

  Future<void> _changeBook(String? id) async {
    if (_savingBook) return;
    setState(() {
      _savingBook = true;
      _bookError = null;
    });
    try {
      await widget.dependencies.repository.setActiveWordbook(
        id == '' ? null : id,
      );
      if (!mounted) return;
      setState(() {
        _data = _load();
      });
      await _data;
    } catch (error) {
      if (mounted) setState(() => _bookError = '未能切换词书：$error');
    } finally {
      if (mounted) setState(() => _savingBook = false);
    }
  }

  void _openSpelling(String? wordbookId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpellingPracticePage(
          dependencies: widget.dependencies,
          wordbookId: wordbookId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final nowUtc = widget.dependencies.nowUtc();
    return PageFrame(
      title: '把新词，变成老朋友。',
      subtitle: '每天一点，慢慢记牢。',
      children: [
        FutureBuilder<_TodaySnapshot>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return MessagePanel(
                title: '暂时无法读取数据',
                message: '${snapshot.error}',
                icon: Icons.error_outline,
                action: OutlinedButton(
                  onPressed: _onRefreshSignal,
                  child: const Text('重试'),
                ),
              );
            }
            final data = snapshot.data ?? _cached;
            if (data == null) {
              return const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final queue = data.status.items;
            final goal = data.status.dailyGoal;
            final learned = data.status.learnedToday;
            final dueCount = queue.where((item) => item.memory != null).length;
            final newCount = queue.length - dueCount;
            final totalRatio = data.progress.total == 0
                ? 0.0
                : data.progress.learned / data.progress.total;
            final goalRatio = goal <= 0
                ? 0.0
                : (learned / goal).clamp(0.0, 1.0);

            final heroCard = _HeroTaskCard(
              status: data.status,
              now: nowUtc,
              queueCount: queue.length,
              dueCount: dueCount,
              newCount: newCount,
              onStart: queue.isEmpty || _savingBook ? null : _openStudy,
            );

            final notebookCard = _NotebookProgressCard(
              learnedWords: data.progress.learned,
              totalWords: data.progress.total,
              ratio: totalRatio,
              onOpenSpelling: _savingBook
                  ? null
                  : () => _openSpelling(data.activeBook?.id),
              books: data.books,
              activeBookId: data.activeBook?.id,
              onBookChanged: _savingBook ? null : _changeBook,
              bookError: _bookError,
            );

            final compact = MediaQuery.sizeOf(context).width < 600;
            final rhythmCard = JournalSurface(
              padding: EdgeInsets.all(compact ? 16 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionHeader(title: '学习节律'),
                  SizedBox(height: compact ? 12 : 16),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCell(
                          label: '今日新词义',
                          value: goal == 0 ? '仅复习' : '$learned / $goal',
                          footnote: JournalProgressBar(
                            value: goalRatio,
                            height: 6,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: MetricCell(
                          label: '连续学习',
                          value: '${data.stats.streak} 天',
                          accent: data.stats.streak > 0,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 14 : 18),
                  Row(
                    children: [
                      Expanded(
                        child: MetricCell(
                          label: '近 7 天回忆成功率',
                          value:
                              '${(data.stats.recentSuccessRate * 100).round()}%',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: MetricCell(
                          label: '今日完成',
                          value: '${data.stats.today} 次',
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 12 : 16),
                  Divider(color: tokens.border),
                  SizedBox(height: compact ? 8 : 12),
                  Text(
                    '安心离线学习 · 在设置中备份你的积累',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.inkMuted),
                  ),
                ],
              ),
            );

            return LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth >= 820) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            heroCard,
                            const SizedBox(height: 18),
                            notebookCard,
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(flex: 5, child: rhythmCard),
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    heroCard,
                    const SizedBox(height: 12),
                    rhythmCard,
                    const SizedBox(height: 12),
                    notebookCard,
                  ],
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _HeroTaskCard extends StatelessWidget {
  const _HeroTaskCard({
    required this.status,
    required this.now,
    required this.queueCount,
    required this.dueCount,
    required this.newCount,
    required this.onStart,
  });

  final StudyQueueStatus status;
  final DateTime now;
  final int queueCount;
  final int dueCount;
  final int newCount;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final finished = queueCount == 0;
    final compact = MediaQuery.sizeOf(context).width < 600;
    final onlyReview = status.dailyGoal == 0;
    final quotaDone = status.quotaExhausted && status.dailyGoal > 0;
    final nextDue = status.nextDue;
    final finishedBadge = onlyReview
        ? '仅安排复习'
        : quotaDone
        ? '今日新词额度已完成'
        : '当前范围暂无新词';
    final finishedTitle = onlyReview
        ? '今天，只和复习见面'
        : quotaDone
        ? '今天的新词，学到这里'
        : '当前范围没有新词';
    final finishedMessages = <String>[
      if (onlyReview)
        '每日新词目标为 0，当前只安排复习。\n'
            '${status.hasUnlearned ? '${status.scopeLabel}还有 ${status.unlearnedCount} 个未学词义。' : '${status.scopeLabel}暂无未学词义。'}'
      else if (quotaDone)
        '今天已完成 ${status.learnedToday} / ${status.dailyGoal} 个新词义；'
            '${status.scopeLabel}还有 ${status.unlearnedCount} 个未学词义，明天继续。'
      else
        '${status.scopeLabel}暂无未学词义。',
      if (nextDue != null)
        '下次复习：${localDateTimeLabel(nextDue)}'
            '（${intervalLabel(nextDue.difference(now))}后）。'
      else
        '当前也没有未来的复习安排。',
    ];
    return JournalSurface(
      variant: JournalSurfaceVariant.hero,
      padding: EdgeInsets.all(compact ? 16 : 20),
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: finished
                          ? [
                              StatusBadge(
                                label: finishedBadge,
                                tone: StatusBadgeTone.review,
                              ),
                            ]
                          : [
                              if (dueCount > 0)
                                StatusBadge(
                                  label: '待复习 $dueCount',
                                  tone: StatusBadgeTone.due,
                                ),
                              if (newCount > 0)
                                StatusBadge(
                                  label: '今日新词 $newCount',
                                  tone: StatusBadgeTone.review,
                                ),
                            ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      finished ? finishedTitle : '留一点时间给记忆',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      finished
                          ? finishedMessages.join('\n')
                          : '本轮 $queueCount 个词义 · 待复习 $dueCount 个',
                      style: Theme.of(context).textTheme.bodyMedium
                          ?.copyWith(color: tokens.inkSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Image.asset(
                'assets/images/study-books.png',
                width: 78,
                height: 92,
                excludeFromSemantics: true,
              ),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
              child: FilledButton(
                onPressed: onStart,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(finished ? '等待下一次复习' : '开始学习'),
                    const SizedBox(width: 8),
                    JournalIcon(
                      Icons.arrow_forward,
                      size: 18,
                      color: finished ? tokens.inkMuted : tokens.onPrimary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotebookProgressCard extends StatelessWidget {
  const _NotebookProgressCard({
    required this.learnedWords,
    required this.totalWords,
    required this.ratio,
    required this.onOpenSpelling,
    required this.books,
    required this.activeBookId,
    required this.onBookChanged,
    required this.bookError,
  });

  final int learnedWords;
  final int totalWords;
  final double ratio;
  final VoidCallback? onOpenSpelling;
  final List<Wordbook> books;
  final String? activeBookId;
  final ValueChanged<String?>? onBookChanged;
  final String? bookError;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return JournalSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              compact ? 16 : 20,
              compact ? 14 : 18,
              compact ? 16 : 20,
              compact ? 12 : 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionHeader(
                  title: '正在学习的词书',
                  trailing: Text(
                    '${(ratio * 100).round()}%',
                    style: JournalTokens.tabular(
                      Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: tokens.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: '新词来自'),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      key: const ValueKey('active-wordbook-selector'),
                      value: activeBookId ?? '',
                      isExpanded: true,
                      isDense: true,
                      icon: const RotatedBox(
                        quarterTurns: 1,
                        child: JournalIcon(Icons.chevron_right, size: 20),
                      ),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('全部词书')),
                        ...books.map(
                          (book) => DropdownMenuItem(
                            value: book.id,
                            child: Text(
                              book.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: onBookChanged,
                    ),
                  ),
                ),
                if (bookError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    bookError!,
                    style: TextStyle(color: tokens.again.foreground),
                  ),
                ],
                const SizedBox(height: 12),
                JournalProgressBar(
                  value: ratio,
                  height: 8,
                  semanticsLabel: '已学 $learnedWords，共 $totalWords 个单词',
                ),
                const SizedBox(height: 8),
                Text(
                  '已学 $learnedWords / $totalWords 个单词',
                  style: JournalTokens.tabular(
                    Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.inkSecondary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '新词按所选词书安排，全部已学词仍按时复习。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.inkSecondary),
                ),
              ],
            ),
          ),
          Divider(color: tokens.border),
          InkWell(
            onTap: onOpenSpelling,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(JournalTokens.radiusLg),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: compact ? 16 : 20,
                vertical: compact ? 12 : 15,
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tokens.surfaceMuted,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: JournalIcon(
                      Icons.edit_outlined,
                      size: 18,
                      color: tokens.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '拼写练习',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          '自由默写抽查 · 不影响复习调度',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.inkSecondary),
                        ),
                      ],
                    ),
                  ),
                  JournalIcon(
                    Icons.chevron_right,
                    size: 18,
                    color: tokens.inkSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
