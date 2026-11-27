import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'study_page.dart';
import 'spelling_practice_page.dart';
import 'journal_style.dart';

class TodayPage extends StatefulWidget {
  const TodayPage({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> {
  late Future<
    ({StudyStats stats, List<StudyItem> queue, int goal, int learned})
  >
  _data;
  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<({StudyStats stats, List<StudyItem> queue, int goal, int learned})>
  _load() async {
    final repo = widget.dependencies.repository;
    return (
      stats: await repo.stats(),
      queue: await repo.queue(),
      goal: await repo.dailyGoal(),
      learned: await repo.newLearnedToday(),
    );
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '把新词，变成老朋友。',
    subtitle: '每天一点，慢慢记牢。',
    children: [
      AsyncContent(
        future: _data,
        retry: () => setState(() => _data = _load()),
        builder: (data) {
          final due = data.queue.where((item) => item.memory != null).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              JournalPanel(
                color: Theme.of(context).colorScheme.primaryContainer,
                padding: const EdgeInsets.all(24),
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
                              Text(
                                data.queue.isEmpty ? '今天，也很有收获' : '留一点时间给记忆',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                data.queue.isEmpty
                                    ? '当前任务已完成'
                                    : '本轮 ${data.queue.length} 个词义 · 待复习 $due 个',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Image.asset(
                          'assets/images/study-books.png',
                          width: 86,
                          height: 100,
                          excludeFromSemantics: true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    FilledButton(
                      onPressed: data.queue.isEmpty
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) => StudyPage(
                                  dependencies: widget.dependencies,
                                ),
                              ),
                            ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(data.queue.isEmpty ? '等待下一次复习' : '开始学习'),
                          const SizedBox(width: 10),
                          JournalIcon(
                            Icons.arrow_forward,
                            size: 20,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              JournalPanel(
                child: StatStrip(
                  items: [
                    (label: '今日新词义', value: '${data.learned} / ${data.goal}'),
                    (label: '连续学习', value: '${data.stats.streak} 天'),
                    (
                      label: '近 7 天回忆成功率',
                      value: '${(data.stats.recentSuccessRate * 100).round()}%',
                    ),
                    (label: '今日完成', value: '${data.stats.today} 次'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        SpellingPracticePage(dependencies: widget.dependencies),
                  ),
                ),
                child: const Row(
                  children: [
                    JournalIcon(Icons.edit_outlined),
                    SizedBox(width: 14),
                    Expanded(child: Text('拼写练习')),
                    JournalIcon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text('你的词汇手账', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: data.stats.totalWords == 0
                    ? 0
                    : data.stats.learnedWords / data.stats.totalWords,
                minHeight: 8,
                semanticsLabel:
                    '已学 ${data.stats.learnedWords}，共 ${data.stats.totalWords} 个单词',
              ),
              const SizedBox(height: 10),
              Text(
                '已学 ${data.stats.learnedWords} / ${data.stats.totalWords} 个单词',
              ),
              const SizedBox(height: 32),
              Text(
                '安心离线学习 · 在设置中备份你的积累',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    ],
  );
}
