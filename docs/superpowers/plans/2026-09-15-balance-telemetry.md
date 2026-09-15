# 通关对战平衡数据采集实施计划

日期：2026-09-15

对应设计：`docs/superpowers/specs/2026-09-15-balance-telemetry-design.md`

## 目标

为正常导出的 Windows／Android 游戏增加不阻塞流程的通关战报采集：一轮内
每场完成对局记录双方五张主卡组和胜负，真正通关后封装为单份报告，经腾讯
CloudBase HTTP 云函数写入文档数据库；离线时本地保留并在以后重试。编辑器
testing mode、自动测试和 AI 基准绝不访问真实服务。

## 任务一：保留基线并建立纯本地遥测存储

新增／修改：

- `scripts/balance_telemetry_store.gd`
- `tests/test_balance_telemetry_store.gd`
- `tools/run_tests.ps1`

步骤：

1. 行为修改前运行完整套件并保存通过基线；本功能不改原生 C++，无需保留或
   重编原生性能基线。
2. 建立独立存档格式：schema、随机匿名 ID、`active_run`、当前待完成对局和
   `pending_reports`，默认路径与玩家进度文件分离。
3. 复用仓库现有的原子写入习惯，实现 `.tmp` 替换与 `.bak` 恢复；测试使用
   独立 `user://` 路径。
4. 实现开始／放弃轮次、开始／放弃／完成对局、封装通关报告、列出待上传、
   成功确认和永久错误诊断。所有入口返回明确结果，但失败不得影响游戏存档。
5. 一场对局使用运行时唯一 token，完成操作幂等；每份通关报告生成稳定唯一
   `report_id`，重启后保持不变。
6. 卡牌列表序列化为普通字符串，不把 `StringName` 或运行时卡牌 Dictionary
   原样写入遥测文件。
7. 测试匿名 ID 稳定性、旧／损坏文件修复、队列跨启动、备份恢复、重复完成、
   放弃、通关封装及重置清理。

## 任务二：从权威主流程采集轮次与对局

修改：

- `scripts/main_flow_controller.gd`
- `scripts/duel_controller.gd`
- `scripts/game_settings.gd`
- `tests/test_main_flow.gd`
- `tests/test_duel_replay.gd` 或新增窄集成测试

步骤：

1. 在 `DuelController` 增加只读快照入口，从已经初始化的权威
   `DuelState`／回放初始状态按五个固定手牌槽返回双方主卡组卡牌 ID。现有
   `debug_get_replay_initial_decks()` 返回的是牌库，不能误作主手牌。
2. `MainFlowController` 在两条真实新轮入口建立 `active_run`：自动开始华山
   进阶零，以及门派选择成功发出的新轮信号。继续旧活跃存档时不自动补建，
   从而排除更新前轮次。
3. `_show_duel()` 完成场景初始化后，记录敌人稳定 ID、玩家等级、难度、
   先后手和双方五槽快照，生成待完成对局 token。
4. 放弃时丢弃该待完成对局。胜负只有在现有进度存档成功后才提交到遥测
   `active_run`；遥测保存失败只写警告，不改变奖励或场景路由。
5. `duel_result.completed` 为真时，以结局摘要封装通关报告并立即发起一次异步
   上传；普通胜负继续积累。序章、失败重试均自然进入同一路径。
6. 闭关重修、封剑归隐以及开始另一轮前清除未完成遥测轮次；匿名 ID 和已经
   封装的待上传报告保留。
7. 测试五槽顺序、敌人 ID、等级、先后手、胜负顺序、序章记录、失败重试、
   放弃排除、旧轮排除、通关封装和所有重置边界。

## 任务三：实现异步上传器与环境门控

新增／修改：

- `scripts/balance_telemetry_uploader.gd`
- `scripts/game_settings.gd`
- `scripts/main_flow_controller.gd`
- `project.godot`
- `export_presets.cfg`
- `tests/test_balance_telemetry_uploader.gd`
- `tests/test_main_flow.gd`
- `tools/run_tests.ps1`

步骤：

1. 用一个持久的 `HTTPRequest` 节点串行上传队首，设置连接和总请求超时；不在
   对局或搜索过程中轮询。
2. 只在通关封装后和显示主菜单的空闲阶段请求上传。一次失败结束本轮尝试，
   避免断网时热循环。
3. 将 HTTP 结果分为：保存成功／重复幂等成功、可重试网络或 429／5xx、永久
   4xx 格式错误。只有前两种成功语义确认删除报告。
4. 将 endpoint 和 `telemetry_enabled` 集中为项目／导出配置；空 endpoint、
   editor、headless、testing mode 和非 Windows／Android 平台一律关闭真实
   网络。
5. 为测试提供假的传输结果入口，不启动真实 HTTP；测试所有响应分类、队列
   串行性和禁用环境。
6. Android Release 打开 `INTERNET` 权限。不得修改玩家正常音频或其它导出
   设置。

## 任务四：实现 CloudBase 云函数和单文档数据库

新增：

- `cloudbase/balance_telemetry/functions/report_api/index.js`
- `cloudbase/balance_telemetry/functions/report_api/package.json`
- `cloudbase/balance_telemetry/cloudbaserc.json`（只含非秘密部署结构）
- `cloudbase/balance_telemetry/README.md`
- `cloudbase/balance_telemetry/tests/report_api.test.js`

步骤：

1. 将请求解析、schema 白名单校验、CSV 格式化和数据库访问分层，使单元测试
   可注入内存 repository，不连接真实云端。
2. `POST /v1/reports` 限制方法、Content-Type、正文大小、字段长度、难度／胜负
   枚举、恰好五张双方主卡组以及合理对局数。
3. `report_id` 用作文档键；创建冲突视为重复成功，其它数据库错误返回可重试
   5xx。一份通关只写 `run_reports` 的一个嵌套文档。
4. 服务端补写可信 `received_at`、清除未知字段，不保存请求 IP、User-Agent
   或原始正文日志。
5. `GET /v1/admin/export` 校验服务端环境变量中的 Bearer token，支持
   `csv/json`、日期范围和分页／流式安全上限；错误 token 返回 401。
6. 用 Node 内建测试覆盖合法写入、非法字段、超大正文、错误卡牌数、重复
   `report_id`、管理鉴权、CSV 转义和日期过滤。

不得把腾讯云 SecretId、SecretKey、管理 token、环境 ID 或个人配置提交到
仓库。客户端上传接口不嵌入共享秘密。

## 任务五：增加本地下载与显式归档工具

新增：

- `tools/download_balance_reports.ps1`
- `tools/archive_balance_reports.ps1`（只有设计和验证删除语义后才启用）
- 对应 PowerShell 参数／格式测试

步骤：

1. 下载脚本从参数或环境变量读取 endpoint，从环境变量读取管理 token；默认
   支持 CSV、JSON 和日期范围。
2. 下载先写临时文件，响应完整且格式有效后原子改名；错误响应不得覆盖已有
   数据。
3. CSV 每场一行，十张牌展开为固定列；JSON 保持轮次嵌套。
4. 下载命令永远只读。云端删除必须由单独的显式归档命令执行，并要求本地
   文件存在、格式校验通过及明确确认；首轮实现若无法可靠证明这些前置条件，
   只交付下载，不交付删除。

## 任务六：部署测试环境并校准用量

外部步骤：

1. 用户登录并开通腾讯 CloudBase 上海地域免费环境；创建 `run_reports`
   集合。
2. 部署云函数和 HTTP 访问服务，设置管理 token 服务端环境变量。需要用户
   登录、实名或控制台授权时暂停，由用户亲自完成，不在仓库保存凭据。
3. 先把地址写入本地测试导出覆盖，不直接污染正式配置。
4. 用正常 Windows Release 发送一份合成通关报告，验证重复上传只存一份，
   CSV／JSON 均能下载。
5. 用 Android Release 在大陆移动网络和 Wi-Fi 各上传一次；全程静音测试。
6. 查看实际报告字节数、函数执行时间、数据库调用和资源点消耗，用真实数据
   修正 10–20 KB、`0.024–0.030` 点／报告的估算。
7. 端到端通过后才把正式 endpoint 写入 Windows／Android 导出配置。

## 任务七：现行文档与隐私准备

修改：

- `docs/HANDOFF.md`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md`
- `docs/TESTING.md`
- `docs/UI_AND_ANDROID.md`

记录遥测文件职责、启用边界、CloudBase 部署／导出方式、Android 网络权限、
错误重试和运营归档流程。明确正式商店发布前仍需增加隐私说明、同意／关闭
入口及相应政策文本；当前集中门控必须允许无重写地接入。

## 任务八：验证与提交

先运行聚焦测试：

```text
test_balance_telemetry_store.gd
test_balance_telemetry_uploader.gd
test_duel_replay.gd
test_main_flow.gd
test_ending_flow.gd
```

再运行云函数单元测试、`git diff --check` 和完整 Godot 套件：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

最后完成静音 Windows／Android 真实端到端验证。检查工作树并只提交本功能、
测试、云函数和现行文档；不提交凭据、CloudBase 本地缓存、下载数据或玩家
遥测文件。
