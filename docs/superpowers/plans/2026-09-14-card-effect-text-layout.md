# 卡牌特效正文结构化排版实施计划

日期：2026-09-14

对应设计：`docs/superpowers/specs/2026-09-14-card-effect-text-layout-design.md`

## 目标

保持卡牌目录、能力声明和所有原始特效文字不变，只在 `CardInspector` 显示特效正文时自动分段、强调段首规则词并缩进 `【……】` 内容。背景正文不变。

## 基线

本轮开始前，完整套件已在相同代码上通过：`79/79`。本功能只涉及 GDScript、场景和 UI 测试，不需要重编原生 C++。

## 任务一：用失败测试固定格式化规则

### 修改文件

- `tests/test_card_inspector.gd`

### 测试内容

在测试顶部预加载计划新增的 `scripts/card_effect_text_formatter.gd`，增加纯格式化器用例：

1. 单句能力不产生多余段落。
2. 两个最外层句号产生两个外层段落。
3. `锁定，指定：` 整体使用强调样式，原文字序不变。
4. `获得以下效果：【……。……】` 只形成一个外层段落，括号内容缩进，内部两句紧凑换行。
5. `（无论我在哪里）` 附着于上一段。
6. 中文/英文引号及圆括号内部的句号不触发外层分段。
7. 原有手工换行成为明确段落边界。
8. ASCII `[`、`]` 显示为普通文字，不注入富文本标签。
9. 未闭合或逆序闭合的括号、引号返回安全回退结果。
10. 把格式化结果交给一个临时 `RichTextLabel`，其 `get_parsed_text()` 与原文一致（仅统一 `CRLF/LF`）。

### 红灯命令

```powershell
& "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" `
  --headless --audio-driver Dummy --path C:\mygame `
  --script res://tests/test_card_inspector.gd
```

预期：新预加载或新断言失败，证明测试确实约束了尚未实现的排版行为。

## 任务二：实现纯展示格式化器

### 新增文件

- `scripts/card_effect_text_formatter.gd`

### API

提供一个无场景依赖的 `RefCounted` 工具：

```gdscript
static func format_bbcode(raw_text: String) -> String
static func normalize_plain_text(text: String) -> String
```

`format_bbcode()` 返回安全 BBCode。`normalize_plain_text()` 只统一换行符，供生产自检与测试比较，不删除或改写任何可见字符。

### 实现步骤

1. 单次线性扫描原文，维护 `【】`、`（）()`、中文引号和英文引号状态。
2. 在嵌套深度为零的句号或手工换行处结束外层段落。
3. 若新片段只以圆括号备注开头，将其并回上一段。
4. 在 `【】` 内按该层句号切成紧凑子段，外层括号保持可见。
5. 只匹配段首白名单前缀；复合前缀优先于单一前缀。
6. 使用 BBCode 段落、缩进、粗体和颜色标签，不插入项目符号。
7. 对原文的方括号控制字符做富文本转义。
8. 任意栈错误、未闭合结构或格式化后纯文本不一致时，返回只经过转义的完整原文。

### 绿灯命令

重复运行 `test_card_inspector.gd`，要求新增格式化器用例通过且没有脚本错误。

## 任务三：把详情页特效正文切换为富文本

### 修改文件

- `scenes/card_inspector.tscn`
- `scripts/card_inspector.gd`
- `tests/test_card_inspector.gd`
- `tests/test_duel_integration.gd`

### 场景调整

把 `Parchment/Body/Margin/Scroll/Content/Description` 从 `Label` 改为 `RichTextLabel`：

- `bbcode_enabled = true`
- `fit_content = true`
- `scroll_active = false`
- `autowrap_mode` 继续使用中文智能换行
- `language = "zh"`
- `mouse_filter = IGNORE`
- 主文字颜色和字号保持当前值
- 通过主题常量设置约半行段间距

外层 `ScrollContainer`、`Flavor` 普通 `Label` 以及全部其它节点不改。

### 控制器调整

1. 将 `description` 的静态类型改为 `RichTextLabel`。
2. `present()` 对非空目录描述调用 `format_bbcode()`；空描述仍显示 `—`。
3. `flavor.text` 继续直接使用 `_display_string()`。
4. `set_board_rect()` 继续按棋盘短边设置特效字号。
5. `_card_snapshot` 仍保存原始数据，不写回格式化文本。

### 集成断言

更新所有把 `Description` 强转为 `Label` 的测试，并确认：

- 控件类型、富文本、自动高度和禁用内部滚动配置正确；
- `get_parsed_text()` 等于原始描述；
- `get_card_snapshot().description` 未变化；
- 空描述仍显示 `—`；
- 背景正文仍为 `Label`，文字和样式未变化；
- 轻触关闭与拖动滚动既有测试继续通过。

## 任务四：增加全目录零文字损失覆盖

### 修改文件

- `tests/test_card_catalog.gd`

### 测试内容

遍历 `Catalog.get_all_card_ids()`：

1. 对每个非空 `description` 调用格式化器。
2. 将结果交给一个复用的临时 `RichTextLabel` 解析。
3. 断言解析后的可见文字与原文一致。
4. 断言结果不是空字符串。
5. 记录并断言复杂样本确实产生多个外层段落或嵌套缩进，防止实现退化为永远回退原文。

不修改 `card_catalog.gd`，也不把展示格式写入目录 schema。

### 聚焦测试

```powershell
& "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" `
  --headless --audio-driver Dummy --path C:\mygame `
  --script res://tests/test_card_catalog.gd

& "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" `
  --headless --audio-driver Dummy --path C:\mygame `
  --script res://tests/test_card_inspector.gd

& "$env:LOCALAPPDATA\SummerEngine\current\Summer.exe" `
  --headless --audio-driver Dummy --path C:\mygame `
  --script res://tests/test_duel_integration.gd
```

## 任务五：同步现行文档

### 修改文件

- `docs/HANDOFF.md`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md`
- `docs/TESTING.md`

记录：

- 特效正文使用纯展示格式化器和 `RichTextLabel`；
- 目录原始描述与卡牌快照保持不变；
- 背景正文不参与格式化；
- 格式化器不进入规则或搜索路径；
- `test_card_catalog.gd` 与 `test_card_inspector.gd` 承担零文字损失和 UI 行为覆盖。

## 任务六：完整验证与实机式视觉检查

### 静态检查

```powershell
git diff --check
```

### 完整套件

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

要求全部现有套件通过，无 `ERROR:`、`SCRIPT ERROR:`、`_FAILED` 或 `CHECK_FAILED`。

### 静音视觉验收

使用 `.summer/local/` 下的临时烟雾脚本，以 Dummy 音频和 `540×960` 窗口分别展示：

1. 普通单能力牌；
2. 三个以上独立能力的长文本牌；
3. 含 `获得以下效果：【……】` 的嵌套牌。

逐张检查：

- 原文无缺失；
- 段距能区分能力但不过度浪费纵向空间；
- 段首强调不喧宾夺主；
- 嵌套缩进清楚；
- 中文换行无裁字和横向溢出；
- 外层滚动正常，轻触关闭正常；
- 背景正文视觉不变。

验收后删除临时脚本和截图，不提交 `.summer/local/` 内容。

## 任务七：提交

只提交本功能涉及的格式化器、详情页场景/控制器、测试和现行文档。建议提交信息：

```text
Improve card effect text readability
```

不重编 C++，不导出 Android；如需安装包，在功能提交并通过完整验证后另行导出。
