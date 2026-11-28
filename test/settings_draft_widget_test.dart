import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:flutter_test/flutter_test.dart';
import 'package:lexi_loop/core/ids.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:lexi_loop/ui/settings_page.dart';

void main() {
  late AppDependencies dependencies;
  late ValueNotifier<int> signal;
  late FilePickerPlatform originalPicker;
  final fixedNow = DateTime.utc(2026, 11, 27, 8, 0);
  setUp(() async {
    dependencies = AppDependencies(
      AppDatabase(NativeDatabase.memory()),
      nowUtc: () => fixedNow,
    );
    await dependencies.initialize();
    signal = ValueNotifier<int>(0);
    originalPicker = FilePickerPlatform.instance;
  });
  tearDown(() async {
    FilePickerPlatform.instance = originalPicker;
    signal.dispose();
    await dependencies.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1280, 1000),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: journalTheme(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SettingsPage(
            dependencies: dependencies,
            refreshListenable: signal,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField goalField(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).first);

  testWidgets('普通刷新保留未保存草稿和空字符串', (tester) async {
    await pump(tester);
    final field = find.byType(TextField).first;
    expect(goalField(tester).controller!.text, '10');
    await tester.enterText(field, '27');
    await tester.pump();
    signal.value++;
    await tester.pumpAndSettle();
    expect(goalField(tester).controller!.text, '27');
    expect(await dependencies.repository.dailyGoal(), 10);

    await tester.enterText(field, '');
    await tester.pump();
    signal.value++;
    await tester.pumpAndSettle();
    expect(goalField(tester).controller!.text, isEmpty);
    expect(await dependencies.repository.dailyGoal(), 10);
    expect(tester.takeException(), isNull);
  });

  testWidgets('无编辑时刷新会显示数据库新值，旧读取不覆盖新输入', (tester) async {
    await pump(tester);
    expect(goalField(tester).controller!.text, '10');
    await dependencies.repository.setDailyGoal(20);
    signal.value++;
    await tester.pumpAndSettle();
    expect(goalField(tester).controller!.text, '20');

    final field = find.byType(TextField).first;
    signal.value++;
    await tester.enterText(field, '33');
    await tester.pumpAndSettle();
    expect(goalField(tester).controller!.text, '33');
    expect(await dependencies.repository.dailyGoal(), 20);
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存成功清除 dirty，后续刷新跟随数据库', (tester) async {
    await pump(tester);
    final field = find.byType(TextField).first;
    await tester.enterText(field, '5');
    await tester.pump();
    await tester.ensureVisible(find.text('保存目标'));
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();
    expect(await dependencies.repository.dailyGoal(), 5);

    await dependencies.repository.setDailyGoal(7);
    signal.value++;
    await tester.pumpAndSettle();
    expect(goalField(tester).controller!.text, '7');
    expect(tester.takeException(), isNull);
  });

  testWidgets('保存失败保留草稿，普通刷新也不覆盖', (tester) async {
    await dependencies.database.customStatement(
      "CREATE TRIGGER reject_goal BEFORE UPDATE ON app_settings "
      "WHEN NEW.key = 'daily_new_goal' "
      "BEGIN SELECT RAISE(ABORT, 'test goal failure'); END",
    );
    await pump(tester);
    final field = find.byType(TextField).first;
    await tester.enterText(field, '6');
    await tester.pump();
    await tester.ensureVisible(find.text('保存目标'));
    await tester.tap(find.text('保存目标'));
    await tester.pumpAndSettle();
    expect(find.textContaining('操作未完成'), findsOneWidget);
    expect(goalField(tester).controller!.text, '6');

    await dependencies.database.customStatement('DROP TRIGGER reject_goal');
    await dependencies.repository.setDailyGoal(9);
    signal.value++;
    await tester.pumpAndSettle();
    expect(goalField(tester).controller!.text, '6');
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复前展示校验摘要，取消不写库也不使撤销失效', (tester) async {
    final item = (await dependencies.repository.queue()).first;
    final eventId = newReviewEventId();
    await dependencies.repository.score(
      item,
      fsrs.Rating.good,
      eventId: eventId,
    );
    final source = await dependencies.backup.export();
    final before = await dependencies.backup.export();
    final picker = _TestFilePicker(_picked('学习备份.json', source));
    FilePickerPlatform.instance = picker;

    await pump(tester, size: const Size(390, 844), textScale: 1.5);
    await tester.ensureVisible(find.text('恢复备份'));
    await tester.tap(find.text('恢复备份'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('备份时间：'), findsOneWidget);
    final local = fixedNow.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    final expectedTime =
        '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
    expect(find.textContaining('备份时间：$expectedTime'), findsOneWidget);
    expect(find.textContaining('已学词义：1'), findsOneWidget);
    expect(find.textContaining('评分记录：1'), findsOneWidget);
    expect(find.textContaining('不会与现有数据合并'), findsOneWidget);
    expect(find.textContaining('只在本机'), findsOneWidget);
    expect(await dependencies.backup.export(), before);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(await dependencies.backup.export(), before);

    await dependencies.repository.undoLastReview(eventId);
    expect(await dependencies.repository.history(), isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('确认恢复后应用备份并刷新目标', (tester) async {
    final source = await dependencies.backup.export();
    await dependencies.repository.setDailyGoal(3);
    FilePickerPlatform.instance = _TestFilePicker(_picked('学习备份.json', source));

    await pump(tester);
    await tester.ensureVisible(find.text('恢复备份'));
    await tester.tap(find.text('恢复备份'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('备份时间：'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('backup-preview-scroll'))).width,
      lessThanOrEqualTo(520),
    );
    await tester.tap(find.text('确认恢复'));
    var restored = false;
    for (var attempt = 0; attempt < 100; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 20));
      final goal = await tester.runAsync(
        () => dependencies.repository.dailyGoal(),
      );
      if (goal == 10) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        restored = true;
        break;
      }
    }
    expect(restored, isTrue);
    await tester.pumpAndSettle();

    expect(await dependencies.repository.dailyGoal(), 10);
    expect(goalField(tester).controller!.text, '10');
    expect(find.textContaining('备份已恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('损坏备份直接明确报错，不显示替换确认', (tester) async {
    final before = await dependencies.backup.export();
    FilePickerPlatform.instance = _TestFilePicker(
      _picked('损坏备份.json', 'not a backup'),
    );

    await pump(tester);
    await tester.ensureVisible(find.text('恢复备份'));
    await tester.tap(find.text('恢复备份'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('备份校验失败'), findsOneWidget);
    expect(await dependencies.backup.export(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('备份取消重复回调只关闭弹框，保留设置页与数据', (tester) async {
    final before = await dependencies.backup.export();
    FilePickerPlatform.instance = _TestFilePicker(_picked('备份.json', before));
    await pump(tester);
    final navigator = Navigator.of(tester.element(find.byType(SettingsPage)));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) =>
              Scaffold(body: SettingsPage(dependencies: dependencies)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('恢复备份'));
    await tester.tap(find.text('恢复备份'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final cancel = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '取消'))
        .onPressed!;
    cancel();
    cancel();
    await tester.pumpAndSettle();
    expect(navigator.canPop(), isTrue);
    expect(find.byType(SettingsPage), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(await dependencies.backup.export(), before);
    expect(tester.takeException(), isNull);
  });

  testWidgets('恢复按钮同帧连点只发起一次文件选择', (tester) async {
    final picker = _TestFilePicker.pending();
    FilePickerPlatform.instance = picker;

    await pump(tester);
    await tester.ensureVisible(find.text('恢复备份'));
    await tester.tap(find.text('恢复备份'));
    await tester.tap(find.text('恢复备份'));
    await tester.pump();
    final calls = picker.pickFileCalls;
    picker.complete(null);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}

PlatformFile _picked(String name, String source) =>
    _MemoryPlatformFile(name, Uint8List.fromList(utf8.encode(source)));

final class _MemoryPlatformFile extends PlatformFile {
  _MemoryPlatformFile(this.name, this.bytes);

  @override
  final String name;
  final Uint8List bytes;

  @override
  Uri get uri => Uri.dataFromBytes(bytes);

  @override
  int? lengthSync() => bytes.length;

  @override
  Future<int?> length() async => bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => bytes;

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _TestFilePicker extends FilePickerPlatform {
  _TestFilePicker(this.file);
  _TestFilePicker.pending() : file = null, _pending = Completer();

  final PlatformFile? file;
  Completer<PlatformFile?>? _pending;
  int pickFileCalls = 0;

  void complete(PlatformFile? result) {
    _pending?.complete(result);
    _pending = null;
  }

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) {
    pickFileCalls++;
    final pending = _pending;
    return pending == null ? Future.value(file) : pending.future;
  }
}
