# Lexi Loop

[![Dev release](https://github.com/AutumnNazi/lexi-loop/actions/workflows/dev-release.yml/badge.svg)](https://github.com/AutumnNazi/lexi-loop/actions/workflows/dev-release.yml)

界面采用墨绿与奶白的学习手账风格。应用图标、16 个页面图标和学习插画均由 magpie-image 生成；素材与提示词保存在 `assets/source/`，切图、透明背景处理和四端尺寸转换由 `scripts/generate_icons.py` 复现（需要 Pillow，仅供开发时处理图片）。

Lexi Loop 是一个离线优先的 Flutter 背词应用，围绕「先回忆，再揭晓，再评分」建立学习循环。复习日期由 FSRS-6 安排，记忆曲线展示遗忘与复习强化的估计趋势。项目已生成 Windows、macOS、Android、iOS 平台工程；各端实际验证范围见下文。

应用数据保存在本机 SQLite，当前内置「日常微光」词书与 24 个原创英语示例词条，每个示例词条包含一个词义和例句。需求来源为 `prompt.md`，本文以当前代码、锁定依赖和实际验证结果为准。

## 功能

| 功能 | 当前行为 |
| --- | --- |
| 今日任务 | 显示到期词义数、今日新词义目标与完成数、整体已学单词数、连续学习天数、近 7 天回忆成功率。 |
| 词义回忆 | 先展示单词，点击「回忆」揭晓释义，再用 Again / Hard / Good / Easy 评分；评分前展示各档预计间隔。 |
| 复习队列 | 优先处理 `due <= now` 的到期词义，再补充当日额度内的新词义；评分后刷新队列，无可学卡片时显示完成态。 |
| 词书与词条 | 按词书浏览，搜索英文单词或中文释义，查看例句、记忆阶段、下次复习时间与该词义的曲线。 |
| 自建词书 | 从现有词义中勾选内容，填写 1–40 字名称创建词书；同一词义跨词书共享进度。 |
| 统计 | 显示今日评分次数、累计评分次数、回忆成功率、连续学习天数及最近 7 天活动图。可选择已学词义查看曲线。 |
| 拼写练习 | 从所选词书随机抽取最多 10 个去重单词；忽略答案首尾空白和大小写，只在本轮统计对错。 |
| 设置与备份 | 每日新词义目标可设为 0–100，默认 10；设为 0 后只安排已学内容的复习。通过系统文件选择器导出或恢复 JSON。 |
| 自动刷新 | 启动、卡片到期、本地午夜、切换页面及应用回到前台时刷新；也可手动刷新。 |
| 自适应布局 | 宽度达到 760 时使用侧边 NavigationRail，否则使用底部 NavigationBar；支持中文界面与系统字号缩放。 |

学习单位是**词义**，记忆状态按「用户 × 词义 × 训练方式」唯一确定。今日新词目标按首次学习的词义计数；整体进度按去重单词计数，单词任一词义已学即计入已学单词。今日完成数和活动图统计的是评分次数，同一个词义当天多次评分会分别计数。

成功率 = `(Good 次数 + Easy 次数) / 全部评分次数`，Hard 不计为成功。连续学习天数按系统本地日历日计算；若今天尚未学习而昨天学过，连续天数仍保留到今天结束。

## 技术栈与许可

本次开发和验证使用 Flutter **3.50.1**、Dart **3.14.0**，`pubspec.yaml` 的 Dart SDK 约束为 `^3.14.0`。依赖实际版本以 `pubspec.lock` 为准。

| 组件 | 实际版本 | 用途 | 许可 |
| --- | --- | --- | --- |
| Flutter / Dart SDK | 3.50.1 / 3.14.0 | 四端应用与语言运行环境 | BSD-3-Clause |
| material_ui | 1.11.1 | UI 组件与主题 | BSD-3-Clause |
| drift | 2.35.4 | SQLite 数据模型、查询与事务 | MIT |
| drift_flutter | 0.3.1 | Flutter 平台数据库连接 | MIT |
| fsrs | 2.0.1 | FSRS-6 调度 | MIT |
| file_picker | 13.4.1 | 原生备份文件选择与保存 | MIT |
| uuid | 4.6.0 | UUIDv7 事件 ID | MIT |
| build_runner | 2.17.1 | 代码生成 | BSD-3-Clause |
| drift_dev | 2.35.3 | Drift 代码生成器 | MIT |
| flutter_lints | 6.0.0 | 静态检查规则 | BSD-3-Clause |
| flutter_test | 随 Flutter SDK | 单元与 Widget 测试 | BSD-3-Clause |

表中许可已按本机 SDK 与包缓存内的许可文件核对，仅列出直接依赖；传递依赖仍保留各自许可。**本项目自身尚未指定开源许可证**，上述依赖许可不等于项目许可。示例词条与例句为本项目原创内容，不包含商业词典或第三方录音资源。

## FSRS 调度与记忆曲线

调度封装位于 `lib/domain/fsrs_engine.dart`，实际复习日期由 `fsrs 2.0.1` 的调度器计算。

| 配置 | 固定值 |
| --- | --- |
| 算法 | FSRS-6 |
| 目标保持率 | 0.90 |
| 新词学习步骤 | 1 分钟、10 分钟 |
| 重学步骤 | 10 分钟 |
| 最大间隔 | 36500 天 |
| 随机扰动 | 关闭，保证相同输入可复现 |
| 版本标识 | `fsrs-6/2.0.1/retention-0.90/fuzz-off` |
| 训练方式 | `recognition` |
| 时间精度 | UTC 毫秒 |

使用包内固定的 21 个默认模型参数，按顺序为：

```text
[0.2172, 1.1771, 3.2602, 16.1507, 7.0114, 0.57, 2.0966,
 0.0069, 1.5261, 0.112, 1.0178, 1.849, 0.1133, 0.3127,
 2.2934, 0.2191, 3.0004, 0.7536, 0.3332, 0.1437, 0.2]
```

完整配置快照包含参数、目标保持率、学习与重学步骤、最大间隔和扰动开关，随每条记忆状态保存到 `schedulerConfigJson`。恢复时必须与当前配置精确匹配；JSON 对象键顺序可以不同，未知版本或不同参数会被拒绝。

评分时间经 `core/clock.dart` 统一归一化为 UTC 毫秒，再用于计算和落库；界面显示本地时间，日统计使用 `core/local_calendar.dart`。若系统时间倒退，学习页会提示检查系统时间。四档间隔预测不会修改原卡片。

界面中的「艾宾浩斯记忆曲线」用于说明遗忘与复习强化趋势，**数值来自 FSRS 连续时间模型估计，不是艾宾浩斯实验数据，也不是对用户记忆的实测结果**。图中展示该词义最近最多 6 次评分：

- 实线表示已发生学习阶段的模型估计，未来部分使用虚线。
- 另一条虚线表示从图中第一次评分开始、假设此后未再复习的参考趋势。
- 水平参考线为 90%，当前保持率也按模型估计显示。
- 曲线只负责展示；实际下次复习时间仍由原包的调度计算决定。

## 数据模型

原生平台数据库由 `drift_flutter` 放置在平台应用文档目录，文件名为 `lexi_loop.sqlite`，数据库 schema 版本为 **1**，外键检查已启用。内部固定用户为 `local-user`。

| 表 | 主要内容与约束 |
| --- | --- |
| `words` | 单词 ID 与唯一拼写。数据库列名为 `text`，Dart 和备份字段名为 `spelling`。 |
| `word_senses` | 词义 ID、关联单词、中文释义、例句、可空音标文本。数据结构支持一词多义。 |
| `wordbooks` | 词书 ID、名称、是否内置。 |
| `wordbook_entries` | 词书与词义的多对多关联，联合主键为词书 ID 与词义 ID。 |
| `memory_states` | 联合主键为用户、词义、训练方式；保存 FSRS 阶段、步骤、稳定度、难度、到期时间、上次评分时间、调度版本和完整配置快照。 |
| `review_events` | 每次评分一行，UUIDv7 为主键；保存用户、词义、训练方式、真实评分时间、评分档位、调度版本、前后卡片快照和可空作答耗时。 |
| `app_settings` | 键值设置，包括初始化版本、每日新词目标、保持率、调度版本与配置。 |

首次初始化在事务中写入示例词条、默认词书和设置；重复初始化不会增加重复内容。评分时，记忆状态更新和事件写入处于同一事务，任一步失败会整体回滚。同一事件 ID 的合法重试返回已有结果，不重复推进记忆状态；重复 ID 被用于不同评分、陈旧候选或未到期卡片会被拒绝。

## 备份格式与恢复

备份是 UTF-8 JSON，通过设置页的原生文件选择器保存。它包含全部内容、学习状态、评分历史与设置，属于完整数据快照。

| 顶层字段 | 格式 |
| --- | --- |
| `format` | 固定字符串 `lexi_loop_backup` |
| `schemaVersion` | 整数 `1` |
| `exportedAt` | UTC、毫秒精度的 ISO 8601 时间字符串 |
| `words` | 单词记录数组，拼写字段为 `spelling` |
| `wordSenses` | 词义记录数组 |
| `wordbooks` | 词书记录数组 |
| `wordbookEntries` | 词书与词义关联数组 |
| `memoryStates` | 记忆状态数组 |
| `reviewEvents` | 评分事件数组 |
| `appSettings` | 设置数组 |

记录字段使用 camelCase。卡片快照 `beforeJson`、`afterJson` 是 JSON 字符串，严格包含 `cardId`、`state`、`step`、`stability`、`difficulty`、`due`、`lastReview` 七个字段；其中时间保存为 UTC Unix 毫秒整数，未学习卡片允许 `lastReview` 为空。

恢复前会验证格式、版本、时间、字段类型、主键与唯一键、外键、支持的用户和训练方式、调度配置及卡片状态语义，并逐条重算评分结果，检查历史连续性、时间递增和最新快照与当前状态的一致性。文件可带 UTF-8 BOM；不兼容或损坏的备份会给出错误。

**恢复会替换本机全部数据，不合并进度。** 用户在界面确认后，程序先完成校验，再在单个事务中清空并重写七张表。校验失败不动数据库；写入中途失败会回滚，保留恢复前数据。完成后刷新界面与每日目标。

## 项目结构

```text
lib/
  main.dart                 数据库与依赖初始化、启动失败提示
  app.dart                  依赖装配、主题与中文界面配置
  core/                     UTC 毫秒时钟、UUIDv7、本地日历
  domain/fsrs_engine.dart   FSRS 配置、评分、预测、快照与曲线估计
  data/app_database.dart    Drift schema 与幂等初始化
  data/app_database.g.dart  自动生成的 Drift 代码
  data/seed_catalog.dart    24 个原创示例词条
  data/study_repository.dart 队列、事务评分、词书与统计
  data/backup_codec.dart    全量导出、校验与事务恢复
  ui/                       导航、学习、词书、统计、设置和记忆曲线
test/                       调度、仓储、备份、日历与 Widget 测试
windows/ macos/ android/ ios/ 平台工程
```

## 开发命令

在项目根目录执行。当前 Windows 工作区使用便携 SDK `.tools/flutter`，没有修改系统 PATH。该目录是本地工具，其他电脑需自行准备兼容 SDK；不要假定项目拷贝中一定包含 SDK。

Windows 首次运行前需要可用的桌面 C++ 工具链与插件符号链接支持。本次环境已有 Visual Studio C++ 工具链，但尚未启用 Windows 开发者模式；需用户自行启用后重跑 `pub get`。依赖准备成功后再运行或构建。

```powershell
$flutterExe = Join-Path $PWD '.tools/flutter/bin/flutter.bat'
$dartExe = Join-Path $PWD '.tools/flutter/bin/dart.bat'

& $flutterExe --version
& $flutterExe doctor -v
& $flutterExe pub get
& $dartExe run build_runner build
& $dartExe format lib test
& $flutterExe analyze --no-pub
& $flutterExe test --no-pub
```

`lib/data/app_database.g.dart` 必须通过 `build_runner` 生成，不手工编辑。变更 Drift 表结构后重新生成代码。应先确认 `pub get` 成功，再执行后续命令；`--no-pub` 只跳过重新解析依赖，不代表平台插件初始化或原生构建已经通过。

在 Windows 环境完成上述准备后：

```powershell
& $flutterExe devices
& $flutterExe run -d windows
& $flutterExe build windows
```

若本机已配置 Flutter 命令，可用常规命令完成相同流程：

```text
flutter pub get
dart run build_runner build
dart format lib test
flutter analyze --no-pub
flutter test --no-pub
flutter devices
flutter run -d <device-id>
```

各端构建命令需在具备对应工具链的主机上执行：

| 目标 | 命令 | 环境要求 |
| --- | --- | --- |
| Windows | `flutter build windows` | Windows 桌面 C++ 工具链、插件符号链接支持 |
| macOS | `flutter build macos` | macOS、Xcode 与可用的原生依赖环境 |
| Android | `flutter build apk` | Android SDK、兼容的 Java 与 Gradle 环境 |
| iOS | `flutter build ios --no-codesign` | macOS、Xcode 与可用的原生依赖环境；真机安装或发布另需签名 |

macOS 的 Debug/Profile 与 Release entitlements 已声明 `com.apple.security.files.user-selected.read-write`，用于用户选择的备份文件读写。该配置仍需在 macOS 上验证实际文件选择和保存流程。

## 验证结果与四端边界

最近一次验证日期：**2026-11-27**，环境为 Windows、Flutter 3.50.1 / Dart 3.14.0。

| 检查 | 结果 |
| --- | --- |
| Drift 代码生成 | 已完成 |
| `dart format lib test` | 无格式变更 |
| `flutter analyze --no-pub` | 0 个问题 |
| `flutter test --no-pub` | 43 项全部通过 |
| Widget 渲染视觉核对 | 已生成 28 张新版页面截图，覆盖手机标准/大字号、手机深色与桌面布局 |

43 项测试包括 FSRS 5 项、仓储 7 项、备份 16 项、日历 2 项、Widget 13 项。覆盖黄金向量与固定配置、事务失败回滚、评分幂等与并发重试、陈旧候选拒绝、跨日额度与到期刷新、备份破坏拒绝和往返恢复、拼写不写库、系统时间倒退提示，以及 390 宽 / 1.5 倍字号和 1280 宽 / 1.0 倍字号布局、图轴标签对齐。测试数据库均使用独立的 `NativeDatabase.memory()` 实例。

| 平台 | 已完成 | 尚未验证 / 当前限制 |
| --- | --- | --- |
| Windows | 平台工程、本地测试；GitHub Actions 的 Release 构建成功 | 本机开发者模式未启用，原生启动与文件选择器未实测。 |
| macOS | 平台工程、文件权限；GitHub macOS runner 的 Release 构建成功 | 未公证，原生运行及文件交互未实测。 |
| Android | 平台工程；GitHub Actions 的 Release APK 构建成功 | 开发签名，模拟器或真机运行、原生文件交互未实测。 |
| iOS | 平台工程；GitHub macOS runner 的未签名 Release 构建成功 | 未签名，设备安装与原生交互未实测。 |

`build/journal-review` 中的截图来自 Widget 渲染器和测试数据，不是四端真机运行证据，截图探针也不计入上述 43 项测试。当前结果证明已列出的逻辑和 Widget 检查通过，不代表四端原生发布包已通过验收。

## Dev 自动构建与发布

仓库为 `AutumnNazi/lexi-loop`，开发分支为 `dev`。工作流位于 `.github/workflows/dev-release.yml`：每次推送到 `dev` 自动检查、测试、构建；向 `dev` 或 `main` 的 PR 只做检查和测试；也可手动触发。后来的同分支提交会取消尚未完成的旧运行。

流程固定使用 Flutter 3.50.1，按 lockfile 安装依赖并生成 Drift 代码。检查与测试通过后并行构建 Windows、Android、macOS、iOS，四项成功后才创建带运行编号的 GitHub 预发布版本，版本对应明确的提交，不覆盖已有发布。构建产物也保留为 Actions artifacts 14 天。

| 发布文件 | 使用方式与边界 |
| --- | --- |
| `lexi-loop-windows-x64.zip` | 解压完整文件夹后运行 `lexi_loop.exe`，不可只复制 exe。 |
| `lexi-loop-android.apk` | Release 模式开发签名 APK；运行间签名可能不同，更新前先导出备份。 |
| `lexi-loop-macos-unsigned.zip` | 未公证的 macOS 应用包。 |
| `lexi-loop-ios-unsigned-app.zip` | 未签名的 `.app`，需要自行签名，不能直接安装到 iPhone。 |

无需在仓库保存个人 GitHub token。发布步骤使用 GitHub 提供的临时令牌，只有该步骤的任务具有 contents 写权限。首次自动运行结果以仓库 Actions 为准；构建成功仍不代表各端真机交互已验收。
## 当前边界

- 无账号、鉴权、多用户界面、云同步、远程 AI 或应用业务网络请求；备份由用户自行保管和转移。
- 无发音播放、录音、TTS 或第三方音频资源。
- 仅内置 24 个原创示例词条；自建词书用于组合现有词义，未提供任意词条编辑、商业词库或外部词典导入。
- 调度训练方式仅为 `recognition`。拼写练习不创建记忆状态、不写评分记录、不参与 FSRS，离开页面后本轮成绩不持久保存。
- 目标保持率和 FSRS 参数固定，未提供个人参数训练、参数编辑或跨调度版本迁移。
- 备份目前只支持本项目版本 1 的完整快照，恢复采用替换方式，未实现增量合并、跨版本迁移或加密。
- 到期刷新在应用运行或恢复前台时生效，未实现系统后台提醒与推送通知。
- 当前目标平台为 Windows、macOS、Android、iOS；未提供 Web、Linux 平台工程和验证结果。