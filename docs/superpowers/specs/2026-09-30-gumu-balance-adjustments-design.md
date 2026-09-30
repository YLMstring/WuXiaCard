# 古墓派三组卡牌平衡调整（2026-09-30）

## 规则和范围

以用户当前目录为准，实装天罗地网、夭矫空碧、小园艺菊。沿用统一下一张手牌赋能队列、同名赋予者延后、手牌/弃牌来源区分以及现有攻击尝试规则。

- 天罗地网二至四阶：自己及下一张从手牌打出的牌获得锁定的敌方移动后四侧减二。保留四阶复制后天现存能力，不能额外复制一次自身刚赋予的减点能力。
- 夭矫空碧一阶只让自己回避；二至四阶让被攻击的友方回避（包含自己）。优先棋盘序首个攻击范围外相邻空格，没有则用首个相邻空格。三、四阶继续在每次尝试额外出牌前抽牌，包括已达上限的尝试。仅四阶在实际移动失败时移除被攻击的实例，不移除赋予保护的另一张牌。
- 小园艺菊一、二阶仍是回合结束恢复的暂时失去非锁定效果；三、四阶是永久失去非锁定效果，仍在下一张手牌进场前执行。三阶不再生成玉女无锋；四阶进场时、己方手牌没有玉女无锋且存在空位才生成。生成、双攻击、点数不足减点和队列赋能是独立能力。

## 最小实现

永久失效直接组合现有 FOR_EACH_SELECTED_CARD 与 PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES。锁定能力照常保留，且不影响友方、手牌或其它区域。

现有 IF 无法读取动作实际结果；检查是否存在空格不能涵盖移动前效果阻断。仅扩展 MOVE_SELF_TO_FIRST_ADJACENT_EMPTY 的可选 `on_no_effect` 非空动作数组，复用 CompiledAction.child_actions 和既有动作执行器。在有效移动目标无相邻空格、或移动流程真正返回 NO_EFFECT 时执行该数组。成功移动（即使仍在攻击范围内）不执行；UNSUPPORTED 传播错误，失效事件引用不执行。后续动作按实例引用定位，已被其它效果移除的实例不会重复移除。原有 STOP_RULE 继续基于组合动作返回值处理。

不新增动作或条件 opcode，不增加紧凑状态/sideload 字段，不添加卡名判断，也不扩大事件发现扫描。未声明失败分支的卡保持原行为；分支检查只位于这个移动 opcode 中。

## 完整能力声明

以下为全部参与数组的能力；未注明锁定的能力保持默认翻面丢失。生成能力的历史名称 GUMU_TIER_THREE_ADD_YUNV 不作无关重命名，四阶复用其通用规则。

```gdscript
const LOCKED_ATTACK_EVASION: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_BE_ATTACKED,
		"conditions": [
			{"type": CONDITION_TRIGGER_CARD_IS_SELF},
			{"type": CONDITION_SOURCE_HAS_ADJACENT_EMPTY_CELL},
		],
		"actions": [
			{
				"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
				"prefer_outside_attacker_range": true,
			},
		],
	}],
}

const GUMU_SUPPRESS_ENEMIES_BEFORE_SUMMON: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
			},
			"actions": [{"type": ACTION_TEMPORARILY_REMOVE_NON_RETAINED_ABILITIES}],
		}],
	}],
}

const GUMU_ATTACK_EACH_TARGET_TWICE: Dictionary = {
	"modifiers": [{"type": MODIFIER_ATTACK_EACH_TARGET_TWICE}],
}

const GUMU_WEAKEN_TARGET_ON_POWER_FAILURE: Dictionary = {
	"modifiers": [{"type": MODIFIER_WEAKEN_TARGET_ON_POWER_FAILURE}],
}

const GUMU_QUEUE_NEXT_SUPPRESSION: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
			"ability": GUMU_SUPPRESS_ENEMIES_BEFORE_SUMMON,
		}],
	}],
}

const GUMU_TIER_THREE_ADD_YUNV: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_ADD_CARD_TO_HAND,
			"card_id": &"YuNvWuFeng",
			"recipient": RECIPIENT_SELF,
			"only_if_absent": true,
		}],
	}],
}

const GUMU_DRAW_BEFORE_EXTRA_PLAY_ATTEMPT: Dictionary = {
	"triggers": [{
		"event": TRIGGER_EXTRA_CARD_PLAY_GRANTED,
		"conditions": [{"type": CONDITION_TURN_OWNER_IS_SELF}],
		"actions": [{"type": ACTION_DRAW_CARDS, "amount": 1}],
	}],
}

const GUMU_ALLY_ATTACK_EVASION: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_BE_ATTACKED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [{
			"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
			"card": CARD_REF_TRIGGER_CARD,
			"prefer_outside_attacker_range": true,
		}],
	}],
}

const GUMU_ENEMY_MOVE_WEAKEN: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_AFTER_MOVED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ENEMY}],
		"actions": [{"type": ACTION_CHANGE_POWERS, "amount": -2,
		             "card": CARD_REF_TRIGGER_CARD}],
	}],
}

const GUMU_TIANLUO_QUEUE: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_GRANT_ABILITY_TO_SELF,
			 "ability": GUMU_ENEMY_MOVE_WEAKEN},
			{"type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
			 "ability": GUMU_ENEMY_MOVE_WEAKEN},
		],
	}],
}

const GUMU_TIANLUO_QUEUE_WITH_ACQUIRED: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [
			{"type": ACTION_GRANT_ABILITY_TO_SELF,
			 "ability": GUMU_ENEMY_MOVE_WEAKEN},
			{"type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
			 "ability": GUMU_ENEMY_MOVE_WEAKEN,
			 "include_acquired_from": CARD_REF_ABILITY_SOURCE,
			 "exclude_ability": GUMU_ENEMY_MOVE_WEAKEN},
		],
	}],
}

const GUMU_REMOVE_ENEMIES_BEFORE_SUMMON: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_BEFORE_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_FOR_EACH_SELECTED_CARD,
			"selector": {
				"zones": [CARD_ZONE_BOARD],
				"conditions": [{"type": CONDITION_SELECTED_CARD_IS_ENEMY}],
			},
			"actions": [{"type": ACTION_PERMANENTLY_REMOVE_NON_RETAINED_ABILITIES, "card": CARD_REF_SELECTED_CARD}],
		}],
	}],
}

const GUMU_QUEUE_NEXT_PERMANENT_SUPPRESSION: Dictionary = {
	"triggers": [{
		"event": TRIGGER_CARD_AFTER_SUMMONED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
		"actions": [{
			"type": ACTION_QUEUE_NEXT_HAND_PLAY_ABILITY,
			"ability": GUMU_REMOVE_ENEMIES_BEFORE_SUMMON,
		}],
	}],
}

const GUMU_ALLY_ATTACK_EVASION_OR_EXILE: Dictionary = {
	"retained_on_flip": true,
	"triggers": [{
		"event": CARD_BE_ATTACKED,
		"conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
		"actions": [{
			"type": ACTION_MOVE_SELF_TO_FIRST_ADJACENT_EMPTY,
			"card": CARD_REF_TRIGGER_CARD,
			"prefer_outside_attacker_range": true,
			"on_no_effect": [{"type": ACTION_EXILE_CARD, "card": CARD_REF_TRIGGER_CARD}],
		}],
	}],
}
```

## 精确 abilities 数组

```gdscript
&"XiaoYuanYiJu1": {"abilities": [GUMU_QUEUE_NEXT_SUPPRESSION],},
&"XiaoYuanYiJu2": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_SUPPRESSION],},
&"XiaoYuanYiJu3": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_PERMANENT_SUPPRESSION],},
&"XiaoYuanYiJu4": {"abilities": [GUMU_TIER_THREE_ADD_YUNV, GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_QUEUE_NEXT_PERMANENT_SUPPRESSION],},
&"KongBi1": {"abilities": [LOCKED_ATTACK_EVASION],},
&"KongBi2": {"abilities": [GUMU_ALLY_ATTACK_EVASION],},
&"KongBi3": {"abilities": [GUMU_DRAW_BEFORE_EXTRA_PLAY_ATTEMPT, GUMU_ALLY_ATTACK_EVASION],},
&"KongBi4": {"abilities": [GUMU_DRAW_BEFORE_EXTRA_PLAY_ATTEMPT, GUMU_ALLY_ATTACK_EVASION_OR_EXILE],},
&"TianLuoDiWang2": {"abilities": [GUMU_TIANLUO_QUEUE],},
&"TianLuoDiWang3": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_TIANLUO_QUEUE],},
&"TianLuoDiWang4": {"abilities": [GUMU_ATTACK_EACH_TARGET_TWICE, GUMU_WEAKEN_TARGET_ON_POWER_FAILURE, GUMU_TIANLUO_QUEUE_WITH_ACQUIRED],},
```

## 验证

回归覆盖真实移动后两份减二、翻面后双方关系变化、四阶不重复复制减点；夭矫空碧自己/其它友方、无空格、移动前生成牌占用空格、成功移动但仍在攻击范围内；小园艺菊等待下一张手牌、锁定保留、友方不受影响、回合结束临时恢复/永久不恢复、三阶不生成/四阶条件生成。

扩展声明需覆盖非法失败数组和非法子动作，执行完整目录原生编译审计、相关规则/搜索/集成测试及全套。静音在540×960生产控制器路径观察移动、移除、能力失效及数值变化动画。保留当前源代码和匹配 Release DLL，在相同固定节点夹具下交错运行新旧 DLL，记录动作、分数、节点、转移数量和时间，不宣称未经测量的提速。

## 已知基线

实施前全套有5个失败套件：古墓能力测试仍预期小园艺菊三阶生成玉女；另外4个分别是敌人目录测试固定无影客十级，以及敌人等级变化导致AI基准/状态键/紧凑状态的历史开局数量断言失效。本任务修订古墓规则测试，其余单独记录，不改动用户已调整的敌人目录。

## 实施验证结果

- 古墓针对性测试257项通过；新增行为夹具在实施前有6项预期失败，实施后消除。
- 完整套件83/87通过，剩余4个失败均与实施前相同，详见已知基线；未新增失败套件。
- 静音竖屏生产控制器检查：无空格时被攻击实例移除且原格视图清除；有空格时移至相邻格且不进入移除区；下一张手牌让敌方仅保留锁定能力；四阶小园艺菊生成玉女；实际移动敌牌四侧由7变5。运行诊断0错误，现有4个编译警告和1个编辑器UID警告单独保留。

Release/template_debug 原生库固定节点对照保存在
`.summer/local/gumu-balance-20260930/`：保留实施前C++源码、目录及DLL，隔离项目
使用同一份实施前目录，确保测试的是原语扩展开销而非新平衡规则的搜索树变化。
三个夹具分别覆盖普通出牌、友方攻击回避、移动后减点；每次5000节点，最多20层，
开启PV、history、8MiB置换表和分项计时。按旧/新/新/旧运行，每轮每夹具预热一次、
采样五次，共60个样本。动作、分数、完成深度、节点、转移数和剪枝数全部一致。

| 夹具 | 旧库中位秒数 | 新库中位秒数 | 时间变化 |
| --- | ---: | ---: | ---: |
| 普通出牌 | 0.349039 | 0.340665 | -2.40% |
| 友方攻击回避 | 0.393760 | 0.399781 | +1.53% |
| 移动后减点 | 0.325531 | 0.320464 | -1.56% |

回避夹具两轮新库中位数分别0.389427/0.414082秒，旧库0.395650/0.391869秒，
方向不一致；这轮对照未观察到可重复退化，也不据此宣称提速。
对照没有衡量新四阶失败移除或永久去效引起的策略树/胜率变化。

旧库SHA256：`06D0426EFD23C3E3D8E87ECAFBD7EC89CC8C0F042A10077544145670A8BB3590`。
新库SHA256：`B1C082F7503075EEA143DD4122557F6A99F74C0B097DC27865AB0DB6A0E0D627`。
