import 'dart:convert';
import 'dart:typed_data';

class WordbookFormatLimits {
  const WordbookFormatLimits._();

  static const maxFileBytes = 10 * 1024 * 1024;
  static const maxEntries = 20000;
  static const maxWordRunes = 128;
  static const maxDefinitionRunes = 2000;
  static const maxPhoneticRunes = 200;
  static const maxExampleRunes = 4000;
  static const maxIssues = 100;
  static const previewEntries = 5;
}

enum WordbookDelimiter {
  tab('\t', 'Tab'),
  comma(',', '逗号'),
  semicolon(';', '分号'),
  pipe('|', '竖线'),
  colon(':', '冒号'),
  space(' ', '空格');

  const WordbookDelimiter(this.character, this.label);

  final String character;
  final String label;

  static WordbookDelimiter? fromFileExtension(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.tsv')) return WordbookDelimiter.tab;
    if (lower.endsWith('.csv')) return WordbookDelimiter.comma;
    return null;
  }

  static WordbookDelimiter? fromAnkiDirective(String value) {
    final clean = value.trim();
    final lower = clean.toLowerCase();
    return switch (lower) {
      'tab' => WordbookDelimiter.tab,
      'comma' => WordbookDelimiter.comma,
      'semicolon' => WordbookDelimiter.semicolon,
      'pipe' => WordbookDelimiter.pipe,
      'colon' => WordbookDelimiter.colon,
      'space' => WordbookDelimiter.space,
      _ => switch (clean) {
        '\t' => WordbookDelimiter.tab,
        ',' => WordbookDelimiter.comma,
        ';' => WordbookDelimiter.semicolon,
        '|' => WordbookDelimiter.pipe,
        ':' => WordbookDelimiter.colon,
        ' ' => WordbookDelimiter.space,
        _ => null,
      },
    };
  }
}

class WordbookParseOptions {
  const WordbookParseOptions({
    this.delimiter,
    this.wordColumn,
    this.definitionColumn,
    this.phoneticColumn,
    this.exampleColumn,
    this.skipFirstRow = false,
    this.forceWordList = false,
  });

  final WordbookDelimiter? delimiter;
  final int? wordColumn;
  final int? definitionColumn;
  final int? phoneticColumn;
  final int? exampleColumn;
  final bool skipFirstRow;
  final bool forceWordList;

  bool get hasMapping => wordColumn != null && definitionColumn != null;

  WordbookParseOptions copyWith({
    WordbookDelimiter? delimiter,
    int? wordColumn,
    int? definitionColumn,
    int? phoneticColumn,
    int? exampleColumn,
    bool? skipFirstRow,
    bool? forceWordList,
    bool clearOptionalColumns = false,
  }) => WordbookParseOptions(
    delimiter: delimiter ?? this.delimiter,
    wordColumn: wordColumn ?? this.wordColumn,
    definitionColumn: definitionColumn ?? this.definitionColumn,
    phoneticColumn: clearOptionalColumns
        ? null
        : phoneticColumn ?? this.phoneticColumn,
    exampleColumn: clearOptionalColumns
        ? null
        : exampleColumn ?? this.exampleColumn,
    skipFirstRow: skipFirstRow ?? this.skipFirstRow,
    forceWordList: forceWordList ?? this.forceWordList,
  );
}

class WordbookEntryDraft {
  const WordbookEntryDraft({
    required this.word,
    required this.definition,
    this.phonetic,
    this.example,
    this.line,
  });

  final String word;
  final String definition;
  final String? phonetic;
  final String? example;
  final int? line;

  String get key => '$word\u0000$definition';

  WordbookEntryDraft copyWith({
    String? word,
    String? definition,
    String? phonetic,
    String? example,
    int? line,
  }) => WordbookEntryDraft(
    word: word ?? this.word,
    definition: definition ?? this.definition,
    phonetic: phonetic ?? this.phonetic,
    example: example ?? this.example,
    line: line ?? this.line,
  );
}

class WordOnlyEntry {
  const WordOnlyEntry({required this.word, required this.line});
  final String word;
  final int line;
}

class WordbookParseIssue {
  const WordbookParseIssue({
    required this.message,
    this.line,
    this.item,
    this.isError = true,
    this.sample,
  });

  final String message;
  final int? line;
  final int? item;
  final bool isError;
  final String? sample;

  String get location => line != null
      ? '第 $line 行'
      : item != null
      ? '第 $item 项'
      : '文件';
}

class ParsedWordbook {
  const ParsedWordbook({
    required this.suggestedName,
    required this.entries,
    required this.wordOnlyEntries,
    required this.issues,
    required this.totalRows,
    required this.duplicateRows,
    required this.errorRows,
    required this.requiresMapping,
    required this.delimiter,
    required this.columns,
    required this.sampleRows,
    required this.metadataColumns,
    required this.htmlFields,
    this.wordColumn,
    this.definitionColumn,
    this.phoneticColumn,
    this.exampleColumn,
    this.headerSkipped = false,
  });

  final String suggestedName;
  final List<WordbookEntryDraft> entries;
  final List<WordOnlyEntry> wordOnlyEntries;
  final List<WordbookParseIssue> issues;
  final int totalRows;
  final int duplicateRows;
  final int errorRows;
  final bool requiresMapping;
  final WordbookDelimiter? delimiter;
  final List<String> columns;
  final List<List<String>> sampleRows;
  final Set<int> metadataColumns;
  final bool htmlFields;
  final int? wordColumn;
  final int? definitionColumn;
  final int? phoneticColumn;
  final int? exampleColumn;
  final bool headerSkipped;

  bool get hasErrors => errorRows > 0;
  bool get isWordList => wordOnlyEntries.isNotEmpty;
}

class WordbookImportResult {
  const WordbookImportResult({
    required this.bookId,
    required this.bookName,
    required this.importedEntries,
    required this.newWords,
    required this.newSenses,
    required this.reusedSenses,
  });

  final String bookId;
  final String bookName;
  final int importedEntries;
  final int newWords;
  final int newSenses;
  final int reusedSenses;
}

class WordListResolution {
  const WordListResolution({
    required this.entries,
    required this.issues,
    required this.duplicateRows,
    required this.errorRows,
  });

  final List<WordbookEntryDraft> entries;
  final List<WordbookParseIssue> issues;
  final int duplicateRows;
  final int errorRows;
}

String decodeWordbookBytes(Uint8List bytes) {
  if (bytes.length > WordbookFormatLimits.maxFileBytes) {
    throw const FormatException('文件超过 10 MB 限制。');
  }
  if (bytes.length >= 2 &&
      ((bytes[0] == 0xFF && bytes[1] == 0xFE) ||
          (bytes[0] == 0xFE && bytes[1] == 0xFF))) {
    throw const FormatException('仅支持 UTF-8 文本，请先将文件转换为 UTF-8。');
  }
  var offset = 0;
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    offset = 3;
  }
  try {
    final text = utf8.decode(bytes.sublist(offset), allowMalformed: false);
    if (text.contains('\u0000')) {
      throw const FormatException('文件包含二进制内容，请选择文本格式。');
    }
    return text;
  } on FormatException catch (error) {
    if (error.message.contains('二进制')) rethrow;
    throw const FormatException('文件不是有效的 UTF-8 文本，可能存在乱码。');
  }
}

ParsedWordbook parseWordbookBytes(
  Uint8List bytes, {
  required String fileName,
  WordbookParseOptions options = const WordbookParseOptions(),
}) {
  _throwIfUnsupportedContainer(fileName);
  return parseWordbookText(
    decodeWordbookBytes(bytes),
    fileName: fileName,
    options: options,
  );
}

ParsedWordbook parseWordbookText(
  String text, {
  required String fileName,
  WordbookParseOptions options = const WordbookParseOptions(),
}) {
  _throwIfUnsupportedContainer(fileName);
  if (text.startsWith('\uFEFF')) text = text.substring(1);
  if (text.contains('\u0000')) {
    throw const FormatException('文本包含 NUL 等不支持的控制字符，请修正后重试。');
  }
  if (utf8.encode(text).length > WordbookFormatLimits.maxFileBytes) {
    throw const FormatException('文件超过 10 MB 限制。');
  }
  if (options.forceWordList) {
    return _parseWordList(
      text,
      fileName: fileName,
      startLine: 1,
      metadataColumns: const {},
      htmlFields: false,
      skipFirstRow: options.skipFirstRow,
    );
  }
  final extension = _extension(fileName);
  if (extension == 'json') {
    return _parseJson(text, fileName: fileName);
  }
  if (extension == 'jsonl' || extension == 'dat') {
    return _parseJsonLines(
      text,
      fileName: fileName,
      strictDat: extension == 'dat',
    );
  }
  if (extension != 'csv' &&
      extension != 'tsv' &&
      extension != 'txt' &&
      extension != '') {
    throw const FormatException('仅支持 CSV、TSV、TXT、JSON、JSONL 文件。');
  }

  final directives = _readAnkiDirectives(text);
  final explicitDelimiter = options.delimiter;
  final directiveDelimiter = directives.separator;
  final fileDelimiter = WordbookDelimiter.fromFileExtension(fileName);
  final htmlFields = directives.html;
  final body = directives.body;
  var delimiter =
      explicitDelimiter ??
      directiveDelimiter ??
      fileDelimiter ??
      (extension == 'txt' ? _detectDelimiter(body) : null);
  final reporter = _IssueReporter();
  final rows = delimiter == null
      ? <_DelimitedRow>[]
      : _parseDelimited(
          body,
          delimiter,
          startLine: directives.firstDataLine,
          reporter: reporter,
        );
  if (delimiter == null) {
    return _parseWordList(
      body,
      fileName: fileName,
      startLine: directives.firstDataLine,
      metadataColumns: directives.metadataColumns,
      htmlFields: htmlFields,
      skipFirstRow: options.skipFirstRow,
    );
  }

  final meaningfulRows = rows
      .where(
        (row) =>
            row.error != null ||
            row.fields.any((field) => field.trim().isNotEmpty),
      )
      .toList();
  if (meaningfulRows.isEmpty) {
    return _emptyResult(
      fileName: fileName,
      delimiter: delimiter,
      metadataColumns: directives.metadataColumns,
      htmlFields: htmlFields,
      issues: [const WordbookParseIssue(message: '文件中没有可导入的词条。')],
      errorRows: 1,
    );
  }

  final maxColumns = meaningfulRows
      .map((row) => row.fields.length)
      .fold<int>(0, (max, value) => value > max ? value : max);
  final metadataColumns = <int>{...directives.metadataColumns};
  if (directives.columnNames != null) {
    metadataColumns.addAll(_metadataHeaderColumns(directives.columnNames!));
  }
  final rowHeaderMappingRaw = _headerMapping(meaningfulRows.first.fields);
  if (rowHeaderMappingRaw != null) {
    metadataColumns.addAll(_metadataHeaderColumns(meaningfulRows.first.fields));
  }
  final rowHeaderMapping =
      rowHeaderMappingRaw != null &&
          _mappingIsValid(rowHeaderMappingRaw, maxColumns, metadataColumns)
      ? rowHeaderMappingRaw
      : null;
  final directiveMappingRaw = directives.columnNames == null
      ? null
      : _headerMapping(directives.columnNames!);
  final directiveMapping =
      directiveMappingRaw != null &&
          _mappingIsValid(directiveMappingRaw, maxColumns, metadataColumns)
      ? directiveMappingRaw
      : null;
  final headerMapping = rowHeaderMapping ?? directiveMapping;
  final firstRowIsDirectiveHeader =
      directives.columnNames != null &&
      _sameColumns(meaningfulRows.first.fields, directives.columnNames!);
  final hasHeader = rowHeaderMapping != null || firstRowIsDirectiveHeader;
  final hasKnownHeaderCell = meaningfulRows.first.fields.any((field) {
    final normalized = _normalizeHeader(field);
    return _wordAliases.contains(normalized) ||
        _definitionAliases.contains(normalized) ||
        _phoneticAliases.contains(normalized) ||
        _exampleAliases.contains(normalized);
  });
  final autoMapping =
      maxColumns == 2 &&
          !metadataColumns.contains(0) &&
          !metadataColumns.contains(1)
      ? const _ColumnMapping(word: 0, definition: 1)
      : null;

  if (options.hasMapping) {
    final selected = [
      options.wordColumn,
      options.definitionColumn,
      options.phoneticColumn,
      options.exampleColumn,
    ].whereType<int>().toList();
    if (selected.any((column) => column < 0 || column >= maxColumns)) {
      throw const FormatException('所选列号超出文件的列数。');
    }
    if (options.wordColumn == options.definitionColumn) {
      throw const FormatException('单词列和释义列不能是同一列。');
    }
    if (selected.any(metadataColumns.contains)) {
      throw const FormatException('GUID、标签、牌组等元数据列不能作为单词或释义。');
    }
  } else if (!hasHeader &&
      headerMapping == null &&
      (autoMapping == null || (maxColumns == 2 && hasKnownHeaderCell))) {
    return ParsedWordbook(
      suggestedName: suggestedWordbookName(fileName),
      entries: const [],
      wordOnlyEntries: const [],
      issues: [
        const WordbookParseIssue(
          message: '未识别到表头。请选择分隔符和单词、释义列后重新预览。',
          isError: false,
        ),
      ],
      totalRows: meaningfulRows.length,
      duplicateRows: 0,
      errorRows: 0,
      requiresMapping: true,
      delimiter: delimiter,
      columns:
          directives.columnNames ??
          List.generate(maxColumns, (index) => '第 ${index + 1} 列'),
      sampleRows: meaningfulRows
          .take(3)
          .map((row) => List<String>.of(row.fields))
          .toList(),
      metadataColumns: metadataColumns,
      htmlFields: htmlFields,
    );
  }

  final mapping = options.hasMapping
      ? _ColumnMapping(
          word: options.wordColumn!,
          definition: options.definitionColumn!,
          phonetic: options.phoneticColumn,
          example: options.exampleColumn,
        )
      : headerMapping ??
            autoMapping ??
            const _ColumnMapping(word: 0, definition: 1);
  final dataRows = options.hasMapping
      ? (options.skipFirstRow ? meaningfulRows.skip(1) : meaningfulRows)
      : hasHeader
      ? meaningfulRows.skip(1)
      : meaningfulRows;
  return _buildEntries(
    dataRows: dataRows,
    mapping: mapping,
    fileName: fileName,
    delimiter: delimiter,
    htmlFields: htmlFields,
    reporter: reporter,
    metadataColumns: metadataColumns,
    headerSkipped: options.hasMapping ? options.skipFirstRow : hasHeader,
    columns:
        directives.columnNames ??
        (hasHeader
            ? _trimmedColumns(meaningfulRows.first.fields)
            : List.generate(maxColumns, (index) => '第 ${index + 1} 列')),
    sampleRows: meaningfulRows
        .take(3)
        .map((row) => List<String>.of(row.fields))
        .toList(),
  );
}

void _throwIfUnsupportedContainer(String fileName) {
  final extension = _extension(fileName);
  if (extension == 'apkg' || extension == 'zip') {
    throw const FormatException(
      'APKG/ZIP 是打包格式，不能直接导入。请在 Anki 桌面端导出 Notes in Plain Text 后导入。',
    );
  }
  if (extension == 'xml') {
    throw const FormatException('暂不支持通用 XML。请在原软件导出 CSV/TSV，或使用本页列映射导入纯文本。');
  }
  if (extension == 'mdx') {
    throw const FormatException('MDX 是词典容器格式，暂不支持。请先转换为 CSV/TSV 或逐行单词 TXT。');
  }
}

ParsedWordbook _buildEntries({
  required Iterable<_DelimitedRow> dataRows,
  required _ColumnMapping mapping,
  required String fileName,
  required WordbookDelimiter delimiter,
  required bool htmlFields,
  required _IssueReporter reporter,
  required Set<int> metadataColumns,
  required bool headerSkipped,
  required List<String> columns,
  required List<List<String>> sampleRows,
}) {
  final entries = <WordbookEntryDraft>[];
  final seen = <String>{};
  var totalRows = 0;
  var duplicates = 0;
  var errorRows = 0;
  for (final row in dataRows) {
    totalRows++;
    if (row.error != null) {
      errorRows++;
      reporter.error(row.line, row.error!);
      continue;
    }
    final reasons = <String>[];
    final definition = _cleanField(
      _fieldAt(row.fields, mapping.definition),
      html: htmlFields,
      warnings: reasons,
      line: row.line,
      fieldLabel: '释义',
      reporter: reporter,
    );
    final wordClean = _cleanField(
      _fieldAt(row.fields, mapping.word),
      html: htmlFields,
      warnings: reasons,
      line: row.line,
      fieldLabel: '单词',
      reporter: reporter,
    );
    final phonetic = _cleanNullable(
      _cleanField(
        mapping.phonetic == null ? '' : _fieldAt(row.fields, mapping.phonetic!),
        html: htmlFields,
        warnings: reasons,
        line: row.line,
        fieldLabel: '音标',
        reporter: reporter,
      ),
    );
    final example = _cleanField(
      mapping.example == null ? '' : _fieldAt(row.fields, mapping.example!),
      html: htmlFields,
      warnings: reasons,
      line: row.line,
      fieldLabel: '例句',
      reporter: reporter,
    );
    if (wordClean.isEmpty) reasons.add('单词为空');
    if (definition.isEmpty) reasons.add('释义为空');
    _checkControlChars(reasons, '单词', wordClean);
    _checkControlChars(reasons, '释义', definition);
    _checkControlChars(reasons, '音标', phonetic ?? '');
    _checkControlChars(reasons, '例句', example);
    _checkRunes(reasons, '单词', wordClean, WordbookFormatLimits.maxWordRunes);
    _checkRunes(
      reasons,
      '释义',
      definition,
      WordbookFormatLimits.maxDefinitionRunes,
    );
    _checkRunes(
      reasons,
      '音标',
      phonetic ?? '',
      WordbookFormatLimits.maxPhoneticRunes,
    );
    _checkRunes(reasons, '例句', example, WordbookFormatLimits.maxExampleRunes);
    if (reasons.isNotEmpty) {
      errorRows++;
      reporter.error(row.line, reasons.join('；'), sample: _rowSample(row));
      continue;
    }
    final entry = WordbookEntryDraft(
      word: wordClean,
      definition: definition,
      phonetic: phonetic,
      example: example.isEmpty ? null : example,
      line: row.line,
    );
    if (!seen.add(entry.key)) {
      duplicates++;
      continue;
    }
    if (entries.length >= WordbookFormatLimits.maxEntries) {
      errorRows++;
      reporter.error(
        row.line,
        '超过最多 ${WordbookFormatLimits.maxEntries} 个词条的限制。',
      );
      break;
    }
    entries.add(entry);
  }
  if (totalRows == 0 && errorRows == 0) {
    errorRows = 1;
    reporter.error(null, '没有可导入的词条。');
  }
  return ParsedWordbook(
    suggestedName: suggestedWordbookName(fileName),
    entries: entries,
    wordOnlyEntries: const [],
    issues: reporter.issues,
    totalRows: totalRows,
    duplicateRows: duplicates,
    errorRows: errorRows,
    requiresMapping: false,
    delimiter: delimiter,
    columns: columns,
    sampleRows: sampleRows,
    metadataColumns: metadataColumns,
    htmlFields: htmlFields,
    wordColumn: mapping.word,
    definitionColumn: mapping.definition,
    phoneticColumn: mapping.phonetic,
    exampleColumn: mapping.example,
    headerSkipped: headerSkipped,
  );
}

ParsedWordbook _parseWordList(
  String text, {
  required String fileName,
  required int startLine,
  required Set<int> metadataColumns,
  required bool htmlFields,
  required bool skipFirstRow,
}) {
  final reporter = _IssueReporter();
  final words = <WordOnlyEntry>[];
  final seen = <String>{};
  var totalRows = 0;
  var duplicates = 0;
  var errorRows = 0;
  var skippedHeader = false;
  final lines = const LineSplitter().convert(text);
  var lineNumber = startLine - 1;
  for (final rawLine in lines) {
    lineNumber++;
    final word = rawLine.trim();
    if (word.isEmpty) continue;
    if (skipFirstRow && !skippedHeader) {
      skippedHeader = true;
      continue;
    }
    totalRows++;
    final reasons = <String>[];
    _checkControlChars(reasons, '单词', word);
    _checkRunes(reasons, '单词', word, WordbookFormatLimits.maxWordRunes);
    if (reasons.isNotEmpty) {
      errorRows++;
      reporter.error(lineNumber, reasons.join('；'), sample: word);
      continue;
    }
    if (!seen.add(word)) {
      duplicates++;
      continue;
    }
    if (words.length >= WordbookFormatLimits.maxEntries) {
      errorRows++;
      reporter.error(
        lineNumber,
        '超过最多 ${WordbookFormatLimits.maxEntries} 个单词的限制。',
      );
      break;
    }
    words.add(WordOnlyEntry(word: word, line: lineNumber));
  }
  if (words.isEmpty && errorRows == 0) {
    errorRows = 1;
    reporter.error(null, '文件中没有可导入的单词。');
  }
  return ParsedWordbook(
    suggestedName: suggestedWordbookName(fileName),
    entries: const [],
    wordOnlyEntries: words,
    issues: reporter.issues,
    totalRows: totalRows,
    duplicateRows: duplicates,
    errorRows: errorRows,
    requiresMapping: false,
    delimiter: null,
    columns: const ['单词'],
    sampleRows: words.take(3).map((word) => [word.word]).toList(),
    metadataColumns: metadataColumns,
    htmlFields: htmlFields,
  );
}

ParsedWordbook _parseJson(String text, {required String fileName}) {
  late final Object? root;
  try {
    root = jsonDecode(text);
  } on FormatException {
    throw const FormatException('JSON 格式不正确，无法解析。');
  }
  final reporter = _IssueReporter();
  String? bookName;
  final records = <Object?>[];
  if (root is List) {
    records.addAll(root);
  } else if (root is Map<String, dynamic> && root['entries'] is List) {
    bookName = root['name'] is String ? (root['name'] as String).trim() : null;
    records.addAll(root['entries'] as List);
  } else {
    throw const FormatException('JSON 必须是词条数组，或包含 entries 数组的对象。');
  }
  return _parseJsonRecords(
    records,
    fileName: fileName,
    suggestedName: bookName,
    reporter: reporter,
  );
}

ParsedWordbook _parseJsonLines(
  String text, {
  required String fileName,
  required bool strictDat,
}) {
  final reporter = _IssueReporter();
  final records = <Object?>[];
  final physicalLines = <int>[];
  var lineNumber = 0;
  var malformed = 0;
  for (final line in const LineSplitter().convert(text)) {
    lineNumber++;
    if (line.trim().isEmpty) continue;
    try {
      records.add(jsonDecode(line));
      physicalLines.add(lineNumber);
    } on FormatException {
      malformed++;
      reporter.error(
        lineNumber,
        strictDat ? 'DAT 仅支持每行一个 JSON 对象的 JSONL 格式。' : 'JSONL 此行不是有效的 JSON。',
      );
    }
  }
  final result = _parseJsonRecords(
    records,
    fileName: fileName,
    reporter: reporter,
    physicalLines: physicalLines,
    reportEmpty: malformed == 0,
  );
  return ParsedWordbook(
    suggestedName: result.suggestedName,
    entries: result.entries,
    wordOnlyEntries: const [],
    issues: result.issues,
    totalRows: result.totalRows + malformed,
    duplicateRows: result.duplicateRows,
    errorRows: result.errorRows + malformed,
    requiresMapping: false,
    delimiter: null,
    columns: const ['word', 'definition', 'phonetic', 'example'],
    sampleRows: const [],
    metadataColumns: const {},
    htmlFields: false,
  );
}

ParsedWordbook _parseJsonRecords(
  List<Object?> records, {
  required String fileName,
  required _IssueReporter reporter,
  String? suggestedName,
  List<int>? physicalLines,
  bool reportEmpty = true,
}) {
  final entries = <WordbookEntryDraft>[];
  final seen = <String>{};
  var duplicates = 0;
  var errors = 0;
  var totalRows = 0;
  for (var index = 0; index < records.length; index++) {
    final record = records[index];
    final line = physicalLines?[index];
    if (record == null) {
      totalRows++;
      errors++;
      reporter.error(
        line,
        '记录不能是 null，必须是 JSON 对象。',
        item: line == null ? index + 1 : null,
      );
      continue;
    }
    totalRows++;
    if (record is! Map) {
      errors++;
      reporter.error(
        line,
        '记录必须是 JSON 对象。',
        item: line == null ? index + 1 : null,
      );
      continue;
    }
    final values = <String, Object?>{};
    for (final entry in record.entries) {
      if (entry.key is! String) continue;
      values[(entry.key as String).trim().toLowerCase()] = entry.value;
    }
    String? read(List<String> aliases, String label, List<String> reasons) {
      for (final alias in aliases) {
        if (!values.containsKey(alias)) continue;
        final value = values[alias];
        if (value == null) return null;
        if (value is! String) {
          reasons.add('$label 必须是字符串');
          return null;
        }
        return value;
      }
      return null;
    }

    final reasons = <String>[];
    final word = _cleanField(read(_wordAliases, '单词', reasons) ?? '');
    final definition = _cleanField(
      read(_definitionAliases, '释义', reasons) ?? '',
    );
    final phonetic = _cleanNullable(
      _cleanField(read(_phoneticAliases, '音标', reasons) ?? ''),
    );
    final example = _cleanField(read(_exampleAliases, '例句', reasons) ?? '');
    if (word.isEmpty) reasons.add('单词为空');
    if (definition.isEmpty) reasons.add('释义为空');
    _checkControlChars(reasons, '单词', word);
    _checkControlChars(reasons, '释义', definition);
    _checkControlChars(reasons, '音标', phonetic ?? '');
    _checkControlChars(reasons, '例句', example);
    _checkRunes(reasons, '单词', word, WordbookFormatLimits.maxWordRunes);
    _checkRunes(
      reasons,
      '释义',
      definition,
      WordbookFormatLimits.maxDefinitionRunes,
    );
    _checkRunes(
      reasons,
      '音标',
      phonetic ?? '',
      WordbookFormatLimits.maxPhoneticRunes,
    );
    _checkRunes(reasons, '例句', example, WordbookFormatLimits.maxExampleRunes);
    if (reasons.isNotEmpty) {
      errors++;
      reporter.error(
        line,
        reasons.join('；'),
        item: line == null ? index + 1 : null,
        sample: word.isEmpty ? null : word,
      );
      continue;
    }
    final entry = WordbookEntryDraft(
      word: word,
      definition: definition,
      phonetic: phonetic,
      example: example.isEmpty ? null : example,
      line: line,
    );
    if (!seen.add(entry.key)) {
      duplicates++;
      continue;
    }
    if (entries.length >= WordbookFormatLimits.maxEntries) {
      errors++;
      reporter.error(
        line,
        '超过最多 ${WordbookFormatLimits.maxEntries} 个词条的限制。',
        item: line == null ? index + 1 : null,
      );
      break;
    }
    entries.add(entry);
  }
  if (reportEmpty && totalRows == 0 && errors == 0) {
    errors = 1;
    reporter.error(null, 'JSON 中没有可导入的词条。');
  }
  final resolvedName = suggestedName == null || suggestedName.trim().isEmpty
      ? suggestedWordbookName(fileName)
      : _clampName(suggestedName.trim());
  return ParsedWordbook(
    suggestedName: resolvedName,
    entries: entries,
    wordOnlyEntries: const [],
    issues: reporter.issues,
    totalRows: totalRows,
    duplicateRows: duplicates,
    errorRows: errors,
    requiresMapping: false,
    delimiter: null,
    columns: const ['word', 'definition', 'phonetic', 'example'],
    sampleRows: const [],
    metadataColumns: const {},
    htmlFields: false,
  );
}

ParsedWordbook _emptyResult({
  required String fileName,
  required WordbookDelimiter delimiter,
  required Set<int> metadataColumns,
  required bool htmlFields,
  required List<WordbookParseIssue> issues,
  required int errorRows,
}) => ParsedWordbook(
  suggestedName: suggestedWordbookName(fileName),
  entries: const [],
  wordOnlyEntries: const [],
  issues: issues,
  totalRows: 0,
  duplicateRows: 0,
  errorRows: errorRows,
  requiresMapping: false,
  delimiter: delimiter,
  columns: const [],
  sampleRows: const [],
  metadataColumns: metadataColumns,
  htmlFields: htmlFields,
);

class _AnkiDirectives {
  const _AnkiDirectives({
    required this.body,
    required this.firstDataLine,
    required this.separator,
    required this.html,
    required this.metadataColumns,
    required this.columnNames,
  });
  final String body;
  final int firstDataLine;
  final WordbookDelimiter? separator;
  final bool html;
  final Set<int> metadataColumns;
  final List<String>? columnNames;
}

_AnkiDirectives _readAnkiDirectives(String text) {
  var body = text.startsWith('\uFEFF') ? text.substring(1) : text;
  var consumed = 0;
  final directives = <({String key, String? value, int? column})>[];
  final known = RegExp(
    r'^#([A-Za-z]+)(?:\s+column\s*:\s*(\d+)|:\s*(.*))?\s*$',
    caseSensitive: false,
  );
  while (true) {
    if (body.isEmpty) break;
    final match = RegExp(r'^([^\r\n]*)(\r\n|\n|\r)?').firstMatch(body);
    if (match == null) break;
    if (match.group(0)!.isEmpty) break;
    final line = (match.group(1) ?? '').trim();
    if (line.isEmpty) {
      consumed += match.group(0)!.length;
      body = body.substring(match.group(0)!.length);
      continue;
    }
    if (!line.startsWith('#')) break;
    final directive = known.firstMatch(line);
    if (directive == null) {
      consumed += match.group(0)!.length;
      body = body.substring(match.group(0)!.length);
      continue;
    }
    final key = directive.group(1)!.toLowerCase();
    if (!{
      'separator',
      'html',
      'columns',
      'notetype',
      'deck',
      'tags',
      'guid',
    }.contains(key)) {
      consumed += match.group(0)!.length;
      body = body.substring(match.group(0)!.length);
      continue;
    }
    final columnText = directive.group(2);
    directives.add((
      key: key,
      value: directive.group(3)?.trim(),
      column: columnText == null ? null : int.tryParse(columnText),
    ));
    consumed += match.group(0)!.length;
    body = body.substring(match.group(0)!.length);
  }
  WordbookDelimiter? separator;
  for (final directive in directives) {
    if (directive.key == 'separator') {
      final parsed = WordbookDelimiter.fromAnkiDirective(directive.value ?? '');
      if (parsed == null) {
        throw FormatException(
          '无法识别 Anki 分隔符“${directive.value ?? ''}”，请使用 Tab、Comma、Semicolon、Pipe、Colon、Space 或对应字符。',
        );
      }
      separator = parsed;
      break;
    }
  }
  var html = false;
  final metadata = <int>{};
  List<String>? columns;
  for (final directive in directives) {
    switch (directive.key) {
      case 'separator':
        break;
      case 'html':
        html =
            (directive.value ?? '').toLowerCase() == 'true' ||
            directive.value == '1';
        break;
      case 'columns':
        final raw = directive.value ?? '';
        final split = raw.split(
          separator?.character ?? WordbookDelimiter.tab.character,
        );
        final names = split.map((name) => name.trim()).toList();
        if (names.any((name) => name.isNotEmpty)) columns = names;
        break;
      case 'notetype':
      case 'deck':
      case 'tags':
      case 'guid':
        final column = directive.column;
        if (column != null && column >= 1) metadata.add(column - 1);
        break;
    }
  }
  return _AnkiDirectives(
    body: body,
    firstDataLine: consumed == 0
        ? 1
        : RegExp(r'\r\n|\n|\r').allMatches(text.substring(0, consumed)).length +
              1,
    separator: separator,
    html: html,
    metadataColumns: metadata,
    columnNames: columns,
  );
}

List<_DelimitedRow> _parseDelimited(
  String text,
  WordbookDelimiter delimiter, {
  required int startLine,
  required _IssueReporter reporter,
}) {
  final rows = <_DelimitedRow>[];
  final field = StringBuffer();
  var fields = <String>[];
  var inQuotes = false;
  var rowStartLine = startLine;
  var line = startLine;
  var rowError = <String>[];
  var atFieldStart = true;
  var afterClosingQuote = false;
  var index = 0;

  void finishField() {
    fields.add(field.toString());
    field.clear();
    atFieldStart = true;
    afterClosingQuote = false;
  }

  void finishRow() {
    finishField();
    if (fields.any((value) => value.trim().isNotEmpty) || rowError.isNotEmpty) {
      rows.add(
        _DelimitedRow(
          fields: fields,
          line: rowStartLine,
          error: rowError.isEmpty ? null : rowError.join('；'),
        ),
      );
    }
    fields = <String>[];
    rowError = <String>[];
    rowStartLine = line + 1;
    afterClosingQuote = false;
  }

  while (index < text.length) {
    final char = text[index];
    if (inQuotes) {
      if (char == '"') {
        if (index + 1 < text.length && text[index + 1] == '"') {
          field.write('"');
          index += 2;
          continue;
        }
        inQuotes = false;
        afterClosingQuote = true;
        index++;
        continue;
      }
      if (char == '\r' || char == '\n') {
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        field.write('\n');
        line++;
        index++;
        continue;
      }
      field.write(char);
      index++;
      continue;
    }
    if (atFieldStart && char == '"') {
      inQuotes = true;
      atFieldStart = false;
      index++;
      continue;
    }
    if (afterClosingQuote) {
      if (char == delimiter.character) {
        finishField();
        index++;
        continue;
      }
      if (char == '\r' || char == '\n') {
        if (char == '\r' &&
            index + 1 < text.length &&
            text[index + 1] == '\n') {
          index++;
        }
        finishRow();
        line++;
        index++;
        continue;
      }
      rowError.add('闭合引号后存在非法字符');
      field.write(char);
      afterClosingQuote = false;
      index++;
      continue;
    }
    if (char == delimiter.character) {
      finishField();
      index++;
      continue;
    }
    if (char == '\r' || char == '\n') {
      if (char == '\r' && index + 1 < text.length && text[index + 1] == '\n') {
        index++;
      }
      finishRow();
      line++;
      index++;
      continue;
    }
    if (char == '"') {
      rowError.add('字段中的双引号必须使用双写转义');
    }
    field.write(char);
    atFieldStart = false;
    index++;
  }
  if (inQuotes) {
    rowError.add('引号字段没有闭合');
  }
  if (field.isNotEmpty || fields.isNotEmpty || rowError.isNotEmpty) {
    finishRow();
  }
  return rows;
}

class _DelimitedRow {
  const _DelimitedRow({required this.fields, required this.line, this.error});
  final List<String> fields;
  final int line;
  final String? error;
}

class _ColumnMapping {
  const _ColumnMapping({
    required this.word,
    required this.definition,
    this.phonetic,
    this.example,
  });
  final int word;
  final int definition;
  final int? phonetic;
  final int? example;
}

const _wordAliases = [
  'word',
  'spelling',
  'term',
  'front',
  'expression',
  '单词',
  '英文',
  '词语',
  '词',
];
const _definitionAliases = [
  'definition',
  'meaning',
  'back',
  'translation',
  '释义',
  '中文',
  '中文释义',
  '解释',
];
const _phoneticAliases = ['phonetic', 'phonetics', 'ipa', '音标'];
const _exampleAliases = ['example', 'sentence', '例句'];
const _metadataAliases = {
  'guid',
  'tags',
  'deck',
  'notetype',
  'note type',
  '标签',
  '牌组',
};

_ColumnMapping? _headerMapping(List<String> fields) {
  final normalized = fields.map(_normalizeHeader).toList();
  final word = _indexOfAlias(normalized, _wordAliases);
  final definition = _indexOfAlias(normalized, _definitionAliases);
  if (word == null || definition == null) return null;
  return _ColumnMapping(
    word: word,
    definition: definition,
    phonetic: _indexOfAlias(normalized, _phoneticAliases),
    example: _indexOfAlias(normalized, _exampleAliases),
  );
}

bool _mappingIsValid(
  _ColumnMapping mapping,
  int columnCount,
  Set<int> metadataColumns,
) {
  final selected = [
    mapping.word,
    mapping.definition,
    if (mapping.phonetic != null) mapping.phonetic!,
    if (mapping.example != null) mapping.example!,
  ];
  if (mapping.word == mapping.definition) return false;
  return selected.every((column) => column >= 0 && column < columnCount) &&
      !selected.any(metadataColumns.contains);
}

Set<int> _metadataHeaderColumns(List<String> fields) => {
  for (var index = 0; index < fields.length; index++)
    if (_metadataAliases.contains(_normalizeHeader(fields[index]))) index,
};

int? _indexOfAlias(List<String> fields, List<String> aliases) {
  for (var index = 0; index < fields.length; index++) {
    if (aliases.contains(fields[index])) return index;
  }
  return null;
}

String _normalizeHeader(String value) =>
    value.replaceAll('\uFEFF', '').trim().toLowerCase();

List<String> _trimmedColumns(List<String> fields) =>
    fields.map((field) => field.trim()).toList();

bool _sameColumns(List<String> fields, List<String> columns) {
  if (fields.length != columns.length) return false;
  for (var index = 0; index < fields.length; index++) {
    if (_normalizeHeader(fields[index]) != _normalizeHeader(columns[index])) {
      return false;
    }
  }
  return true;
}

String _fieldAt(List<String> fields, int index) =>
    index < fields.length ? fields[index] : '';

String _cleanField(
  String value, {
  bool html = false,
  List<String>? warnings,
  int? line,
  String? fieldLabel,
  _IssueReporter? reporter,
}) {
  var result = value;
  if (html) {
    final converted = _htmlToText(
      result,
      warnings: warnings,
      line: line,
      fieldLabel: fieldLabel,
      reporter: reporter,
    );
    result = converted;
  }
  return result.trim();
}

String? _cleanNullable(String value) {
  final clean = value.trim();
  return clean.isEmpty ? null : clean;
}

String _htmlToText(
  String value, {
  List<String>? warnings,
  int? line,
  String? fieldLabel,
  _IssueReporter? reporter,
}) {
  var result = value;
  final hadMedia = RegExp(
    r'<(img|audio|video)\b|\[sound:[^\]]+\]',
    caseSensitive: false,
  ).hasMatch(result);
  final hadScript = RegExp(
    r'<(script|style)\b',
    caseSensitive: false,
  ).hasMatch(result);
  result = result.replaceAll(
    RegExp(r'<(audio|video)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    '',
  );
  result = result.replaceAll(
    RegExp(r'<(script|style)\b[^>]*>[\s\S]*?</\1>', caseSensitive: false),
    '',
  );
  result = result.replaceAll(
    RegExp(r'\[sound:[^\]]+\]', caseSensitive: false),
    '',
  );
  result = result.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  result = result.replaceAll(
    RegExp(r'</(p|div|li|tr)>', caseSensitive: false),
    '\n',
  );
  result = result.replaceAll(RegExp(r'<[^>]+>'), '');
  result = result.replaceAllMapped(
    RegExp(
      r'&(amp|lt|gt|quot|nbsp|#39|#x[0-9a-f]+|#[0-9]+);',
      caseSensitive: false,
    ),
    (match) {
      final entity = match.group(1)!.toLowerCase();
      final named = switch (entity) {
        'amp' => '&',
        'lt' => '<',
        'gt' => '>',
        'quot' => '"',
        'nbsp' => ' ',
        '#39' => "'",
        _ => null,
      };
      if (named != null) return named;
      final hex = entity.startsWith('#x');
      final code = int.tryParse(
        entity.substring(hex ? 2 : 1),
        radix: hex ? 16 : 10,
      );
      final character = _decodeHtmlCodePoint(code);
      if (character == null) {
        warnings?.add('HTML 数字实体编码不合法');
        return match.group(0)!;
      }
      return character;
    },
  );
  if ((hadMedia || hadScript) && reporter != null) {
    reporter.warning(
      line,
      '${fieldLabel ?? '字段'}中的'
      '${hadMedia ? '媒体引用已丢弃' : ''}'
      '${hadMedia && hadScript ? '，' : ''}'
      '${hadScript ? '脚本/样式已移除' : ''}。',
    );
  } else if (hadMedia) {
    warnings?.add('媒体引用已丢弃');
  }
  return result;
}

String? _decodeHtmlCodePoint(int? code) {
  if (code == null ||
      code <= 0 ||
      code > 0x10FFFF ||
      (code >= 0xD800 && code <= 0xDFFF)) {
    return null;
  }
  return String.fromCharCode(code);
}

void _checkRunes(List<String> reasons, String label, String value, int max) {
  if (value.runes.length > max) reasons.add('$label超过 $max 字符限制');
}

bool hasInvalidControlCharacters(String value) {
  for (final rune in value.runes) {
    final invalid =
        rune == 0x7F ||
        (rune < 0x20 && rune != 0x09 && rune != 0x0A && rune != 0x0D);
    if (invalid) {
      return true;
    }
  }
  return false;
}

void _checkControlChars(List<String> reasons, String label, String value) {
  if (hasInvalidControlCharacters(value)) {
    reasons.add('$label包含不支持的控制字符');
  }
}

String _rowSample(_DelimitedRow row) {
  final text = row.fields.join(' | ');
  return text.length <= 80 ? text : '${text.substring(0, 80)}…';
}

WordbookDelimiter? _detectDelimiter(String text) {
  for (final line in const LineSplitter().convert(text)) {
    if (line.trim().isEmpty) continue;
    if (line.contains('\t')) return WordbookDelimiter.tab;
    if (line.contains(',')) return WordbookDelimiter.comma;
    if (line.contains(';')) return WordbookDelimiter.semicolon;
    if (line.contains('|')) return WordbookDelimiter.pipe;
    return null;
  }
  return null;
}

String _extension(String fileName) {
  final base = fileName.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  return dot < 0 ? '' : base.substring(dot + 1).toLowerCase();
}

String suggestedWordbookName(String fileName) {
  var base = fileName.replaceAll('\\', '/').split('/').last;
  final dot = base.lastIndexOf('.');
  if (dot > 0) base = base.substring(0, dot);
  base = base.trim();
  if (base.isEmpty) base = '导入词书';
  return _clampName(base);
}

String _clampName(String value) {
  final runes = value.runes.toList();
  if (runes.length > 40) {
    return String.fromCharCodes(runes.take(40));
  }
  return value;
}

class _IssueReporter {
  final issues = <WordbookParseIssue>[];

  void error(int? line, String message, {int? item, String? sample}) {
    if (issues.length >= WordbookFormatLimits.maxIssues) return;
    issues.add(
      WordbookParseIssue(
        line: line,
        item: item,
        message: message,
        sample: sample,
      ),
    );
  }

  void warning(int? line, String message, {int? item}) {
    if (issues.length >= WordbookFormatLimits.maxIssues) return;
    issues.add(
      WordbookParseIssue(
        line: line,
        item: item,
        message: message,
        isError: false,
      ),
    );
  }
}

String exportWordbookCsv(
  String name,
  List<WordbookEntryDraft> entries, {
  bool withBom = true,
}) {
  final buffer = StringBuffer();
  if (withBom) buffer.write('\uFEFF');
  buffer.writeln('word,definition,phonetic,example');
  for (final entry in entries) {
    buffer.writeln(
      [
        entry.word,
        entry.definition,
        entry.phonetic ?? '',
        entry.example ?? '',
      ].map(_escapeCsv).join(','),
    );
  }
  return buffer.toString();
}

String exportWordbookJson(String name, List<WordbookEntryDraft> entries) =>
    jsonEncode({
      'format': 'lexi_loop_wordbook',
      'version': 1,
      'name': name,
      'entries': [
        for (final entry in entries)
          {
            'word': entry.word,
            'definition': entry.definition,
            if (entry.phonetic != null) 'phonetic': entry.phonetic,
            if (entry.example != null) 'example': entry.example,
          },
      ],
    });

String wordbookCsvTemplate() => exportWordbookCsv('模板', const [
  WordbookEntryDraft(
    word: 'example',
    definition: '释义，包含逗号',
    phonetic: '/ɪɡˈzɑːmpəl/',
    example: 'A quoted "example".',
  ),
]);

String wordbookJsonTemplate() => exportWordbookJson('模板', const [
  WordbookEntryDraft(
    word: 'example',
    definition: '释义，包含逗号',
    phonetic: '/ɪɡˈzɑːmpəl/',
    example: 'A quoted "example".',
  ),
]);

String _escapeCsv(String value) {
  if (value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}
