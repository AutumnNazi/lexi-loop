import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../app.dart';
import 'common.dart';
import 'journal_style.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.dependencies});
  final AppDependencies dependencies;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _goal = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    _readGoal();
  }

  Future<void> _readGoal() async {
    try {
      final goal = await widget.dependencies.repository.dailyGoal();
      if (mounted) setState(() => _goal.text = '$goal');
    } catch (error) {
      if (mounted) setState(() => _message = '$error');
    }
  }

  @override
  void dispose() {
    _goal.dispose();
    super.dispose();
  }

  Future<void> _perform(Future<String?> Function() task) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final message = await task();
      if (mounted) setState(() => _message = message);
    } catch (error) {
      if (mounted) setState(() => _message = '操作未完成：$error');
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
    final source = utf8.decode(bytes);
    if (!mounted) return null;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复备份会替换当前进度'),
        content: Text(
          '将读取「${picked.name}」。校验通过后替换本机的词书、设置和学习记录；校验或写入失败会保留当前数据。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('恢复备份'),
          ),
        ],
      ),
    );
    if (confirmed != true) return null;
    await widget.dependencies.backup.restore(source);
    widget.dependencies.repository.refresh();
    await _readGoal();
    return '备份已恢复，学习进度已刷新。';
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '按照自己的节奏',
    subtitle: '离线学习，数据由你保管。',
    children: [
      JournalPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('每日新词目标', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('以新词义为单位，范围 0–100。设为 0 时只复习已学内容。'),
            const SizedBox(height: 16),
            TextField(
              controller: _goal,
              enabled: !_busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '每天学习的新词义数量'),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                onPressed: _busy
                    ? null
                    : () => _perform(() async {
                        final value = int.tryParse(_goal.text.trim());
                        if (value == null) {
                          throw const FormatException('请输入 0 到 100 之间的整数。');
                        }
                        await widget.dependencies.repository.setDailyGoal(
                          value,
                        );
                        return '每日目标已保存。';
                      }),
                child: const Text('保存目标'),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 24),
      JournalPanel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('备份与恢复', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('备份包含词书、词义、全部学习记录和设置。建议在换设备前导出。'),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _perform(_export),
                  icon: const JournalIcon(Icons.file_download_outlined),
                  label: const Text('导出备份'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _perform(_restore),
                  icon: const JournalIcon(Icons.file_upload_outlined),
                  label: const Text('恢复备份'),
                ),
              ],
            ),
          ],
        ),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 20),
          child: LinearProgressIndicator(),
        ),
      if (_message != null)
        Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Semantics(liveRegion: true, child: Text(_message!)),
        ),
      const SizedBox(height: 36),
      Text('关于 Lexi Loop', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      const Text(
        '复习计划使用 FSRS-6，目标保持率为 90%。记忆曲线呈现遗忘与复习强化的估计趋势。'
        '\n\n当前仅包含 24 个原创示例词条。无账号、云同步、网络请求或发音功能。',
      ),
    ],
  );
}
