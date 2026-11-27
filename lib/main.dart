import 'package:drift_flutter/drift_flutter.dart';
import 'package:material_ui/material_ui.dart';

import 'app.dart';
import 'data/app_database.dart';
import 'ui/journal_style.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppDependencies? dependencies;
  try {
    dependencies = AppDependencies(
      AppDatabase(driftDatabase(name: 'lexi_loop')),
    );
    await dependencies.initialize();
    runApp(LexiLoopApp(dependencies: dependencies));
  } catch (error) {
    await dependencies?.dispose();
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const JournalIcon(Icons.error_outline, size: 48),
                    const SizedBox(height: 24),
                    const Text(
                      'Lexi Loop 暂时无法启动',
                      style: TextStyle(fontSize: 24),
                    ),
                    const SizedBox(height: 12),
                    Text('本地数据库初始化失败：$error'),
                    const SizedBox(height: 16),
                    const Text('请检查应用的数据目录权限，然后重新启动。'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
