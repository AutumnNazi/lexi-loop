import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/data/wordbook_exchange.dart';
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:lexi_loop/ui/wordbook_import_page.dart';

void main() {
  Future<void> surface(
    WidgetTester tester, {
    double width = 390,
    double scale = 1.5,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  }

  ParsedWordbook parsed({
    List<WordbookEntryDraft> entries = const [],
    List<WordbookParseIssue> issues = const [],
    int totalRows = 0,
    int duplicates = 0,
    int errors = 0,
    bool requiresMapping = false,
    List<String> columns = const [],
    Set<int> metadataColumns = const {},
    int? wordColumn,
    int? definitionColumn,
    String name = '测试词书',
  }) => ParsedWordbook(
    suggestedName: name,
    entries: entries,
    wordOnlyEntries: const [],
    issues: issues,
    totalRows: totalRows,
    duplicateRows: duplicates,
    errorRows: errors,
    requiresMapping: requiresMapping,
    delimiter: WordbookDelimiter.tab,
    columns: columns,
    sampleRows: const [
      ['guid-1', 'apple', 'fruit', 'tag'],
    ],
    metadataColumns: metadataColumns,
    htmlFields: false,
    wordColumn: wordColumn,
    definitionColumn: definitionColumn,
  );

  AppDependencies createDependencies() {
    final dependencies = AppDependencies(AppDatabase(NativeDatabase.memory()));
    addTearDown(dependencies.dispose);
    return dependencies;
  }

  Future<void> pumpPage(
    WidgetTester tester,
    AppDependencies dependencies, {
    WordbookFilePicker? filePicker,
    WordbookFileParser? fileParser,
    WordbookTextParser? textParser,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        home: WordbookImportPage(
          dependencies: dependencies,
          filePicker: filePicker,
          fileParser: fileParser,
          textParser: textParser,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget importHost(
    AppDependencies dependencies, {
    WordbookFilePicker? filePicker,
    WordbookFileParser? fileParser,
    WordbookTextParser? textParser,
    bool deep = false,
  }) {
    Widget page() => WordbookImportPage(
      dependencies: dependencies,
      filePicker: filePicker,
      fileParser: fileParser,
      textParser: textParser,
    );
    return MaterialApp(
      theme: journalTheme(Brightness.light),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (secondContext) => deep
                      ? Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () => Navigator.of(secondContext).push(
                                MaterialPageRoute<void>(builder: (_) => page()),
                              ),
                              child: const Text('打开导入'),
                            ),
                          ),
                        )
                      : page(),
                ),
              ),
              child: Text(deep ? '进入二级' : '打开导入'),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('预览后确认导入，连点只创建一本词书并可一键开始学习', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '测试词书.csv', bytes: Uint8List(0));
    final result = parsed(
      totalRows: 2,
      entries: const [
        WordbookEntryDraft(word: 'apple', definition: '苹果'),
        WordbookEntryDraft(word: 'pear', definition: '梨'),
      ],
    );
    await pumpPage(
      tester,
      dependencies,
      filePicker: () async => file,
      fileParser: (_, _) async => result,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('pick-wordbook-file')),
    );
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    expect(find.text('总行数 2'), findsOneWidget);
    expect(find.text('有效词条 2'), findsOneWidget);
    expect(find.text('重复行 0'), findsOneWidget);
    expect(find.text('错误行 0'), findsOneWidget);
    expect(find.text('apple'), findsOneWidget);

    final confirm = find.byKey(const ValueKey('confirm-import-wordbook'));
    await tester.ensureVisible(confirm);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    await tester.tap(confirm);
    await tester.tap(confirm, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('导入完成'), findsOneWidget);
    expect(find.text('词书词条 2'), findsOneWidget);
    final books = await dependencies.repository.books();
    expect(
      books.where((book) => book.name == '测试词书' && !book.isBuiltIn),
      hasLength(1),
    );
    final book = books.singleWhere(
      (book) => book.name == '测试词书' && !book.isBuiltIn,
    );
    expect(
      await dependencies.repository.senseIdsForWordbook(book.id),
      hasLength(2),
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('start-imported-wordbook')),
    );
    await tester.tap(find.byKey(const ValueKey('start-imported-wordbook')));
    await tester.pumpAndSettle();
    expect((await dependencies.repository.activeWordbook())?.id, book.id);
    expect(find.text('词义回忆'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('有错误时禁止导入，可重新选择且不写库', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '错误词书.tsv', bytes: Uint8List(0));
    final result = parsed(
      totalRows: 2,
      errors: 1,
      entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
      issues: const [WordbookParseIssue(line: 2, message: '释义为空')],
    );
    await pumpPage(
      tester,
      dependencies,
      filePicker: () async => file,
      fileParser: (_, _) async => result,
    );
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm-import-wordbook'));
    await tester.ensureVisible(confirm);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(find.textContaining('存在错误时不能导入'), findsOneWidget);
    expect(find.textContaining('第 2 行'), findsOneWidget);
    expect(
      (await dependencies.repository.books()).where((book) => !book.isBuiltIn),
      isEmpty,
    );

    await tester.ensureVisible(find.text('重新选择'));
    await tester.tap(find.text('重新选择'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-wordbook-file')), findsOneWidget);
    expect(find.text('导入完成'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('文件选择防连点，解析错误可重试，旧结果不会覆盖新状态', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    var pickerCalls = 0;
    final gate = Completer<WordbookPickedFile?>();
    final file = WordbookPickedFile(name: '重试词书.csv', bytes: Uint8List(0));
    var parserCalls = 0;
    await pumpPage(
      tester,
      dependencies,
      filePicker: () {
        pickerCalls++;
        return pickerCalls == 1 ? gate.future : Future.value(file);
      },
      fileParser: (_, _) async {
        parserCalls++;
        if (parserCalls == 1) throw const FormatException('第一次解析失败');
        return parsed(
          totalRows: 1,
          entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
        );
      },
    );
    final pick = find.byKey(const ValueKey('pick-wordbook-file'));
    await tester.tap(pick);
    await tester.tap(pick, warnIfMissed: false);
    await tester.pump();
    expect(pickerCalls, 1);
    gate.complete(null);
    await tester.pumpAndSettle();

    await tester.tap(pick);
    await tester.pumpAndSettle();
    expect(find.textContaining('第一次解析失败'), findsOneWidget);
    expect(find.text('重新选择或粘贴'), findsOneWidget);
    await tester.ensureVisible(find.text('重试解析'));
    await tester.tap(find.text('重试解析'));
    await tester.pumpAndSettle();
    expect(find.text('总行数 1'), findsOneWidget);
    expect(find.text('导入完成'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('列映射应用后保留实际选列，并仍可折叠调整', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '映射词书.txt', bytes: Uint8List(0));
    var calls = 0;
    WordbookParseOptions? applied;
    await pumpPage(
      tester,
      dependencies,
      filePicker: () async => file,
      fileParser: (_, options) async {
        calls++;
        if (calls == 1) {
          return parsed(
            requiresMapping: true,
            columns: const ['GUID', 'Front', 'Back', 'Tags'],
            metadataColumns: const {0, 3},
          );
        }
        applied = options;
        return parsed(
          totalRows: 1,
          wordColumn: options.wordColumn,
          definitionColumn: options.definitionColumn,
          entries: const [
            WordbookEntryDraft(word: 'apple', definition: 'fruit'),
          ],
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('apply-wordbook-mapping')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('apply-wordbook-mapping')),
    );
    await tester.tap(find.byKey(const ValueKey('apply-wordbook-mapping')));
    await tester.pumpAndSettle();
    expect(applied?.wordColumn, 1);
    expect(applied?.definitionColumn, 2);
    expect(find.text('总行数 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('adjust-wordbook-columns')),
      findsOneWidget,
    );
    expect(find.textContaining('单词第 2 列'), findsOneWidget);
    expect(find.textContaining('释义第 3 列'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('调整分隔符会按新列重新解析并清空旧索引', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '单列误判.csv', bytes: Uint8List(0));
    var calls = 0;
    WordbookParseOptions? reparsed;
    await pumpPage(
      tester,
      dependencies,
      filePicker: () async => file,
      fileParser: (_, options) async {
        calls++;
        if (calls == 1) {
          return parsed(
            requiresMapping: true,
            columns: const ['单列'],
            metadataColumns: const {},
          );
        }
        reparsed = options;
        return parsed(
          requiresMapping: true,
          columns: const ['单词', '释义'],
          metadataColumns: const {},
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    final delimiter = find.byType(DropdownButtonFormField<WordbookDelimiter>);
    await tester.ensureVisible(delimiter);
    await tester.tap(delimiter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('分号').last);
    await tester.pumpAndSettle();
    expect(reparsed?.delimiter, WordbookDelimiter.semicolon);
    expect(find.textContaining('需要选择列'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('390 大字号下超长 Anki 列名映射控件不溢出', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    const longWord = 'This_Is_An_Extremely_Long_Word_Column_Name_For_Layout';
    const longDefinition =
        'This_Is_An_Extremely_Long_Definition_Column_Name_For_Layout';
    const longPhonetic =
        'This_Is_An_Extremely_Long_Phonetic_Column_Name_For_Layout';
    const longExample =
        'This_Is_An_Extremely_Long_Example_Column_Name_For_Layout';
    final text =
        '#separator:Tab\n'
        '#columns:$longWord\t$longDefinition\t$longPhonetic\t$longExample\n'
        'apple\tfruit\t/æ/\tAn example.\n';
    final file = WordbookPickedFile(
      name: 'anki-long-columns.txt',
      bytes: Uint8List.fromList(utf8.encode(text)),
    );
    await pumpPage(
      tester,
      dependencies,
      filePicker: () async => file,
      fileParser: (file, options) async => parseWordbookText(
        utf8.decode(file.bytes),
        fileName: file.name,
        options: options,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    expect(find.text('需要选择列'), findsOneWidget);
    await tester.ensureVisible(find.text('需要选择列'));
    expect(find.byType(DropdownButtonFormField<int>), findsNWidgets(4));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('粘贴文本默认自动识别，走同一预览管线', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    WordbookParseOptions? seenOptions;
    await pumpPage(
      tester,
      dependencies,
      textParser: (text, options) async {
        seenOptions = options;
        return parsed(
          totalRows: 1,
          entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
        );
      },
    );
    await tester.tap(find.byKey(const ValueKey('paste-wordbook-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wordbook-paste-input')),
      'apple\t苹果',
    );
    await tester.tap(find.byKey(const ValueKey('parse-pasted-wordbook')));
    await tester.pumpAndSettle();
    expect(seenOptions?.delimiter, isNull);
    expect(find.text('总行数 1'), findsOneWidget);
    expect(find.text('apple'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('事务失败保留预览，修复后可原地重试导入', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '重试事务.csv', bytes: Uint8List(0));
    await dependencies.database.customStatement(
      "CREATE TRIGGER reject_import_widget BEFORE INSERT ON wordbook_entries "
      "BEGIN SELECT RAISE(ABORT, 'test widget import failure'); END",
    );
    await pumpPage(
      tester,
      dependencies,
      filePicker: () async => file,
      fileParser: (_, _) async => parsed(
        totalRows: 1,
        entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm-import-wordbook'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.textContaining('导入失败，原有数据未变'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(
      (await dependencies.repository.books()).where((book) => !book.isBuiltIn),
      isEmpty,
    );

    await dependencies.database.customStatement(
      'DROP TRIGGER reject_import_widget',
    );
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('导入完成'), findsOneWidget);
    expect(
      (await dependencies.repository.books()).where(
        (book) => book.name == '测试词书' && !book.isBuiltIn,
      ),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('粘贴解析中取消会使旧请求失效，不回填预览', (tester) async {
    await surface(tester);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final gate = Completer<ParsedWordbook>();
    await pumpPage(tester, dependencies, textParser: (_, _) => gate.future);
    await tester.tap(find.byKey(const ValueKey('paste-wordbook-text')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wordbook-paste-input')),
      'apple\t苹果',
    );
    await tester.tap(find.byKey(const ValueKey('parse-pasted-wordbook')));
    await tester.pump();
    expect(find.text('取消粘贴'), findsOneWidget);
    await tester.ensureVisible(find.text('取消粘贴'));
    await tester.tap(find.text('取消粘贴'));
    await tester.pump();
    gate.complete(
      parsed(
        totalRows: 1,
        entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('总行数 1'), findsNothing);
    expect(find.byKey(const ValueKey('pick-wordbook-file')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('粘贴草稿返回确认，取消保留草稿，空粘贴框直接返回', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    await tester.pumpWidget(importHost(dependencies));
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsNothing);
    expect(find.text('打开导入'), findsOneWidget);
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paste-wordbook-text')));
    await tester.pumpAndSettle();
    final paste = find.byKey(const ValueKey('wordbook-paste-input'));
    await tester.enterText(paste, 'apple\t苹果');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsOneWidget);
    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(paste).controller!.text, 'apple\t苹果');

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃并返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开导入'), findsOneWidget);
    expect(await dependencies.repository.books(), hasLength(5));

    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paste-wordbook-text')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsNothing);
    expect(find.text('打开导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('导入预览返回确认，取消保留预览，放弃不写库', (tester) async {
    await surface(tester, width: 320, scale: 1.5);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '预览.csv', bytes: Uint8List(0));
    final result = parsed(
      totalRows: 2,
      entries: const [
        WordbookEntryDraft(word: 'apple', definition: '苹果'),
        WordbookEntryDraft(word: 'pear', definition: '梨'),
      ],
    );
    await tester.pumpWidget(
      importHost(
        dependencies,
        filePicker: () async => file,
        fileParser: (_, _) async => result,
        deep: true,
      ),
    );
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    expect(find.text('总行数 2'), findsOneWidget);

    final name = find.byKey(const ValueKey('import-book-name'));
    final confirm = find.byKey(const ValueKey('confirm-import-wordbook'));
    final staleImport = tester.widget<FilledButton>(confirm).onPressed;
    expect(staleImport, isNotNull);
    await tester.enterText(name, '');
    // 模拟名称清空后同帧旧 onPressed 回调，名称错误必须可修正后恢复导入。
    staleImport!();
    await tester.pumpAndSettle();
    expect(find.text('请填写 1 到 40 字的词书名称。'), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(name, '修正后的词书');
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsOneWidget);
    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
    expect(find.text('总行数 2'), findsOneWidget);
    expect(tester.widget<TextField>(name).controller!.text, '修正后的词书');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃并返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开导入'), findsOneWidget);
    expect(await dependencies.repository.books(), hasLength(5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('解析中放弃返回后旧结果不会回填或写库', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final gate = Completer<ParsedWordbook>();
    final file = WordbookPickedFile(name: '慢解析.csv', bytes: Uint8List(0));
    await tester.pumpWidget(
      importHost(
        dependencies,
        filePicker: () async => file,
        fileParser: (_, _) => gate.future,
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pump();
    await tester.pump();
    expect(find.text('取消解析'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('放弃本次词书导入？'), findsOneWidget);
    await tester.tap(find.text('放弃并返回'));
    await tester.pumpAndSettle();
    expect(find.text('打开导入'), findsOneWidget);

    gate.complete(
      parsed(
        totalRows: 1,
        entries: const [WordbookEntryDraft(word: '晚到', definition: '不应出现')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('总行数 1'), findsNothing);
    expect(await dependencies.repository.books(), hasLength(5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('导入成功态返回不弹确认', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '成功.csv', bytes: Uint8List(0));
    final result = parsed(
      totalRows: 1,
      entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
    );
    await tester.pumpWidget(
      importHost(
        dependencies,
        filePicker: () async => file,
        fileParser: (_, _) async => result,
        deep: true,
      ),
    );
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    final confirm = find.byKey(const ValueKey('confirm-import-wordbook'));
    await tester.ensureVisible(confirm);
    await tester.tap(confirm);
    await tester.pumpAndSettle();
    expect(find.text('导入完成'), findsOneWidget);
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsNothing);
    expect(find.text('打开导入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('错误态内联返回也进入丢弃确认', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '错误.csv', bytes: Uint8List(0));
    await tester.pumpWidget(
      importHost(
        dependencies,
        filePicker: () async => file,
        fileParser: (_, _) async => throw StateError('解析失败'),
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    expect(find.textContaining('解析失败'), findsOneWidget);
    await tester.ensureVisible(find.text('返回'));
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsOneWidget);
    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('解析失败'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('预览内联取消也进入丢弃确认', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '内联取消.csv', bytes: Uint8List(0));
    final result = parsed(
      totalRows: 1,
      entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
    );
    await tester.pumpWidget(
      importHost(
        dependencies,
        filePicker: () async => file,
        fileParser: (_, _) async => result,
      ),
    );
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    expect(find.text('总行数 1'), findsOneWidget);
    await tester.ensureVisible(find.text('取消'));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsOneWidget);
    await tester.tap(find.text('继续导入'));
    await tester.pumpAndSettle();
    expect(find.text('总行数 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('成功态内联返回不确认且只退一层', (tester) async {
    await surface(tester, width: 1280, scale: 1.0);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    final file = WordbookPickedFile(name: '成功内联.csv', bytes: Uint8List(0));
    final result = parsed(
      totalRows: 1,
      entries: const [WordbookEntryDraft(word: 'apple', definition: '苹果')],
    );
    await tester.pumpWidget(
      importHost(
        dependencies,
        filePicker: () async => file,
        fileParser: (_, _) async => result,
        deep: true,
      ),
    );
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pick-wordbook-file')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('confirm-import-wordbook')),
    );
    await tester.tap(find.byKey(const ValueKey('confirm-import-wordbook')));
    await tester.pumpAndSettle();
    expect(find.text('导入完成'), findsOneWidget);
    await tester.ensureVisible(find.text('返回词书页'));
    final callback = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '返回词书页'))
        .onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsNothing);
    expect(find.text('打开导入'), findsOneWidget);
    expect(find.text('进入二级'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('丢弃确认继续按钮同帧重复回调不退出草稿页', (tester) async {
    await surface(tester, width: 390, scale: 1.5);
    final dependencies = createDependencies();
    await tester.runAsync(dependencies.initialize);
    await tester.pumpWidget(importHost(dependencies, deep: true));
    await tester.tap(find.text('进入二级'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('paste-wordbook-text')));
    await tester.pumpAndSettle();
    final paste = find.byKey(const ValueKey('wordbook-paste-input'));
    await tester.enterText(paste, 'apple\t苹果');
    await tester.tap(find.byTooltip('返回'));
    await tester.pumpAndSettle();
    expect(find.text('放弃本次词书导入？'), findsOneWidget);
    final continueButton = find.widgetWithText(TextButton, '继续导入');
    final callback = tester.widget<TextButton>(continueButton).onPressed!;
    callback();
    callback();
    await tester.pumpAndSettle();
    expect(find.text('打开导入'), findsNothing);
    expect(paste, findsOneWidget);
    expect(tester.widget<TextField>(paste).controller!.text, 'apple\t苹果');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
