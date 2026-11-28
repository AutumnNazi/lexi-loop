import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'journal_style.dart';

typedef SpellingSampleLoader = Future<List<StudyItem>> Function(
  String? wordbookId,
  EntryFilter filter,
  int limit,
);

class SpellingPracticePage extends StatefulWidget {
  const SpellingPracticePage({
    super.key,
    required this.dependencies,
    this.wordbookId,
    this.spellingLoader,
  });
  final AppDependencies dependencies;
  final String? wordbookId;
  final SpellingSampleLoader? spellingLoader;
  @override
  State<SpellingPracticePage> createState() => _SpellingPracticePageState();
}

class _SpellingPracticePageState extends State<SpellingPracticePage> {
  final _answer = TextEditingController();
  final _answerFocus = FocusNode();
  final _nextFocus = FocusNode();
  List<StudyItem> _items = const [];
  final List<StudyItem> _wrong = [];
  int _index = 0, _correct = 0;
  bool _checked = false, _right = false;
  bool _loading = true, _starting = false;
  String? _loadError, _answerError;
  int _generation = 0;
  bool _exitDialogOpen = false;
  bool _allowExit = false;
  bool _routePopped = false;
  bool _optionsOpen = false;
  EntryFilter _filter = EntryFilter.all;
  int _limit = 10;

  bool get _hasActiveDraft =>
      _items.isNotEmpty &&
      _index < _items.length &&
      (_index > 0 || _answer.text.trim().isNotEmpty || _checked);

  @override
  void initState() {
    super.initState();
    _startNewRound();
  }

  Future<void> _startNewRound() async {
    if (_starting || _optionsOpen || _exitDialogOpen || _allowExit) return;
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _loading = true;
      _loadError = null;
      _answerError = null;
      _items = const [];
      _wrong.clear();
      _index = 0;
      _correct = 0;
      _checked = false;
      _right = false;
      _answer.clear();
    });
    try {
      final loader = widget.spellingLoader;
      final items = await (loader != null
          ? loader(widget.wordbookId, _filter, _limit)
          : widget.dependencies.repository.spellingSample(
              wordbookId: widget.wordbookId,
              filter: _filter,
              limit: _limit,
            ));
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
      _focusAfterFrame(_answerFocus);
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
    _focusAfterFrame(_answerFocus);
  }

  void _retryWrong() {
    if (_wrong.isEmpty || _optionsOpen || _exitDialogOpen || _allowExit) {
      return;
    }
    _beginRound(List<StudyItem>.of(_wrong));
  }

  String get _scopeLabel => widget.wordbookId == null ? '全部词书' : '当前词书';
  String get _filterLabel => switch (_filter) {
    EntryFilter.all => '全部',
    EntryFilter.learned => '已学',
    EntryFilter.due => '待复习',
    EntryFilter.unlearned => '未学',
  };
  String get _emptyMessage => switch (_filter) {
    EntryFilter.learned => '当前词书中还没有已学的词义，先学习一些词再来练习。',
    EntryFilter.due => '当前词书中暂时没有到期词义，等复习时间到了再来。',
    EntryFilter.unlearned => '当前词书中没有符合条件的未学词义。',
    EntryFilter.all => '当前范围内还没有可练习的词。',
  };

  Future<void> _openOptions() async {
    if (_loading ||
        _starting ||
        _optionsOpen ||
        _exitDialogOpen ||
        _allowExit) {
      return;
    }
    setState(() => _optionsOpen = true);
    final result = await showDialog<({EntryFilter filter, int limit})>(
      context: context,
      builder: (dialogContext) {
        var draftFilter = _filter;
        var draftLimit = _limit;
        var responded = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final changed = draftFilter != _filter || draftLimit != _limit;
            final discardProgress = changed && _hasActiveDraft;
            void close([({EntryFilter filter, int limit})? value]) {
              if (responded) return;
              responded = true;
              Navigator.of(dialogContext).pop(value);
            }

            return AlertDialog(
              constraints: const BoxConstraints(maxWidth: 460),
              title: const Text('调整拼写练习'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('范围'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('spelling-filter-all'),
                          label: const Text('全部'),
                          selected: draftFilter == EntryFilter.all,
                          onSelected: (_) => setDialogState(
                            () => draftFilter = EntryFilter.all,
                          ),
                        ),
                        ChoiceChip(
                          key: const ValueKey('spelling-filter-learned'),
                          label: const Text('已学'),
                          selected: draftFilter == EntryFilter.learned,
                          onSelected: (_) => setDialogState(
                            () => draftFilter = EntryFilter.learned,
                          ),
                        ),
                        ChoiceChip(
                          key: const ValueKey('spelling-filter-due'),
                          label: const Text('待复习'),
                          selected: draftFilter == EntryFilter.due,
                          onSelected: (_) => setDialogState(
                            () => draftFilter = EntryFilter.due,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text('每轮题量'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final count in const [5, 10, 20])
                          ChoiceChip(
                            key: ValueKey('spelling-count-$count'),
                            label: Text('$count 词'),
                            selected: draftLimit == count,
                            onSelected: (_) =>
                                setDialogState(() => draftLimit = count),
                          ),
                      ],
                    ),
                    if (discardProgress) ...[
                      const SizedBox(height: 16),
                      Text(
                        '应用新选项会放弃当前题号、草稿和本轮错词。',
                        style: TextStyle(
                          color: JournalTokens.of(context).again.foreground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  key: const ValueKey('spelling-options-cancel'),
                  onPressed: () => close(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  key: const ValueKey('spelling-options-apply'),
                  onPressed: () =>
                      close((filter: draftFilter, limit: draftLimit)),
                  child: Text(
                    discardProgress
                        ? '放弃本轮并开始'
                        : changed
                        ? '开始新一轮'
                        : '保留当前练习',
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (!mounted) return;
    setState(() => _optionsOpen = false);
    if (result == null) return;
    if (result.filter == _filter && result.limit == _limit) return;
    setState(() {
      _filter = result.filter;
      _limit = result.limit;
    });
    await _startNewRound();
  }

  @override
  void dispose() {
    _answerFocus.dispose();
    _nextFocus.dispose();
    _answer.dispose();
    super.dispose();
  }

  void _focusAfterFrame(FocusNode node) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          !_optionsOpen &&
          !_exitDialogOpen &&
          !_loading &&
          !_starting &&
          !_allowExit &&
          node.canRequestFocus) {
        node.requestFocus();
      }
    });
  }

  void _check(StudyItem item) {
    if (_checked || _loading || _optionsOpen || _exitDialogOpen || _allowExit) {
      return;
    }
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
    _focusAfterFrame(_nextFocus);
  }

  void _reveal(StudyItem item) {
    if (_checked || _loading || _optionsOpen || _exitDialogOpen || _allowExit) {
      return;
    }
    setState(() {
      _answerError = null;
      _checked = true;
      _right = false;
      if (!_wrong.any((wrong) => wrong.word.id == item.word.id)) {
        _wrong.add(item);
      }
    });
    _focusAfterFrame(_nextFocus);
  }

  void _next() {
    if (!_checked || _optionsOpen || _exitDialogOpen || _allowExit) return;
    setState(() {
      _index++;
      _checked = false;
      _right = false;
      _answer.clear();
      _answerError = null;
    });
    _focusAfterFrame(_answerFocus);
  }

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || _optionsOpen || _allowExit) return;
    _exitDialogOpen = true;
    final discard = await confirmDiscardChanges(
      context,
      title: '放弃本轮拼写练习？',
      message: '继续练习会保留当前题号、草稿和本轮错词；放弃并返回后本轮成绩不会保存。',
      keepLabel: '继续练习',
    );
    _exitDialogOpen = false;
    if (mounted) setState(() {});
    if (!discard || !mounted) return;
    _exitWithoutPrompt();
  }

  Future<void> _handleBack() async {
    if (_allowExit || _exitDialogOpen || _optionsOpen) return;
    if (_hasActiveDraft) {
      await _confirmExit();
    } else {
      _exitWithoutPrompt();
    }
  }

  void _exitWithoutPrompt() {
    if (!mounted || _allowExit) return;
    _generation++;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_routePopped) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return PopScope(
      canPop: _allowExit,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _routePopped = true;
          return;
        }
        _handleBack();
      },
      child: Scaffold(
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
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '$_scopeLabel · $_filterLabel · 每轮 $_limit 词',
                          key: const ValueKey('spelling-current-options'),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: tokens.inkSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        OutlinedButton.icon(
                          key: const ValueKey('spelling-options'),
                          onPressed: _loading || _starting || _optionsOpen
                              ? null
                              : _openOptions,
                          icon: const JournalIcon(Icons.tune, size: 17),
                          label: const Text('调整练习'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
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
                        action: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _startNewRound,
                              child: const Text('重试'),
                            ),
                            OutlinedButton(
                              key: const ValueKey('spelling-options-error'),
                              onPressed: _openOptions,
                              child: const Text('调整练习'),
                            ),
                          ],
                        ),
                      )
                    else if (_items.isEmpty)
                      MessagePanel(
                        title: '当前范围没有可练习的词',
                        message: _emptyMessage,
                        icon: Icons.menu_book_outlined,
                        action: OutlinedButton(
                          key: const ValueKey('spelling-options-empty'),
                          onPressed: _openOptions,
                          child: const Text('调整练习'),
                        ),
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
          TextButton(onPressed: _handleBack, child: const Text('返回')),
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
          Focus(
            canRequestFocus: false,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                if (_checked) {
                  _next();
                } else {
                  _check(item);
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: _answer,
              focusNode: _answerFocus,
              readOnly: _checked,
              autocorrect: false,
              enableSuggestions: false,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() => _answerError = null),
              decoration: InputDecoration(
                labelText: '写出英文单词',
                errorText: _answerError,
              ),
              onSubmitted: (_) {
                if (_checked) {
                  _next();
                } else {
                  _check(item);
                }
              },
            ),
          ),
          const SizedBox(height: 20),
          if (!_checked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton(
                  onPressed: () => _check(item),
                  child: const Text('检查答案'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _reveal(item),
                  child: const Text('不知道，查看答案'),
                ),
              ],
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
              focusNode: _nextFocus,
              onPressed: _next,
              child: Text(_index + 1 == _items.length ? '查看本轮成绩' : '下一题'),
            ),
          ],
        ],
      ),
    );
  }
}
