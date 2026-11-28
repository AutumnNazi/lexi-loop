import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import '../core/theme_settings.dart';
import '../data/backup_codec.dart';
import 'common.dart';
import 'journal_style.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.dependencies,
    this.refreshListenable,
  });

  final AppDependencies dependencies;
  final Listenable? refreshListenable;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _goal = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;
  bool _goalDirty = false;
  int _goalInputRevision = 0;
  int _goalLoadRevision = 0;

  static const _goalPresets = [0, 10, 20, 30];

  @override
  void initState() {
    super.initState();
    widget.refreshListenable?.addListener(_onRefreshSignal);
    _readGoal();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshListenable != widget.refreshListenable) {
      oldWidget.refreshListenable?.removeListener(_onRefreshSignal);
      widget.refreshListenable?.addListener(_onRefreshSignal);
    }
  }

  void _onRefreshSignal() {
    if (!mounted || _busy) return;
    _readGoal();
  }

  Future<void> _readGoal({bool force = false}) async {
    final loadRevision = ++_goalLoadRevision;
    final inputRevision = _goalInputRevision;
    try {
      final goal = await widget.dependencies.repository.dailyGoal();
      if (!mounted || loadRevision != _goalLoadRevision) return;
      final canApply =
          force || (!_goalDirty && inputRevision == _goalInputRevision);
      if (canApply) {
        setState(() {
          _goal.text = '$goal';
          _goalDirty = false;
        });
      }
    } catch (error) {
      if (mounted && loadRevision == _goalLoadRevision) {
        setState(() {
          _message = '$error';
          _messageIsError = true;
        });
      }
    }
  }

  @override
  void dispose() {
    widget.refreshListenable?.removeListener(_onRefreshSignal);
    _goal.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<String?> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
      _messageIsError = false;
    });
    try {
      final message = await task();
      if (mounted) {
        setState(() {
          _message = message;
          _messageIsError = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          final detail = error is FormatException ? error.message : '$error';
          _message = '操作未完成：$detail';
          _messageIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _export() async {
    final source = await widget.dependencies.backup.export();
    final date = widget.dependencies.nowUtc().toIso8601String().substring(
      0,
      10,
    );
    final path = await FilePicker.saveFile(
      dialogTitle: '保存学习备份',
      fileName: 'lexi-loop-$date.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(utf8.encode(source)),
    );
    return path == null ? null : '备份已保存。';
  }

  Future<String?> _restore() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择学习备份',
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null) return null;
    final bytes = await picked.readAsBytes();
    final String source;
    try {
      source = utf8.decode(bytes);
    } on FormatException {
      throw const FormatException('备份文件不是有效的 UTF-8 文本。');
    }
    if (!mounted) return null;
    final BackupPreview preview;
    try {
      preview = await widget.dependencies.backup.preview(source);
    } on FormatException catch (error) {
      throw FormatException('备份校验失败：${error.message}');
    }
    if (!mounted) return null;
    final response = DialogResponse<bool>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        title: const Text('恢复备份会替换当前数据'),
        content: SingleChildScrollView(
          key: const ValueKey('backup-preview-scroll'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('文件：${picked.name}'),
              const SizedBox(height: 12),
              const Text('备份校验通过。'),
              const SizedBox(height: 8),
              Text('备份时间：${localDateTimeWithYearLabel(preview.exportedAt)}'),
              Text('词书：${preview.wordbookCount} 本'),
              Text('词义：${preview.senseCount} 个'),
              Text('已学词义：${preview.learnedSenseCount} 个'),
              Text('评分记录：${preview.reviewEventCount} 条'),
              Text('每日新词目标：${preview.dailyGoal} 个'),
              const SizedBox(height: 12),
              const Text(
                '恢复会用备份替换本机的词书、设置和学习记录，不会与现有数据合并。'
                '离线换机时，请先在当前设备导出，再到另一台设备恢复后继续；'
                '两台设备各自新增的进度不能合并。',
              ),
              const SizedBox(height: 8),
              const Text('备份文件只在本机读取，不会上传。恢复后，此前页面上的撤销入口会失效。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => response.close(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => response.close(context, true),
            child: const Text('确认恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    await widget.dependencies.backup.restore(source);
    await widget.dependencies.reloadTheme();
    widget.dependencies.repository.refresh();
    await _readGoal(force: true);
    return '备份已恢复，学习进度已刷新。';
  }

  Future<void> _setTheme(ThemeSettings settings) => _perform(() async {
    await widget.dependencies.theme.save(settings);
    return '主题设置已保存。';
  });

  Future<void> _saveGoal() => _perform(() async {
    final value = int.tryParse(_goal.text.trim());
    if (value == null) {
      throw const FormatException('请输入 0 到 100 之间的整数。');
    }
    await widget.dependencies.repository.setDailyGoal(value);
    _goalLoadRevision++;
    _goalDirty = false;
    return '每日目标已保存。';
  });

  @override
  Widget build(BuildContext context) {
    final tokens = JournalTokens.of(context);
    final currentGoal = int.tryParse(_goal.text.trim());
    final themeSettings = widget.dependencies.theme.settings;

    return PageFrame(
      title: '按照自己的节奏',
      subtitle: '离线学习，数据由你保管。',
      children: [
        JournalSurface(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: '外观主题'),
              const SizedBox(height: 8),
              Text(
                '四套配色都提供完整的浅色与深色表面；切换后立即生效并随本机设置保存。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.inkSecondary),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 720 ? 4 : 2;
                  final cardWidth =
                      (constraints.maxWidth - 12 * (columns - 1)) / columns;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: JournalThemeId.values.map((theme) {
                      final palette = JournalTokens.forTheme(
                        theme,
                        Brightness.light,
                      );
                      final selected = themeSettings.themeId == theme;
                      return SizedBox(
                        width: cardWidth,
                        child: Semantics(
                          selected: selected,
                          button: true,
                          label: '主题 ${theme.label}',
                          child: Material(
                            color: selected
                                ? tokens.heroSurface
                                : tokens.surface,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              key: ValueKey('theme-card-${theme.storageValue}'),
                              onTap: _busy
                                  ? null
                                  : () => _setTheme(
                                      themeSettings.copyWith(themeId: theme),
                                    ),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: selected
                                        ? tokens.primary
                                        : tokens.border,
                                    width: selected ? 1.6 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        _ThemeSwatch(
                                          color: palette.canvas,
                                          border: tokens.border,
                                        ),
                                        _ThemeSwatch(
                                          color: palette.surface,
                                          border: tokens.border,
                                        ),
                                        _ThemeSwatch(
                                          color: palette.primary,
                                          border: tokens.border,
                                        ),
                                        _ThemeSwatch(
                                          color: palette.accent,
                                          border: tokens.border,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            theme.label,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        if (selected)
                                          JournalIcon(
                                            Icons.check_circle_outline,
                                            size: 17,
                                            color: tokens.primary,
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      theme.description,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: tokens.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 18),
              Text(
                '显示模式',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: AppThemeMode.values.map((mode) {
                  return ChoiceChip(
                    key: ValueKey('theme-mode-${mode.storageValue}'),
                    label: Text(mode.label),
                    selected: themeSettings.mode == mode,
                    onSelected: _busy
                        ? null
                        : (_) => _setTheme(themeSettings.copyWith(mode: mode)),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        JournalSurface(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: '每日新词目标'),
              const SizedBox(height: 8),
              Text(
                '以新词义为单位，范围 0–100。设为 0 时只复习已学内容。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.inkSecondary),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _goalPresets.map((preset) {
                  final label = preset == 0 ? '0 · 仅复习' : '$preset 个/天';
                  return ChoiceChip(
                    label: Text(label),
                    selected: currentGoal == preset,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _goal.text = '$preset';
                            _goalDirty = true;
                            _goalInputRevision++;
                          }),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _goal,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {
                  _goalDirty = true;
                  _goalInputRevision++;
                }),
                decoration: const InputDecoration(labelText: '每天学习的新词义数量'),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: _busy ? null : _saveGoal,
                  child: const Text('保存目标'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        JournalSurface(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: '备份与恢复'),
              const SizedBox(height: 8),
              Text(
                '备份包含词书、词义、全部学习记录和设置。离线换机时，先在当前设备导出，'
                '再在另一台设备恢复后继续；恢复是整份替换，不会合并两台设备各自新增的进度。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.inkSecondary),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _perform(_export),
                    icon: const JournalIcon(
                      Icons.file_download_outlined,
                      size: 18,
                    ),
                    label: const Text('导出备份'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _perform(_restore),
                    icon: const JournalIcon(
                      Icons.file_upload_outlined,
                      size: 18,
                    ),
                    label: const Text('恢复备份'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: LinearProgressIndicator(),
          ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Semantics(
              liveRegion: true,
              child: JournalSurface(
                color: _messageIsError
                    ? tokens.again.background
                    : tokens.good.background,
                borderColor: _messageIsError
                    ? tokens.again.border
                    : tokens.good.border,
                radius: JournalTokens.radiusSm,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    JournalIcon(
                      _messageIsError
                          ? Icons.error_outline
                          : Icons.check_circle_outline,
                      size: 18,
                      color: _messageIsError
                          ? tokens.again.foreground
                          : tokens.good.foreground,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _message!,
                        style: TextStyle(
                          color: _messageIsError
                              ? tokens.again.foreground
                              : tokens.good.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: 18),
        JournalSurface(
          variant: JournalSurfaceVariant.muted,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader(title: '关于 Lexi Loop'),
              const SizedBox(height: 10),
              Text(
                '复习计划使用 FSRS-6，目标保持率为 90%。记忆曲线呈现遗忘与复习强化的估计趋势。',
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: tokens.inkSecondary),
              ),
              const SizedBox(height: 10),
              Text(
                '包含 4 本离线考试词书及 24 个原创示例词条。词条释义和音标来自 MIT 许可的 ECDICT 数据，不提供例句；考试词表不代表官方年度大纲。无账号、云同步、网络请求或发音功能。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: tokens.inkMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.color, required this.border});
  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) => Container(
    width: 20,
    height: 20,
    decoration: BoxDecoration(
      color: color,
      shape: BoxShape.circle,
      border: Border.all(color: border),
    ),
  );
}
