# 全真派新卡与双手互搏设计

日期：2026-09-25

## 目标与范围

实现当前 `scripts/card_catalog.gd` 新增的 18 张卡牌目录项：天罡北斗阵 2–5、金雁功 2–4、先天功 5、七星聚会 1–4、定阳针 1–4、空碗盛饭 4，以及江湖心法双手互搏 5。目录文字是本次玩法的依据，现有 `abilities: []` 不是已实现的证据。卡牌效果必须通过 `DuelSimulator` 的同一原生规则路径作用于玩家、测试模式、回放与 AI。

本次只实现卡牌规则及其必要的合法落点和呈现；不新增可选的全真派门派、解锁路线、敌人或初始牌组。`JinYanGong5` 改为 `XianTianGong5`，`WuDangMianZhang4` 改为 `KongWanChengFan4`，并同步目录 ID 列表和相关测试。这两张此前未发布，不做旧 ID 存档迁移。图片、数值、品阶、门派、武器与文案保持目录现值。

## 方案选择

采用小范围的通用规则扩展。已有的抽牌、内力增减、点数增减、攻击、阻止翻面、交换、重新进场、玩家持有的持续效果和额外出牌负责主要行为。只为目前无法准确表达的部分补局部邻接判断、现有相邻交换动作与选牌条件的可选卡牌引用，以及卡牌声明控制的友方占位出牌。交换仍复用现有结算、前后移动触发和视图事件，不复制另一套交换算法。

备选方案一是扩建通用的目标表达式和手牌出场规则框架。它可以减少日后个别声明，但本批卡牌只需少量能力，验证面和搜索热路径成本更大。备选方案二是在 C++ 按这几张卡的 ID 写分支，改动看似短，却会让 AI、玩家和目录能力的同一路径失去保证。两者均不采用。

## 共享时序和身份规则

- 相邻指正交四邻；“首个”按棋盘格 `0..8` 的行优先顺序取第一个当前仍有效的目标。用 `limit: 1` 表达首个，不用 `required_count: 1`，后者表示恰好只有一个候选。
- “进场时”在放置后、标准攻击前结算；“进场后”在既有 `CARD_AFTER_SUMMONED` 阶段结算。每个攻击、抽牌和重新进场沿用现有完整生命周期。
- 翻面阻止只在目标当前有相邻友方且至少有 1 内力时，先消耗 1 内力，再提交对该确切实例的阻止请求。目标和邻居在触发执行时重新定位；没有内力或邻居时按普通翻面继续。
- “重新进场”沿用现有 `ACTION_RESUMMON_CARD_IN_PLACE`：旧实例离场，新目录实例在当前格进场，重置为目录点数、内力和能力，再走进场和攻击阶段；受每个实际回合最多 20 次特殊进场的现有上限约束。
- 多个同类效果按现有格位、能力和触发顺序执行，并逐项重新验证实例。失效目标不替换为另一张牌，也不凭视觉子节点顺序查找。

## 各卡能力

### 天罡北斗阵 2–5

2–4 阶进场后，让当前相邻的所有其他友方依格位顺序各发起一次标准攻击；5 阶改为场上所有其他友方。快照候选、执行前重检所属与格位，已翻面或离场的候选不攻击。

3–5 阶获得共享的耗内力阻止自身翻面效果。4 阶在自身翻面被阻止后，与当前首个相邻友方交换，若交换成功则将自身重新进场。5 阶改为任何友方翻面被阻止后，让被阻止的那张牌与**它**当前首个相邻友方交换，再让该牌重新进场；这张牌可以不挨着天罡北斗阵。

4 阶的交换直接沿用泰山十八盘所用的选牌与 `ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE`，选牌声明使用 `limit: 1`。5 阶的能力来源和被阻止的牌不同；给现有 `CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE` 与 `ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE` 增加可选的 `card: CARD_REF_TRIGGER_CARD`，仅在显式声明时把原本的 ability source 换成被阻止的确切牌。先按行优先选出该牌首个相邻友方，再调用原有相邻交换结算；旧声明不带 `card` 时仍以 ability source 为邻接锚点和交换一端。无相邻友方、交换被移动前触发打断、来源失效等情况均不执行随后的重新进场。交换动作必须以是否实际完成两张确切实例换位来判定成功，不能把移动前反应输出的其他事件误当作交换成功；既有事件仍照常保留。若交换成功但特殊进场已达 20 次上限，交换保留，重新进场按现有上限成为无效果。

### 金雁功 2–4、先天功 5

金雁功 2–4 阶进场后抽一张牌；它仍在场时，己方每次成功抽牌后令该确切抽到的牌内力加 1。3–4 阶继续复用梯云纵的锁定翻面前移动：能移向首个相邻空格时改为移动并阻止翻面；无空格时照原规则处理翻面。4 阶在己方抽牌加内力后，再授予该抽到的牌共享的耗内力邻友保护能力；能力处于手牌时不会扫描全手牌触发，进场后正常生效。

先天功在 `duel_started` 的一次性手牌发现阶段，依固定物理槽位给当前所属方所有手牌内力加 1；它本身作为手牌也在范围内。同一方多张先天功逐张结算并可叠加，不在后续抽牌时补发。

### 七星聚会 1–4

各阶有共享的耗内力邻友保护。2 阶起，己方牌进场时若与本牌相邻，令进场牌内力加 1 并授予同一保护能力。3–4 阶将条件扩大为进场牌与**任意**当前友方相邻，不要求挨着七星聚会；若七星聚会本身进场且邻接其他友方，也符合条件。4 阶再复用现有“攻击时使用防御者最小一侧点数”的锁定修正。

邻接任意友方采用一个仅查看触发牌四邻的通用条件，不增加每次搜索转换都无条件执行的全棋盘扫描。重复授予结构相同的被动能力沿用现有幂等规则；多个七星聚会来源的内力增加仍分别结算。

### 定阳针 1–4

各阶有共享的耗内力邻友保护。只在本牌作为攻击者**成功将原本的敌方翻面**后触发进阶效果；攻击开始、翻面被阻止和其他牌造成的翻面均不算。

- 2 阶：令刚翻面的确切目标内力加 1，再授予共享保护。
- 3 阶：给目标授予共享保护，再令场上所有其他当前友方内力各加 1。刚被翻面的目标此时已是友方，若仍在场也包含在“其他友方”内；不再额外执行 2 阶的单独目标加内力动作。
- 4 阶：给目标授予共享保护，再令场上所有其他当前友方四侧点数和内力各加 1；刚被翻面的目标同样可在范围内。点数与内力均按确定的选牌次序结算，点数变化沿用现有批次呈现。

### 空碗盛饭 4

保留目前列出的武当绵掌 3 阶式“翻面前移除自身，自己将其他牌翻面后失去此效果，自己将其他牌翻面后令其发起攻击”两项能力，并增加仅此类目录声明可用的友方占位出牌规则。枚举合法出牌时，除空格外也包含当前所属方已占据的格；敌方格仍非法。手牌打向友方格时，先按正常移除生命周期处理原格牌，重新检查目标仍为空，再将手牌落位并运行正常进场流程。若前置移除反应使该格仍被占用，整个行动判为无效，不消费手牌或回合；原生转换副本中的中间效果不提交。占位许可视为卡牌固有的落点属性；已选定出牌行动后才消费的待生效手牌能力压制不倒推取消本次合法落点。

控制器从模拟器合法行动列表取得拖牌落点，并按“旧牌移除→新牌落位”事件顺序呈现，不加只作用于玩家的规则分支。空碗盛饭在全满棋盘上的能力不改变既有终局规则；仅当当前已获得的额外出牌机会尚未完成时，才可能在满盘局面继续出牌。

### 双手互搏 5

进场前先执行自我移除，再无条件给当时所属玩家授予一份独立的持续效果；授予不依赖移除是否成功。通常自身已离场，不进行后续进场攻击；若其他移除前反应打断了自我移除，自身仍在场时按正常进场生命周期继续，持续效果仍已授予。每份效果在己方牌进场前先令该确切进场牌内力减 1，再令四侧点数各减 1。先处理内力是为了避免四侧归零移除后仍修改移除区中的内力。两种资源均按既有下限处理：内力最低 0，不要求牌原本有内力；点数各侧最低 0，四侧全 0 时按正常规则移除。

该玩家回合结束时，查找其最近一次**从自己手牌实际打出**的确切实例，不限本回合。即使该牌后来换格或翻成敌方，只要它仍在场，就尝试正常移除；只有该确切实例确实产生 `card_exiled` 结果，才抽 1 张牌并申请 1 次额外出牌。该记录可能指向刚打出并已移除的双手互搏本身，此时不抽牌、不追加出牌。多个双手互搏持续效果分别结算，但同一确切目标只能成功移除一次；后续效果不凭同 ID 的其他实例代替。抽牌满手或牌库空的行为沿用现有抽牌规则；追加出牌沿用每方每实际回合最多一次的额度及合法出牌检查。四侧 `-1` 的不可变点数哨兵仍遵守现有 `can_change_powers()`，不强制变成四个 0。

持续效果使用现有 owner-held aura，来源牌移除后依然归授予时的玩家持有；不将能力写入任意场上卡牌，也不对所有离场区域做事件扫描。上一张手牌出牌身份沿用现有 `last_hand_play_by_owner` 记录和 `CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY`，不新增平行状态。

## 目录能力声明

以下是本次设计要求写入 `scripts/card_catalog.gd` 的完整能力声明；共用常量在各卡 `abilities` 数组中按列出的顺序引用。`CONDITION_TRIGGER_CARD_HAS_ADJACENT_ALLY`、`CONDITION_LAST_EXILE_SUCCEEDED` 与顶层 `play_on_ally_occupied_cell` 是本设计新增的通用目录词汇；`CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE` 和 `ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE` 的可选 `card` 是现有原语的参数扩展。其余词汇已经存在。

共同的保护能力与现有复用能力：

```gdscript
const QZ_SPEND_KI_TO_PREVENT_FLIP: Dictionary = {
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_HAS_ADJACENT_ALLY},
			{"type": CONDITION_KI_AT_LEAST, "amount": 1},
		],
		"actions": [
			{"type": ACTION_SPEND_KI, "amount": 1, "on_invalid_context": STOP_RULE},
			{"type": ACTION_PREVENT_TRIGGER_FLIP},
		],
	}],
}

# 现有声明；保留其 retained_on_flip、触发条件和动作顺序。
const TIYUNZONG_LOCKED_FLIP_MOVE: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
		],
		"actions": [
			{"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY, "on_invalid_context": STOP_RULE},
			{"type": ACTION_PREVENT_TRIGGER_FLIP},
		],
	}],
}

const KUIHUA_MINIMUM_DEFENSE_RETAINED: Dictionary = {
	"retained_on_flip": true,
	"modifiers": [{"type": MODIFIER_DEFENDING_POWER_USES_MINIMUM_SIDE}],
}

const WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP: Dictionary = {
	"triggers": [
		{
			"event": CARD_BEFORE_FLIPPED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
			"actions": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
		},
		{
			"event": CARD_AFTER_FLIPPED,
			"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
			"actions": [{"type": ACTION_REMOVE_THIS_ABILITY}],
		},
	],
}

const WUDANG_FLIPPED_CARD_ATTACK: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_STANDARD_ATTACK_WITH_CARD,
			"card": CARD_REF_TRIGGER_CARD,
		}],
	}],
}
```

天罡北斗阵的进场攻击与受保护后的交换：

```gdscript
const QZ_TIAN_ADJACENT_ALLIES_ATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
				],
			},
			"actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
		}],
	}],
}

const QZ_TIAN_ALL_OTHER_ALLIES_ATTACK: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
				],
			},
			"actions": [{"type": ACTION_STANDARD_ATTACK_WITH_SELF}],
		}],
	}],
}

const QZ_TIAN_SELF_PREVENTED_SWAP_RESUMMON: Dictionary = {
	"triggers": [{
		"event": CARD_FLIP_PREVENTED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE},
				],
				"limit": 1,
			},
			"actions": [
				{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE,
				 "on_invalid_context": STOP_RULE},
				{"type": ACTION_RESUMMON_CARD_IN_PLACE, "card": CARD_REF_ABILITY_SOURCE},
			],
		}],
	}],
}

const QZ_TIAN_ALLY_PREVENTED_SWAP_RESUMMON: Dictionary = {
	"triggers": [{
		"event": CARD_FLIP_PREVENTED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					{"type": CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE,
					 "card": CARD_REF_TRIGGER_CARD},
				],
				"limit": 1,
			},
			"actions": [
				{"type": ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE,
				 "card": CARD_REF_TRIGGER_CARD,
				 "on_invalid_context": STOP_RULE},
				{"type": ACTION_RESUMMON_CARD_IN_PLACE,
				 "card": CARD_REF_TRIGGER_CARD},
			],
		}],
	}],
}
```

金雁功、先天功与七星聚会：

```gdscript
const QZ_JINYAN_ENTRY_DRAW: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
	}],
}

const QZ_JINYAN_ALLY_DRAW_GAIN_KI: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_DRAWN,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [{"type": ACTION_GAIN_KI, "amount": 1,
		             "card": CARD_REF_TRIGGER_CARD}],
	}],
}

const QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_DRAWN,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [
			{"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
		],
	}],
}

const QZ_XIANTIAN_OPENING_HAND_KI: Dictionary = {
	"triggers": [{
		"event": TRIGGER_DUEL_STARTED,
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_HAND],
				"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
			},
			"actions": [{"type": ACTION_GAIN_KI, "amount": 1,
			             "card": CARD_REF_SELECTED_CARD}],
		}],
	}],
}

const QZ_QIXIN_ADJACENT_ALLY_ENTRY: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_ADJACENT_TO_SOURCE},
		],
		"actions": [
			{"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
		],
	}],
}

const QZ_QIXIN_ANY_ALLIED_NEIGHBOR_ENTRY: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_ALLY},
			{"type": CONDITION_TRIGGER_CARD_HAS_ADJACENT_ALLY},
		],
		"actions": [
			{"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
		],
	}],
}
```

定阳针的成功翻面效果；三、四阶的“其他友方”排除定阳针本身，但包括刚翻成友方的目标：

```gdscript
const QZ_DING_FLIP_GAIN_KI_AND_PROTECT: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY},
		],
		"actions": [
			{"type": ACTION_GAIN_KI, "amount": 1, "card": CARD_REF_TRIGGER_CARD},
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
		],
	}],
}

const QZ_DING_FLIP_PROTECT_AND_ALLY_KI: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY},
		],
		"actions": [
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
					],
				},
				"actions": [{"type": ACTION_GAIN_KI, "amount": 1,
				             "card": CARD_REF_SELECTED_CARD}],
			},
		],
	}],
}

const QZ_DING_FLIP_PROTECT_ALLY_POWERS_AND_KI: Dictionary = {
	"triggers": [{
		"event": CARD_AFTER_FLIPPED,
		"conditions": [
			{"type": CONDITION_ATTACKER_CARD_IS_SELF},
			{"type": CONDITION_TRIGGER_CARD_WAS_ENEMY},
		],
		"actions": [
			{"type": ACTION_GRANT_TRIGGER_CARD_ABILITY,
			 "ability": QZ_SPEND_KI_TO_PREVENT_FLIP},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
						{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
					],
				},
				"actions": [{"type": ACTION_CHANGE_POWERS, "amount": 1,
				             "card": CARD_REF_SELECTED_CARD}],
			},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_BOARD],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_IS_NOT_SOURCE},
					],
				},
				"actions": [{"type": ACTION_GAIN_KI, "amount": 1,
				             "card": CARD_REF_SELECTED_CARD}],
			},
		],
	}],
}
```

双手互搏的自我移除及授予玩家的独立持续效果：

```gdscript
const QZ_HUBO_OWNER_AURA: Dictionary = {
	"triggers": [
		{
			"event": TRIGGER_CARD_BEFORE_SUMMONED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
			"actions": [
				{"type": ACTION_SPEND_KI, "amount": 1,
				 "card": CARD_REF_TRIGGER_CARD},
				{"type": ACTION_CHANGE_POWERS, "amount": -1,
				 "card": CARD_REF_TRIGGER_CARD},
			],
		},
		{
			"event": TRIGGER_END_OWNER_TURN,
			"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
			"actions": [
				{
					"type": ACTION_FOR_EACH_SELECTED_CARD,
					"selector": {
						"zones": [CARD_ZONE_BOARD],
						"conditions": [{
							"type": CONDITION_SELECTED_CARD_IS_PREVIOUS_HAND_PLAY,
							"played_by": OWNER_ABILITY_SOURCE,
						}],
						"limit": 1,
					},
					"actions": [{"type": ACTION_EXILE_CARD,
					             "card": CARD_REF_SELECTED_CARD}],
				},
				{
					"type": ACTION_IF,
					"conditions": [{"type": CONDITION_LAST_EXILE_SUCCEEDED}],
					"actions": [
						{"type": ACTION_DRAW_CARDS, "amount": 1},
						{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
					],
				},
			],
		},
	],
}

const QZ_HUBO_BEFORE_SUMMON: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
			{"type": ACTION_GRANT_OWNER_AURA, "aura": QZ_HUBO_OWNER_AURA},
		],
	}],
}
```

逐卡目录能力组合；未列出的目录字段保持现值。这里的数组顺序就是目录实际执行顺序，不把低阶效果隐式继承到高阶：

```gdscript
&"TianGangBeiDou2": {"abilities": [QZ_TIAN_ADJACENT_ALLIES_ATTACK]},
&"TianGangBeiDou3": {"abilities": [QZ_TIAN_ADJACENT_ALLIES_ATTACK,
	QZ_SPEND_KI_TO_PREVENT_FLIP]},
&"TianGangBeiDou4": {"abilities": [QZ_TIAN_ADJACENT_ALLIES_ATTACK,
	QZ_SPEND_KI_TO_PREVENT_FLIP, QZ_TIAN_SELF_PREVENTED_SWAP_RESUMMON]},
&"TianGangBeiDou5": {"abilities": [QZ_TIAN_ALL_OTHER_ALLIES_ATTACK,
	QZ_SPEND_KI_TO_PREVENT_FLIP, QZ_TIAN_ALLY_PREVENTED_SWAP_RESUMMON]},
&"JinYanGong2": {"abilities": [QZ_JINYAN_ENTRY_DRAW,
	QZ_JINYAN_ALLY_DRAW_GAIN_KI]},
&"JinYanGong3": {"abilities": [TIYUNZONG_LOCKED_FLIP_MOVE,
	QZ_JINYAN_ENTRY_DRAW, QZ_JINYAN_ALLY_DRAW_GAIN_KI]},
&"JinYanGong4": {"abilities": [TIYUNZONG_LOCKED_FLIP_MOVE,
	QZ_JINYAN_ENTRY_DRAW, QZ_JINYAN_ALLY_DRAW_GAIN_KI_AND_PROTECT]},
&"XianTianGong5": {"abilities": [QZ_XIANTIAN_OPENING_HAND_KI]},
&"QiXinJuHui1": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP]},
&"QiXinJuHui2": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP,
	QZ_QIXIN_ADJACENT_ALLY_ENTRY]},
&"QiXinJuHui3": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP,
	QZ_QIXIN_ANY_ALLIED_NEIGHBOR_ENTRY]},
&"QiXinJuHui4": {"abilities": [KUIHUA_MINIMUM_DEFENSE_RETAINED,
	QZ_SPEND_KI_TO_PREVENT_FLIP, QZ_QIXIN_ANY_ALLIED_NEIGHBOR_ENTRY]},
&"DingYangZhen1": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP]},
&"DingYangZhen2": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP,
	QZ_DING_FLIP_GAIN_KI_AND_PROTECT]},
&"DingYangZhen3": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP,
	QZ_DING_FLIP_PROTECT_AND_ALLY_KI]},
&"DingYangZhen4": {"abilities": [QZ_SPEND_KI_TO_PREVENT_FLIP,
	QZ_DING_FLIP_PROTECT_ALLY_POWERS_AND_KI]},
&"KongWanChengFan4": {
	"play_on_ally_occupied_cell": true,
	"abilities": [WUDANG_EXILE_BEFORE_FLIP_UNTIL_OWN_FLIP,
		WUDANG_FLIPPED_CARD_ATTACK],
},
&"ZuoYouHuBo5": {"abilities": [QZ_HUBO_BEFORE_SUMMON]},
```

## 必要的原生接口改动

1. 为触发牌提供“当前至少有一个相邻友方”的通用条件；使用四邻局部读取，处理翻面保护与七星聚会 3–4 阶，不检查卡 ID。
2. 扩展现有 `CONDITION_SELECTED_CARD_ADJACENT_TO_SOURCE` 和 `ACTION_SELF_SWAPPED_WITH_ABILITY_SOURCE`，仅允许可选的 `card: CARD_REF_TRIGGER_CARD` 把邻接锚点及交换一端从 ability source 换成确切触发牌。未声明时仍使用 ability source，旧目录无需改动。选牌依棋盘格顺序取首个当前友方；交换前后重检两个实例、相邻关系和当前归属，调用原有交换结算。移动前反应有输出但两牌并未换位时，交换动作报告 `NO_EFFECT` 以使 `STOP_RULE` 阻止重新进场；反应产生的事件依旧保留，现有只在交换成功后继续攻击的能力也因此符合其文字规则。
3. 给目录卡定义增加布尔字段 `play_on_ally_occupied_cell`，表示“可在友方占据格子出牌并先移除原牌”。原生合法行动枚举、`owner_has_legal_play`、出牌转换以及目录校验使用同一声明，避免 AI 和玩家分叉。未声明的牌仍只可落在空格。
4. 为 `ACTION_IF` 增加 `CONDITION_LAST_EXILE_SUCCEEDED`：上一项 `ACTION_EXILE_CARD` 确实让其确切目标产生 `card_exiled`。现有 `ACTION_EXILE_CARD` 在移除前触发将目标挪走时也报告动作已执行，故不能用其当前返回值判断双手互搏回合末的“若如此做”。进入 `ACTION_FOR_EACH_SELECTED_CARD` 前把该结果重置为假；选中至多一个目标时，将这个目标的移除结果传给外层后续 `ACTION_IF`，而不传递其他嵌套动作的临时状态。该结果只存在于本次触发结算上下文，不写入 `DuelState`，也不改变其他移除动作的返回语义。双手互搏进场前的自我移除没有此条件：无论移除结果如何，都授予持续效果。抽牌和额外出牌留在玩家光环的顶层动作列表中执行，以确保受益者是光环持有者，即使被移除的旧牌已经翻成敌方。

目录 schema、原生编译和运行时效果均要拒绝未知或不匹配的声明。所有新规则输出既有纯数据事件；若必要，仅在控制器通用事件呈现上修正顺序，不引入命名卡牌分支。热路径先判断相关事件和手牌声明，再做常数级邻接/目标判断。

## 验证与性能

先为目录与原生模拟器编写会在能力缺失时失败的聚焦测试，再实现声明和 UI 呈现。覆盖各阶能力差异、行优先“首个”、多目标攻击与翻面后重检、保护耗内力、保护由其他效果触发、交换前移动反应虽产出事件却打断实际交换、旧天外玉龙能力在此情况下停止后续攻击、重新进场新实例及 20 次上限、叠加来源、双手互搏自我移除被打断后仍授予持续效果、抽牌满手、四侧归零、跨回合上一张手牌、目标翻敌或离场、无行动跳过回合、占位出牌前置移除与失败回滚。用正常模式和测试模式在 540×960 竖屏走受影响的拖牌、攻击、翻面和抽牌路径。

改动前完整基线：2026-09-25 在当前源码与已安装 Summer Engine 上运行 `tools/run_tests.ps1`，84/84 套件通过。实现后先跑聚焦测试，再跑完整套件。修改合法行动枚举或事件热路径前，按仓库要求保留完全匹配的改前源码和 Release native build，同机器同配置同 fixture 做交错 A/B；记录搜索行动、得分、遍历是否一致和相关热点耗时，发现可重复回退立即报告，不把未经测量的改动称作提速。
