# Lexi Loop 项目提示词（用于在另一台电脑上由 AI 实现完整项目）

> 用法：把「提示词正文」整段发给新电脑上的 AI 编码助手即可。它不依赖任何本机路径，包含复现本项目所需的全部设计约束。

---

## 提示词正文

```text
你是一位资深 Flutter / Dart 工程师。请按下面的规格，从零实现一个名为 Lexi Loop（包名 lexi_loop）的离线优先跨平台背单词应用，支持 Windows、macOS、Android、iOS 四端。实现完成后必须自验：flutter analyze 0 问题、flutter test 全部通过，并如实报告未能在本机实测的构建边界。全程用中文交流，按任务清单推进。

# 一、产品定位与硬性边界
- 离线优先：数据全部存本地 SQLite，无任何账号、鉴权、云同步、远程 AI、网络请求。
- 不含发音播放 / TTS；UI 不得出现无效的播放按钮。
- 词库只用应用内置的 24 个自编英语示例词条（每个词可含多个词义、例句），禁止引入商业词典、第三方录音或授权不明的词库资源。
- 不做多用户，内部以固定单用户（user_id 常量）建模，为将来多用户留数据模型余量。
- 当前训练方式只有一种：recognition（词义回忆）；另有独立的拼写练习模式，它只在内存统计本轮对错，不创建记忆状态、不写复习记录、不参与调度。

# 二、技术栈（版本锁定，写入 pubspec）
- Flutter + Dart，SDK 约束 ^3.14.0。
- 依赖：
  - material_ui ^1.1.0（UI 组件与主题）
  - drift ^2.35.4 + drift_flutter ^0.3.1 + build_runner + drift_dev（本地持久化）
  - fsrs 2.0.1（FSRS-6 间隔复习算法，MIT）
  - file_picker ^13.4.0（四端原生文件选择器，用于备份导出/导入）
  - uuid ^4.6.0
- 开发依赖：flutter_test、flutter_lints ^6.0.0。
- 生成 Drift 代码：dart run build_runner build；app_database.g.dart 不手工维护。
- 四端平台工程都要生成（flutter create 带 platforms 参数：windows,macos,android,ios）。
- macOS 沙盒：在 Debug/Release entitlements 中声明 com.apple.security.files.user-selected.read-write。
- 数据库文件：平台应用文档目录下 lexi_loop.sqlite。

# 三、功能需求
1. 今日任务页（应用主页）：
   - 展示：待复习数（到期卡片）、今日新词目标与完成数、词书整体进度（已学/总数）、连续学习天数、近期回忆成功率。
   - 进入学习流；新词与复习混合成今日队列。
2. 学习流（词义回忆）：
   - 卡片先显示单词，用户点击「回忆」后才揭晓中文释义；
   - 揭晓后显示 Again / Hard / Good / Easy 四档评分按钮，并显示各档对应的预计下次间隔；
   - 评分后由 FSRS 调度下一次复习时间；
   - 队列实时刷新：评分后若仍有到期卡继续；无到期卡时显示完成态。
3. 词书页：词书列表、词条浏览、搜索、点击进词条详情。
4. 词条详情页：单词、词义（多个）、例句、学习状态（当前记忆阶段/下次复习时间），可发起学习或查看该词义的记忆状态。
5. 统计页：今日完成数、累计复习次数、成功率、连续学习天数、最近 7 天活动图表。
6. 设置页：每日新词目标调整；备份导出（选文件保存 JSON）与恢复（选文件导入 JSON）。
7. 拼写练习页：从词书抽词，用户拼写、判对错，轮内统计正确率；不写库、不建调度。
8. 刷新策略：启动时刷新、到点（到期）自动刷新、跨日刷新、切回今日页时刷新、应用从后台恢复前台时刷新。
9. 导航与布局：桌面端自适应 NavigationRail，移动端 NavigationBar；窄屏（约 390 宽、1.5x 字号）与宽屏（1280 宽、1.0 字号）都要通过 widget 测试不破版。

# 四、FSRS 调度规格（必须精确实现）
- 使用 fsrs 2.0.1 包（其 2.0.0 起实现 FSRS-6，21 个默认模型参数）。
- 固定配置：
  - 目标保持率 0.90；
  - 新词学习步骤：1 分钟、10 分钟；
  - 重学步骤：10 分钟；
  - 最大间隔：36500 天；
  - 随机扰动（fuzzing）关闭，保证同一输入可复现；
  - 调度版本标识字符串：fsrs-6/2.0.1/retention-0.90/fuzz-off。
- 时间归一化：所有评分时间统一为 UTC 毫秒（DateTime UTC 毫秒精度），再交给调度器并落库；数据库存毫秒字段，避免微秒精度在快照与 DB 间不一致。写一个 core/clock.dart 提供 systemUtcNow()，UI 与业务统一注入 nowUtc 以便测试。
- 每条 memory_state 记录保存 schedulerConfigJson 快照（完整 21 参数 JSON），恢复备份时要求与当前参数精确一致，未知算法/参数直接拒绝而非静默迁移。
- 调度引擎封装（domain/fsrs_engine.dart）：暴露 schedulerVersion、configurationJson、学习步骤、四档评分、给定卡片预测下一间隔（供 UI 显示预计间隔）。

# 五、数据模型（Drift / SQLite 表）
内容与进度分两组表，单数据库文件：
内容组：
- words：词（text 唯一）。
- word_senses：词义（word_id、definition、example、可选 phonetics 文本——注意不存音频）。同一词义可被多词书收录，记忆状态按「用户 × 词义 × 训练方式」共享。
- wordbooks：词书（内置 + 用户自建）。
- wordbook_entries：词书 × 词义 关联。
用户组：
- memory_states：主键 (user_id, word_sense_id, training_mode)。字段含 fsrs 卡片状态 state、学习步骤序号 step、stability、difficulty、due（UTC 毫秒）、lastReview（UTC 毫秒）、schedulerVersion、schedulerConfigJson。
- review_events：每次评分一行。字段含事件 ID（独立 UUIDv7 语义，用 uuid 包生成）、真实 UTC 评分时间（毫秒）、评分等级（again/hard/good/easy）、调度版本、评分前卡片快照（JSON）、评分后卡片快照（JSON）、可选作答耗时。同一事件 ID 幂等：重试返回已有结果，不重复推进状态。
- app_settings：键值表（每日新词目标、目标保持率等），启动时 seed 默认值。
关键行为：
- 每次评分在单个事务内写 review_events + 更新 memory_states；任何一步失败整体回滚。
- 队列查询：due <= now 的到期卡 + 新词（无 memory_state 且词书内未学过），新词按每日目标限量。
- 统计：成功率 = good+easy 占全部评分比；连续学习天数按本地日历日（core/local_calendar.dart，用户时区）计算，跨日刷新逻辑要处理「今天已过、明天 0 点」边界。
启动 seed（ensureSeeded）：写入 24 个示例词条（词、词义、例句、默认词书）与默认设置，幂等可重入；记录当前 schedulerVersion 与 configJson 快照。

# 六、备份规格
- 顶层标识 lexi_loop_backup，schemaVersion = 1，含导出时间；内容包括全部词书、词条词义、学习状态、评分记录、设置。
- 导出：JSON 文件，经 file_picker 原生保存。
- 恢复前校验（全部通过才动库）：
  1. 解析 JSON，校验顶层格式、版本、导出时间；
  2. 各表反序列化，检查主键、外键、唯一键、字段类型；
  3. 检查用户 ID、训练方式、调度版本是否受支持；
  4. 完整 21 项 FSRS 参数与当前一致；memory_state 的 state/step/stability/difficulty/due/lastReview 语义约束合法；
  5. 解析每条 review_event 的前后卡片快照，检查卡片连续性、时间单调，且最新卡片与当前 memory_state 一致；
  6. 全部通过后开事务清空并重写所有表；失败即回滚，原有进度不受影响。
- 校验或写入失败时给用户可读错误，禁止部分恢复。

# 七、工程结构（必须一致）
lib/
  main.dart                  SQLite 初始化、依赖装配、启动失败兜底页
  app.dart                   AppDependencies、主题、本地化（中文文案）
  core/clock.dart            UTC 毫秒时钟 + systemUtcNow
  core/ids.dart              UUIDv7 语义事件 ID 生成
  core/local_calendar.dart   本地日历日计算（连续天数、跨日）
  data/app_database.dart     Drift schema + ensureSeeded（.g.dart 由 build_runner 生成）
  data/seed_catalog.dart     24 条示例词书数据
  data/study_repository.dart 队列、事务评分（幂等）、统计
  data/backup_codec.dart     导出 / 语义校验 / 事务恢复
  domain/fsrs_engine.dart    FSRS-6 封装与配置快照
  ui/app_shell.dart          自适应导航壳
  ui/common.dart             共用小组件
  ui/today_page.dart        今日任务
  ui/study_page.dart        学习流
  ui/library_page.dart      词书浏览
  ui/word_detail_page.dart  词条详情
  ui/stats_page.dart        统计
  ui/settings_page.dart     设置 + 备份
  ui/spelling_practice_page.dart 拼写练习
test/
  fsrs_engine_test.dart     配置快照、学习步骤、FSRS 黄金向量
  study_repository_test.dart 队列、事务、幂等、陈旧候选、统计、持久化
  backup_codec_test.dart    导出/恢复往返、失败回滚、语义校验、微秒精度
  study_flow_widget_test.dart 学习交互、动态刷新、移动布局（390×1.5x）与宽屏（1280×1.0）、拼写统计

# 八、验收标准（完成 = 全部满足）
1. flutter analyze 0 问题。
2. flutter test 全绿，且测试是「会咬人的」：仓库测试覆盖 FSRS 黄金向量、评分幂等、事务回滚、备份语义校验失败拒绝、跨日刷新、窄屏不破版；新增测试必须在未实现功能上先红再绿。
3. 测试数据库统一用 NativeDatabase.memory() 独立实例，禁止共享全局库。
4. 提交说明与代码注释一致：注释只描述真实实现的行为，禁止写未实现的承诺。
5. 如实报告构建边界：哪一端在什么工具链下实测跑过、哪一端只过了静态检查，不得宣称未实测的安装包已验证。
6. 交付 README（中文）：功能清单、技术栈与许可表、FSRS 配置、数据模型、备份格式、开发命令、验证结果与构建边界、当前边界（不做的事）。

# 九、开发流程纪律
- 开工先输出完整任务清单（依赖安装 → 生成平台工程 → 数据层 → 调度引擎 → 仓储 → 备份 → 各页面 → 测试 → 验证），每完成一项立即勾选。
- TDD 顺序（逻辑层）：先写失败测试并确认真红（红在断言上而非语法错），再最小实现变绿，然后重构。纯 UI 样式调整可豁免 TDD 但仍需 widget 测试兜底。
- 每次改完跑 flutter analyze + flutter test 才算一步完成；不能跑就明说哪步没验，禁止假装绿灯。
- 最小改动优先：不引入规格外的依赖、不做规格外的功能（尤其不做账号/云同步/发音）。
- 遇到规格没写清的细节，列出选项问我，不要擅自扩大范围。
```

---

## 附：本机现状对照（仅供你核对新实现是否一致，不需要喂给 AI）
- 本机项目位于 E:\code\lexi-loop，验证记录：flutter analyze 0 问题，32 项测试全过；
  另做过 3 项备份探针、4 项 UI 探针（390/1280 宽 × 1.0/1.5 字号）全过。
- 原生安装包在本机（Windows + 无 Android SDK + 无 Mac）未实测，与提示词第九节第 5 条一致。
- 若新电脑产出与本机实现有出入，可对照本机 lib/、test/ 目录逐文件 diff。
