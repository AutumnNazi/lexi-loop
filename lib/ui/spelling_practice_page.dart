import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
import 'common.dart';

class SpellingPracticePage extends StatefulWidget {
  const SpellingPracticePage({
    super.key,
    required this.dependencies,
    this.wordbookId,
  });
  final AppDependencies dependencies;
  final String? wordbookId;
  @override
  State<SpellingPracticePage> createState() => _SpellingPracticePageState();
}

class _SpellingPracticePageState extends State<SpellingPracticePage> {
  final _answer = TextEditingController();
  late final Future<List<StudyItem>> _items = _load();
  int _index = 0, _correct = 0;
  bool _checked = false, _right = false;
  String? _error;
  Future<List<StudyItem>> _load() async {
    final entries = await widget.dependencies.repository.entries(
      wordbookId: widget.wordbookId,
    );
    final words = {
      for (final item in entries) item.word.id: item,
    }.values.toList()..shuffle();
    return words.take(10).toList();
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _check(StudyItem item) {
    if (_checked) return;
    if (_answer.text.trim().isEmpty) {
      setState(() => _error = '先写下你的答案。');
      return;
    }
    setState(() {
      _error = null;
      _checked = true;
      _right =
          _answer.text.trim().toLowerCase() == item.word.spelling.toLowerCase();
      if (_right) _correct++;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: journalBackButton(context),
      title: const Text('拼写练习'),
    ),
    body: SafeArea(
      child: PageFrame(
        title: '把记住的词，写下来',
        subtitle: '本轮成绩只保留在当前页面，不改变学习进度和复习计划。',
        children: [
          AsyncContent(
            future: _items,
            builder: (items) {
              if (items.isEmpty) {
                return const MessagePanel(
                  title: '词书还是空的',
                  message: '选择有词条的词书后再试。',
                );
              }
              if (_index >= items.length) {
                return MessagePanel(
                  title: '拼写练习完成',
                  message:
                      '答对 $_correct / ${items.length}，正确率 ${(_correct * 100 / items.length).round()}%。',
                  action: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('返回'),
                  ),
                );
              }
              final item = items[_index];
              final answered = _index + (_checked ? 1 : 0);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '第 ${_index + 1} / ${items.length} 题 · 已答对 $_correct / $answered',
                  ),
                  const SizedBox(height: 24),
                  Text(
                    item.sense.definition,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _answer,
                    readOnly: _checked,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    decoration: InputDecoration(
                      labelText: '写出英文单词',
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _check(item),
                  ),
                  const SizedBox(height: 24),
                  if (!_checked)
                    FilledButton(
                      onPressed: () => _check(item),
                      child: const Text('检查答案'),
                    )
                  else ...[
                    Text(
                      _right ? '答对了！' : '正确答案：${item.word.spelling}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    Text(item.sense.example),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => setState(() {
                        _index++;
                        _checked = false;
                        _answer.clear();
                      }),
                      child: Text(
                        _index + 1 == items.length ? '查看本轮成绩' : '下一题',
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    ),
  );
}
