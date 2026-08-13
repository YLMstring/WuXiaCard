# 挥剑自宫与葵花牌组能力设计

## 目标

实装以下五张江湖牌的完整目录描述，并保持 `DuelSimulator` 为人类玩家、测试模式、
贪心 AI 与深度搜索的唯一规则路径：

- `KuiHua0`：挥剑自宫
- `KuiHua1`：天人化生
- `KuiHua2`：钟馗抉目
- `KuiHua3`：飞燕穿柳
- `KuiHua4`：群邪辟易

实现必须保持搜索卡牌无关。模拟器、搜索和控制器不得按上述卡牌 ID 分支；卡牌差异只由
目录声明、通用能力门控、触发、条件、动作和修正表达。运行时卡牌身份继续使用
`instance_id`，所有新增状态都必须进入 AI 克隆、状态键和回放快照。

## 已确认的全局语义

### “需自宫”能力门控

`KuiHua1–4` 在卡牌级声明通用能力门控 `EFFECT_GATE_SELF_CASTRATION`。

- 敌方的此门控在每局对战中默认开启，不检查敌方牌库或解锁状态。
- 玩家只有在开局读取的存档中已解锁 `KuiHua0` 时开启此门控。
- `KuiHua0` 无需携带或出现在本局的手牌、牌库、场上或移除区。
- 玩家门控关闭时，需自宫牌仍可按其基础点数正常打出、被攻击、翻面和计分，但其所有
  效果均无效。
- 门控控制该牌当前拥有的全部能力，包括目录初始触发、锁定修正、主动能力和后来获得的
  能力；不会从实例的 `active_abilities` 中删除数据。
- 一张需自宫牌翻到另一方后，以当前拥有者的门控决定效果是否生效。敌方始终开启；玩家
  取决于本局开局快照。

当前产品决定是 `KuiHua0–4` 暂时都不加入初始锁定列表，因此新存档默认解锁
`KuiHua0`，玩家门控默认开启。规则仍按真实解锁状态初始化，以便将来重新调整初始锁定
列表或加载未解锁 `KuiHua0` 的有效存档。

### “被攻击时”

“被攻击时”沿用现有万花剑法语义：标准攻击先根据攻击范围、攻击方点数、目标防御点数
和攻击许可判断目标是否会被成功攻击。只有通过初始检查的目标才发出 `attack_started`
并进入 `CARD_BE_ATTACKED`。

因此，攻击点数不足、范围不符或攻击许可不满足时，不会触发返回手牌或万花复制。目标在
`CARD_BE_ATTACKED` 中返回手牌、被移除、移动后令攻击失效，仍然算本次攻击确实开始过。

### “攻击后”

普通进场攻击和能力请求的标准或定向攻击，只有至少产生一个 `attack_started` 时，才在
整次攻击全部目标结算完毕后发出一次 `TRIGGER_CARD_AFTER_ATTACK`。

- 无目标或所有目标点数比较失败时，不发出任何攻击后触发。
- 目标进入 `CARD_BE_ATTACKED` 后返回手牌、被移除或最终被阻止翻面，仍会发出攻击后。
- 多目标攻击只在全部目标结算后发出一次攻击后。
- 阴阳掌力的重复攻击遵守相同规则；首次攻击没有成功开始的目标时，不会请求重复攻击。

触发上下文保留 `attacker_instance_id`、攻击者开场拥有者、`attack_flips` 与重复攻击标记。
`attack_flips` 的每一项记录目标翻面前的拥有者，供“本次是否翻动敌方”判断。

## 卡牌能力

### `KuiHua1` 天人化生

天人化生在其当前拥有者的正常回合结束边界触发，请求一次额外手牌出牌。

- 触发要求回合拥有者为能力来源的当前拥有者。
- 不需要气，也不获得或消耗气。
- 同一回合的多个合法请求沿用现有合并规则，只授予一次待用额外出牌。
- 额外出牌不会再次进入该回合的结束边界，因此不会自循环。
- 门控关闭时不发现或结算该触发。

### `KuiHua2` 钟馗抉目

钟馗抉目由三个独立能力条目组成：

1. `CARD_BE_ATTACKED` 且被攻击牌为自身时，使用标准返回手牌动作将自身移回当前拥有者
   手牌。若目标手牌已满，沿用标准规则将其移除到原始拥有者的移除区。
2. 一个翻面保留的攻击方修正：钟馗抉目攻击任意防御者时，防御者参与比较的点数改为其
   当前四侧有效点数中的最小值。
3. `TRIGGER_CARD_AFTER_ATTACK` 且攻击者为自身时，给自身授予一个普通、非翻面保留的
   “敌方攻击时不分敌我”能力。只要本次确实有至少一个 `attack_started`，即使没有翻面
   目标，也会获得该效果。结构相同的重复授予保持幂等。

“敌方攻击时不分敌我”是来源牌的全局攻击规则修正：

- 敌方标准攻击在收集攻击目标时，同时考虑当前攻击者的敌方和友方。
- 范围、距离二规则、阻挡和点数比较照常执行。
- 目标顺序保持上、右、下、左；距离二目标沿用当前每个方向的既有顺序。
- 攻击原本与攻击者同阵营的牌成功时，该目标翻为该效果来源 `KuiHua2` 的当前拥有者，
  而不是攻击者的当前拥有者。
- 同一方存在多个有效来源时只改变一次目标集合，不对同一目标重复发动攻击；翻面归属为
  该方共同的当前拥有者。
- 来源翻面后，普通非保留能力按既有流程失去，规则立即消失。该效果不会因为最初授予它
  的 `KuiHua2` 再次攻击而堆叠。

### `KuiHua3` 飞燕穿柳

飞燕穿柳包含三个独立能力条目：

1. 与钟馗抉目相同的被成功攻击时返回手牌能力。
2. 自身 `TRIGGER_CARD_AFTER_SUMMONED` 时，对相邻敌方做精确实例快照。只有恰好一个合法
   目标时，使用现有交换动作与其交换位置。零个或两个以上目标均不交换。交换失败时停止
   该条规则的后续动作；标准进场攻击仍由召唤管线从其最终位置继续。
3. `TRIGGER_CARD_AFTER_ATTACK` 且攻击者为自身，并且本次 `attack_flips` 至少包含一张
   翻面前属于敌方的牌时，重新进场。

重新进场在整次标准攻击完全结束后发生：

1. 按 `instance_id` 找到飞燕穿柳当前实例与当前格；
2. 旧实例从场上离开但不进入任何移除区；
3. 在该格为旧实例当前拥有者创建同一目录 ID 的全新实例；
4. 新实例恢复目录初始点数、气与全部初始能力；
5. 新实例完整经历进场、进场后交换和标准攻击。

新实例若再次确实攻击并翻动敌方，可以继续触发下一次重新进场。每一轮都使用全新的唯一
`instance_id`，旧实例不会被后续快照误认。没有 `attack_started`、有攻击但没有翻动敌方、
只翻动本来属于友方的目标，均不重新进场。

### `KuiHua4` 群邪辟易

群邪辟易包含被成功攻击时返回手牌能力，以及自身进场后的转换能力。

自身 `TRIGGER_CARD_AFTER_SUMMONED` 按以下顺序结算：

1. 当前拥有者抽一张牌。手牌已满或牌库为空时无效果，但继续后续步骤。
2. 按场上格号 `0..8` 快照所有“当前为能力来源友方，且 `original_owner` 是能力来源
   当前敌方”的精确实例。
3. 逐个重新验证所声明的选择条件；仍合法时将目标标准移除。
4. 目标进入其 `original_owner` 的移除区并发出普通 `card_exiled` 事件。
5. 只有目标成功移除后，才在其移除前的格子生成能力来源 `KuiHua4` 的全新复制。

每张复制属于触发本次转换的能力来源当前拥有者，拥有唯一 `instance_id`，并完整经历进场、
抽牌、转换与标准攻击。选择器的初始精确实例快照和逐项重检确保一个物理目标最多被同一
条规则转换一次。新复制不是“最初是敌方的友方”，因此不会成为后续复制的转换目标；有限
棋盘和目标单调减少共同保证递归终止。

## 目录声明

卡牌级门控采用可验证的稳定词汇：

```gdscript
const EFFECT_GATE_SELF_CASTRATION: StringName = &"self_castration"

&"KuiHua1": {
	...
	"effect_gate": EFFECT_GATE_SELF_CASTRATION,
	"abilities": [KUIHUA_EXTRA_PLAY],
}
```

`KuiHua2–4` 使用相同 `effect_gate`。`KuiHua0` 只保留其解锁说明；对局初始化由存档是否
包含该精确 ID 推导玩家门控，不要求把解锁作用声明成场上能力。

目录验证必须拒绝未知门控和非 `StringName`/String 门控值。门控是卡牌级属性，不复制到
每个能力条目，避免同一张牌的若干条目出现不一致。

声明优先组合现有通用词汇：

- `ACTION_RETURN_CARD_TO_HAND`
- `ACTION_SWAP_SELF_WITH_TARGET`
- `ACTION_DRAW_CARDS`
- `ACTION_FOR_EACH_SELECTED_CARD`
- `ACTION_EXILE_SELF`
- `ACTION_SUMMON_CARD`
- `ACTION_GRANT_ABILITY_TO_SELF`
- `MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE`

本次实装采用的完整声明如下（省略卡牌元数据）：

```gdscript
const KUIHUA_RETURN_TO_HAND := {
	"triggers": [{
		"event": CARD_BE_ATTACKED,
		"conditions": [{"type": CONDITION_ATTACKED_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_RETURN_CARD_TO_HAND,
			"card": CARD_REF_ABILITY_SOURCE,
			"recipient": OWNER_CARD_CURRENT,
		}],
	}],
}

const KUIHUA_INDISCRIMINATE_ATTACK := {
	"modifiers": [{"type": MODIFIER_ENEMY_ATTACKS_ALL}],
}

const KUIHUA2_ABILITIES := [
	KUIHUA_RETURN_TO_HAND,
	{
		"retained_on_flip": true,
		"modifiers": [{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE}],
	},
	{
		"triggers": [{
			"event": TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{
				"type": ACTION_GRANT_ABILITY_TO_SELF,
				"ability": KUIHUA_INDISCRIMINATE_ATTACK,
			}],
		}],
	},
]

const KUIHUA3_ABILITIES := [
	KUIHUA_RETURN_TO_HAND,
	{
		"triggers": [{
			"event": TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ENEMY},
						{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
					],
					"required_count": 1,
				},
				"actions": [{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE}],
			}],
		}],
	},
	{
		"triggers": [{
			"event": TRIGGER_CARD_AFTER_ATTACK,
			"conditions": [
				{"type": CONDITION_ATTACKER_CARD_IS_SELF},
				{"type": CONDITION_ATTACK_FLIPPED_ENEMY},
			],
			"actions": [{
				"type": ACTION_RESUMMON_CARD_IN_PLACE,
				"card": CARD_REF_ABILITY_SOURCE,
			}],
		}],
	},
]

const KUIHUA4_ABILITIES := [
	KUIHUA_RETURN_TO_HAND,
	{
		"triggers": [{
			"event": TRIGGER_CARD_AFTER_SUMMONED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [
				{"type": ACTION_DRAW_CARDS, "amount": 1},
				{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [
							{"type": CONDITION_SELECTED_CARD_IS_ALLY},
							{"type": CONDITION_SELECTED_CARD_ORIGINAL_OWNER_IS_ENEMY},
						],
					},
					"actions": [
						{"type": ACTION_EXILE_SELF, "on_invalid_context": STOP_RULE},
						{
							"type": ACTION_SUMMON_CARD,
							"card": {"type": CARD_SPEC_FRESH_COPY, "of": CARD_REF_ABILITY_SOURCE},
							"cell": {"type": CELL_REF_INITIAL_CARD_CELL, "card": CARD_REF_SELECTED_CARD},
						},
					],
				},
			],
		}],
	},
]
```

现有 `ACTION_RESUMMON_TRIGGER_CARD_IN_PLACE` 泛化为接受卡牌引用的
`ACTION_RESUMMON_CARD_IN_PLACE`：

```gdscript
{
	"type": ACTION_RESUMMON_CARD_IN_PLACE,
	"card": CARD_REF_ABILITY_SOURCE,
}
```

绵里藏针改为传入 `CARD_REF_TRIGGER_CARD`，保持现有行为。该通用动作负责旧实例无移除
离场并请求原格完整召唤，继续复用 `card_departed_for_resummon` 表现事件。

群邪辟易不增加复合专用动作。在选择器内部用 `ACTION_EXILE_SELF` 移除当前目标，再以
`CARD_SPEC_FRESH_COPY` 指向能力来源，并用目标初始格引用执行 `ACTION_SUMMON_CARD`。
动作上下文必须保留已移除选择目标的初始格和原始能力来源，保证先移除后生成仍可解析。

## 状态模型与对局初始化

`DuelState` 新增纯数据门控集合，例如：

```gdscript
var enabled_effect_gates_by_owner: Dictionary = {
	Rules.PLAYER_OWNER: [],
	Rules.OPPONENT_OWNER: [Catalog.EFFECT_GATE_SELF_CASTRATION],
}
```

生产对局创建时读取玩家档案：若 `get_unlocked_ids(profile)` 包含 `KuiHua0`，给玩家加入
`EFFECT_GATE_SELF_CASTRATION`；敌方始终加入。测试可直接构造开启或关闭门控的状态。

该字段必须：

- 在 `duplicate_state()` 中深复制；
- 进入 `DuelStateKey.build()`；
- 被回放初始状态和最终状态自然保存；
- 不包含场景节点、存档对象或控制器引用。

触发发现、触发组重新验证、主动能力查询和修正收集都必须通过同一通用门控判断。不得只
在控制器隐藏交互，也不得在实例创建时删除能力。AI 合法动作和评估因此自然使用同一规则。

## 不分敌我的攻击模型

攻击规则需要把“目标阵营许可”和“成功翻面后的归属”从固定的攻击者拥有者中泛化出来。
模拟器在一次标准攻击开始时，从当前场上有效能力中取得通用攻击策略：

```gdscript
{
	"allow_allied_targets": true,
	"captured_owner_id": kuihua_owner,
}
```

普通攻击策略仍为只允许敌方目标，翻面归属攻击者。策略不写入卡牌 ID；来源失效、门控
关闭或能力丢失时即恢复默认。

初始目标收集与 `CARD_BE_ATTACKED` 后重检使用同一策略快照，防止同阵营目标在第二次范围
检查时被默认规则取消。进入 `CARD_BEFORE_FLIPPED` 后继续沿用现有已承诺翻面语义；真正
翻面时使用策略指定的归属。攻击事件记录实际攻击者、目标及最终新拥有者，表现无需知道
策略来源。

## 事件与表现

不增加卡牌专用表现分支。以下事件和现有动画继续复用：

- `attack_started`
- `card_returned_to_hand`
- `card_moved`
- `card_drawn`
- `card_exiled`
- `ability_triggered`
- `ability_granted`
- `card_departed_for_resummon`
- 现有生成牌/进场事件

飞燕穿柳旧实例使用现有重新进场淡出，再由墨迹进场展示新实例，不显示进入移除区的动画。
群邪辟易目标先完整播放移除，再在相同格播放复制进场。复制逐张结算和展示，不把不同递归
层合并成无法辨认的大批动画。

门控关闭不需要单独战斗事件或提示；卡面描述与解锁状态负责向玩家解释规则。面朝下的牌
仍不得通过门控或事件泄露元数据。

## 测试覆盖

新增聚焦模拟器与目录测试，至少覆盖：

### 门控与状态

- 敌方需自宫能力默认有效；
- 玩家有、无 `KuiHua0` 时分别有效和无效；
- 门控关闭时基础点数、出牌和翻面仍正常；
- 翻面后按当前拥有者门控决定效果；
- 触发、锁定修正、获得能力和主动能力统一受控；
- 状态复制、状态键、贪心与深度搜索、回放保持门控；
- 目录拒绝未知或错误类型的门控。

### 攻击边界

- 零合法目标和所有目标点数不足时不触发攻击后；
- 至少一个 `attack_started` 后只触发一次攻击后；
- 被攻击阶段返回、移除或阻止翻面仍触发攻击后；
- 多目标与定向攻击使用相同规则；
- 阴阳掌力零目标不再重复攻击。

### 天人化生

- 正常回合结束授予一次额外出牌；
- 额外出牌不重复回合结束；
- 多来源请求合并；
- 门控关闭时不授予。

### 钟馗抉目

- 点数不足时不返回，点数足够时返回，满手时标准移除；
- 攻击时使用防御者四侧最小值；
- 有实际攻击但未翻面时仍授予不分敌我，零攻击时不授予；
- 不分敌我攻击仍需满足范围与点数；
- 攻击原友方后将其翻给 `KuiHua2` 当前拥有者；
- 多来源不重复攻击；来源翻面、能力丢失或门控关闭后规则消失。

### 飞燕穿柳

- 零个、一个、多个相邻敌方的交换边界；
- 交换后从最终位置攻击；
- 零攻击、未翻面、只翻动非敌方时不重新进场；
- 翻动敌方后旧实例不进移除区，新实例恢复初始状态并完整进场；
- 连锁重新进场使用不同实例 ID，并在合法目标耗尽时停止。

### 群邪辟易

- 抽牌先于转换；满手或空牌库不阻断后续；
- 只选择当前友方且最初为敌方的牌；
- 按 `0..8` 顺序移除，进入正确原始拥有者移除区；
- 只有移除成功才在原格生成复制；
- 每张复制完整进场、抽牌、转换并攻击；
- 精确实例重检、重复目标、来源移动/翻面/离场和递归终止。

## 验证

实现前后运行：

```powershell
powershell -ExecutionPolicy Bypass -File tools/run_tests.ps1
```

目录与聚焦模拟器测试先通过，再运行完整测试套件。玩法与可见事件完成后，必须在生产主
场景的 `540×960` 竖屏路径实际游玩，检查：

- 被攻击返回只在会成功攻击时播放；
- 钟馗抉目不分敌我的目标与翻面归属；
- 飞燕穿柳攻击结束后淡出并原格重新进场；
- 群邪辟易逐张移除、原格复制、递归进场的展示顺序；
- 回放与原局结果、事件顺序一致；
- 控制台没有新增脚本错误或警告。
