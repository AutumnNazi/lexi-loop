import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../data/app_database.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'word_detail_page.dart';
import 'spelling_practice_page.dart';
import 'journal_style.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String? _bookId;
  String _search = '';
  late Future<({List<Wordbook> books, List<StudyItem> items})> _data;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _data = _load();
  }

  Future<({List<Wordbook> books, List<StudyItem> items})> _load() async => (
    books: await widget.dependencies.repository.books(),
    items: await widget.dependencies.repository.entries(
      wordbookId: _bookId,
      search: _search,
    ),
  );

  Future<void> _createBook() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CreateWordbookPage(dependencies: widget.dependencies),
      ),
    );
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '我的词汇书架',
    subtitle: '收藏遇见的词，把它们慢慢记牢。',
    actions: [
      OutlinedButton.icon(
        onPressed: _createBook,
        icon: const JournalIcon(Icons.add),
        label: const Text('自建词书'),
      ),
      OutlinedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SpellingPracticePage(
              dependencies: widget.dependencies,
              wordbookId: _bookId,
            ),
          ),
        ),
        icon: const JournalIcon(Icons.edit_outlined),
        label: const Text('拼写练习'),
      ),
    ],
    children: [
      TextField(
        decoration: const InputDecoration(
          labelText: '搜索单词或释义',
          prefixIcon: Padding(
            padding: EdgeInsets.all(14),
            child: JournalIcon(Icons.search),
          ),
        ),
        onChanged: (value) => setState(() {
          _search = value;
          _reload();
        }),
      ),
      const SizedBox(height: 24),
      AsyncContent(
        future: _data,
        retry: () => setState(_reload),
        builder: (data) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('全部词书'),
                  selected: _bookId == null,
                  onSelected: (_) => setState(() {
                    _bookId = null;
                    _reload();
                  }),
                ),
                ...data.books.map(
                  (book) => ChoiceChip(
                    label: Text(book.name),
                    selected: _bookId == book.id,
                    onSelected: (_) => setState(() {
                      _bookId = book.id;
                      _reload();
                    }),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (data.items.isEmpty)
              const MessagePanel(
                icon: Icons.search_off,
                title: '没有找到匹配的词条',
                message: '试试其他单词或中文释义。',
              ),
            ...data.items.map(
              (item) => Column(
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    title: Text(
                      item.word.spelling,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    subtitle: Text(item.sense.definition),
                    trailing: JournalIcon(
                      item.memory == null
                          ? Icons.chevron_right
                          : Icons.check_circle_outline,
                    ),
                    onTap: () async {
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
                  ),
                  const Divider(height: 1),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CreateWordbookPage extends StatefulWidget {
  const _CreateWordbookPage({required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<_CreateWordbookPage> createState() => _CreateWordbookPageState();
}

class _CreateWordbookPageState extends State<_CreateWordbookPage> {
  final _name = TextEditingController();
  final _selected = <int>{};
  late final _items = widget.dependencies.repository.entries();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.dependencies.repository.createWordbook(
        _name.text,
        _selected,
      );
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
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: journalBackButton(context),
      title: const Text('自建词书'),
    ),
    body: SafeArea(
      child: PageFrame(
        title: '把想学的词放在一起',
        subtitle: '从内置词义中选择；已有学习进度会自动共享。',
        children: [
          TextField(
            controller: _name,
            maxLength: 40,
            decoration: const InputDecoration(labelText: '词书名称'),
          ),
          AsyncContent(
            future: _items,
            builder: (items) => Column(
              children: items
                  .map(
                    (item) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.word.spelling),
                      subtitle: Text(item.sense.definition),
                      value: _selected.contains(item.sense.id),
                      onChanged: _busy
                          ? null
                          : (checked) => setState(() {
                              if (checked == true) {
                                _selected.add(item.sense.id);
                              } else {
                                _selected.remove(item.sense.id);
                              }
                            }),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (_error != null) Text(_error!),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '正在保存…' : '创建词书（${_selected.length} 个词义）'),
          ),
        ],
      ),
    ),
  );
}
