# 固定组牌与奖励音乐池设计

日期：2026-08-26

## 目标

组牌界面和普通奖励界面不再扫描 `res://music`。与菜单、战斗音乐池一致，所有可选曲目都在 `MusicDirector` 中显式声明；新增文件不会自动进入音乐池。

## 固定清单与权重

以下 `village` 曲目各占两个加权条目：

- `funny-village.mp3`
- `happy-village.mp3`
- `lively-village.mp3`
- `monk-village.mp3`
- `monk2-village.mp3`
- `peace-village.mp3`
- `virtue-village.mp3`

以下 `story` 曲目各占一个加权条目：

- `exciting-story.mp3`
- `happy-story.mp3`
- `sad-story.mp3`
- `sadder-story.mp3`

固定数组共 18 个加权条目。随机抽取、允许连续重复、组牌与普通奖励同池续播等既有规则保持不变。

## 实现

- `MusicDirector` 用一个显式常量数组替代目录扫描函数。
- 删除仅供扫描使用的目录、扩展名常量和初始化逻辑。
- 测试核对固定数组的精确曲名、18 个加权条目，以及 village/story 的 2:1 重复次数。
- 更新原音乐设计、架构、决策和测试文档中“扫描目录”的描述。

## 非目标

- 不修改菜单、战斗或特殊音乐池。
- 不修改淡出、淡入、自然续播或快速切换逻辑。
- 不加入响度归一化或新的音乐文件。
