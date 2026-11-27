import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'memory_curve_chart.dart';
import 'study_page.dart';

class WordDetailPage extends StatefulWidget {
  const WordDetailPage({
    super.key,
    required this.dependencies,
    required this.wordId,
  });
  final AppDependencies dependencies;
  final int wordId;
  @override
  State<WordDetailPage> createState() => _WordDetailPageState();
}

class _WordDetailPageState extends State<WordDetailPage> {
  late Future<List<StudyItem>> _items;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _items = widget.dependencies.repository.entries().then(
      (items) => items.where((item) => item.word.id == widget.wordId).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: journalBackButton(context),
      title: const Text('词条详情'),
    ),
    body: SafeArea(
      child: AsyncContent(
        future: _items,
        retry: () => setState(_reload),
        builder: (items) => items.isEmpty
            ? const MessagePanel(
                title: '词条不存在',
                message: '备份恢复后内容可能已变化，请返回词书刷新。',
              )
            : PageFrame(
                title: items.first.word.spelling,
                subtitle: '每个词义独立记忆，跨词书共享学习进度。',
                children: items.map((item) {
                  final memory = item.memory;
                  final due = memory == null
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(
                          memory.due,
                          isUtc: true,
                        );
                  final state = memory == null
                      ? '尚未学习'
                      : switch (memory.state) {
                          1 => '学习中',
                          2 => '复习中',
                          _ => '重新学习',
                        };
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          item.sense.definition,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        if (item.sense.phonetics != null)
                          Text(item.sense.phonetics!),
                        const SizedBox(height: 12),
                        Text(
                          item.sense.example,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '$state${due == null ? '' : ' · 下次复习 ${localDateTimeLabel(due)}'}',
                        ),
                        const SizedBox(height: 16),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed:
                                due != null &&
                                    due.isAfter(widget.dependencies.nowUtc())
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => StudyPage(
                                          dependencies: widget.dependencies,
                                          senseId: item.sense.id,
                                        ),
                                      ),
                                    );
                                    if (mounted) setState(_reload);
                                  },
                            child: Text(memory == null ? '学习这个词义' : '复习这个词义'),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Divider(),
                        const SizedBox(height: 28),
                        AsyncContent(
                          future: widget.dependencies.repository.history(
                            senseId: item.sense.id,
                          ),
                          builder: (history) => MemoryCurveChart(
                            history: history,
                            engine: widget.dependencies.engine,
                            nowUtc: widget.dependencies.nowUtc(),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    ),
  );
}
