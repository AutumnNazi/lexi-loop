import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/app_database.dart';
import '../data/study_repository.dart';
import '../data/wordbook_exchange.dart';
import 'common.dart';
import 'journal_style.dart';
import 'spelling_practice_page.dart';
import 'study_page.dart';
import 'wordbook_import_page.dart';
import 'word_detail_page.dart';

typedef _LibrarySnapshot = ({List<Wordbook> books, List<StudyItem> items});
const _libraryPageSize = 40;
const _entryFilters = [
  (filter: EntryFilter.all, label: '全部'),
  (filter: EntryFilter.unlearned, label: '未学'),
  (filter: EntryFilter.learned, label: '已学'),
  (filter: EntryFilter.due, label: '待复习'),
];

class LibraryPage extends StatefulWidget {
  const LibraryPage({
    super.key,
    required this.dependencies,
    this.refreshListenable,
  });

  final AppDependencies dependencies;
  final Listenable? refreshListenable;

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? _bookId;
  EntryFilter _filter = EntryFilter.all;
  String _search = '';
  int? _selectedWordId;
  int _entryCount = 0;
  int _shownEntryCount = _libraryPageSize;
  final TextEditingController _searchController = TextEditingController();
  late Future<_LibrarySnapshot> _data;
  _LibrarySnapshot? _cached;
  int _loadRevision = 0;
  String? _manageError;
  String? _manageNotice;

  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(_onRefreshSignal);
    _data = _load();
  }

  @override
  void didUpdateWidget(covariant LibraryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_onRefreshSignal);
      widget.refreshListenable?.addListener(_onRefreshSignal);
    }
    if (oldWidget.dependencies != widget.dependencies) _reload();
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_onRefreshSignal);
    _searchController.dispose();
    super.dispose();
  }

  void _onRefreshSignal() {
    if (!mounted) return;
    setState(_reload);
  }

  void _reload() {
    _data = _load();
  }

  Future<_LibrarySnapshot> _load() async {
    final revision = ++_loadRevision;
    final books = await widget.dependencies.repository.books();
    final bookId = _bookId != null && books.any((book) => book.id == _bookId)
        ? _bookId
        : null;
    final search = _search;
    final filter = _filter;
    final shownEntryCount = _shownEntryCount;
    final nowMilliseconds = widget.dependencies.nowUtc().millisecondsSinceEpoch;
    final items = await widget.dependencies.repository.entries(
      wordbookId: bookId,
      search: search,
      limit: shownEntryCount,
      filter: filter,
      nowMilliseconds: nowMilliseconds,
    );
    final entryCount = await widget.dependencies.repository.entryCount(
      wordbookId: bookId,
      search: search,
      filter: filter,
      nowMilliseconds: nowMilliseconds,
    );
    final snapshot = (books: books, items: items);
    if (mounted && revision == _loadRevision) {
      _cached = snapshot;
      _entryCount = entryCount;
      _bookId = bookId;
      _selectedWordId = items.isEmpty
          ? null
          : (items.any((item) => item.word.id == _selectedWordId)
                ? _selectedWordId
                : items.first.word.id);
    }
    return snapshot;
  }

  Future<void> _createBook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordbookEditorPage(dependencies: widget.dependencies),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _editBook(Wordbook book) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            WordbookEditorPage(dependencies: widget.dependencies, book: book),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _deleteBook(Wordbook book) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${book.name}”？'),
        content: const Text(
          '只会删除这本自建词书及其选词关联。词条、学习状态和评分历史都会保留；'
          '如果它正用于首页学习，首页会恢复为全部词书。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-wordbook'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除词书'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _manageError = null);
    try {
      await widget.dependencies.repository.deleteWordbook(book.id);
      if (!mounted) return;
      setState(() {
        _bookId = null;
        _shownEntryCount = _libraryPageSize;
        _reload();
      });
    } catch (error) {
      if (mounted) setState(() => _manageError = '未能删除词书：$error');
    }
  }

  void _openSpelling() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SpellingPracticePage(
          dependencies: widget.dependencies,
          wordbookId: _bookId,
        ),
      ),
    );
  }

  Future<void> _openStudy() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudyPage(dependencies: widget.dependencies, wordbookId: _bookId),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _importBook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WordbookImportPage(dependencies: widget.dependencies),
      ),
    );
    if (mounted) setState(_reload);
  }

  Future<void> _showExportDialog(Wordbook book) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('导出“${book.name}”'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('仅导出词条内容，不包含学习进度、评分历史或设置。'),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                FilledButton(
                  key: const ValueKey('export-wordbook-csv'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _exportBook(book, 'csv');
                  },
                  child: const Text('导出 CSV'),
                ),
                OutlinedButton(
                  key: const ValueKey('export-wordbook-json'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _exportBook(book, 'json');
                  },
                  child: const Text('导出 JSON'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'CSV 为 UTF-8 BOM，适合表格软件；JSON 适合保留词书名称和完整词条。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBook(Wordbook book, String format) async {
    setState(() {
      _manageError = null;
      _manageNotice = null;
    });
    try {
      final entries = await widget.dependencies.repository
          .exportWordbookEntries(book.id);
      final isCsv = format == 'csv';
      final content = isCsv
          ? exportWordbookCsv(book.name, entries)
          : exportWordbookJson(book.name, entries);
      final safeName = book.name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = await FilePicker.saveFile(
        dialogTitle: '导出词书',
        fileName: '$safeName.${isCsv ? 'csv' : 'json'}',
        mimeType: isCsv ? 'text/csv' : 'application/json',
        bytes: Uint8List.fromList(utf8.encode(content)),
      );
      if (path != null && mounted) {
        setState(() => _manageNotice = '已导出 ${entries.length} 个词条。');
      }
    } catch (error) {
      if (mounted) setState(() => _manageError = '导出失败：$error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final nowUtc = widget.dependencies.nowUtc();

    return Material(
      color: Colors.transparent,
      child: PageFrame(
        title: '我的词汇书架',
        subtitle: '收藏遇见的词，把它们慢慢记牢。',
        actions: [
          OutlinedButton.icon(
            onPressed: _createBook,
            icon: const JournalIcon(Icons.add, size: 18),
            label: const Text('自建词书'),
          ),
          OutlinedButton.icon(
            onPressed: _importBook,
            icon: const JournalIcon(Icons.file_upload_outlined, size: 18),
            label: const Text('导入词库'),
          ),
          OutlinedButton.icon(
            onPressed: _openSpelling,
            icon: const JournalIcon(Icons.edit_outlined, size: 18),
            label: const Text('拼写练习'),
          ),
        ],
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              labelText: '搜索单词或释义',
              prefixIcon: const Padding(
                padding: EdgeInsets.all(14),
                child: JournalIcon(Icons.search, size: 20),
              ),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清除搜索',
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _search = '';
                          _shownEntryCount = _libraryPageSize;
                          _reload();
                        });
                      },
                      icon: const JournalIcon(Icons.close, size: 18),
                    ),
            ),
            onChanged: (value) => setState(() {
              _search = value;
              _shownEntryCount = _libraryPageSize;
              _reload();
            }),
          ),
          const SizedBox(height: 16),
          FutureBuilder<_LibrarySnapshot>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return MessagePanel(
                  title: '暂时无法读取数据',
                  message: '${snapshot.error}',
                  icon: Icons.error_outline,
                  action: OutlinedButton(
                    onPressed: () => setState(_reload),
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

              final bookChips = Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('全部词书'),
                    selected: _bookId == null,
                    onSelected: (_) => setState(() {
                      _bookId = null;
                      _shownEntryCount = _libraryPageSize;
                      _reload();
                    }),
                  ),
                  ...data.books.map(
                    (book) => ChoiceChip(
                      label: Text(book.name),
                      selected: _bookId == book.id,
                      onSelected: (_) => setState(() {
                        _bookId = book.id;
                        _shownEntryCount = _libraryPageSize;
                        _reload();
                      }),
                    ),
                  ),
                ],
              );
              final selectedBook = data.books
                  .where((book) => book.id == _bookId)
                  .firstOrNull;
              final filterLabel = _entryFilters
                  .firstWhere((entry) => entry.filter == _filter)
                  .label;

              final effectiveSelectedId = data.items.isEmpty
                  ? null
                  : (data.items.any((e) => e.word.id == _selectedWordId)
                        ? _selectedWordId
                        : data.items.first.word.id);
              final hasMore = data.items.length < _entryCount;

              Widget buildList({required bool masterDetail}) {
                if (data.items.isEmpty) {
                  final searching = _search.trim().isNotEmpty;
                  final (title, message) = switch (_filter) {
                    EntryFilter.due =>
                      searching
                          ? ('没有匹配的待复习词义', '试试其他单词或释义，或清除搜索后查看全部到期词义。')
                          : ('当前没有到期词义', '这个范围内暂时没有需要复习的词义，到期后会自动刷新。'),
                    EntryFilter.unlearned =>
                      searching
                          ? ('没有匹配的未学词义', '试试其他单词、中文释义或筛选条件。')
                          : ('没有未学词义', '当前筛选范围内已经学过全部词义，可以切换到“已学”查看。'),
                    EntryFilter.learned =>
                      searching
                          ? ('没有匹配的已学词义', '试试其他单词、中文释义或筛选条件。')
                          : ('还没有已学词义', '完成一次学习后，就能在这里按记忆状态查找。'),
                    EntryFilter.all => ('没有找到匹配的词条', '试试其他单词、中文释义或筛选条件。'),
                  };
                  return MessagePanel(
                    icon: Icons.search_off,
                    title: title,
                    message: message,
                  );
                }
                return JournalSurface(
                  padding: EdgeInsets.zero,
                  child: ListView.builder(
                    shrinkWrap: true,
                    physics: masterDetail
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    itemCount:
                        data.items.length + (masterDetail && hasMore ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == data.items.length) {
                        return Center(
                          child: TextButton(
                            onPressed: () => setState(() {
                              _shownEntryCount += _libraryPageSize;
                              _reload();
                            }),
                            child: Text(
                              '加载更多（还剩 ${_entryCount - data.items.length} 个词义）',
                            ),
                          ),
                        );
                      }
                      final item = data.items[i];
                      final stage = memoryStageInfo(item.memory, nowUtc);
                      final selected =
                          masterDetail && item.word.id == effectiveSelectedId;
                      return Column(
                        children: [
                          Material(
                            color: selected
                                ? tokens.heroSurface.withValues(alpha: .72)
                                : Colors.transparent,
                            borderRadius: BorderRadius.vertical(
                              top: i == 0
                                  ? const Radius.circular(
                                      JournalTokens.radiusLg,
                                    )
                                  : Radius.zero,
                              bottom: i + 1 == data.items.length
                                  ? const Radius.circular(
                                      JournalTokens.radiusLg,
                                    )
                                  : Radius.zero,
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.vertical(
                                top: i == 0
                                    ? const Radius.circular(
                                        JournalTokens.radiusLg,
                                      )
                                    : Radius.zero,
                                bottom: i + 1 == data.items.length
                                    ? const Radius.circular(
                                        JournalTokens.radiusLg,
                                      )
                                    : Radius.zero,
                              ),
                              onTap: () async {
                                if (masterDetail) {
                                  setState(
                                    () => _selectedWordId = item.word.id,
                                  );
                                  return;
                                }
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => WordDetailPage(
                                      dependencies: widget.dependencies,
                                      wordId: item.word.id,
                                    ),
                                  ),
                                );
                                if (mounted) setState(_reload);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.word.spelling,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            _preview(
                                              item.sense.definition,
                                              120,
                                            ),
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
                                    StatusBadge(
                                      label: stage.label,
                                      tone: stage.tone,
                                    ),
                                    if (!masterDetail) ...[
                                      const SizedBox(width: 8),
                                      JournalIcon(
                                        Icons.chevron_right,
                                        size: 18,
                                        color: tokens.inkMuted,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          if (i + 1 < data.items.length)
                            Divider(height: 1, color: tokens.border),
                        ],
                      );
                    },
                  ),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  bookChips,
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _entryFilters
                        .map(
                          (entry) => ChoiceChip(
                            key: ValueKey(
                              'library-filter-${entry.filter.name}',
                            ),
                            label: Text(entry.label),
                            selected: _filter == entry.filter,
                            onSelected: (_) => setState(() {
                              _filter = entry.filter;
                              _shownEntryCount = _libraryPageSize;
                              _reload();
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${_bookId == null ? '全部词书' : selectedBook?.name ?? '词书'} · '
                    '$filterLabel · 共 $_entryCount 个词义'
                    '${_search.isEmpty ? '' : ' · 搜索“$_search”'}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: tokens.inkSecondary),
                  ),
                  if (selectedBook != null) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const ValueKey('export-wordbook'),
                          onPressed: () => _showExportDialog(selectedBook),
                          icon: const JournalIcon(
                            Icons.file_download_outlined,
                            size: 17,
                          ),
                          label: const Text('导出词书'),
                        ),
                        if (!selectedBook.isBuiltIn) ...[
                          OutlinedButton.icon(
                            key: const ValueKey('edit-wordbook'),
                            onPressed: () => _editBook(selectedBook),
                            icon: const JournalIcon(
                              Icons.edit_outlined,
                              size: 17,
                            ),
                            label: const Text('编辑词书'),
                          ),
                          TextButton.icon(
                            key: const ValueKey('delete-wordbook'),
                            onPressed: () => _deleteBook(selectedBook),
                            icon: const JournalIcon(Icons.close, size: 16),
                            label: const Text('删除词书'),
                          ),
                        ],
                      ],
                    ),
                    if (_manageError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _manageError!,
                        style: TextStyle(color: tokens.again.foreground),
                      ),
                    ],
                    if (_manageNotice != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _manageNotice!,
                        style: TextStyle(color: tokens.good.foreground),
                      ),
                    ],
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton(
                      onPressed: _openStudy,
                      child: Text(_bookId == null ? '学习全部词书' : '学习这本词书'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final masterDetail =
                          constraints.maxWidth >= 820 && data.items.isNotEmpty;
                      if (!masterDetail) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            buildList(masterDetail: false),
                            if (hasMore)
                              Center(
                                child: TextButton(
                                  onPressed: () => setState(() {
                                    _shownEntryCount += _libraryPageSize;
                                    _reload();
                                  }),
                                  child: Text(
                                    '加载更多（还剩 ${_entryCount - data.items.length} 个词义）',
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 5,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 820),
                              child: buildList(masterDetail: true),
                            ),
                          ),
                          const SizedBox(width: 22),
                          Expanded(
                            flex: 7,
                            child: SingleChildScrollView(
                              child: WordDetailBody(
                                dependencies: widget.dependencies,
                                wordId: effectiveSelectedId!,
                                embedded: true,
                                onChanged: () => setState(_reload),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

String _preview(String text, int maxLength) {
  final clean = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  return clean.length <= maxLength
      ? clean
      : '${clean.substring(0, maxLength)}…';
}

class WordbookEditorPage extends StatefulWidget {
  const WordbookEditorPage({
    super.key,
    required this.dependencies,
    this.book,
    this.existingItemsLoader,
  });
  final AppDependencies dependencies;
  final Wordbook? book;
  final Future<List<StudyItem>> Function(String wordbookId)?
  existingItemsLoader;
  @override
  State<WordbookEditorPage> createState() => _WordbookEditorPageState();
}

class _WordbookEditorPageState extends State<WordbookEditorPage> {
  late final TextEditingController _name;
  final _search = TextEditingController();
  final _selected = <int, StudyItem>{};
  String? _bookId;
  bool _selectedOnly = false;
  int _offset = 0;
  static const _pageSize = 40;
  late final _books = widget.dependencies.repository.books();
  late Future<({List<StudyItem> items, int total})> _items;
  bool _busy = false;
  bool _preparing = false;
  bool _selectionReady = true;
  String? _error;

  bool get _editing => widget.book != null;
  bool get _canSelect => !_busy && !_preparing && _selectionReady;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.book?.name ?? '');
    _preparing = _editing;
    _selectionReady = !_editing;
    _items = _load();
    if (_editing) _prepareExistingSelection();
  }

  Future<void> _prepareExistingSelection() async {
    setState(() {
      _preparing = true;
      _error = null;
    });
    try {
      final loader = widget.existingItemsLoader;
      final items = loader != null
          ? await loader(widget.book!.id)
          : await widget.dependencies.repository.itemsForSenses(
              await widget.dependencies.repository.senseIdsForWordbook(
                widget.book!.id,
              ),
            );
      if (!mounted) return;
      setState(() {
        _selected
          ..clear()
          ..addEntries(items.map((item) => MapEntry(item.sense.id, item)));
        _preparing = false;
        _selectionReady = true;
        _items = _load();
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _preparing = false;
          _selectionReady = false;
          _error = '暂时无法读取词书内容：$error';
        });
      }
    }
  }

  Future<({List<StudyItem> items, int total})> _load() async {
    if (_selectedOnly) {
      final selected = _selected.values.toList()
        ..sort((a, b) => a.sense.id.compareTo(b.sense.id));
      // 在已选列表取消最后一页的词义后，回到仍有内容的页面。
      final lastOffset = selected.isEmpty
          ? 0
          : (selected.length - 1) ~/ _pageSize * _pageSize;
      if (_offset > lastOffset) _offset = lastOffset;
      return (
        items: selected.skip(_offset).take(_pageSize).toList(),
        total: selected.length,
      );
    }
    final bookId = _bookId;
    final search = _search.text;
    final offset = _offset;
    final repository = widget.dependencies.repository;
    final items = await repository.entries(
      wordbookId: bookId,
      search: search,
      offset: offset,
      limit: _pageSize,
    );
    final total = await repository.entryCount(
      wordbookId: bookId,
      search: search,
    );
    return (items: items, total: total);
  }

  void _reload({bool resetPage = true}) {
    if (resetPage) _offset = 0;
    _items = _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_editing) {
        await widget.dependencies.repository.updateWordbook(
          widget.book!.id,
          _name.text,
          _selected.keys.toSet(),
        );
      } else {
        await widget.dependencies.repository.createWordbook(
          _name.text,
          _selected.keys.toSet(),
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(
        leading: journalBackButton(context),
        title: Text(_editing ? '编辑词书' : '自建词书'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  width < 600 ? 18 : 36,
                  12,
                  width < 600 ? 18 : 36,
                  24,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _editing ? '调整这本词书' : '把想学的词放在一起',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _editing
                              ? '可以改名，也可以继续从词书中增删词义；学习进度会继续共享。'
                              : '从内置词义中选择；已有学习进度会自动共享。',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: tokens.inkSecondary),
                        ),
                        const SizedBox(height: 20),
                        TextField(
                          key: const ValueKey('wordbook-name'),
                          controller: _name,
                          enabled: !_busy && !_preparing,
                          maxLength: 40,
                          decoration: const InputDecoration(labelText: '词书名称'),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('查找词义'),
                              selected: !_selectedOnly,
                              onSelected:
                                  _busy || _preparing || !_selectionReady
                                  ? null
                                  : (_) => setState(() {
                                      _selectedOnly = false;
                                      _reload();
                                    }),
                            ),
                            ChoiceChip(
                              key: const ValueKey('wordbook-selected-only'),
                              label: Text('已选词义（${_selected.length}）'),
                              selected: _selectedOnly,
                              onSelected:
                                  _busy || _preparing || !_selectionReady
                                  ? null
                                  : (_) => setState(() {
                                      _selectedOnly = true;
                                      _reload();
                                    }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (!_selectedOnly) ...[
                          AsyncContent(
                            future: _books,
                            builder: (books) => DropdownButtonFormField<String>(
                              key: const ValueKey('wordbook-source'),
                              initialValue: _bookId ?? '',
                              isExpanded: true,
                              icon: const RotatedBox(
                                quarterTurns: 1,
                                child: JournalIcon(
                                  Icons.chevron_right,
                                  size: 20,
                                ),
                              ),
                              decoration: const InputDecoration(
                                labelText: '从哪本词书选词',
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('全部词书'),
                                ),
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
                              onChanged: _canSelect
                                  ? (value) => setState(() {
                                      _bookId = value == '' ? null : value;
                                      _reload();
                                    })
                                  : null,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            key: const ValueKey('wordbook-search'),
                            controller: _search,
                            enabled: _canSelect,
                            decoration: InputDecoration(
                              labelText: '搜索单词或释义',
                              prefixIcon: const Padding(
                                padding: EdgeInsets.all(14),
                                child: JournalIcon(Icons.search, size: 20),
                              ),
                              suffixIcon: _search.text.isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: '清除搜索',
                                      onPressed: _canSelect
                                          ? () => setState(() {
                                              _search.clear();
                                              _reload();
                                            })
                                          : null,
                                      icon: const JournalIcon(
                                        Icons.close,
                                        size: 18,
                                      ),
                                    ),
                            ),
                            onChanged: (_) => setState(_reload),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '切换搜索、词书或页码，已勾选的词义都会保留。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.inkSecondary),
                          ),
                        ] else
                          Text(
                            '这里展示全部已选词义，可以取消勾选。',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.inkSecondary),
                          ),
                        const SizedBox(height: 16),
                        AsyncContent(
                          key: ObjectKey(_items),
                          future: _items,
                          retry: () =>
                              setState(() => _reload(resetPage: false)),
                          builder: (data) => JournalSurface(
                            padding: EdgeInsets.zero,
                            child: Material(
                              color: Colors.transparent,
                              child: Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Wrap(
                                      spacing: 16,
                                      runSpacing: 8,
                                      children: [
                                        Text('已选 ${_selected.length} 个词义'),
                                        Text(
                                          data.total == 0
                                              ? '0 个结果'
                                              : '${_offset + 1}–${_offset + data.items.length} / ${data.total}',
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (data.items.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        16,
                                        8,
                                        16,
                                        24,
                                      ),
                                      child: Text(
                                        _selectedOnly
                                            ? '还没有选择词义，去“查找词义”中添加。'
                                            : '没有找到匹配的词义，试试其他单词、中文释义或词书。',
                                      ),
                                    ),
                                  ...List.generate(data.items.length, (i) {
                                    final item = data.items[i];
                                    return Column(
                                      children: [
                                        CheckboxListTile(
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 14,
                                                vertical: 4,
                                              ),
                                          title: Text(
                                            item.word.spelling,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          subtitle: Text(
                                            _preview(
                                              item.sense.definition,
                                              120,
                                            ),
                                          ),
                                          value: _selected.containsKey(
                                            item.sense.id,
                                          ),
                                          onChanged: _canSelect
                                              ? (checked) => setState(() {
                                                  if (checked == true) {
                                                    _selected[item.sense.id] =
                                                        item;
                                                  } else {
                                                    _selected.remove(
                                                      item.sense.id,
                                                    );
                                                  }
                                                  if (_selectedOnly) {
                                                    _reload(resetPage: false);
                                                  }
                                                })
                                              : null,
                                        ),
                                        if (i + 1 < data.items.length)
                                          Divider(
                                            height: 1,
                                            color: tokens.border,
                                          ),
                                      ],
                                    );
                                  }),
                                  if (_offset > 0 ||
                                      _offset + data.items.length < data.total)
                                    Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Wrap(
                                        spacing: 12,
                                        children: [
                                          if (_offset > 0)
                                            TextButton(
                                              onPressed: _canSelect
                                                  ? () => setState(() {
                                                      _offset =
                                                          (_offset - _pageSize)
                                                              .clamp(
                                                                0,
                                                                1 << 30,
                                                              );
                                                      _reload(resetPage: false);
                                                    })
                                                  : null,
                                              child: const Text('上一页'),
                                            ),
                                          if (_offset + data.items.length <
                                              data.total)
                                            TextButton(
                                              onPressed: _canSelect
                                                  ? () => setState(() {
                                                      _offset += _pageSize;
                                                      _reload(resetPage: false);
                                                    })
                                                  : null,
                                              child: const Text('下一页'),
                                            ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: tokens.surface,
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              padding: EdgeInsets.fromLTRB(
                width < 600 ? 18 : 36,
                14,
                width < 600 ? 18 : 36,
                16,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        Text(
                          _error!,
                          style: TextStyle(color: tokens.again.foreground),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_editing && !_selectionReady && !_preparing) ...[
                        TextButton(
                          onPressed: _prepareExistingSelection,
                          child: const Text('重新读取词书内容'),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FilledButton(
                        onPressed: _busy || _preparing || !_selectionReady
                            ? null
                            : _save,
                        child: Text(
                          _busy
                              ? '正在保存…'
                              : _preparing
                              ? '正在读取词书…'
                              : _editing
                              ? '保存修改（${_selected.length} 个词义）'
                              : '创建词书（${_selected.length} 个词义）',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
