import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
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

class _WordDetailBodyState extends State<WordDetailBody> {
  late Future<List<StudyItem>> _items;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant WordDetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.wordId != widget.wordId) {
      _reload();
    }
  }

  void _reload() {
    _items = widget.dependencies.repository.entries(wordId: widget.wordId);
  }

  Future<void> _openStudy(int senseId) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudyPage(dependencies: widget.dependencies, senseId: senseId),
      ),
    );
    if (mounted) {
      setState(_reload);
      widget.onChanged?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final nowUtc = widget.dependencies.nowUtc();

    return AsyncContent(
      future: _items,
      retry: () => setState(_reload),
      builder: (items) {
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
                                    : '下次复习 ${localDateTimeLabel(due)}',
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
                    JournalSurface(
                      padding: const EdgeInsets.all(22),
                      child: AsyncContent(
                        future: widget.dependencies.repository.history(
                          senseId: item.sense.id,
                        ),
                        builder: (history) => MemoryCurveChart(
                          history: history,
                          engine: widget.dependencies.engine,
                          nowUtc: widget.dependencies.nowUtc(),
                        ),
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
