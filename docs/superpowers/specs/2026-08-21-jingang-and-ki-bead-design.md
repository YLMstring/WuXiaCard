# 金刚不坏与内力珠分类设计

## 范围

本次实现 `JinGangBuHuai1`–`JinGangBuHuai4` 的完整能力，并把内力珠颜色改为按
当前运行时能力的语义分类。八卦方位永远不显示内力珠。

实现继续以 `DuelSimulator` 为唯一规则路径。卡牌只声明通用事件、条件和 action，
模拟器、搜索与展示代码均不按金刚不坏的卡牌 ID 分支。

## 通用弃牌与同实例回手

新增以下通用声明词汇：

```gdscript
const CARD_ZONE_DISCARD: StringName = &"discard"
const ACTION_DISCARD_CARD: StringName = &"discard_card"
```

`ACTION_DISCARD_CARD` 接受已有的 `card` 精确引用。目标必须仍在手牌中；成功后从
其当前所属方手牌移除同一 Dictionary，追加到该方弃牌区，并发出纯数据
`card_discarded` 事件。弃牌不是移除，不触发 `CARD_BEFORE_EXILED`。

选择器和精确实例定位支持 `CARD_ZONE_DISCARD`。该区域对来源所属方优先，并保持
弃牌数组顺序。

现有 `ACTION_RETURN_CARD_TO_HAND` 增加可选字段：

```gdscript
{
    "type": ACTION_RETURN_CARD_TO_HAND,
    "card": CARD_REF_SELECTED_CARD,
    "recipient": OWNER_CARD_CURRENT,
    "preserve_instance": true,
}
```

默认行为保持不变。仅在 `preserve_instance = true` 且精确目标位于弃牌区时，action
从弃牌区取出原 Dictionary 并追加到目标手牌，保留 `instance_id`、点数、内力和
当前能力。目标手牌已满时不移动，牌仍留在弃牌区。成功后沿用
`card_returned_to_hand` 事件，且 `old_instance_id == instance_id`。

## 翻面被阻止时点

把现有纯数据事件 `card_flip_prevented` 同时注册为可声明的全场触发事件：

```gdscript
const CARD_FLIP_PREVENTED: StringName = &"card_flip_prevented"
```

攻击与非攻击翻面沿用相同顺序：

1. 结算全部 `CARD_BEFORE_FLIPPED` 能力；
2. 若精确目标与预定新所属方匹配一条阻止请求，先发出
   `card_flip_prevented` 纯数据事件；
3. 再以该目标为 trigger card 结算全场 `CARD_FLIP_PREVENTED`，来源按格子
   `0 -> 8`、能力顺序、trigger 顺序依次处理；
4. 不发出 `CARD_AFTER_FLIPPED`。

删除、离场或目标已属于预定新所属方仍只是令翻面失效，不伪装成“翻面被阻止”；
只有显式 `ACTION_PREVENT_TRIGGER_FLIP` 请求产生该时点。

## 金刚不坏 declaration

共用的一级保护能力为：

```gdscript
const JINGANG_DISCARD_PROTECTION: Dictionary = {
    "triggers": [{
        "event": CARD_BEFORE_FLIPPED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_HAND],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
                "limit": 1,
                "required_count": 1,
            },
            "actions": [
                {"type": ACTION_DISCARD_CARD, "card": CARD_REF_SELECTED_CARD},
                {"type": ACTION_PREVENT_TRIGGER_FLIP},
            ],
        }],
    }],
}
```

`JinGangBuHuai1` 使用该能力。选择器从来源当前所属方手牌按索引访问，因此选中
最左侧手牌；空手时 `required_count` 令整个 wrapper 无效果，翻面照常完成。

二至四级使用带抽回的版本：

```gdscript
const JINGANG_DISCARD_PROTECTION_WITH_RECALL: Dictionary = {
    "triggers": [{
        "event": CARD_BEFORE_FLIPPED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_SELF}],
        "actions": [{
            "type": ACTION_FOR_EACH_SELECTED_CARD,
            "selector": {
                "zones": [CARD_ZONE_HAND],
                "conditions": [{"type": CONDITION_SELECTED_CARD_IS_ALLY}],
                "limit": 1,
                "required_count": 1,
            },
            "actions": [
                {"type": ACTION_DISCARD_CARD, "card": CARD_REF_SELECTED_CARD},
                {"type": ACTION_PREVENT_TRIGGER_FLIP},
                {
                    "type": ACTION_SPEND_KI,
                    "amount": 1,
                    "card": CARD_REF_ABILITY_SOURCE,
                    "on_invalid_context": STOP_RULE,
                },
                {
                    "type": ACTION_RETURN_CARD_TO_HAND,
                    "card": CARD_REF_SELECTED_CARD,
                    "recipient": OWNER_CARD_CURRENT,
                    "preserve_instance": true,
                },
            ],
        }],
    }],
}
```

没有内力时，丢牌和阻止翻面已经完成；耗内力返回 `NO_EFFECT` 并以 `STOP_RULE`
停止抽回。`JinGangBuHuai2` 没有初始内力，但以后获得内力时仍可抽回。
`JinGangBuHuai3`、`JinGangBuHuai4` 保持现有一点初始内力。

四级另有独立能力条目：

```gdscript
const JINGANG_PREVENTED_ALLY_RALLY: Dictionary = {
    "triggers": [{
        "event": CARD_FLIP_PREVENTED,
        "conditions": [{"type": CONDITION_TRIGGER_CARD_IS_ALLY}],
        "actions": [
            {
                "type": ACTION_CHANGE_POWERS,
                "amount": 1,
                "card": CARD_REF_TRIGGER_CARD,
            },
            {
                "type": ACTION_STANDARD_ATTACK_WITH_CARD,
                "card": CARD_REF_TRIGGER_CARD,
            },
        ],
    }],
}
```

“友方”包括四级自身。多张四级在场时，每张都按稳定全场顺序触发一次，因此目标
会分别加一点并各发起一次标准攻击；每次成功发起仍计入每方每回合 20 次攻击上限。

## 内力珠分类

卡牌 definition 可声明：

```gdscript
"suppress_ki_bead": true
```

该字段必须是 bool，并复制到运行时实例。`BaGuaFangWei` 声明为 `true`。它优先于
所有能力和内力规则，即使将来获得内力或其它能力也永远不显示珠子。

其余卡牌按当前 `active_abilities` 计算，优先级为：

1. 任一能力递归包含 `ACTION_PREVENT_TRIGGER_FLIP`：`KI_BEAD_GOLD`；
2. 任一能力语义上会移除能力来源自身：新增 `KI_BEAD_GRAY`；
3. 其余保持现有 light、dark、none 规则。

“移除能力来源自身”包括：

- 在能力来源 action 作用域中的 `ACTION_EXILE_SELF`；
- `ACTION_EXILE_CARD` 明确引用 `CARD_REF_ABILITY_SOURCE`；
- trigger 同时声明 `CONDITION_TRIGGER_CARD_IS_SELF`，并对
  `CARD_REF_TRIGGER_CARD` 执行 `ACTION_EXILE_CARD`。

进入 `ACTION_FOR_EACH_SELECTED_CARD` 后，action subject 改为 selected card；其中的
`ACTION_EXILE_SELF` 不自动视为移除能力来源。移除能力条目、回手、重新进场和点数
归零均不属于此分类。递归检查覆盖 activation 的 costs/actions、trigger actions 和
wrapper 内层 actions。能力失去、获得或被临时压制后，颜色随运行时声明立即更新。

灰珠使用以下固定颜色，尺寸、阴影比例、文字内容和数字显示规则不变：

```gdscript
GRAY_KI_BEAD_BACKGROUND = Color("aeb4b2")
GRAY_KI_BEAD_BORDER = Color("e5e8e5")
GRAY_KI_BEAD_SHADOW = Color(0.12, 0.14, 0.14, 0.35)
GRAY_KI_TEXT = Color("303737")
GRAY_KI_TEXT_OUTLINE = Color("dfe3e1")
```

## 展示

`card_discarded` 复用现有卡牌渐隐动画，动画完成后令对应固定手牌槽暂时清空；
这只是展示复用，规则事件仍是弃牌而非 `card_exiled`。对手未揭示的手牌只渐隐
牌背，不泄露卡名或图片。同实例抽回等待渐隐完成，再使用现有回手展示路径重新
填入一个空槽。翻面被阻止事件仍先于四级的加点与攻击展示，因此玩家先看到防御
成立，再看到逐个四级来源响应。

## 测试与验证

新增独立金刚不坏模拟器测试，覆盖：

- 四张卡的完整 declaration；
- 空手时不丢牌、不阻止翻面；
- 最左侧手牌进入当前所属方弃牌区；
- 一级即使有内力也不抽回；
- 二至四级无内力时牌留在弃牌区；
- 有内力时消耗一点并以同一 `instance_id` 抽回；
- 攻击与非攻击翻面共用相同行为；
- 四级响应自身、其它友方和任意其它阻止翻面的能力；
- 多个四级来源按格子顺序分别加点并攻击；
- 删除目标或八卦移除不产生阻止时点。

扩充内力珠测试，覆盖金色大于灰色、灰色大于普通、嵌套 action 的 subject 语义、
运行时能力增减，以及八卦在有内力和被授予能力时仍为 `none`。增加弃牌/抽回的
控制器集成覆盖，并在竖屏对局中检查金、灰、普通三种珠子和八卦隐藏状态。

实施后先运行金刚不坏、catalog、内力珠和相关集成测试，再只运行一次完整套件。
