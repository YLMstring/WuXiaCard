# Twenty Sect Cards Design

## Goal

Add twenty explicit placeholder cards to `CardCatalog`, divided evenly among the five entries in `SectCatalog`. The cards have no abilities, but every other required card field is populated. They are locked by default, remain absent from both new and existing profile libraries, and still join the global side-deck pool.

## Organization

Add all IDs and definitions directly to `scripts/card_catalog.gd`. This follows the current explicit catalog pattern and avoids introducing data-merging machinery for placeholder content.

Each definition contains:

- `id`
- `glyph`
- `picture`
- `sect`
- `tier`
- `weapon`
- `description`
- `flavor`
- four integer `powers`
- `abilities: []`

The authored tiers stay within the current prestige of the corresponding sect, but neither production validation nor tests enforce a relationship between card tier and sect prestige.

## Card Definitions

### 玄岳剑宗

#### `hanfeng_liezhen`

- `glyph`: 寒峰列阵
- `picture`: `res://pics/LKT010_011.png`
- `sect`: 玄岳剑宗
- `tier`: 1
- `weapon`: 剑阵
- `description`: 依山势错步列锋，以数道交叠剑路封住对手的进退方向。
- `flavor`: 玄岭初雪时，外门弟子会在石阶上反复排阵，直到每一道足印都被风重新抹平。
- `powers`: `[4, 5, 3, 6]`

#### `huixue_liuguang`

- `glyph`: 回雪流光
- `picture`: `res://pics/LKT010_012.png`
- `sect`: 玄岳剑宗
- `tier`: 2
- `weapon`: 剑阵
- `description`: 剑锋随回旋步法折返，前一道寒光未散，后一道剑势已从侧面掩至。
- `flavor`: 相传此式创于一场大雪，祖师只出一剑，崖边积雪却绕身三周方才落地。
- `powers`: `[6, 3, 5, 4]`

#### `qiyao_lianfeng`

- `glyph`: 七曜连锋
- `picture`: `res://pics/LKT010_013.png`
- `sect`: 玄岳剑宗
- `tier`: 3
- `weapon`: 剑阵
- `description`: 七处剑位首尾呼应，任一处受阻，其余剑势便立刻补上缺口。
- `flavor`: 剑坪上的七盏铜灯从不同时熄灭，那是玄岳弟子留给夜归同门的路标。
- `powers`: `[7, 5, 6, 4]`

#### `wanyue_guizong`

- `glyph`: 万岳归宗
- `picture`: `res://pics/LKT010_014.png`
- `sect`: 玄岳剑宗
- `tier`: 5
- `weapon`: 剑阵
- `description`: 收束四方剑势于一点，以沉雄如山的正锋压垮对手最后的守势。
- `flavor`: 历代宗主继位时皆要独登万仞台。下山之后，他们从不再谈那一夜看见了什么。
- `powers`: `[8, 7, 5, 8]`

### 烟雨楼

#### `yuyan_tousuo`

- `glyph`: 雨燕投梭
- `picture`: `res://pics/LKT010_015.png`
- `sect`: 烟雨楼
- `tier`: 1
- `weapon`: 暗器
- `description`: 借袖口遮掩投出细梭，轨迹轻捷多变，如雨燕贴水掠行。
- `flavor`: 烟雨楼的铜梭从不刻名，只在尾端留一道浅痕，方便主人在暗处以指腹辨认。
- `powers`: `[3, 6, 4, 5]`

#### `wusuo_changqiao`

- `glyph`: 雾锁长桥
- `picture`: `res://pics/LKT010_016.png`
- `sect`: 烟雨楼
- `tier`: 2
- `weapon`: 暗器
- `description`: 以烟丸遮断视线，再从桥栏、瓦隙与水面反射中寻找出手角度。
- `flavor`: 江南有座无名旧桥，每逢晨雾便少一块青砖，却从来没人见过取砖的人。
- `powers`: `[5, 4, 6, 3]`

#### `feixing_ruye`

- `glyph`: 飞星入夜
- `picture`: `res://pics/LKT010_017.png`
- `sect`: 烟雨楼
- `tier`: 3
- `weapon`: 暗器
- `description`: 连续掷出明暗两组星镖，以可见寒芒诱使对手忽略真正的杀机。
- `flavor`: 楼中弟子说，最亮的星只负责引路，真正决定归途的那一颗从不发光。
- `powers`: `[7, 3, 5, 6]`

#### `qianji_tingyu`

- `glyph`: 千机听雨
- `picture`: `res://pics/LKT010_018.png`
- `sect`: 烟雨楼
- `tier`: 4
- `weapon`: 暗器
- `description`: 从雨声的细微变化判断周围动静，并以连环机括封锁多个方位。
- `flavor`: 暴雨之夜，烟雨楼主常独坐檐下。若茶盏中的涟漪忽然停住，整座楼便会同时熄灯。
- `powers`: `[6, 8, 4, 7]`

### 赤砂门

#### `hengsha_duanlu`

- `glyph`: 横沙断路
- `picture`: `res://pics/LKT010_019.png`
- `sect`: 赤砂门
- `tier`: 1
- `weapon`: 刀法
- `description`: 横刀卷起沙尘迫使对手停步，再以宽阔刀势截断前路。
- `flavor`: 赤砂门的第一堂刀课不教劈砍，只教弟子在风沙里睁着眼睛看清来路。
- `powers`: `[6, 4, 3, 5]`

#### `chilian_huifeng`

- `glyph`: 赤练回风
- `picture`: `res://pics/LKT010_020.png`
- `sect`: 赤砂门
- `tier`: 1
- `weapon`: 刀法
- `description`: 短促旋身带动刀锋折返，能在一次进势中兼顾前后两面。
- `flavor`: 门中刀穗皆以赤练草编成，草叶越旧，颜色反而越深。
- `powers`: `[4, 6, 5, 3]`

#### `shahai_zhuri`

- `glyph`: 沙海逐日
- `picture`: `res://pics/LKT010_021.png`
- `sect`: 赤砂门
- `tier`: 2
- `weapon`: 刀法
- `description`: 以不停歇的追击积累气势，刀路随着步幅逐渐放大，逼迫对手正面应战。
- `flavor`: 赤砂门人远行不带日晷，他们看刀背上的光，便知道自己还能追多久。
- `powers`: `[7, 5, 4, 6]`

#### `damo_guzhan`

- `glyph`: 大漠孤斩
- `picture`: `res://pics/LKT010_022.png`
- `sect`: 赤砂门
- `tier`: 3
- `weapon`: 刀法
- `description`: 摒弃多余变化，将全身力量凝于一次孤绝重斩，以气魄先破敌胆。
- `flavor`: 大漠深处立着半截黑色石碑，上面只有一道刀痕，百年来无人知道另一半去了哪里。
- `powers`: `[8, 4, 7, 5]`

### 听潮谷

#### `dielang_tuizhou`

- `glyph`: 叠浪推舟
- `picture`: `res://pics/LKT010_023.png`
- `sect`: 听潮谷
- `tier`: 1
- `weapon`: 掌法
- `description`: 连续送出轻重不同的掌劲，后劲推前劲，如叠浪托舟而行。
- `flavor`: 谷中孩童学会走路后，先要学会在小舟上站稳，才会正式拜师。
- `powers`: `[5, 3, 6, 4]`

#### `huichao_tingjin`

- `glyph`: 回潮听劲
- `picture`: `res://pics/LKT010_024.png`
- `sect`: 听潮谷
- `tier`: 2
- `weapon`: 掌法
- `description`: 以掌心感知来力方向，先顺势卸劲，再借回潮之势反送回去。
- `flavor`: 听潮谷的练功石没有一块完整，裂纹却都朝向海面。
- `powers`: `[4, 6, 3, 7]`

#### `canghai_sandie`

- `glyph`: 沧海三叠
- `picture`: `res://pics/LKT010_025.png`
- `sect`: 听潮谷
- `tier`: 3
- `weapon`: 掌法
- `description`: 三重掌劲间隔而至，第一重开势，第二重乱息，第三重方显真正威力。
- `flavor`: 海上老船工最怕无风时忽然出现三道浪，因为那往往意味着听潮谷有人在远处试掌。
- `powers`: `[7, 6, 5, 4]`

#### `haitian_yizhang`

- `glyph`: 海天一掌
- `picture`: `res://pics/LKT010_026.png`
- `sect`: 听潮谷
- `tier`: 4
- `weapon`: 掌法
- `description`: 心息与潮声合一，将繁复变化归于平直一掌，势如海天相接而无处可避。
- `flavor`: 谷主闭关之处面朝东海，门前没有守卫，只有一道永远不会越过门槛的潮线。
- `powers`: `[8, 5, 7, 6]`

### 白鹿书院

#### `zhujian_cangfeng`

- `glyph`: 竹简藏锋
- `picture`: `res://pics/LKT010_027.png`
- `sect`: 白鹿书院
- `tier`: 1
- `weapon`: 奇门
- `description`: 将细小机关藏入成束竹简，展开阵图时也能出其不意地牵制近身之敌。
- `flavor`: 书院借出的竹简总会如数归还，只是偶尔会多出一片无人认得字迹的新简。
- `powers`: `[3, 5, 4, 6]`

#### `luming_wenlu`

- `glyph`: 鹿鸣问路
- `picture`: `res://pics/LKT010_028.png`
- `sect`: 白鹿书院
- `tier`: 1
- `weapon`: 奇门
- `description`: 以声响和标记试探周围变化，逐步排除虚路，找到阵势中唯一的生门。
- `flavor`: 山中白鹿从不踏进死路。书院弟子跟随它们多年，却仍不明白究竟是谁在为谁引路。
- `powers`: `[5, 4, 6, 3]`

#### `jingwei_dingju`

- `glyph`: 经纬定局
- `picture`: `res://pics/LKT010_029.png`
- `sect`: 白鹿书院
- `tier`: 2
- `weapon`: 奇门
- `description`: 以纵横线位划分战场，预先安排机关与退路，使对手的每一步都落入推演。
- `flavor`: 院中棋盘没有黑白子，只有长短不同的木筹，因为胜负从来不只分成两边。
- `powers`: `[6, 7, 4, 5]`

#### `zhishang_shanhe`

- `glyph`: 纸上山河
- `picture`: `res://pics/LKT010_030.png`
- `sect`: 白鹿书院
- `tier`: 2
- `weapon`: 奇门
- `description`: 将地形、敌我与时机绘入一卷阵图，以周密布置弥补正面力量的不足。
- `flavor`: 书院地窖藏着一幅从未完成的天下图，据说每当江湖格局改变，纸上便会自行多出一道墨痕。
- `powers`: `[7, 5, 6, 4]`

## Unlocking and Runtime Behavior

Add all twenty IDs to `DeckProfileStore.DEFAULT_LOCKED_IDS`.

- New profiles do not place them in the main deck or library.
- Existing profiles do not gain them automatically.
- The default five-card main deck remains unchanged.
- `DuelDecks.get_side_deck_card_ids()` continues to return every catalog card, so the side deck grows from 10 to 30 cards and includes these locked cards.
- No ability, trigger, action, activation, ki, or new gameplay rule is introduced.

## Validation and Testing

Update existing tests to cover:

- `CardCatalog` contains 30 unique ordered IDs.
- All twenty picture resources exist and are distinct.
- All new string metadata is present and nonempty.
- Every new card has four integer powers and an empty ability array.
- Definition getters continue to return defensive copies.
- Default profiles keep the twenty new IDs locked.
- Existing valid profiles remain unchanged by repair/loading.
- The side-deck getter returns all 30 catalog IDs defensively.
- Fixed catalog-count expectations in integration tests are updated from 10 to 30 where appropriate.

Do not add a production or test dependency from `CardCatalog` to `SectCatalog`, and do not enforce card tier against sect prestige.
