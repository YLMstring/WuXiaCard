# Sect Catalog Design

## Goal

Add a data-only catalog containing five fictional sects. Sect definitions will be compatible with the existing card-inspection display contract, but they will not participate in decks, duels, card ownership, powers, abilities, or any other gameplay system.

## Architecture

Create `scripts/sect_catalog.gd` as a `RefCounted` catalog following the established `CardCatalog` conventions:

- An ordered `ALL_SECT_IDS` array of stable `StringName` IDs.
- A private dictionary containing one definition per ID.
- `has_sect(sect_id)`.
- `get_all_sect_ids()`, returning a defensive copy.
- `get_definition(sect_id)`, returning a deep defensive copy.
- `validate_definition(definition, sect_id)`.
- `validate_catalog()`.

The catalog remains independent from `CardCatalog` and gameplay code. Reuse comes from sharing the inspector-facing dictionary contract rather than treating sects as playable card instances.

## Definition Schema

Every sect definition contains exactly these display fields:

- `id: StringName` — stable catalog identity.
- `glyph: String` — sect name.
- `picture: String` — temporary path to an existing project image.
- `sect: String` — the sect's home region.
- `tier: int` — the sect's prestige.
- `weapon: String` — the sect's signature specialty.
- `description: String` — doctrine and practical overview.
- `flavor: String` — history, motto, or atmosphere.

The field names and types match the metadata consumed by `CardInspector.present()`. No sect definition contains `powers`, `abilities`, `starting_ki`, ownership, or runtime instance state.

## Initial Definitions

### `xuanyue_jianzong`

- `glyph`: 玄岳剑宗
- `picture`: `res://pics/LKT010_568.png`
- `sect`: 北岳玄岭
- `tier`: 5
- `weapon`: 剑阵
- `description`: 玄岳剑宗奉行“众锋同心”，弟子以步法牵引剑势，擅长多人结阵、封锁退路，并在严寒山势中磨炼持久战法。
- `flavor`: 宗门立于终年积雪的玄岭之巅。每逢朔月，山门百剑齐鸣，传说那是历代剑主仍在风中校正后辈的锋芒。

### `yanyu_lou`

- `glyph`: 烟雨楼
- `picture`: `res://pics/LKT010_002.png`
- `sect`: 江南水乡
- `tier`: 4
- `weapon`: 暗器
- `description`: 烟雨楼讲究藏锋于柔，以水巷、舟桥与薄雾掩护身形，门人精于细小暗器、情报传递和不留痕迹的牵制。
- `flavor`: 楼中没有永远点亮的灯，只有雨夜偶尔响起的铜铃。江湖人说，听见第三声时，烟雨楼早已知道你为何而来。

### `chisha_men`

- `glyph`: 赤砂门
- `picture`: `res://pics/LKT010_003.png`
- `sect`: 西域赤沙
- `tier`: 3
- `weapon`: 刀法
- `description`: 赤砂门崇尚直取胜机，刀法借旋风与流沙之势不断变向，重视体魄、耐渴训练和在恶劣地形中的迅猛突袭。
- `flavor`: 门中弟子入门时要独自穿过一片红色沙海。归来者把第一捧赤砂封入刀柄，以提醒自己绝不畏惧无路可走。

### `tingchao_gu`

- `glyph`: 听潮谷
- `picture`: `res://pics/LKT010_004.png`
- `sect`: 东海群岛
- `tier`: 4
- `weapon`: 掌法
- `description`: 听潮谷以潮汐悟劲，掌法时缓时急，善于卸去正面冲击，再以层叠内劲反攻。门人也精通舟行与水上身法。
- `flavor`: 谷中石壁布满天然孔洞，涨潮时会奏出低沉长音。掌门择徒不问出身，只问来者能否听出潮声中的第七次回响。

### `bailu_shuyuan`

- `glyph`: 白鹿书院
- `picture`: `res://pics/LKT010_005.png`
- `sect`: 中州鹿鸣山
- `tier`: 2
- `weapon`: 奇门
- `description`: 白鹿书院主张先明理而后用武，将机关、阵图与经义融为奇门之术。门人正面武力不盛，却擅长准备、推演和改变战场条件。
- `flavor`: 书院藏书楼前常有白鹿出没，从不畏人。院中旧规写道：“能胜一局者可学术，能止一战者方可传道。”

## Validation

Catalog validation reports errors for:

- Empty catalog IDs, duplicate IDs, missing definitions, or unlisted definitions.
- A definition whose `id` does not match its catalog key.
- Missing, incorrectly typed, or empty string display fields.
- Empty or excessively long `glyph` values; use the card catalog's current 1–7 character title limit.
- A non-integer or non-positive `tier`.
- A missing picture resource.
- Unsupported fields, including playable-card fields such as `powers` and `abilities`.

## Testing

Add `tests/test_sect_catalog.gd` and include it in the project test runner. Tests cover:

- The production catalog validates without errors.
- Exactly five sect IDs exist in the approved order.
- Every definition resolves and contains the approved nonempty metadata.
- Every picture path exists.
- IDs are unique and match their definitions.
- Prestige values are positive integers.
- Invalid schemas produce validation errors.
- Mutating an ID list or returned definition does not mutate catalog storage.
- Sect definitions omit playable-card fields.

No scene, inspector, deck, duel, or save-profile integration is included in this change.
