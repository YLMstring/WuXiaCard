# 卡牌特效正文纯文本分段实施计划

日期：2026-09-14

对应设计：`docs/superpowers/specs/2026-09-14-card-effect-text-layout-design.md`

## 目标

恢复特效正文原有普通 `Label` 的字号、字重和颜色。只按最外层句号拆成多个纯文本段落，段落间保留约 7 像素、约半行间距；任何括号或引号内部均不拆段、不缩进。

目录原文、卡牌声明、背景正文和全部结算规则不变。本功能不需要重编 C++。

## 基线

实施前的最终代码已通过完整 `79/79` 套件。此后只有设计文档变更，可复用该基线。

## 任务一：先修改测试固定新规则

修改：

- `tests/test_card_inspector.gd`
- `tests/test_card_catalog.gd`
- `tests/test_duel_integration.gd`

测试要求：

1. 单句返回一个段落，句末不产生空段。
2. 多个最外层句号产生多个有序段落。
3. `【】`、`（）()`、中文单双引号和英文双引号内部的句号不拆段。
4. 原有手工换行作为明确段落边界，不产生空段。
5. 普通 ASCII 方括号保持原样，无富文本转义。
6. 未闭合或逆序结构完整回退为单段原文。
7. 全目录中，依次拼接段落必须能还原统一换行后的原文。
8. 详情页的特效子节点全部是普通 `Label`，颜色、字号、字重、中文换行与旧样式一致；容器间距为 7。
9. 卡牌快照仍保存原文，空描述仍显示 `—`，背景仍是原有 `Label`。

先运行 `test_card_inspector.gd` 确认旧实现不能满足这些断言，再实现绿灯。

## 任务二：简化纯文本格式化器

修改：

- `scripts/card_effect_text_formatter.gd`

API 调整为：

```gdscript
static func split_paragraphs(raw_text: String) -> Array[String]
static func normalize_plain_text(text: String) -> String
```

实现为一次线性扫描：维护受支持括号和引号栈，只在栈为空的句号或原有换行处结束段落。删除前缀白名单、颜色、粗体、BBCode、缩进及 RichTextLabel 完整性探针。结构非法时返回只含完整原文的单元素数组。

## 任务三：用普通 Label 组成特效段落

修改：

- `scenes/card_inspector.tscn`
- `scripts/card_inspector.gd`

把 `Description` 改为 `VBoxContainer`，间距固定为 7。`CardInspector` 根据格式器结果动态创建普通 `Label`：

- `font_color` 沿用旧值 `Color(0.2, 0.15, 0.1, 1)`；
- `font_size` 沿用旧的棋盘短边计算值；
- `autowrap_mode = 3`、`language = "zh"`；
- `mouse_filter = IGNORE`；
- 不设置粗体、强调色或缩进。

每次 `present()` 先清除旧段落再按顺序创建，防止连续查看卡牌残留文字。外层 `ScrollContainer` 继续负责滚动，`Flavor` 不改。

## 任务四：同步现行文档

修改：

- `docs/HANDOFF.md`
- `docs/ARCHITECTURE.md`
- `docs/DECISIONS.md`
- `docs/TESTING.md`

删除 RichText、规则词强调和授予效果缩进的现行说明，改为普通 Label 段落、最外层句号拆分、7 像素段距及括号内部不拆分。

## 任务五：验证

聚焦测试：

```powershell
test_card_catalog.gd
test_card_inspector.gd
test_duel_integration.gd
```

随后运行：

```powershell
git diff --check
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

最后用 Dummy 音频在 `540×960` 连续展示短文本、多句文本和含 `【】` 文本，检查：

- 字号、字重和颜色恢复原观感；
- 段间距约半行；
- 括号内部没有换行或缩进；
- 连续查看没有残留；
- 外层滚动和背景文字不受影响。

临时脚本和截图验收后删除，不提交 `.summer/local/` 内容。

## 任务六：提交

提交格式器、详情页、测试、现行文档，以及 Godot 为新格式器生成的 `.gd.uid`。不导出 Android。
