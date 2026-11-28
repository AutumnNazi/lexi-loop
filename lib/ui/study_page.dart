import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:fsrs/fsrs.dart' as fsrs;
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/ids.dart';
import '../data/study_repository.dart';
import 'common.dart';
import 'journal_style.dart';

enum _NewWordStage { browse, test }

class StudyPage extends StatefulWidget {
  const StudyPage({
    super.key,
    required this.dependencies,
    this.senseId,
    this.wordbookId,
    this.todayPlan = false,
    this.queueStatusLoader,
    this.sessionSummaryLoader,
    this.itemLoader,
  });
  final AppDependencies dependencies;
  final int? senseId;
  final String? wordbookId;
  final bool todayPlan;
  final Future<StudyQueueStatus> Function()? queueStatusLoader;
  final Future<StudySessionSummary> Function(Set<String> eventIds)?
  sessionSummaryLoader;
  final Future<StudyItem?> Function(int senseId)? itemLoader;
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> with WidgetsBindingObserver {
  StudyItem? _item;
  StudyQueueStatus? _status;
  bool _revealed = false, _busy = false, _loading = true;
  _NewWordStage? _newWordStage;
  List<StudyItem> _newWordGroup = const [];
  int _newWordBrowseIndex = 0;
  int _newWordTestIndex = 0;
  final Set<int> _newWordScored = {};
  bool _browseAdvancePending = false;
  List<StudyItem>? _undoNewWordGroup;
  int? _undoNewWordIndex;
  Set<int>? _undoNewWordScored;
  bool _loadFailed = false;
  String? _error;
  String? _summaryError;
  String _eventId = newReviewEventId();
  String? _lastUndoEventId;
  DateTime? _shownAt;
  Timer? _timer;
  StreamSubscription<void>? _subscription;
  int _generation = 0;
  int _completedCount = 0;
  int _summaryRevision = 0;
  bool _summaryOpening = false;
  bool _exitDialogOpen = false;
  bool _allowExit = false;
  bool _exitScheduled = false;
  bool _routePopped = false;
  final Set<String> _sessionEventIds = {};
  StudySessionSummary? _sessionSummary;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.dependencies.repository.changes.listen((_) {
      if (!_busy) {
        _refreshSessionSummary();
        _load();
      }
    });
    _load();
    _refreshSessionSummary();
  }

  Future<void> _load({int? preferSenseId}) async {
    if (!mounted || _allowExit || _exitScheduled) return;
    final generation = ++_generation;
    final deps = widget.dependencies;
    _timer?.cancel();
    if (_item == null && !_loading) {
      setState(() => _loading = true);
    }
    try {
      final status = widget.queueStatusLoader != null
          ? await widget.queueStatusLoader!()
          : widget.todayPlan
          ? await deps.repository.queueStatus(todayPlan: true)
          : await deps.repository.queueStatus(
              wordbookId: widget.wordbookId,
              senseId: widget.senseId,
            );
      if (!mounted || generation != _generation) return;
      if (_newWordStage != null) {
        final stillValid = await _newWordGroupStillValid(status);
        if (!mounted || generation != _generation) return;
        if (!stillValid || _activeNewWordItem == null) {
          _newWordStage = null;
          _newWordGroup = const [];
          _newWordBrowseIndex = 0;
          _newWordTestIndex = 0;
          _newWordScored.clear();
        }
      }
      if (_newWordStage != null) {
        setState(() {
          _item = _activeNewWordItem;
          _status = status;
          _loading = false;
          _loadFailed = false;
          _error = null;
        });
        _scheduleWake(status);
        return;
      }
      final matches = status.items;
      final dueItems = matches
          .where((item) => item.memory != null)
          .toList(growable: false);
      final preferredId = preferSenseId ?? _item?.sense.id;
      StudyItem? next;
      List<StudyItem> group = const [];
      _NewWordStage? stage;
      if (dueItems.isNotEmpty) {
        next = preferredId == null
            ? dueItems.first
            : dueItems.firstWhere(
                (item) => item.sense.id == preferredId,
                orElse: () => dueItems.first,
              );
      } else {
        final newItems = matches
            .where((item) => item.memory == null)
            .toList(growable: false);
        if (newItems.isNotEmpty) {
          final preferredIndex = preferredId == null
              ? -1
              : newItems.indexWhere((item) => item.sense.id == preferredId);
          final ordered = preferredIndex <= 0
              ? newItems
              : [
                  newItems[preferredIndex],
                  ...newItems.where((item) => item.sense.id != preferredId),
                ];
          group = ordered.take(5).toList(growable: false);
          next = group.first;
          stage = _NewWordStage.browse;
        }
      }
      final itemChanged = !_sameStudyItem(_item, next);
      setState(() {
        if (itemChanged) {
          _revealed = false;
          _eventId = newReviewEventId();
          _shownAt = deps.nowUtc();
        }
        _newWordStage = stage;
        _newWordGroup = group;
        if (group.isNotEmpty) {
          _newWordBrowseIndex = 0;
          _newWordTestIndex = 0;
          _newWordScored.clear();
        }
        _item = next;
        _status = status;
        _loading = false;
        _loadFailed = false;
        _error = null;
      });
      if (itemChanged) {
        unawaited(widget.dependencies.pronunciation.stop());
      }
      _scheduleWake(status);
    } catch (error) {
      if (mounted && generation == _generation) {
        _timer?.cancel();
        setState(() {
          _loading = false;
          _loadFailed = true;
          _item = null;
          _status = null;
          _error = '$error';
        });
      }
    }
  }

  void _scheduleWake(StudyQueueStatus status) {
    final now = widget.dependencies.nowUtc();
    final midnight = widget.dependencies.repository.calendar.nextMidnightUtc(
      now,
    );
    final due = status.nextDue;
    final wakeAt = due != null && due.isBefore(midnight) ? due : midnight;
    final delay = wakeAt.difference(now);
    _timer = Timer(delay.isNegative ? Duration.zero : delay, () {
      if (!_busy) _load();
    });
  }

  Future<StudyItem?> _itemForSense(int senseId) async {
    final loader = widget.itemLoader;
    return loader != null
        ? loader(senseId)
        : widget.dependencies.repository.itemBySenseId(senseId);
  }

  bool _sameItemContent(StudyItem a, StudyItem b) =>
      a.word.id == b.word.id &&
      a.word.spelling == b.word.spelling &&
      a.sense.id == b.sense.id &&
      a.sense.definition == b.sense.definition &&
      a.sense.example == b.sense.example &&
      a.sense.phonetics == b.sense.phonetics;

  Future<bool> _newWordGroupStillValid(StudyQueueStatus status) async {
    final inScope = status.items.map((item) => item.sense.id).toSet();
    for (final original in _newWordGroup) {
      final current = await _itemForSense(original.sense.id);
      if (current == null || !_sameItemContent(current, original)) {
        return false;
      }
      final scored = _newWordScored.contains(original.sense.id);
      if (scored ? current.memory == null : current.memory != null) {
        return false;
      }
      // 每日额度或学习词书被外部调整后，未测新词若已离开当前范围，
      // 不能继续沿用旧组，否则会绕过额度或学到范围外词义。
      if (!scored && !inScope.contains(original.sense.id)) {
        return false;
      }
    }
    return true;
  }

  StudyItem? get _activeNewWordItem {
    if (_newWordStage == null || _newWordGroup.isEmpty) return null;
    final index = _newWordStage == _NewWordStage.browse
        ? _newWordBrowseIndex
        : _newWordTestIndex;
    if (index < 0 || index >= _newWordGroup.length) return null;
    return _newWordGroup[index];
  }

  void _advanceBrowse() {
    if (_busy ||
        _summaryOpening ||
        _newWordStage != _NewWordStage.browse ||
        _newWordGroup.isEmpty) {
      return;
    }
    if (_browseAdvancePending) return;
    _browseAdvancePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _browseAdvancePending = false;
    });
    _generation++;
    unawaited(widget.dependencies.pronunciation.stop());
    if (_newWordBrowseIndex + 1 < _newWordGroup.length) {
      setState(() {
        _newWordBrowseIndex++;
        _item = _newWordGroup[_newWordBrowseIndex];
        _revealed = false;
        _eventId = newReviewEventId();
        _shownAt = widget.dependencies.nowUtc();
      });
      return;
    }
    setState(() {
      _newWordStage = _NewWordStage.test;
      _newWordTestIndex = 0;
      _newWordScored.clear();
      _item = _newWordGroup.first;
      _revealed = false;
      _eventId = newReviewEventId();
      _shownAt = widget.dependencies.nowUtc();
    });
  }

  void _rememberUndoNewWordContext(
    List<StudyItem>? group,
    int? index,
    Set<int>? scored,
  ) {
    _undoNewWordGroup = group;
    _undoNewWordIndex = index;
    _undoNewWordScored = scored;
  }

  Future<bool> _canRestoreUndoneNewWord(StudyUndoResult result) async {
    final group = _undoNewWordGroup;
    final index = _undoNewWordIndex;
    final scoredBefore = _undoNewWordScored;
    if (!result.firstLearning ||
        group == null ||
        index == null ||
        scoredBefore == null ||
        index < 0 ||
        index >= group.length ||
        group[index].sense.id != result.wordSenseId) {
      return false;
    }
    for (var i = 0; i < group.length; i++) {
      final current = await _itemForSense(group[i].sense.id);
      if (current == null || !_sameItemContent(current, group[i])) {
        return false;
      }
      // 被撤销的词回到未学；同组其他已评词仍须保留当时的记忆状态。
      final wasScored = scoredBefore.contains(group[i].sense.id);
      if (i == index) {
        if (current.memory != null) return false;
      } else if (wasScored != (current.memory != null)) {
        return false;
      }
    }
    return true;
  }

  void _restoreUndoneNewWordTest(StudyUndoResult result) {
    final group = _undoNewWordGroup!;
    final index = _undoNewWordIndex!;
    final scored = Set<int>.of(_undoNewWordScored!);
    setState(() {
      _newWordStage = _NewWordStage.test;
      _newWordGroup = group;
      _newWordBrowseIndex = 0;
      _newWordTestIndex = index;
      _newWordScored
        ..clear()
        ..addAll(scored);
      _item = group[index];
      _revealed = false;
      _eventId = newReviewEventId();
      _shownAt = widget.dependencies.nowUtc();
      _loading = false;
      _loadFailed = false;
      _error = null;
    });
  }

  Future<void> _rate(fsrs.Rating rating) async {
    if (_busy ||
        _summaryOpening ||
        _exitDialogOpen ||
        _allowExit ||
        !_revealed ||
        _item == null ||
        _newWordStage == _NewWordStage.browse) {
      return;
    }
    unawaited(widget.dependencies.pronunciation.stop());
    _generation++;
    final undoGroup = _newWordStage == _NewWordStage.test
        ? List<StudyItem>.of(_newWordGroup)
        : null;
    final undoIndex = _newWordStage == _NewWordStage.test
        ? _newWordTestIndex
        : null;
    final undoScored = _newWordStage == _NewWordStage.test
        ? Set<int>.of(_newWordScored)
        : null;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final item = _item!;
      final eventId = _eventId;
      final elapsed = widget.dependencies
          .nowUtc()
          .difference(_shownAt!)
          .inMilliseconds;
      await widget.dependencies.repository.score(
        item,
        rating,
        eventId: eventId,
        durationMs: elapsed < 0 ? 0 : elapsed,
      );
      if (!mounted) return;
      _completedCount++;
      _sessionEventIds.add(eventId);
      _lastUndoEventId = eventId;
      _rememberUndoNewWordContext(undoGroup, undoIndex, undoScored);
      await _refreshSessionSummary();
      if (!mounted) return;
      if (_newWordStage == _NewWordStage.test && _newWordGroup.isNotEmpty) {
        _newWordScored.add(item.sense.id);
        if (_newWordTestIndex + 1 < _newWordGroup.length) {
          final next = _newWordGroup[_newWordTestIndex + 1];
          setState(() {
            _newWordTestIndex++;
            _item = next;
            _revealed = false;
            _eventId = newReviewEventId();
            _shownAt = widget.dependencies.nowUtc();
          });
          await _load();
          if (mounted && _loadFailed) {
            setState(() => _error = '评分已保存，但刷新队列失败：$_error');
          }
        } else {
          setState(() {
            _newWordStage = null;
            _newWordGroup = const [];
            _newWordBrowseIndex = 0;
            _newWordTestIndex = 0;
            _newWordScored.clear();
            _item = null;
            _loading = true;
          });
          await _load();
        }
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _sameSessionEvents(Set<String> ids) =>
      ids.length == _sessionEventIds.length &&
      ids.every(_sessionEventIds.contains);

  bool _sameStudyItem(StudyItem? a, StudyItem? b) {
    if (a == null || b == null) return a == b;
    return a.word.id == b.word.id &&
        a.word.spelling == b.word.spelling &&
        a.sense.id == b.sense.id &&
        a.sense.definition == b.sense.definition &&
        a.sense.example == b.sense.example &&
        a.sense.phonetics == b.sense.phonetics &&
        a.memory == b.memory;
  }

  Future<void> _refreshSessionSummary() async {
    final ids = Set<String>.of(_sessionEventIds);
    final revision = ++_summaryRevision;
    try {
      final summary = widget.sessionSummaryLoader != null
          ? await widget.sessionSummaryLoader!(ids)
          : await widget.dependencies.repository.sessionSummary(ids);
      if (!mounted ||
          revision != _summaryRevision ||
          !_sameSessionEvents(ids)) {
        return;
      }
      setState(() {
        _sessionSummary = summary;
        _summaryError = null;
      });
    } catch (error) {
      if (mounted && revision == _summaryRevision && _sameSessionEvents(ids)) {
        setState(() => _summaryError = '$error');
      }
    }
  }

  Future<void> _undo() async {
    final eventId = _lastUndoEventId;
    if (eventId == null ||
        _busy ||
        _summaryOpening ||
        _exitDialogOpen ||
        _allowExit ||
        _loading) {
      return;
    }
    unawaited(widget.dependencies.pronunciation.stop());
    _generation++;
    var wrote = false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.dependencies.repository.undoLastReview(
        eventId,
      );
      wrote = true;
      if (!mounted) return;
      _sessionEventIds.remove(eventId);
      _lastUndoEventId = null;
      _completedCount = math.max(0, _completedCount - 1);
      await _refreshSessionSummary();
      if (!mounted) return;
      var restoredNewWord = false;
      try {
        restoredNewWord = await _canRestoreUndoneNewWord(result);
      } catch (_) {
        restoredNewWord = false;
      }
      if (!mounted) return;
      if (restoredNewWord) {
        _restoreUndoneNewWordTest(result);
      }
      _rememberUndoNewWordContext(null, null, null);
      _timer?.cancel();
      if (restoredNewWord) {
        // 组仍有效时按阶段刷新队列状态，避免重新排序把当前词换掉。
        await _load();
        if (mounted && _loadFailed) {
          setState(() => _error = '评分已撤销，但刷新队列失败：$_error');
        }
        return;
      }
      if (_newWordStage != null) {
        setState(() {
          _newWordStage = null;
          _newWordGroup = const [];
          _newWordBrowseIndex = 0;
          _newWordTestIndex = 0;
          _newWordScored.clear();
        });
      }
      await _load(preferSenseId: result.wordSenseId);
      if (mounted && _loadFailed) {
        setState(() => _error = '评分已撤销，但刷新队列失败：$_error');
        return;
      }
      if (mounted && _item?.sense.id != result.wordSenseId) {
        try {
          final item = widget.itemLoader != null
              ? await widget.itemLoader!(result.wordSenseId)
              : await widget.dependencies.repository.itemBySenseId(
                  result.wordSenseId,
                );
          if (item != null && mounted) {
            setState(() {
              if (_newWordStage == _NewWordStage.browse &&
                  !_newWordGroup.any(
                    (candidate) => candidate.sense.id == item.sense.id,
                  )) {
                _newWordStage = null;
                _newWordGroup = const [];
                _newWordBrowseIndex = 0;
                _newWordTestIndex = 0;
                _newWordScored.clear();
              }
              _item = item;
              _revealed = false;
              _eventId = newReviewEventId();
              _shownAt = widget.dependencies.nowUtc();
              _loading = false;
              _loadFailed = false;
            });
          }
        } catch (error) {
          if (mounted) {
            setState(() => _error = '评分已撤销，但读取原词失败：$error');
          }
        }
      }
    } on UndoUnavailable catch (error) {
      if (mounted) {
        setState(() {
          _lastUndoEventId = null;
          _error = '$error';
        });
      }
      _rememberUndoNewWordContext(null, null, null);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = wrote ? '评分已撤销，但刷新当前词失败：$error' : '撤销失败，记忆状态未变：$error',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openSummary() async {
    if (_summaryOpening || _exitDialogOpen || _allowExit) return;
    unawaited(widget.dependencies.pronunciation.stop());
    setState(() => _summaryOpening = true);
    try {
      await _refreshSessionSummary();
      if (!mounted) return;
      final response = DialogResponse<bool>();
      final endRound = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('本轮学习小结'),
            content: SingleChildScrollView(
              child: SizedBox(
                width: math.min(520, MediaQuery.sizeOf(context).width - 96),
                child: _summaryContent(
                  context,
                  onRetry: () async {
                    await _refreshSessionSummary();
                    if (context.mounted) setDialogState(() {});
                  },
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => response.close(dialogContext, false),
                child: const Text('继续学习'),
              ),
              if (_item != null)
                FilledButton(
                  onPressed: () => response.close(dialogContext, true),
                  child: const Text('结束本轮并返回'),
                ),
            ],
          ),
        ),
      );
      if (endRound == true && mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _summaryOpening = false);
    }
  }

  Widget _summaryContent(BuildContext context, {VoidCallback? onRetry}) {
    final tokens = JournalTokens.of(context);
    final summary = _sessionSummary;
    if (_summaryError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '本轮统计暂时无法读取：$_summaryError',
            style: TextStyle(color: tokens.again.foreground),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: onRetry ?? _refreshSessionSummary,
            child: const Text('重试统计'),
          ),
        ],
      );
    }
    if (summary == null) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final rate = summary.successRate;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        StatStrip(
          items: [
            (label: '本轮评分', value: '${summary.ratingCount} 次'),
            (label: '首次学习', value: '${summary.firstLearnedSenses} 个词义'),
            (label: '复习评分', value: '${summary.reviewCount} 次'),
            (
              label: 'Good+Easy 成功率',
              value: rate == null ? '—' : '${(rate * 100).round()}%',
            ),
          ],
        ),
        if (summary.ratingCount == 0) ...[
          const SizedBox(height: 10),
          Text(
            '本轮还没有评分记录，成功率显示为 —。',
            key: const ValueKey('session-no-ratings'),
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: tokens.inkSecondary),
          ),
        ],
        const SizedBox(height: 12),
        Text(
          '同一词义本轮多次学习按评分次数统计；已撤销的评分不计入。',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: tokens.inkSecondary),
        ),
      ],
    );
  }

  Widget _summaryCard(BuildContext context) => JournalSurface(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '本轮小结'),
        const SizedBox(height: 12),
        _summaryContent(context),
      ],
    ),
  );

  KeyEventResult _handleKey(KeyEvent event, bool clockMovedBack) {
    if (event is KeyRepeatEvent) return KeyEventResult.ignored;
    if (event is! KeyDownEvent ||
        _loading ||
        _busy ||
        _summaryOpening ||
        _exitDialogOpen ||
        _allowExit ||
        clockMovedBack ||
        _error != null) {
      return KeyEventResult.ignored;
    }
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                null)) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    final commandPressed = keyboard.isControlPressed || keyboard.isMetaPressed;
    final disallowedCommandModifier =
        keyboard.isAltPressed || keyboard.isShiftPressed;
    if (commandPressed &&
        !disallowedCommandModifier &&
        key == LogicalKeyboardKey.keyZ) {
      if (_lastUndoEventId != null) {
        _undo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    if (_item == null) return KeyEventResult.ignored;
    if (_newWordStage == _NewWordStage.browse) {
      if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
        _advanceBrowse();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    if (!_revealed) {
      if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
        setState(() => _revealed = true);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    final rating = switch (key) {
      LogicalKeyboardKey.digit1 ||
      LogicalKeyboardKey.numpad1 => fsrs.Rating.again,
      LogicalKeyboardKey.digit2 ||
      LogicalKeyboardKey.numpad2 => fsrs.Rating.hard,
      LogicalKeyboardKey.digit3 ||
      LogicalKeyboardKey.numpad3 => fsrs.Rating.good,
      LogicalKeyboardKey.digit4 ||
      LogicalKeyboardKey.numpad4 => fsrs.Rating.easy,
      _ => null,
    };
    if (rating != null) {
      _rate(rating);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  bool get _needsNewWordExitConfirm =>
      !_allowExit &&
      _newWordStage != null &&
      _newWordGroup.isNotEmpty &&
      !_loadFailed;

  Future<void> _handleBack() async {
    if (_exitDialogOpen || _allowExit) return;
    if (!_needsNewWordExitConfirm) {
      Navigator.of(context).maybePop();
      return;
    }
    if (_busy || _summaryOpening) return;
    _exitDialogOpen = true;
    unawaited(widget.dependencies.pronunciation.stop());
    try {
      final response = DialogResponse<bool>();
      final message = _newWordScored.isEmpty
          ? '这一组新词还没有测试，离开不会记为已学。'
          : '本组已评分的 ${_newWordScored.length} 个词义已保存；尚未测试的浏览不会记为已学。';
      final leave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          constraints: const BoxConstraints(maxWidth: 460),
          title: const Text('结束本组新词学习？'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => response.close(dialogContext, false),
              child: const Text('继续学习'),
            ),
            FilledButton(
              onPressed: () => response.close(dialogContext, true),
              child: const Text('退出并保留已评'),
            ),
          ],
        ),
      );
      if (leave == true && mounted) {
        if (_exitScheduled) return;
        _exitScheduled = true;
        _generation++;
        setState(() => _allowExit = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_routePopped) Navigator.of(context).maybePop();
        });
      }
    } finally {
      _exitDialogOpen = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_busy) _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _subscription?.cancel();
    unawaited(widget.dependencies.pronunciation.stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final item = _item;
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 760;
    final now = widget.dependencies.nowUtc();
    final card = item?.card(widget.dependencies.engine, now);
    final clockMovedBack = card?.lastReview?.isAfter(now) ?? false;
    final predictions = card == null || clockMovedBack
        ? <fsrs.Rating, Duration>{}
        : widget.dependencies.engine.predict(card, now);
    final ratingCount = _sessionSummary?.ratingCount ?? _completedCount;
    final waitingCount = _status?.items.length ?? 0;
    final browsing = _newWordStage == _NewWordStage.browse;
    final testingNewWords = _newWordStage == _NewWordStage.test;
    final showDefinition = browsing || _revealed;
    final newWordProgress = browsing
        ? '新词先看 ${_newWordBrowseIndex + 1} / ${_newWordGroup.length}'
        : testingNewWords
        ? '新词测试 ${_newWordTestIndex + 1} / ${_newWordGroup.length}'
        : null;
    final browseButtonLabel = _newWordBrowseIndex + 1 < _newWordGroup.length
        ? '下一个'
        : '浏览完成，开始测试';

    final ratings = [
      (
        rating: fsrs.Rating.again,
        label: 'Again · 忘记',
        tone: tokens.again,
        shortcut: '1',
      ),
      (
        rating: fsrs.Rating.hard,
        label: 'Hard · 困难',
        tone: tokens.hard,
        shortcut: '2',
      ),
      (
        rating: fsrs.Rating.good,
        label: 'Good · 记得',
        tone: tokens.good,
        shortcut: '3',
      ),
      (
        rating: fsrs.Rating.easy,
        label: 'Easy · 轻松',
        tone: tokens.easy,
        shortcut: '4',
      ),
    ];

    return PopScope(
      canPop: !_needsNewWordExitConfirm,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _routePopped = true;
          return;
        }
        _handleBack();
      },
      child: Focus(
        autofocus: true,
        onKeyEvent: (_, event) => _handleKey(event, clockMovedBack),
        child: Scaffold(
          appBar: AppBar(
            leading: journalBackButton(context),
            title: const Text('词义回忆'),
            actions: [
              IconButton(
                tooltip: '本轮小结',
                onPressed:
                    _loading ||
                        _busy ||
                        _summaryOpening ||
                        _exitDialogOpen ||
                        _allowExit
                    ? null
                    : _openSummary,
                icon: const JournalIcon(Icons.insights_outlined, size: 21),
              ),
            ],
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
                      if (!_loading && !_loadFailed) ...[
                        Text(
                          '本轮已评 $ratingCount 次 · 当前待学 $waitingCount',
                          style: JournalTokens.tabular(
                            Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: tokens.inkSecondary),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(64),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_loadFailed)
                        MessagePanel(
                          icon: Icons.error_outline,
                          title: '暂时无法读取学习队列',
                          message: '$_error',
                          action: OutlinedButton(
                            onPressed: _load,
                            child: const Text('刷新学习队列'),
                          ),
                        )
                      else if (clockMovedBack)
                        MessagePanel(
                          icon: Icons.error_outline,
                          title: '请检查系统时间',
                          message: '当前时间早于上次学习。校准时间后刷新，即可继续复习。',
                          action: OutlinedButton(
                            onPressed: _load,
                            child: const Text('刷新学习队列'),
                          ),
                        )
                      else if (item == null)
                        _buildEmptyQueue(context, now)
                      else ...[
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: JournalSurface(
                            key: ValueKey(
                              '${item.sense.id}|${item.word.spelling}|${item.sense.definition.hashCode}|${item.memory?.due ?? 'new'}',
                            ),
                            variant: JournalSurfaceVariant.elevated,
                            padding: EdgeInsets.symmetric(
                              horizontal: width < 600 ? 22 : 34,
                              vertical: width < 600 ? 28 : 36,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Center(
                                  child: StatusBadge(
                                    key: browsing
                                        ? const ValueKey(
                                            'new-word-browse-progress',
                                          )
                                        : testingNewWords
                                        ? const ValueKey(
                                            'new-word-test-progress',
                                          )
                                        : null,
                                    label:
                                        newWordProgress ??
                                        (item.memory == null ? '新词义' : '复习'),
                                    tone: browsing
                                        ? StatusBadgeTone.newWord
                                        : testingNewWords
                                        ? StatusBadgeTone.accent
                                        : item.memory == null
                                        ? StatusBadgeTone.accent
                                        : StatusBadgeTone.review,
                                  ),
                                ),
                                const SizedBox(height: 22),
                                Text(
                                  item.word.spelling,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displayMedium
                                      ?.copyWith(
                                        fontSize: wide ? 52 : 42,
                                        height: 1.12,
                                      ),
                                ),
                                if (item.sense.phonetics != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    item.sense.phonetics!,
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: tokens.inkMuted),
                                  ),
                                ],
                                const SizedBox(height: 10),
                                Center(
                                  child: WordPronunciationButton(
                                    dependencies: widget.dependencies,
                                    word: item.word.spelling,
                                    enabled:
                                        !_busy &&
                                        !_summaryOpening &&
                                        !_exitDialogOpen &&
                                        !_allowExit,
                                  ),
                                ),
                                if (browsing) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    '先完整浏览这一组新词，全部看完后再回忆测试。',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: tokens.inkSecondary),
                                  ),
                                ],
                                AnimatedSize(
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOutCubic,
                                  alignment: Alignment.topCenter,
                                  child: !showDefinition
                                      ? Padding(
                                          padding: const EdgeInsets.only(
                                            top: 22,
                                          ),
                                          child: Text(
                                            '先想一想它的意思，再揭晓答案。',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  color: tokens.inkMuted,
                                                ),
                                          ),
                                        )
                                      : Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            const SizedBox(height: 26),
                                            Divider(color: tokens.border),
                                            const SizedBox(height: 24),
                                            Text(
                                              item.sense.definition,
                                              textAlign: TextAlign.center,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .headlineSmall,
                                            ),
                                            const SizedBox(height: 18),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 14,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: tokens.surfaceMuted,
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                              child: Text(
                                                item.sense.example.isEmpty
                                                    ? '这份词库没有提供例句。'
                                                    : item.sense.example,
                                                textAlign: TextAlign.center,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      color:
                                                          tokens.inkSecondary,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        if (browsing)
                          Center(
                            child: FilledButton(
                              key: const ValueKey('new-word-browse-next'),
                              onPressed:
                                  _busy ||
                                      _summaryOpening ||
                                      _exitDialogOpen ||
                                      _allowExit
                                  ? null
                                  : _advanceBrowse,
                              child: wide
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(browseButtonLabel),
                                        const SizedBox(width: 10),
                                        KeyHintBadge(
                                          'Space',
                                          foreground: tokens.primary,
                                          border: tokens.onPrimary.withValues(
                                            alpha: .3,
                                          ),
                                        ),
                                      ],
                                    )
                                  : Text(
                                      browseButtonLabel,
                                      textAlign: TextAlign.center,
                                    ),
                            ),
                          )
                        else if (!_revealed)
                          Center(
                            child: FilledButton(
                              onPressed:
                                  _summaryOpening ||
                                      _exitDialogOpen ||
                                      _allowExit
                                  ? null
                                  : () => setState(() => _revealed = true),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('回忆 · 揭晓释义'),
                                  if (wide) ...[
                                    const SizedBox(width: 10),
                                    KeyHintBadge(
                                      'Space',
                                      foreground: tokens.primary,
                                      border: tokens.onPrimary.withValues(
                                        alpha: .3,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        else
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final fourInRow = constraints.maxWidth >= 540;
                              final cellWidth = fourInRow
                                  ? (constraints.maxWidth - 30) / 4
                                  : (constraints.maxWidth - 10) / 2;
                              return Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: ratings
                                    .map(
                                      (entry) => SizedBox(
                                        width: cellWidth,
                                        child: _RatingButton(
                                          label: entry.label,
                                          interval: intervalLabel(
                                            predictions[entry.rating]!,
                                          ),
                                          tone: entry.tone,
                                          shortcut: wide
                                              ? entry.shortcut
                                              : null,
                                          highlighted:
                                              entry.rating == fsrs.Rating.good,
                                          onPressed:
                                              _busy ||
                                                  _summaryOpening ||
                                                  _exitDialogOpen ||
                                                  _allowExit
                                              ? null
                                              : () => _rate(entry.rating),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                      ],
                      if (_busy)
                        const Padding(
                          padding: EdgeInsets.only(top: 18),
                          child: LinearProgressIndicator(),
                        ),
                      if (_error != null && !_loadFailed) ...[
                        const SizedBox(height: 16),
                        JournalSurface(
                          color: tokens.again.background,
                          borderColor: tokens.again.border,
                          radius: JournalTokens.radiusSm,
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: tokens.again.foreground,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextButton(
                                onPressed: _busy ? null : _load,
                                child: const Text('刷新学习队列'),
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (!_loading && !_loadFailed) ...[
                        if (_lastUndoEventId != null) ...[
                          const SizedBox(height: 14),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              key: const ValueKey('undo-last-score'),
                              onPressed:
                                  _busy ||
                                      _summaryOpening ||
                                      _exitDialogOpen ||
                                      _allowExit
                                  ? null
                                  : _undo,
                              icon: const JournalIcon(
                                Icons.arrow_back,
                                size: 17,
                              ),
                              label: const Text('撤销上一评分'),
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Text(
                          browsing
                              ? '键盘：Space / Enter 下一个新词 · Ctrl / Cmd + Z 撤销'
                              : '键盘：Space / Enter 揭晓 · 1–4 评分 · Ctrl / Cmd + Z 撤销',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: tokens.inkMuted),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyQueue(BuildContext context, DateTime now) {
    final status = _status;
    if (status == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MessagePanel(
            title: '当前没有可学词义',
            message: '到期或跨日后会自动更新。',
            action: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('返回'),
            ),
          ),
          const SizedBox(height: 14),
          _summaryCard(context),
        ],
      );
    }
    final messages = <String>[];
    if (status.dailyGoal == 0) {
      messages.add('每日新词目标为 0，当前只安排复习。');
    } else if (status.quotaExhausted) {
      messages.add('今天的新词额度已用完（${status.learnedToday} / ${status.dailyGoal}）。');
    }
    if (status.unlearnedCount > 0) {
      messages.add(
        '${status.scopeLabel}仍有 ${status.unlearnedCount} 个未学词义。'
        '${status.dailyGoal == 0 ? '可在设置中调整目标后继续。' : '明天会按每日额度继续。'}',
      );
    } else {
      messages.add('${status.scopeLabel}暂无未学词义。');
    }
    final due = status.nextDue;
    if (due != null) {
      messages.add(
        '下次复习：${localDateTimeLabel(due)}'
        '（${intervalLabel(due.difference(now))}后）。',
      );
    } else {
      messages.add('当前也没有未来的复习安排。');
    }
    final onlyReview = status.dailyGoal == 0;
    final quotaExhausted = status.quotaExhausted && !onlyReview;
    final title = onlyReview
        ? '今天只安排复习'
        : quotaExhausted
        ? '今天的新词额度已用完'
        : '当前没有可学词义';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MessagePanel(
          icon: quotaExhausted ? Icons.hourglass_empty : Icons.event_available,
          title: title,
          message: messages.join('\n\n'),
          action: Wrap(
            spacing: 10,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton(onPressed: _load, child: const Text('刷新学习队列')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _summaryCard(context),
      ],
    );
  }
}

class _RatingButton extends StatelessWidget {
  const _RatingButton({
    required this.label,
    required this.interval,
    required this.tone,
    required this.highlighted,
    this.shortcut,
    this.onPressed,
  });

  final String label;
  final String interval;
  final RatingTone tone;
  final bool highlighted;
  final String? shortcut;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    style: OutlinedButton.styleFrom(
      backgroundColor: tone.background,
      foregroundColor: tone.foreground,
      side: BorderSide(color: tone.border, width: highlighted ? 1.6 : 1.0),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    onPressed: onPressed,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(color: tone.foreground, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                interval,
                style: JournalTokens.tabular(
                  Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tone.foreground.withValues(alpha: .88),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            if (shortcut != null) ...[
              const SizedBox(width: 6),
              KeyHintBadge(
                shortcut!,
                foreground: tone.foreground,
                border: tone.border,
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
