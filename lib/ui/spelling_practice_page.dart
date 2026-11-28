import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'journal_style.dart';

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
  List<StudyItem> _items = const [];
  final List<StudyItem> _wrong = [];
  int _index = 0, _correct = 0;
  bool _checked = false, _right = false;
  bool _loading = true, _starting = false;
  String? _loadError, _answerError;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _startNewRound();
  }

  Future<void> _startNewRound() async {
    if (_starting) return;
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _loading = true;
      _loadError = null;
      _answerError = null;
    });
    try {
      final items = await widget.dependencies.repository.spellingSample(
        wordbookId: widget.wordbookId,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _items = items;
        _index = 0;
        _correct = 0;
        _checked = false;
        _right = false;
        _wrong.clear();
        _answer.clear();
        _loading = false;
        _starting = false;
      });
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() {
          _items = const [];
          _wrong.clear();
          _loading = false;
          _starting = false;
          _loadError = '$error';
        });
      }
    }
  }

  void _beginRound(List<StudyItem> items) {
    setState(() {
      _items = List<StudyItem>.unmodifiable(items);
      _index = 0;
      _correct = 0;
      _checked = false;
      _right = false;
      _wrong.clear();
      _answer.clear();
      _answerError = null;
      _loadError = null;
    });
  }

  void _retryWrong() {
    if (_wrong.isEmpty) return;
    _beginRound(List<StudyItem>.of(_wrong));
  }

  @override
  void dispose() {
    _answer.dispose();
    super.dispose();
  }

  void _check(StudyItem item) {
    if (_checked || _loading) return;
    if (_answer.text.trim().isEmpty) {
      setState(() => _answerError = '先写下你的答案。');
      return;
    }
    setState(() {
      _answerError = null;
      _checked = true;
      _right =
          _answer.text.trim().toLowerCase() == item.word.spelling.toLowerCase();
      if (_right) {
        _correct++;
      } else if (!_wrong.any((wrong) => wrong.word.id == item.word.id)) {
        _wrong.add(item);
      }
    });
  }

  void _next() {
    if (!_checked) return;
    setState(() {
      _index++;
      _checked = false;
      _right = false;
      _answer.clear();
      _answerError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        leading: journalBackButton(context),
        title: const Text('拼写练习'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            width < 600 ? 18 : 36,
            width < 600 ? 12 : 28,
            width < 600 ? 18 : 36,
            32,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '把记住的词，写下来',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '本轮成绩只保留在当前页面，不改变学习进度和复习计划。',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.inkSecondary),
                  ),
                  const SizedBox(height: 22),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(56),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_loadError != null)
                    MessagePanel(
                      title: '暂时无法读取拼写题目',
                      message: '$_loadError',
                      icon: Icons.error_outline,
                      action: OutlinedButton(
                        onPressed: _startNewRound,
                        child: const Text('重试'),
                      ),
                    )
                  else if (_items.isEmpty)
                    const MessagePanel(
                      title: '还没有可练习的词',
                      message: '换一本有词条的词书后再试。',
                    )
                  else if (_index >= _items.length)
                    _buildCompletion(context, tokens)
                  else
                    _buildQuestion(context, tokens, width, _items[_index]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompletion(BuildContext context, JournalTokens tokens) {
    final ratio = (_correct * 100 / _items.length).round();
    return JournalSurface(
      variant: JournalSurfaceVariant.elevated,
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('拼写练习完成', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '答对 $_correct / ${_items.length}，正确率 $ratio%。',
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: tokens.inkSecondary),
          ),
          if (_wrong.isNotEmpty) ...[
            const SizedBox(height: 18),
            Divider(color: tokens.border),
            const SizedBox(height: 14),
            Text(
              '本轮错词',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ..._wrong.map(
              (item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.word.spelling,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      item.sense.definition,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: tokens.inkSecondary),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const ValueKey('retry-wrong-spelling'),
              onPressed: _retryWrong,
              child: const Text('仅重练错词'),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            key: const ValueKey('restart-spelling'),
            onPressed: _startNewRound,
            child: const Text('重新随机一轮'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    JournalTokens tokens,
    double width,
    StudyItem item,
  ) {
    final answered = _index + (_checked ? 1 : 0);
    final feedbackTone = _right ? tokens.good : tokens.again;
    return JournalSurface(
      variant: JournalSurfaceVariant.elevated,
      padding: EdgeInsets.all(width < 600 ? 20 : 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '第 ${_index + 1} / ${_items.length} 题 · 已答对 $_correct / $answered',
                  style: JournalTokens.tabular(
                    Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.inkSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          JournalProgressBar(value: answered / _items.length, height: 6),
          const SizedBox(height: 24),
          Text(
            item.sense.definition,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _answer,
            readOnly: _checked,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: '写出英文单词',
              errorText: _answerError,
            ),
            onSubmitted: (_) => _check(item),
          ),
          const SizedBox(height: 20),
          if (!_checked)
            FilledButton(
              onPressed: () => _check(item),
              child: const Text('检查答案'),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: feedbackTone.background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: feedbackTone.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _right ? '答对了！' : '正确答案：${item.word.spelling}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: feedbackTone.foreground,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.sense.example.isEmpty
                        ? '这份词库没有提供例句。'
                        : item.sense.example,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.inkSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _next,
              child: Text(_index + 1 == _items.length ? '查看本轮成绩' : '下一题'),
            ),
          ],
        ],
      ),
    );
  }
}
