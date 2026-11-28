import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/wordbook_exchange.dart';
import 'common.dart';
import 'journal_style.dart';
import 'study_page.dart';

class WordbookPickedFile {
  const WordbookPickedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
}

typedef WordbookFilePicker = Future<WordbookPickedFile?> Function();
typedef WordbookFileParser = Future<ParsedWordbook> Function(
  WordbookPickedFile file,
  WordbookParseOptions options,
);
typedef WordbookTextParser = Future<ParsedWordbook> Function(
  String text,
  WordbookParseOptions options,
);

class WordbookImportPage extends StatefulWidget {
  const WordbookImportPage({
    super.key,
    required this.dependencies,
    this.filePicker,
    this.fileParser,
    this.textParser,
  });

  final AppDependencies dependencies;
  final WordbookFilePicker? filePicker;
  final WordbookFileParser? fileParser;
  final WordbookTextParser? textParser;

  @override
  State<WordbookImportPage> createState() => _WordbookImportPageState();
}

class _WordbookImportPageState extends State<WordbookImportPage> {
  static const _extensions = [
    'csv',
    'tsv',
    'txt',
    'json',
    'jsonl',
    'dat',
    'apkg',
    'xml',
    'zip',
    'mdx',
  ];

  final _name = TextEditingController();
  final _paste = TextEditingController();
  WordbookPickedFile? _file;
  String? _pasteText;
  ParsedWordbook? _parsed;
  List<WordbookEntryDraft> _entries = const [];
  List<WordbookParseIssue> _issues = const [];
  int _totalRows = 0;
  int _duplicateRows = 0;
  int _errorRows = 0;
  bool _wordListResolved = false;
  bool _showPaste = false;
  bool _loading = false;
  bool _picking = false;
  bool _importing = false;
  bool _starting = false;
  String? _error;
  String? _importError;
  String? _notice;
  WordbookImportResult? _result;
  WordbookParseOptions _options = const WordbookParseOptions();
  WordbookDelimiter? _pasteDelimiter;
  bool _pasteWordListMode = false;
  WordbookDelimiter _mappingDelimiter = WordbookDelimiter.tab;
  int? _mappingWord;
  int? _mappingDefinition;
  int? _mappingPhonetic;
  int? _mappingExample;
  bool _mappingSkipFirst = false;
  int _requestId = 0;
  bool _exitDialogOpen = false;
  bool _allowExit = false;
  bool _routePopped = false;
  String? _nameError;

  bool get _hasPendingChanges {
    if (_result != null) return false;
    return _file != null ||
        _pasteText != null ||
        _parsed != null ||
        _entries.isNotEmpty ||
        _name.text.trim().isNotEmpty ||
        (_showPaste && _paste.text.trim().isNotEmpty);
  }

  bool get _busyForBack => _importing || _starting;
  bool get _inputsLocked =>
      _importing || _starting || _exitDialogOpen || _allowExit;

  @override
  void dispose() {
    _name.dispose();
    _paste.dispose();
    super.dispose();
  }

  void _exitPage() {
    if (!mounted || _allowExit) return;
    _requestId++;
    setState(() => _allowExit = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_routePopped) Navigator.of(context).maybePop();
    });
  }

  Future<void> _handleBack() async {
    if (_exitDialogOpen || _allowExit) return;
    if (_busyForBack) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_importing ? '正在导入词书，请稍候…' : '正在设置学习词书，请稍候…')),
      );
      return;
    }
    if (!_hasPendingChanges) {
      _exitPage();
      return;
    }
    _exitDialogOpen = true;
    final discard = await confirmDiscardChanges(
      context,
      title: '放弃本次词书导入？',
      message: '继续导入会保留当前来源、名称、映射和预览；放弃并返回后不会写入词库。',
      keepLabel: '继续导入',
    );
    _exitDialogOpen = false;
    if (mounted) setState(() {});
    if (!mounted || !discard) return;
    // 只取消后续结果接收；已在运行的 isolate 不承诺终止。
    _requestId++;
    _exitPage();
  }

  Future<WordbookPickedFile?> _defaultPickFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择自定义词库文件',
      type: FileType.custom,
      allowedExtensions: _extensions,
    );
    if (picked == null) return null;
    int? knownLength;
    try {
      knownLength = picked.lengthSync();
    } catch (_) {
      try {
        knownLength = await picked.length();
      } catch (_) {
        knownLength = null;
      }
    }
    if (knownLength != null &&
        knownLength > WordbookFormatLimits.maxFileBytes) {
      throw const FormatException('文件超过 10 MB 限制。');
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in picked.readAsByteStream()) {
      if (builder.length + chunk.length > WordbookFormatLimits.maxFileBytes) {
        throw const FormatException('文件超过 10 MB 限制。');
      }
      builder.add(chunk);
    }
    return WordbookPickedFile(name: picked.name, bytes: builder.takeBytes());
  }

  Future<ParsedWordbook> _defaultParseFile(
    WordbookPickedFile file,
    WordbookParseOptions options,
  ) => Isolate.run(
    () => parseWordbookBytes(file.bytes, fileName: file.name, options: options),
  );

  Future<ParsedWordbook> _defaultParseText(
    String text,
    WordbookParseOptions options,
  ) => Isolate.run(
    () => parseWordbookText(text, fileName: '粘贴内容.txt', options: options),
  );

  Future<void> _pickFile() async {
    if (_loading || _importing || _picking || _exitDialogOpen || _allowExit) {
      return;
    }
    final requestId = ++_requestId;
    setState(() {
      _picking = true;
      _error = null;
      _importError = null;
      _notice = null;
    });
    try {
      final picked = await (widget.filePicker ?? _defaultPickFile)();
      if (picked == null ||
          !mounted ||
          requestId != _requestId ||
          _exitDialogOpen ||
          _allowExit) {
        return;
      }
      setState(() {
        _picking = false;
        _file = picked;
        _pasteText = null;
        _options = const WordbookParseOptions();
        _parsed = null;
        _entries = const [];
        _issues = const [];
        _result = null;
        _importError = null;
        _totalRows = 0;
        _duplicateRows = 0;
        _errorRows = 0;
        _wordListResolved = false;
        _mappingDelimiter = WordbookDelimiter.tab;
        _mappingWord = null;
        _mappingDefinition = null;
        _mappingPhonetic = null;
        _mappingExample = null;
        _mappingSkipFirst = false;
        _name.clear();
        _nameError = null;
      });
      await _parseSource(options: _options);
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _error = '$error';
        });
      }
    } finally {
      if (mounted && requestId == _requestId) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _parsePastedText() async {
    if (_loading || _importing || _picking || _exitDialogOpen || _allowExit) {
      return;
    }
    final text = _paste.text;
    if (text.trim().isEmpty) {
      setState(() => _error = '请先粘贴词语和定义文本。');
      return;
    }
    setState(() {
      _pasteText = text;
      _file = null;
      _parsed = null;
      _entries = const [];
      _issues = const [];
      _result = null;
      _importError = null;
      _options = WordbookParseOptions(
        delimiter: _pasteWordListMode ? null : _pasteDelimiter,
        forceWordList: _pasteWordListMode,
      );
      _totalRows = 0;
      _duplicateRows = 0;
      _errorRows = 0;
      _wordListResolved = false;
      _mappingDelimiter = WordbookDelimiter.tab;
      _mappingWord = null;
      _mappingDefinition = null;
      _mappingPhonetic = null;
      _mappingExample = null;
      _mappingSkipFirst = false;
      _name.clear();
      _nameError = null;
      _requestId++;
    });
    await _parseSource(options: _options);
  }

  Future<void> _parseSource({required WordbookParseOptions options}) async {
    if (_loading || _importing || _exitDialogOpen || _allowExit) return;
    final requestId = ++_requestId;
    final file = _file;
    final pasteText = _pasteText;
    if (file == null && (pasteText == null || pasteText.isEmpty)) return;
    setState(() {
      _loading = true;
      _error = null;
      _importError = null;
      _notice = null;
    });
    try {
      final parsed = file != null
          ? await (widget.fileParser ?? _defaultParseFile)(file, options)
          : await (widget.textParser ?? _defaultParseText)(pasteText!, options);
      if (!mounted || requestId != _requestId) return;
      var entries = parsed.entries;
      var issues = List<WordbookParseIssue>.of(parsed.issues);
      var duplicates = parsed.duplicateRows;
      var errors = parsed.errorRows;
      var resolved = false;
      if (parsed.wordOnlyEntries.isNotEmpty) {
        final resolution = await widget.dependencies.repository
            .resolveWordOnlyEntries(parsed.wordOnlyEntries);
        if (!mounted || requestId != _requestId) return;
        entries = resolution.entries;
        issues.addAll(resolution.issues);
        duplicates += resolution.duplicateRows;
        errors += resolution.errorRows;
        resolved = true;
      }
      if (!mounted || requestId != _requestId) return;
      _options = options;
      if (_name.text.trim().isEmpty) {
        _name.text = parsed.suggestedName;
      }
      final columns = parsed.columns;
      _mappingDelimiter =
          parsed.delimiter ?? options.delimiter ?? _mappingDelimiter;
      final available = [
        for (var index = 0; index < columns.length; index++)
          if (!parsed.metadataColumns.contains(index)) index,
      ];
      if (options.hasMapping) {
        _mappingWord = options.wordColumn;
        _mappingDefinition = options.definitionColumn;
        _mappingPhonetic = options.phoneticColumn;
        _mappingExample = options.exampleColumn;
        _mappingSkipFirst = options.skipFirstRow;
      } else if (parsed.wordColumn != null) {
        _mappingWord = parsed.wordColumn;
        _mappingDefinition = parsed.definitionColumn;
        _mappingPhonetic = parsed.phoneticColumn;
        _mappingExample = parsed.exampleColumn;
        _mappingSkipFirst = parsed.headerSkipped;
      } else {
        if (!available.contains(_mappingWord)) {
          _mappingWord = available.isNotEmpty ? available[0] : null;
        }
        if (!available.contains(_mappingDefinition)) {
          _mappingDefinition = available.length > 1 ? available[1] : null;
        }
        _mappingPhonetic = null;
        _mappingExample = null;
      }
      setState(() {
        _loading = false;
        _nameError = null;
        _parsed = parsed;
        _entries = entries;
        _issues = issues;
        _totalRows = parsed.totalRows;
        _duplicateRows = duplicates;
        _errorRows = errors;
        _wordListResolved = resolved;
      });
    } catch (error) {
      if (mounted && requestId == _requestId) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _applyMapping() async {
    if (_loading || _importing || _exitDialogOpen || _allowExit) return;
    final parsed = _parsed;
    if (parsed == null) return;
    if (_mappingWord == null || _mappingDefinition == null) {
      setState(() => _error = '请选择单词列和释义列。');
      return;
    }
    if (_mappingWord == _mappingDefinition) {
      setState(() => _error = '单词列和释义列不能是同一列。');
      return;
    }
    await _parseSource(
      options: WordbookParseOptions(
        delimiter: _mappingDelimiter,
        wordColumn: _mappingWord,
        definitionColumn: _mappingDefinition,
        phoneticColumn: _mappingPhonetic,
        exampleColumn: _mappingExample,
        skipFirstRow: _mappingSkipFirst,
      ),
    );
  }

  void _resetSource() {
    if (_importing || _starting || _exitDialogOpen || _allowExit) return;
    _requestId++;
    setState(() {
      _loading = false;
      _picking = false;
      _file = null;
      _pasteText = null;
      _parsed = null;
      _entries = const [];
      _issues = const [];
      _result = null;
      _error = null;
      _importError = null;
      _notice = null;
      _showPaste = false;
      _name.clear();
      _nameError = null;
      _paste.clear();
      _options = const WordbookParseOptions();
      _pasteDelimiter = null;
      _pasteWordListMode = false;
      _mappingDelimiter = WordbookDelimiter.tab;
      _mappingWord = null;
      _mappingDefinition = null;
      _mappingPhonetic = null;
      _mappingExample = null;
      _mappingSkipFirst = false;
      _totalRows = 0;
      _duplicateRows = 0;
      _errorRows = 0;
      _wordListResolved = false;
    });
  }

  void _cancelPaste() {
    if (_importing || _starting || _exitDialogOpen || _allowExit) return;
    _requestId++;
    setState(() {
      _showPaste = false;
      _paste.clear();
      _pasteText = null;
      _loading = false;
      _error = null;
      _importError = null;
      _notice = null;
      _nameError = null;
    });
  }

  Future<void> _import() async {
    if (_loading ||
        _importing ||
        _starting ||
        _result != null ||
        _exitDialogOpen ||
        _allowExit ||
        _nameError != null) {
      return;
    }
    final parsed = _parsed;
    if (parsed == null || parsed.requiresMapping || _error != null) return;
    final cleanName = _name.text.trim();
    if (cleanName.isEmpty) {
      setState(() => _nameError = '请填写 1 到 40 字的词书名称。');
      return;
    }
    if (cleanName.runes.length > 40) {
      setState(() => _nameError = '词书名称不能超过 40 字。');
      return;
    }
    if (_entries.isEmpty || _errorRows > 0) {
      setState(() => _error = '存在错误或没有可导入词条，请修正后重新选择。');
      return;
    }
    setState(() {
      _importing = true;
      _nameError = null;
      _error = null;
      _importError = null;
      _notice = null;
    });
    try {
      final result = await widget.dependencies.repository.importWordbook(
        name: cleanName,
        entries: _entries,
      );
      if (mounted) setState(() => _result = result);
    } catch (error) {
      if (mounted) {
        setState(() => _importError = '导入失败，原有数据未变：$error');
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _setActiveAndStart() async {
    final result = _result;
    if (result == null || _starting || _exitDialogOpen || _allowExit) return;
    setState(() {
      _starting = true;
      _error = null;
      _importError = null;
    });
    try {
      await widget.dependencies.repository.setActiveWordbook(result.bookId);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              StudyPage(dependencies: widget.dependencies, todayPlan: true),
        ),
      );
    } catch (error) {
      if (mounted) {
        setState(() => _importError = '未能切换学习词书：$error');
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _saveTemplate(String format) async {
    final isCsv = format == 'csv';
    final content = isCsv ? wordbookCsvTemplate() : wordbookJsonTemplate();
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: '保存词书模板',
        fileName: 'lexi-loop-wordbook-template.${isCsv ? 'csv' : 'json'}',
        mimeType: isCsv ? 'text/csv' : 'application/json',
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (path != null && mounted) {
        setState(() => _notice = '模板已保存。');
      }
    } catch (error) {
      if (mounted) setState(() => _error = '模板保存失败：$error');
    }
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
          title: const Text('导入自定义词库'),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              width < 600 ? 18 : 36,
              12,
              width < 600 ? 18 : 36,
              36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_result != null)
                      _buildSuccess(context, tokens, _result!)
                    else ...[
                      Text(
                        '把你的词，带进来',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '支持 CSV、TSV、TXT、JSON、JSONL、Anki 纯文本；'
                        'Quizlet 可粘贴词语/定义。先预览校验，确认前不会写库。',
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: tokens.inkSecondary),
                      ),
                      const SizedBox(height: 18),
                      if (_file == null &&
                          (_pasteText == null || _parsed == null)) ...[
                        if (!_showPaste) ...[
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [
                              FilledButton.icon(
                                key: const ValueKey('pick-wordbook-file'),
                                onPressed:
                                    _loading ||
                                        _picking ||
                                        _importing ||
                                        _exitDialogOpen ||
                                        _allowExit
                                    ? null
                                    : _pickFile,
                                icon: const JournalIcon(
                                  Icons.file_upload_outlined,
                                  size: 18,
                                ),
                                label: const Text('选择文件'),
                              ),
                              OutlinedButton.icon(
                                key: const ValueKey('paste-wordbook-text'),
                                onPressed:
                                    _loading ||
                                        _picking ||
                                        _importing ||
                                        _exitDialogOpen ||
                                        _allowExit
                                    ? null
                                    : () => setState(() => _showPaste = true),
                                icon: const JournalIcon(
                                  Icons.edit_outlined,
                                  size: 18,
                                ),
                                label: const Text('粘贴文本'),
                              ),
                            ],
                          ),
                          if (_picking)
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: LinearProgressIndicator(),
                            ),
                        ] else
                          _buildPasteInput(context),
                      ],
                      const SizedBox(height: 14),
                      _buildFormatHelp(context, tokens),
                      if (_error != null ||
                          _importError != null ||
                          _notice != null) ...[
                        const SizedBox(height: 14),
                        _buildMessage(context, tokens),
                      ],
                      if (_loading)
                        Padding(
                          padding: const EdgeInsets.all(42),
                          child: Column(
                            children: [
                              const CircularProgressIndicator(),
                              const SizedBox(height: 14),
                              TextButton(
                                onPressed: _resetSource,
                                child: const Text('取消解析'),
                              ),
                            ],
                          ),
                        ),
                      if (!_loading && _parsed != null) ...[
                        const SizedBox(height: 20),
                        AbsorbPointer(
                          absorbing: _inputsLocked,
                          child: _buildPreview(context, tokens),
                        ),
                      ],
                      if (!_loading &&
                          _parsed == null &&
                          _error != null &&
                          (_file != null || _pasteText != null)) ...[
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () => _parseSource(options: _options),
                              child: const Text('重试解析'),
                            ),
                            OutlinedButton(
                              onPressed: _resetSource,
                              child: const Text('重新选择或粘贴'),
                            ),
                            TextButton(
                              onPressed: _handleBack,
                              child: const Text('返回'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormatHelp(BuildContext context, JournalTokens tokens) {
    return JournalSurface(
      variant: JournalSurfaceVariant.muted,
      padding: EdgeInsets.zero,
      child: Material(
        color: Colors.transparent,
        child: ExpansionTile(
          key: const ValueKey('wordbook-format-help'),
          leading: JournalIcon(
            Icons.menu_book_outlined,
            size: 20,
            color: tokens.inkSecondary,
          ),
          title: const Text('支持格式与限制'),
          subtitle: const Text('Anki 纯文本 · Quizlet 粘贴 · CSV/TSV/JSON/JSONL'),
          childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CSV / TSV / JSON / JSONL 支持 word 或 单词 与 definition 或 释义 等表头。'
                    'Anki 请在桌面端导出 Notes in Plain Text；Quizlet 使用导出的词语/定义文本，'
                    '可直接粘贴。其他软件请先导出表格或逐行单词。',
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: tokens.inkSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '支持 Anki 的 #separator / #html / #columns 与 column 元数据头；'
                    'APKG、ZIP、XML、MDX、加密包不能直接读取，请先在原软件导出 CSV/TSV/TXT。'
                    'terms.dat 仅按每行 JSON 的 JSONL 读取；纯单词 TXT 会用本地全部同拼写词义补全，'
                    '未匹配单词会报错。',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.inkMuted),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '上限：文件 10 MB、20,000 个词条；单词 128、释义 2,000、音标 200、例句 4,000 字符。'
                    '不支持 UTF-16 或任意 DAT 猜测。',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.inkMuted),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: _loading || _picking
                            ? null
                            : () => _saveTemplate('csv'),
                        child: const Text('保存 CSV 模板'),
                      ),
                      TextButton(
                        onPressed: _loading || _picking
                            ? null
                            : () => _saveTemplate('json'),
                        child: const Text('保存 JSON 模板'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasteInput(BuildContext context) {
    return JournalSurface(
      padding: const EdgeInsets.all(18),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('wordbook-paste-input'),
              controller: _paste,
              minLines: 6,
              maxLines: 10,
              decoration: const InputDecoration(
                labelText: '粘贴词语与定义（每行一条）',
                hintText: 'apple\t苹果\npear\t梨',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WordbookDelimiter?>(
              initialValue: _pasteDelimiter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '字段分隔符'),
              items: [
                const DropdownMenuItem<WordbookDelimiter?>(
                  value: null,
                  child: Text('自动识别'),
                ),
                ...WordbookDelimiter.values.map(
                  (delimiter) => DropdownMenuItem<WordbookDelimiter?>(
                    value: delimiter,
                    child: Text(delimiter.label),
                  ),
                ),
              ],
              onChanged: _pasteWordListMode
                  ? null
                  : (value) => setState(() => _pasteDelimiter = value),
            ),
            CheckboxListTile(
              key: const ValueKey('paste-word-list-mode'),
              contentPadding: EdgeInsets.zero,
              title: const Text('按纯单词列表补全'),
              subtitle: const Text('每行一个单词；使用本地词典补全全部同拼写词义。'),
              value: _pasteWordListMode,
              onChanged: (value) => setState(() {
                _pasteWordListMode = value ?? false;
              }),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('parse-pasted-wordbook'),
                  onPressed:
                      _loading ||
                          _picking ||
                          _importing ||
                          _exitDialogOpen ||
                          _allowExit
                      ? null
                      : _parsePastedText,
                  child: const Text('解析并预览'),
                ),
                TextButton(
                  onPressed: _importing || _exitDialogOpen || _allowExit
                      ? null
                      : _cancelPaste,
                  child: const Text('取消粘贴'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, JournalTokens tokens) {
    final parsed = _parsed!;
    final nameText = _name.text.trim();
    final nameValid = nameText.isNotEmpty && nameText.runes.length <= 40;
    final canImport =
        !_loading &&
        !_importing &&
        !_starting &&
        !_inputsLocked &&
        _error == null &&
        _nameError == null &&
        _errorRows == 0 &&
        _entries.isNotEmpty &&
        nameValid &&
        !parsed.requiresMapping;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JournalSurface(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: '确认词书'),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('import-book-name'),
                controller: _name,
                maxLength: 40,
                enabled: !_inputsLocked,
                decoration: InputDecoration(
                  labelText: '词书名称',
                  errorText:
                      _nameError ?? (nameText.isEmpty ? '请填写词书名称' : null),
                ),
                onChanged: (_) => setState(() => _nameError = null),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _CountPill(label: '总行数', value: '$_totalRows'),
                  _CountPill(label: '有效词条', value: '${_entries.length}'),
                  _CountPill(label: '重复行', value: '$_duplicateRows'),
                  _CountPill(
                    label: '错误行',
                    value: '$_errorRows',
                    warning: _errorRows > 0,
                  ),
                ],
              ),
              if (_wordListResolved) ...[
                const SizedBox(height: 10),
                Text(
                  '纯单词列表已用本地词典补全；同一拼写的全部本地词义都会导入，未匹配单词列为错误。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: tokens.inkSecondary),
                ),
              ],
            ],
          ),
        ),
        if (parsed.isWordList) ...[
          const SizedBox(height: 10),
          CheckboxListTile(
            key: const ValueKey('skip-word-list-header'),
            contentPadding: EdgeInsets.zero,
            title: const Text('跳过首个单词'),
            subtitle: const Text('用于首行是“word/单词”等表头或说明的纯单词列表。'),
            value: _options.skipFirstRow,
            onChanged: _loading
                ? null
                : (value) => _parseSource(
                    options: _options.copyWith(skipFirstRow: value ?? false),
                  ),
          ),
        ],
        if (parsed.requiresMapping) ...[
          const SizedBox(height: 14),
          _buildMapping(context, tokens, parsed),
        ] else if (parsed.delimiter != null) ...[
          const SizedBox(height: 14),
          JournalSurface(
            padding: EdgeInsets.zero,
            child: Material(
              color: Colors.transparent,
              child: ExpansionTile(
                key: const ValueKey('adjust-wordbook-columns'),
                title: const Text('调整列对应'),
                subtitle: Text(
                  '当前：单词第 ${(parsed.wordColumn ?? 0) + 1} 列 · '
                  '释义第 ${(parsed.definitionColumn ?? 1) + 1} 列',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                children: [_buildMapping(context, tokens, parsed)],
              ),
            ),
          ),
        ],
        if (_entries.isNotEmpty) ...[
          const SizedBox(height: 14),
          JournalSurface(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SectionHeader(title: '样例预览'),
                const SizedBox(height: 8),
                ..._entries
                    .take(5)
                    .map(
                      (entry) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.word,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              entry.definition,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: tokens.inkSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],
        if (_issues.isNotEmpty) ...[
          const SizedBox(height: 14),
          JournalSurface(
            color: _errorRows > 0
                ? tokens.again.background
                : tokens.hard.background,
            borderColor: _errorRows > 0
                ? tokens.again.border
                : tokens.hard.border,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _errorRows > 0 ? '需要修正的错误' : '导入提示',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: _errorRows > 0
                        ? tokens.again.foreground
                        : tokens.hard.foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                ..._issues
                    .take(12)
                    .map(
                      (issue) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '${issue.location}：${issue.message}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: issue.isError
                                    ? tokens.again.foreground
                                    : tokens.inkSecondary,
                              ),
                        ),
                      ),
                    ),
                if (_errorRows > _issues.where((issue) => issue.isError).length)
                  Text(
                    '还有 ${_errorRows - _issues.where((issue) => issue.isError).length} 个错误未展开。',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.inkSecondary),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              key: const ValueKey('confirm-import-wordbook'),
              onPressed: canImport ? _import : null,
              icon: _importing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const JournalIcon(Icons.check_circle_outline, size: 18),
              label: Text(_importing ? '正在导入…' : '确认导入'),
            ),
            OutlinedButton(
              onPressed:
                  _importing || _starting || _exitDialogOpen || _allowExit
                  ? null
                  : _resetSource,
              child: const Text('重新选择'),
            ),
            TextButton(
              onPressed:
                  _importing || _starting || _exitDialogOpen || _allowExit
                  ? null
                  : _handleBack,
              child: const Text('取消'),
            ),
          ],
        ),
        if (_errorRows > 0)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '存在错误时不能导入。请修正文件后重新选择，应用不会静默丢弃错误行。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.again.foreground),
            ),
          ),
      ],
    );
  }

  Widget _buildMapping(
    BuildContext context,
    JournalTokens tokens,
    ParsedWordbook parsed,
  ) {
    final columns = [
      for (var index = 0; index < parsed.columns.length; index++)
        if (!parsed.metadataColumns.contains(index)) index,
    ];
    String label(int index) {
      final name = parsed.columns[index].trim();
      return name.isEmpty ? '第 ${index + 1} 列' : name;
    }

    Widget columnDropdown({
      required String labelText,
      required int? value,
      required ValueChanged<int?> onChanged,
      bool required = false,
    }) {
      return DropdownButtonFormField<int>(
        key: ValueKey('mapping-$labelText-$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: labelText),
        items: [
          if (!required)
            const DropdownMenuItem<int>(value: null, child: Text('不导入')),
          ...columns.map(
            (index) => DropdownMenuItem<int>(
              value: index,
              child: Text(
                label(index),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
        onChanged: _loading ? null : onChanged,
      );
    }

    return JournalSurface(
      padding: const EdgeInsets.all(18),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(title: '需要选择列'),
            const SizedBox(height: 8),
            Text(
              '没有识别到可靠表头。请选择分隔符与单词/释义列；GUID、标签、牌组列已从候选中排除。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: tokens.inkSecondary),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<WordbookDelimiter>(
              key: ValueKey('mapping-delimiter-${_mappingDelimiter.name}'),
              initialValue: _mappingDelimiter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '分隔符'),
              items: WordbookDelimiter.values
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(value.label),
                    ),
                  )
                  .toList(),
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value == null) return;
                      _mappingDelimiter = value;
                      _mappingWord = null;
                      _mappingDefinition = null;
                      _mappingPhonetic = null;
                      _mappingExample = null;
                      _parseSource(
                        options: WordbookParseOptions(
                          delimiter: value,
                          skipFirstRow: _mappingSkipFirst,
                        ),
                      );
                    },
            ),
            const SizedBox(height: 10),
            columnDropdown(
              labelText: '单词列',
              value: columns.contains(_mappingWord) ? _mappingWord : null,
              required: true,
              onChanged: (value) => setState(() => _mappingWord = value),
            ),
            const SizedBox(height: 10),
            columnDropdown(
              labelText: '释义列',
              value: columns.contains(_mappingDefinition)
                  ? _mappingDefinition
                  : null,
              required: true,
              onChanged: (value) => setState(() => _mappingDefinition = value),
            ),
            const SizedBox(height: 10),
            columnDropdown(
              labelText: '音标列（可选）',
              value: columns.contains(_mappingPhonetic)
                  ? _mappingPhonetic
                  : null,
              onChanged: (value) => setState(() => _mappingPhonetic = value),
            ),
            const SizedBox(height: 10),
            columnDropdown(
              labelText: '例句列（可选）',
              value: columns.contains(_mappingExample) ? _mappingExample : null,
              onChanged: (value) => setState(() => _mappingExample = value),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('首行是表头，跳过'),
              value: _mappingSkipFirst,
              onChanged: (value) =>
                  setState(() => _mappingSkipFirst = value ?? false),
            ),
            if (parsed.sampleRows.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '样例：${parsed.sampleRows.first.join('  |  ')}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.inkMuted),
              ),
            ],
            const SizedBox(height: 12),
            FilledButton(
              key: const ValueKey('apply-wordbook-mapping'),
              onPressed: _loading ? null : _applyMapping,
              child: const Text('应用映射并预览'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessage(BuildContext context, JournalTokens tokens) {
    final message = _error ?? _importError ?? _notice ?? '';
    final isError = _error != null || _importError != null;
    final tone = isError ? tokens.again : tokens.good;
    return JournalSurface(
      color: tone.background,
      borderColor: tone.border,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          JournalIcon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            size: 18,
            color: tone.foreground,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: tone.foreground)),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess(
    BuildContext context,
    JournalTokens tokens,
    WordbookImportResult result,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        JournalSurface(
          variant: JournalSurfaceVariant.hero,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('导入完成', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 8),
              Text(
                '“${result.bookName}”已创建。',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _CountPill(label: '词书词条', value: '${result.importedEntries}'),
                  _CountPill(label: '新增单词', value: '${result.newWords}'),
                  _CountPill(label: '新增词义', value: '${result.newSenses}'),
                  _CountPill(label: '复用词义', value: '${result.reusedSenses}'),
                ],
              ),
            ],
          ),
        ),
        if (_error != null || _importError != null) ...[
          const SizedBox(height: 14),
          _buildMessage(context, tokens),
        ],
        const SizedBox(height: 18),
        FilledButton(
          key: const ValueKey('start-imported-wordbook'),
          onPressed: _starting ? null : _setActiveAndStart,
          child: Text(_starting ? '正在准备学习…' : '设为学习词书并开始学习'),
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          onPressed: _starting ? null : _handleBack,
          child: const Text('返回词书页'),
        ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    this.warning = false,
  });
  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final tone = warning ? tokens.again.foreground : tokens.inkPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: warning ? tokens.again.background : tokens.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: warning ? tokens.again.border : tokens.border,
        ),
      ),
      child: Text(
        '$label $value',
        style: JournalTokens.tabular(
          Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tone, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
