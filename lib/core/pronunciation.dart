import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class PronunciationController extends ChangeNotifier {
  PronunciationController({required this.loadRate, required this.saveRate});
  final Future<double> Function() loadRate;
  final Future<void> Function(double) saveRate;
  double rate = .5;
  String? error;
  bool starting = false;
  bool playing = false;
  Object? owner;
  FlutterTts? _tts;
  Future<void> _commands = Future.value();
  int _generation = 0;
  bool _disposed = false;
  bool _used = false;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() task) {
    final next = _commands.then((_) => task());
    // 当前调用仍接收异常，队列尾只负责让后续停音或重试能够继续。
    _commands = next.catchError((Object _) {});
    return next;
  }

  Future<void> _requireSuccess(Future<dynamic> operation) async {
    final result = await operation.timeout(const Duration(seconds: 10));
    if (result != 1) throw StateError('系统语音未能完成操作，请检查英语声音是否已安装。');
  }

  String _errorMessage(Object failure) => switch (failure) {
    MissingPluginException() => '此设备的读音服务尚未就绪，请安装包含语音插件的新版本。',
    TimeoutException() => '系统语音响应超时，请检查英语语音包后重试。',
    StateError() => failure.message,
    _ => '读音未能播放，请检查系统英语语音包后重试。',
  };

  Future<void> play(String word, {required Object owner}) async {
    if (_disposed || word.trim().isEmpty) return;
    final generation = ++_generation;
    this.owner = owner;
    error = null;
    starting = true;
    playing = false;
    _notify();
    bool current() => !_disposed && generation == _generation;
    await _enqueue(() async {
      if (!current()) return;
      try {
        final tts = _tts ??= FlutterTts();
        if (_used) await _requireSuccess(tts.stop());
        if (!current()) return;
        var started = false;
        var finished = false;
        tts.setStartHandler(() {
          if (current()) started = true;
        });
        void completed() {
          if (!current() || (starting && !started)) return;
          finished = true;
          playing = false;
          _notify();
        }

        tts.setCompletionHandler(completed);
        tts.setCancelHandler(completed);
        tts.setErrorHandler((_) {
          if (!current()) return;
          playing = false;
          error = '系统未能播放读音，请检查英语语音包后重试。';
          _notify();
        });
        rate = await loadRate();
        final rawVoices = await tts.getVoices.timeout(
          const Duration(seconds: 10),
        );
        if (!current()) return;
        final voices = rawVoices is List ? rawVoices.whereType<Map>() : <Map>[];
        final english = voices.where((voice) {
          final locale = '${voice['locale']}'
              .replaceAll('_', '-')
              .toLowerCase();
          final network = '${voice['network_required']}'.toLowerCase();
          return (locale == 'en' || locale.startsWith('en-')) &&
              network != 'true' &&
              network != '1' &&
              !'${voice['features']}'.contains('notInstalled') &&
              voice['name'] is String;
        }).toList();
        if (english.isEmpty) {
          throw StateError('未找到可用的本地英语声音，请在系统语音设置中安装英语语音包后重试。');
        }
        final voice = english.firstWhere(
          (voice) => '${voice['locale']}'.replaceAll('_', '-') == 'en-US',
          orElse: () => english.first,
        );
        await _requireSuccess(
          tts.setVoice({
            'name': voice['name'] as String,
            'locale': voice['locale'] as String,
          }),
        );
        if (!current()) return;
        await _requireSuccess(tts.setSpeechRate(rate));
        if (!current()) return;
        // 等待的是启动结果，避免 Windows 在未开始发音时等待完成回调。
        _used = true;
        await _requireSuccess(tts.speak(word.trim(), focus: true));
        if (current()) playing = error == null && !finished;
      } catch (failure) {
        if (current()) error = _errorMessage(failure);
      } finally {
        if (current()) {
          starting = false;
          _notify();
        }
      }
    });
  }

  Future<void> stop({Object? owner}) async {
    if (owner != null && !identical(this.owner, owner)) return;
    ++_generation;
    starting = false;
    playing = false;
    this.owner = null;
    // 生命周期回调可能在 build/dispose 中触发，通知推迟到当前栈结束。
    scheduleMicrotask(_notify);
    // 尚未调用 speak 时，代次检查已能取消准备过程，无须排队访问引擎。
    if (_tts == null || !_used) return;
    await _enqueue(() async {
      if (_tts == null || !_used) return;
      try {
        await _requireSuccess(_tts!.stop());
        _used = false;
      } catch (failure) {
        error = _errorMessage(failure);
        _notify();
      }
    });
  }

  Future<void> changeRate(double value) async {
    if (![.35, .5, .65].contains(value)) throw ArgumentError('不支持的语速。');
    await saveRate(value);
    rate = value;
    _notify();
  }

  Future<void> reloadSettings() async {
    rate = await loadRate();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }
}
