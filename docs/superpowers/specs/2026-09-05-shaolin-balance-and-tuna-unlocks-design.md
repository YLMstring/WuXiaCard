# 少林平衡调整与吐纳术升阶解锁设计

## 范围

实现当前 `card_catalog.gd` 中三类最新调整：

- `RanMuDaoFa2`、`RanMuDaoFa3` 的主动弃牌强化改为只影响剩余手牌；
- `JinGangBuHuai2` 改为先阻止翻面、再尝试弃牌，并移除复制效果；
- 玩家升到二阶、三阶时，分别优先解锁 `TuNaShu2`、`TuNaShu3`。

所有玩法继续通过目录声明和现有通用原语进入唯一的原生规则路径；搜索、
模拟器和控制器不得按这些卡牌 ID 增加分支。

## 燃木刀法二、三

主动能力维持指定己方手牌、消耗一点内力的入口。成功支付后依次结算：

1. 丢弃指定的确切手牌实例；若目标失效，按现有 `STOP_RULE` 停止，已经支付的
   内力不退还；
2. 从当前所属方手牌选择所有点数可变化的友方牌，四边加一；
3. 获得一次额外手牌出牌。

第二步读取弃牌完整结算后的实时手牌，因此刚被丢弃的牌不再属于手牌，不会
加点；弃牌连锁新加入手牌的牌则属于当时手牌，可以被强化。四边全为 `-1` 的
牌由既有点数可变条件跳过。所有目标使用同一个点数变化批次组，共用一次变化前
停顿并并行动画；未揭示手牌仍遵循当前暗牌展示规则。场上友方不会被这项指定
能力强化。

`RanMuDaoFa3` 独立的攻击后能力保持不变：真实攻击结束后只强化当时场上的
友方牌，不扩大到手牌。

## 山门护法二

`JinGangBuHuai2` 使用独立能力条目，不再复用三、四阶的弃牌复制能力。自身进入
`CARD_BEFORE_FLIPPED` 时依次：

1. 对确切触发牌提交 `ACTION_PREVENT_TRIGGER_FLIP`；
2. 从当前所属方手牌选择物理最左侧的一张牌并丢弃。

第二步不声明 `required_count`。空手时选择器无效果，但第一步已经提交的阻止请求
仍然生效，并照常产生 `CARD_FLIP_PREVENTED`。该牌不消耗内力、不获得复制。

`JinGangBuHuai1` 仍须先成功丢弃最左侧手牌才阻止翻面；`JinGangBuHuai3`、
`JinGangBuHuai4` 的弃牌、阻止、耗内力复制及四阶友方响应保持不变。

`JinGangBuHuai1`、`JinGangBuHuai2` 的目录点数更新为 `[8, 4, 8, 4]`，只需
同步目录与测试，不新增运行时规则。

## 目录原语声明

设计文档必须给出所设计卡牌能力的完整目录原语声明和 `abilities` 组合，不能
只写自然语言或只列出新增字段。本节是本次实现的直接目录依据。

燃木刀法二、三共用的指定能力为：

```gdscript
const RANMU_LOCKED_DISCARD_ACTIVATION: Dictionary = {
	"retained_on_flip": true,
	"activation": {
		"input": ACTIVATION_DRAG_TO_TARGET,
		"target_rule": TARGET_ALLY_HAND_CARD,
		"costs": [{"type": ACTION_SPEND_KI, "amount": 1}],
		"actions": [
			{
				"type": ACTION_DISCARD_CARD,
				"card": CARD_REF_SELECTED_CARD,
				"on_invalid_context": STOP_RULE,
			},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
						{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
					],
				},
				"power_change_batch_group": &"ranmu_all_allies",
				"actions": [{
					"type": ACTION_CHANGE_POWERS,
					"amount": 1,
					"card": CARD_REF_SELECTED_CARD,
				}],
			},
			{"type": ACTION_GRANT_EXTRA_CARD_PLAY, "amount": 1},
		],
	},
}
```

燃木刀法三独立的攻击后能力保持完整声明如下：

```gdscript
const RANMU_AFTER_ATTACK_BUFF: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_ATTACK,
		"conditions": [{"type": CONDITION_ATTACKER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					{"type": CONDITION_SELECTED_CARD_POWERS_CAN_CHANGE},
				],
			},
			"power_change_batch_group": &"ranmu_all_allies",
			"actions": [{
				"type": ACTION_CHANGE_POWERS,
				"amount": 1,
				"card": CARD_REF_SELECTED_CARD,
			}],
		}],
	}],
}
```

山门护法二使用新的独立能力，不声明 `required_count`：

```gdscript
const JINGANG_PREVENT_THEN_DISCARD: Dictionary = {
	"triggers": [{
		"event": CARD_BEFORE_FLIPPED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_PREVENT_TRIGGER_FLIP},
			{
				"type": ACTION_FOR_EACH_SELECTED_CARD,
				"selector": {
					"zones": [CARD_ZONE_HAND],
					"conditions": [
						{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					],
					"limit": 1,
				},
				"actions": [{
					"type": ACTION_DISCARD_CARD,
					"card": CARD_REF_SELECTED_CARD,
				}],
			},
		],
	}],
}
```

三个目录条目的能力组合固定为：

```gdscript
&"RanMuDaoFa2": {
	# 其余目录字段省略。
	"abilities": [RANMU_LOCKED_DISCARD_ACTIVATION],
},
&"RanMuDaoFa3": {
	# 其余目录字段省略。
	"abilities": [RANMU_AFTER_ATTACK_BUFF, RANMU_LOCKED_DISCARD_ACTIVATION],
},
&"JinGangBuHuai2": {
	# 其余目录字段省略。
	"abilities": [JINGANG_PREVENT_THEN_DISCARD],
},
```

吐纳术升阶解锁属于存档推进逻辑，不是卡牌能力；不得为它伪造目录原语。

## 吐纳术升阶解锁

角色阶级沿用现有等级门槛：等级 2 进入二阶，等级 5 进入三阶。胜利推进跨越
门槛时，构造有序的主要解锁列表：

- 进入二阶：`TuNaShu2`，随后是当前门派全部二阶牌；
- 进入三阶：`TuNaShu3`，随后是当前门派全部三阶牌。

四阶、五阶的自动解锁保持现状。解锁扩展继续负责去重：吐纳术已经解锁时直接
跳过，不重复进入牌库或 `added_ids`。主要解锁按上述顺序进入牌库顶部，继承的
同名低阶牌仍按既有规则追加到牌库底部。

自动解锁发生在本场胜利推进并保存时，早于下一次奖励生成，因此新解锁的吐纳术
和门派牌都不会进入紧接着的随机奖励。牌库容量不足或存档失败时，继续沿用当前
原子失败与回滚行为。

## 测试与文档

- 少林弃牌能力测试覆盖燃木主动能力只强化剩余手牌、跳过弃牌实例和四边 `-1`，
  不强化场上友方，并确认攻击后能力仍只影响棋盘。
- 金刚不坏测试覆盖二阶有手牌和空手两种防翻、无内力消耗、无复制，以及一、三、
  四阶行为不变。
- 存档测试覆盖二阶和三阶解锁顺序、去重、牌库顶部顺序及奖励池排除。
- 更新当前交接与规则文档，历史规格保留为历史记录。
- 先运行相关聚焦测试，再运行完整测试套件。
