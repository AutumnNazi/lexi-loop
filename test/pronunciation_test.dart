import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:lexi_loop/app.dart';
import 'package:lexi_loop/core/pronunciation.dart';
import 'package:lexi_loop/data/app_database.dart';
import 'package:lexi_loop/ui/common.dart';
import 'package:lexi_loop/ui/journal_style.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('flutter_tts');
  final calls = <MethodCall>[];
  late PronunciationController speech;
  var storedRate = .5;
  setUp(() {
    calls.clear();
    storedRate = .5;
    speech = PronunciationController(
      loadRate: () async => storedRate,
      saveRate: (value) async => storedRate = value,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            return [
              {'name': 'Chinese', 'locale': 'zh-CN'},
              {'name': 'Online', 'locale': 'en-US', 'network_required': true},
              {'name': 'English', 'locale': 'en-US', 'network_required': false},
            ];
          }
          return 1;
        });
  });
  tearDown(() async {
    await speech.stop();
    speech.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('点击读音选择本地英语声音并应用语速，重播前停止旧读音', () async {
    final owner = Object();
    await speech.play(' bloom ', owner: owner);
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    expect(calls.where((c) => c.method == 'speak').single.arguments, 'bloom');
    expect(calls.firstWhere((c) => c.method == 'setVoice').arguments, {
      'name': 'English',
      'locale': 'en-US',
    });
    expect(calls.firstWhere((c) => c.method == 'setSpeechRate').arguments, .5);
    expect(speech.error, isNull);
    calls.clear();
    await speech.play('bloom', owner: owner);
    expect(calls.first.method, 'stop');
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
  });

  Future<void> platformEvent(String method, [Object? value]) async {
    final done = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          'flutter_tts',
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, value),
          ),
          (_) => done.complete(),
        );
    await done.future;
  }

  test('系统完成与报错会更新播放状态，错误允许重试', () async {
    final owner = Object();
    await speech.play('bloom', owner: owner);
    expect(speech.playing, isTrue);
    await platformEvent('speak.onComplete');
    expect(speech.playing, isFalse);
    await speech.play('bloom', owner: owner);
    await platformEvent('speak.onError', 'engine unavailable');
    expect(speech.playing, isFalse);
    expect(speech.error, contains('系统'));
    await speech.play('bloom', owner: owner);
    expect(speech.error, isNull);
  });

  test('短词完成事件早于启动响应时不会残留播放中状态', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getVoices') {
            return [
              {'name': 'English', 'locale': 'en-US'},
            ];
          }
          if (call.method == 'speak') {
            await platformEvent('speak.onStart');
            await platformEvent('speak.onComplete');
          }
          return 1;
        });
    await speech.play('a', owner: Object());
    expect(speech.starting, isFalse);
    expect(speech.playing, isFalse);
    expect(speech.error, isNull);
  });

  test('Android 字符串标志排除联网和未安装声音', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            return [
              {'name': 'Network', 'locale': 'en-US', 'network_required': '1'},
              {
                'name': 'Not installed',
                'locale': 'en-US',
                'features': 'notInstalled',
              },
              {
                'name': 'Offline UK',
                'locale': 'en-GB',
                'network_required': '0',
              },
            ];
          }
          return 1;
        });
    await speech.play('bloom', owner: Object());
    expect(calls.firstWhere((c) => c.method == 'setVoice').arguments, {
      'name': 'Offline UK',
      'locale': 'en-GB',
    });
  });

  test('没有英语声音和引擎拒绝播放均明确报错，不冒充成功', () async {
    var available = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            return available
                ? [
                    {'name': 'English', 'locale': 'en-US'},
                  ]
                : [
                    {'name': 'Chinese', 'locale': 'zh-CN'},
                  ];
          }
          return call.method == 'speak' ? 0 : 1;
        });
    await speech.play('bloom', owner: Object());
    expect(speech.error, contains('安装英语语音包'));
    expect(calls.where((c) => c.method == 'speak'), isEmpty);
    available = true;
    await speech.play('bloom', owner: Object());
    expect(speech.error, contains('系统语音'));
    expect(speech.playing, isFalse);
  });

  test('准备读音时离开，晚到的声音列表不会触发播放', () async {
    final gate = Completer<List<Map<String, String>>>();
    final queried = Completer<void>();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getVoices') {
            queried.complete();
            return gate.future;
          }
          return 1;
        });
    final owner = Object();
    final play = speech.play('bloom', owner: owner);
    await queried.future;
    final stop = speech.stop(owner: owner);
    gate.complete([
      {'name': 'English', 'locale': 'en-US'},
    ]);
    await Future.wait([play, stop]);
    expect(calls.where((c) => c.method == 'speak'), isEmpty);
    expect(speech.starting, isFalse);
  });

  test('旧页面停止请求不打断新页面，语速保存失败保留旧值', () async {
    final oldOwner = Object(), newOwner = Object();
    await speech.play('bloom', owner: oldOwner);
    await speech.play('steady', owner: newOwner);
    calls.clear();
    await speech.stop(owner: oldOwner);
    expect(calls, isEmpty);
    expect(speech.owner, same(newOwner));
    await speech.changeRate(.35);
    expect(storedRate, .35);
    await speech.play('steady', owner: newOwner);
    expect(calls.firstWhere((c) => c.method == 'setSpeechRate').arguments, .35);
    await expectLater(speech.changeRate(double.nan), throwsArgumentError);
    final rejected = PronunciationController(
      loadRate: () async => .5,
      saveRate: (_) async => throw StateError('storage unavailable'),
    );
    await expectLater(rejected.changeRate(.35), throwsStateError);
    expect(rejected.rate, .5);
    rejected.dispose();
  });

  test('语速随完整备份恢复，旧备份无语速时使用标准', () async {
    final deps = AppDependencies(AppDatabase(NativeDatabase.memory()));
    await deps.initialize();
    final original = await deps.backup.export();
    await deps.pronunciation.changeRate(.35);
    final slow = await deps.backup.export();
    expect(await deps.repository.pronunciationRate(), .35);
    expect(await deps.repository.history(), isEmpty);
    await deps.backup.restore(original);
    await deps.reloadTheme();
    expect(deps.pronunciation.rate, .5);
    await deps.backup.restore(slow);
    await deps.reloadTheme();
    expect(deps.pronunciation.rate, .35);
    expect(await deps.repository.history(), isEmpty);
    await deps.dispose();
  });

  testWidgets('窄屏读音支持重播和语速，换词或离开会停止', (tester) async {
    final deps = AppDependencies(AppDatabase(NativeDatabase.memory()));
    await tester.runAsync(deps.initialize);
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Future<void> show(String word) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: journalTheme(Brightness.dark),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Scaffold(
            body: WordPronunciationButton(dependencies: deps, word: word),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await show('bloom');
    await tester.tap(find.text('听读音'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'speak'), hasLength(1));
    expect(find.text('再听一次'), findsOneWidget);
    await tester.tap(find.text('再听一次'));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'speak'), hasLength(2));
    await tester.tap(find.text('语速 · 标准'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('慢速').last);
    await tester.pumpAndSettle();
    expect(await deps.repository.pronunciationRate(), .35);
    await tester.tap(find.text('再听一次'));
    await tester.pumpAndSettle();
    calls.clear();
    await show('steady');
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    expect(find.text('听读音'), findsOneWidget);
    await tester.tap(find.text('听读音'));
    await tester.pumpAndSettle();
    calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    expect(deps.pronunciation.playing, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.tap(find.text('再听一次'));
    await tester.pumpAndSettle();
    calls.clear();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    expect(tester.takeException(), isNull);
    await deps.dispose();
  });
}
