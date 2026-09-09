# 2026-09-09 最新目录平衡调整设计

## 范围

本次按 `scripts/card_catalog.gd` 当前最新描述同步两项规则：

- `HuJiaDao2`（怀中抱月）的抽牌属于牌手光环本身，不再属于被攻击友方获得的虚拟能力；
- `FeiTian5`（飞天神行）仅在其所属方手牌或场上存在友方刀法时，于所属方回合结束授予一次额外出牌。

不新增目录原语，不修改两张牌的名称、图片、门派、品阶、武器、点数或背景文本，
也不修改牌手光环、额外出牌上限与回合边界的既有通用规则。

## 怀中抱月

牌手光环的受击触发按“揭示来源、来源四边减一、光环持有者抽一张”的顺序结算。
光环赋予友方场上牌的虚拟能力只保留防守点数视为零与受击时移除自身。

完整相关声明为：

```gdscript
const HUJIA_EMBRACE_MOON_GRANTED: Dictionary = {
	"modifiers": [{
		"type": MODIFIER_DEFENDING_POWER_OVERRIDE,
		"value": 0,
	}],
	"triggers": [{
		"event": CARD_BE_ATTACKED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_EXILE_SELF},
		],
	}],
}

const HUJIA_EMBRACE_MOON_AURA: Dictionary = {
	"triggers": [
		{
			"event": CARD_BE_ATTACKED,
			"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
			"actions": [
				{
					"type": ACTION_REVEAL_CARD,
					"card": CARD_REF_ABILITY_SOURCE,
					"observer": OWNER_OPPONENT_OF_ABILITY_SOURCE,
				},
				{
					"type": ACTION_CHANGE_POWERS,
					"amount": -1,
					"card": CARD_REF_ABILITY_SOURCE,
				},
				{"type": ACTION_DRAW_CARDS, "amount": 1},
			],
		},
		HUJIA_OWNER_AURA_EXPIRE,
	],
	"auras": [{
		"selector": {
			"zones": [CARD_ZONE_BOARD],
			"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
		},
		"ability": HUJIA_EMBRACE_MOON_GRANTED,
	}],
}

const HUJIA_EMBRACE_MOON: Dictionary = {
	"triggers": [{
		"event": TRIGGER_DUEL_STARTED,
		"actions": [{
			"type": ACTION_GRANT_OWNER_AURA,
			"aura": HUJIA_EMBRACE_MOON_AURA,
		}],
	}],
}

HuJiaDao2.abilities = [HUJIA_EMBRACE_MOON]
```

当同一牌手持有多份怀中抱月光环时，每份光环都独立揭示、减点并抽一张；随后
第一个仍有效的虚拟受击能力移除被攻击友方，其余虚拟能力因接收牌已离场而失效。
来源因减点归零离开手牌，不会中断已经开始的抽牌动作；光环仍按既有规则在回合
结束时检查并移除。

## 飞天神行

复用 `ACTION_FOR_EACH_SELECTED_CARD` 做存在性查询：依次检查来源所属方手牌与
场上牌，只取第一张友方刀法。找到后以飞天神行本身作为额外出牌来源；找不到则
整个动作无效果。

完整 `abilities` 声明为：

```gdscript
"abilities": [{
	"triggers": [{
		"event": TRIGGER_END_OWNER_TURN,
		"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_HAND, CARD_ZONE_BOARD],
				"conditions": [
					{"type": CONDITION_SELECTED_CARD_IS_ALLY},
					{
						"type": CONDITION_SELECTED_CARD_WEAPON_IS,
						"weapon": "刀法",
					},
				],
				"limit": 1,
			},
			"actions": [{
				"type": ACTION_GRANT_EXTRA_CARD_PLAY,
				"amount": 1,
				"card": CARD_REF_ABILITY_SOURCE,
			}],
		}],
	}],
}]
```

友方刀法可以在手牌或场上；敌方刀法不满足条件。额外出牌继续遵守每名牌手每个
实际回合最多获得一次的通用限制。

## 性能

本次不增加事件类型、触发条件、全局事件发现或修正器查询。飞天神行仅在其自身
合法的回合结束触发已经被发现后执行一次有上限的选择器查询，最多命中一张牌；
怀中抱月只是在现有光环动作列表与虚拟能力之间移动一次抽牌动作。因此无需新增
C++ 热路径或专项固定节点性能对照。

## 测试与交付

- 更新怀中抱月测试，确认减点后由牌手光环抽牌，再移除受击友方；
- 验证多份怀中抱月光环各自抽牌；
- 验证飞天神行在友方刀法位于手牌、位于场上时生效；
- 验证没有友方刀法、只有敌方刀法时不生效；
- 同步东方不败最新敌人卡组的过期测试期望；
- 运行完整自动化套件；
- 静音检查实际游戏启动与相关流程；
- 使用现有 Android Release 脚本导出 ARM64 APK，并核对产物存在、大小与时间戳。
