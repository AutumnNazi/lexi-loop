import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexi_loop/data/wordbook_exchange.dart';

void main() {
  test('CSV 支持 BOM、CRLF、引号内逗号换行和双引号转义', () {
    final text =
        '\uFEFFword,definition,phonetic,example\r\n'
        'apple,"fruit, red",/æpəl/,"He said ""hi""."\r\n'
        'pear,"line one\nline two",,\r\n'
        'apple,"fruit, red",/æpəl/,"duplicate"\r\n'
        'bad,,,\r\n';
    final parsed = parseWordbookBytes(
      Uint8List.fromList(utf8.encode(text)),
      fileName: 'words.csv',
    );
    expect(parsed.entries, hasLength(2));
    expect(parsed.entries.first.word, 'apple');
    expect(parsed.entries.first.definition, 'fruit, red');
    expect(parsed.entries.first.example, 'He said "hi".');
    expect(parsed.entries[1].definition, 'line one\nline two');
    expect(parsed.duplicateRows, 1);
    expect(parsed.errorRows, 1);
    expect(parsed.hasErrors, isTrue);
    expect(parsed.issues.single.line, 6);
    expect(parsed.suggestedName, 'words');
  });

  test('Anki 纯文本指令、列映射、元数据列和 HTML 转换', () {
    final text =
        '#separator:Tab\n'
        '#html:true\n'
        '#columns:Front\tBack\tGUID\tTags\n'
        '#guid column:3\n'
        '#tags column:4\n'
        '#deck:My Deck\n'
        'apple\t<b>fruit</b><br>red &amp; sweet\tguid-1\ttag\n'
        'pear\tLine&#10;two\tguid-2\ttag2\n';
    final parsed = parseWordbookText(text, fileName: 'anki.txt');
    expect(parsed.requiresMapping, isFalse);
    expect(parsed.metadataColumns, {2, 3});
    expect(parsed.entries, hasLength(2));
    expect(parsed.entries.first.word, 'apple');
    expect(parsed.entries.first.definition, 'fruit\nred & sweet');
    expect(parsed.entries[1].definition, 'Line\ntwo');
    expect(parsed.columns, ['Front', 'Back', 'GUID', 'Tags']);
  });

  test('Anki 纯媒体释义不能成为有效词义，HTML 实体越界会报错', () {
    final media = parseWordbookText(
      '#separator:Tab\n#html:true\napple\t[sound:a.mp3]\n',
      fileName: 'anki.txt',
    );
    expect(media.entries, isEmpty);
    expect(media.errorRows, 1);
    expect(media.issues.any((issue) => !issue.isError), isTrue);

    final entity = parseWordbookText(
      '#separator:Tab\n#html:true\napple\tbad &#x110000; entity\n',
      fileName: 'anki.txt',
    );
    expect(entity.entries, isEmpty);
    expect(entity.errorRows, 1);
    expect(entity.issues.single.message, contains('实体编码'));
  });

  test('普通注释行会被忽略，字面分隔符和空列位置保持稳定', () {
    final commented = parseWordbookText(
      '# generated export\n'
      '#separator:Tab\n'
      '#html:true\n'
      'apple\t&lt;b&gt;fruit&lt;/b&gt;\n',
      fileName: 'anki.txt',
    );
    expect(commented.entries.single.word, 'apple');
    expect(commented.entries.single.definition, '<b>fruit</b>');

    final columns = parseWordbookText(
      '#separator:Tab\n'
      '#columns:Front\t\tBack\n'
      'apple\tguid123\tfruit\n',
      fileName: 'anki.txt',
    );
    expect(columns.entries.single.definition, 'fruit');
    expect(columns.columns, ['Front', '', 'Back']);

    final literal = parseWordbookText(
      '#separator:;\napple;fruit\n',
      fileName: 'anki.txt',
    );
    expect(literal.entries.single.word, 'apple');
    expect(
      () => parseWordbookText(
        '#separator:Unknown\napple\tfruit\n',
        fileName: 'anki.txt',
      ),
      throwsFormatException,
    );
  });

  test('未闭合引号和自动列映射的元数据列不能静默通过', () {
    final unclosed = parseWordbookText(
      'word\tdefinition\napple\tfruit\n"',
      fileName: 'words.tsv',
    );
    expect(unclosed.errorRows, 1);
    expect(unclosed.issues.single.line, 3);
    expect(unclosed.issues.single.message, contains('引号'));

    final metadata = parseWordbookText(
      '#separator:Tab\n'
      '#guid column:2\n'
      '#columns:Front\tBack\n'
      'apple\tguid123\n',
      fileName: 'anki.txt',
    );
    expect(metadata.requiresMapping, isTrue);
    expect(metadata.entries, isEmpty);
  });

  test('HTML 实体只解码一次，双编码内容不会二次展开', () {
    final parsed = parseWordbookText(
      '#separator:Tab\n#html:true\n'
      'apple\t&amp;lt;tag&amp;gt;\n',
      fileName: 'anki.txt',
    );
    expect(parsed.entries.single.definition, '&lt;tag&gt;');
  });

  test('无表头多列要求映射，同列和元数据列被拒绝', () {
    final text = 'extra\tapple\tfruit\nother\tpear\tnut\n';
    final initial = parseWordbookText(text, fileName: 'words.txt');
    expect(initial.requiresMapping, isTrue);
    expect(initial.entries, isEmpty);
    expect(initial.columns, hasLength(3));

    final mapped = parseWordbookText(
      text,
      fileName: 'words.txt',
      options: const WordbookParseOptions(
        delimiter: WordbookDelimiter.tab,
        wordColumn: 1,
        definitionColumn: 2,
      ),
    );
    expect(mapped.entries, hasLength(2));
    expect(mapped.entries.first.word, 'apple');

    expect(
      () => parseWordbookText(
        text,
        fileName: 'words.txt',
        options: const WordbookParseOptions(
          delimiter: WordbookDelimiter.tab,
          wordColumn: 1,
          definitionColumn: 1,
        ),
      ),
      throwsFormatException,
    );
  });

  test('Anki 元数据列不能被选为单词或释义', () {
    final text =
        '#separator:Tab\n#guid column:1\n#columns:GUID\tWord\tMeaning\n'
        'guid-1\tapple\tfruit\n';
    expect(
      () => parseWordbookText(
        text,
        fileName: 'anki.txt',
        options: const WordbookParseOptions(wordColumn: 0, definitionColumn: 2),
      ),
      throwsFormatException,
    );
  });

  test('JSON 数组与 entries 对象支持字段别名，null 有准确项号', () {
    final parsed = parseWordbookText(
      '[{"spelling":"apple","meaning":"fruit","phonetic":"/æ/",'
      '"example":"one"}, null, '
      '{"单词":"pear","释义":"fruit"}]',
      fileName: 'words.json',
    );
    expect(parsed.entries, hasLength(2));
    expect(parsed.entries.first.word, 'apple');
    expect(parsed.errorRows, 1);
    expect(parsed.issues.single.item, 2);
    expect(parsed.issues.single.message, contains('JSON 对象'));

    final object = parseWordbookText(
      '{"name":"我的词书","entries":[{"word":"apple","definition":"fruit"}]}',
      fileName: 'fallback.json',
    );
    expect(object.suggestedName, '我的词书');
    expect(object.entries.single.word, 'apple');
  });

  test('JSONL 和 terms.dat 保留物理行号，DAT 不做任意文本猜测', () {
    final jsonl =
        '\n\n{"word":"apple","definition":"fruit"}\n'
        '\n{"word":"pear","meaning":123}\n';
    final parsed = parseWordbookText(jsonl, fileName: 'words.jsonl');
    expect(parsed.entries, hasLength(1));
    expect(parsed.errorRows, 1);
    expect(parsed.issues.single.line, 5);

    final dat = parseWordbookText(
      '{"word":"apple","phonetic":"/æ/","meaning":"fruit"}\n',
      fileName: 'terms.dat',
    );
    expect(dat.entries.single.word, 'apple');
    expect(
      () => parseWordbookText('apple\tfruit\n', fileName: 'terms.dat'),
      returnsNormally,
    );
    final badDat = parseWordbookText('apple\tfruit\n', fileName: 'terms.dat');
    expect(badDat.errorRows, 1);
  });

  test('纯单词 TXT 仅返回待本地补全的单词，多义由调用方全部展开', () {
    final parsed = parseWordbookText(
      'word\napple\npear\napple\n',
      fileName: 'words.txt',
    );
    expect(parsed.isWordList, isTrue);
    expect(parsed.wordOnlyEntries.map((entry) => entry.word), [
      'word',
      'apple',
      'pear',
    ]);
    expect(parsed.duplicateRows, 1);

    final skipped = parseWordbookText(
      'word\napple\npear\napple\n',
      fileName: 'words.txt',
      options: const WordbookParseOptions(skipFirstRow: true),
    );
    expect(skipped.wordOnlyEntries.map((entry) => entry.word), [
      'apple',
      'pear',
    ]);
  });

  test('普通数据首列为 deck/tags 时不会被误判为元数据', () {
    final parsed = parseWordbookText(
      'deck\t甲板\napple\t苹果\ntags\t标签\n',
      fileName: 'words.tsv',
    );
    expect(parsed.metadataColumns, isEmpty);
    expect(parsed.entries, hasLength(3));
    expect(parsed.entries.first.word, 'deck');
  });

  test('粘贴文本拒绝 NUL，JSON 转义控制字符按字段报错', () {
    expect(
      () => parseWordbookText('apple,fr\u0000uit', fileName: 'paste.txt'),
      throwsFormatException,
    );
    final escaped = parseWordbookText(
      '[{"word":"apple","definition":"fr\\u0000uit"}]',
      fileName: 'words.json',
    );
    expect(escaped.entries, isEmpty);
    expect(escaped.errorRows, 1);
  });

  test('编码检测拒绝 UTF-16 与非法 UTF-8，不静默替换', () {
    expect(
      () => decodeWordbookBytes(Uint8List.fromList([0xFF, 0xFE, 0x61, 0x00])),
      throwsFormatException,
    );
    expect(
      () => decodeWordbookBytes(Uint8List.fromList([0x61, 0x80, 0x62])),
      throwsFormatException,
    );
  });

  test('CSV/JSON 导出可等价回读，模板可解析', () {
    const entries = [
      WordbookEntryDraft(
        word: 'apple',
        definition: '水果，含逗号',
        phonetic: '/æpəl/',
        example: 'He said "hi".\nSecond line.',
      ),
      WordbookEntryDraft(word: 'pear', definition: '一种水果'),
    ];
    final csv = exportWordbookCsv('我的词书', entries);
    final fromCsv = parseWordbookBytes(
      Uint8List.fromList(utf8.encode(csv)),
      fileName: 'export.csv',
    );
    expect(fromCsv.errorRows, 0);
    expect(fromCsv.entries, hasLength(2));
    expect(fromCsv.entries.first.definition, '水果，含逗号');
    expect(fromCsv.entries.first.example, 'He said "hi".\nSecond line.');

    final json = exportWordbookJson('我的词书', entries);
    final fromJson = parseWordbookText(json, fileName: 'export.json');
    expect(fromJson.errorRows, 0);
    expect(fromJson.entries, hasLength(2));
    expect(fromJson.suggestedName, '我的词书');

    expect(
      parseWordbookBytes(
        Uint8List.fromList(utf8.encode(wordbookCsvTemplate())),
        fileName: 'template.csv',
      ).entries,
      hasLength(1),
    );
    expect(
      parseWordbookText(
        wordbookJsonTemplate(),
        fileName: 'template.json',
      ).entries,
      hasLength(1),
    );
  });

  test('字段长度和文件大小边界显式拒绝', () {
    final longWord = 'a' * (WordbookFormatLimits.maxWordRunes + 1);
    final parsed = parseWordbookText(
      'word,definition\n$longWord,fruit\n',
      fileName: 'words.csv',
    );
    expect(parsed.errorRows, 1);
    expect(parsed.issues.single.message, contains('字符限制'));
    expect(
      () =>
          decodeWordbookBytes(Uint8List(WordbookFormatLimits.maxFileBytes + 1)),
      throwsFormatException,
    );
  });
}
