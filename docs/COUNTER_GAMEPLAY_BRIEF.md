# 克制玩法四件套 — 实现 brief

设计参考：`docs/zombie-siege-genre-ideas.md` §2 #1/#2/#3/#13 + 手感反馈；现有 Boss 覆甲/再生已在线上。

目标：**让玩家看懂并被迫换枪**。四项全做完、测过、合并 `main`、部署 Pages 后再收工。

## 分支与流程
- 从最新 `main` 开 `feature/counter-gameplay`
- **分期 commit**（建议）：
  1. `feat: wave preview, weakness tags, counter hit feedback + weapon loadout slots`
  2. `feat: element synergies (wet/shatter/quench)`
  3. `feat: danger levels and stackable contracts`
  4. docs/README + harness 补测（可并进上一笔）
- 中文改完：
  ```
  /tmp/zombie-siege-phase1/venv/bin/python -I tools/build_font.py \
    /private/tmp/zs-font-dl/x/fusion-pixel-12px-proportional-zh_hans.ttf
  godot --headless --path . -- --fontcheck=$PWD/tools/font_chars.txt
  ```
  若完整字体或 venv 丢了：按一期方式重下 Fusion Pixel 12px proportional zh_hans，或 `python3 -m venv` + `pip install fonttools` 再建；阻塞写 REPORT。
- 代理：`export HTTPS_PROXY=http://127.0.0.1:7897 HTTP_PROXY=http://127.0.0.1:7897 ALL_PROXY=socks5://127.0.0.1:7897`
- 同一动作失败 **两次就停**，写 `/tmp/zombie-siege-counter/REPORT.md`
- **测过**再 merge `main` 并 `tools/deploy_pages.sh`；再 `git push origin main feature/counter-gameplay`（与上次不同：这次要推 main）
- 日志目录：`/tmp/zombie-siege-counter/`

## 禁止
- 新 Boss / 新精英杂兵 / 武器进化 / 商店锁定刷新（那些是 P1）
- 大拆架构；别改坏现有 8 Boss 与偶数波节奏
- 不要用 user-X / 付费 API

---

## Commit 1 — 预告 + 弱点 + 命中反馈 + 枪槽上限

### 1A. 下波预告（商店）
现状：`shop_menu.refresh` 标题已有「下一波：第 N 波 NAME」+ `events.forecast_text()`。

补强（UI 紧凑，别撑爆 480 宽屏）：
- 在标题下方或 `status_label` 旁加一行 **情报**：
  - 怪种摘要：按 `GameData.WAVES[next]` 列出主要 kind 中文名×数量（合并小类，最多显示 5 项，如「普通×8 快跑×4 巨像×1」）
  - 若有 Boss kind：前缀「Boss：覆甲巨像」并用现有 `wave_hint(next)` 缩短显示（一行截断）
  - 出怪方向：若现有 spawn 逻辑有边（top/bottom/left/right）可预告「多从上方」；**没有就写「四边」或省略**，不要硬编
- 新开局第一波前若没有商店，可在倒计时 HUD 旁用现有 `wave_hint`（已有则不动）

辅助：在 `GameData` 加 `wave_preview(wave) -> Dictionary`（name/hint/kinds[{id,name,count}]/boss_kind），商店与 harness 共用。

### 1B. 弱点标签
- 给 `GameData.ZOMBIES` / Boss 条目加可选字段 `"weak": "霰弹/狙击/榴弹"` 这类短标签（中文，用 `/` 分隔）。没有就从图鉴 `tip` 推一行「怕：…」也可，但 **优先显式 weak**。
- 覆盖至少：shielder、colossus、graveborn、burrowlord、mirror、plague、boss(屠夫)、overlord、tank、balloon、summoner、screamer、vanguard — 与现有 tip 一致，别发明新克制。
- **图鉴** `bestiary.gd`：在 desc/tip 下画「怕：{weak}」（橙色）
- **击杀掉落/击杀瞬间**（可选轻量）：首次打死某 kind 时 `fx.text(..., "解锁图鉴", ...)` 已有则跳过；至少保证图鉴能看到 weak
- 解锁：沿用现有 bestiary 解锁逻辑；没有「首次击杀解锁」就保持全开，只加标签

### 1C. 克制命中反馈
已有：`fx.number` / `fx.text`；覆甲 `absorb` 轻伤时 `_say(..., "装甲挡住了", 灰)`。

改成玩家一眼能懂：
1. **叮（灰）**：覆甲阈值减免触发时，把文案改成 **「叮」**（可保留偶发「装甲挡住了」或统一「叮」）；颜色 `#c8d0dc`；可降频（同目标 0.25s 内不叠字）
2. **弱点!（橙）** `#ffa040`：在下列情况飘一次（降频同理）：
   - 覆甲怪被 `FLOOR_EXEMPT` 来源打出 **未减免的满额**（buckshot/beam/rang/blast/nuke）
   - 护盾兵被绕后/爆炸/火 tick/电弧破盾有效伤害
   - 冻住目标（`vulnerability()>1`）被打出额外易伤伤害时（已有数值，补字）
   - 镜面被非直射（arc/blast/tick）打中
3. 实现建议：在 `zombie.take_damage` / `boss_brain.absorb` 返回后根据 `src`+状态决定 `fx.text`；不要每发 SMG 刷屏

Harness：加小断言或 bot note，确认打巨像 SMG 出「叮」、霰弹/狙击出「弱点」。

### 1D. 随身枪数上限
现状：手枪/霰弹/冲锋 `unlock_cost=0` 开局 level=1；另外 6 把商店解锁后 **可 9 把全带**（`owned_weapons` = 所有 level>0）。

规则：
- `GameData.BASE_WEAPON_SLOTS := 4`，`MAX_WEAPON_SLOTS := 5`
- `player.weapon_slots` 初始 = BASE；商店商品 **「扩容枪袋」**（防御或补给页）花费 **220**，+1 槽，最多到 MAX；限买一次（slots==MAX 时 locked）
- **开局仍 3 把**（手枪/霰弹/冲锋），空 1 槽
- `player.loadout: Array[String]`：当前携带的枪 id，顺序用于滚轮/数字键
- `owns_weapon` 仍表示「已解锁（level>0）」；**`owned_weapons()` 改为只返回 loadout 里且 level>0 的**（HUD/切枪/补弹循环都走它）
- 解锁新枪（`upgrade_weapon` 从 0→1）：
  - 若 loadout.size() < weapon_slots → 自动装入
  - 若已满 → **拒绝购买**并提示「枪袋已满，先卸下一把」或在商店该行显示禁用原因（推荐：买之前检查，`shop_buy` 返回 false + `fx`/status 提示）
- 武器页每把 **已解锁且在 loadout** 的枪加「卸下」按钮（或第二按钮）；卸下后从 loadout 移除，**保留 level/弹药**，不能切到它
- 武器页每把 **已解锁但不在 loadout** 的枪加「装备」；loadout 未满才可
- **不可卸到 0 把**；建议 **手枪不可卸下**（永远在 loadout），避免软锁
- 数字键：仍按 `WEAPON_ORDER` 索引切到「若在 loadout」；不在则无效（已有未解锁逻辑可复用）
- 弹药页/升级：已解锁不在 loadout 的仍可升级与买弹药（或仅 loadout 可买弹药——选 **仍可升级，弹药仅 loadout** 更贴「随身」）
- 更新 flowtest：`商店武器页` 断言别再假设「解锁就能切到第 9 把」；测满槽拒绝、卸下再装、扩槽

README 补一句：随身最多 4 把（可扩到 5）。

---

## Commit 2 — 元素联动

现状：
- 全局暴雨：`events.arc_mult = 1.35`，`splash` 缩小；**没有 per-zombie 湿身**
- `ignite` 清冰；`apply_chill` 清火；冻住有 `FREEZE_VULN`
- 酸液池在 hazards

新增状态（zombie.gd）：
1. **`_wet_t`**
   - 来源：天气 `rain` 激活时，在场僵尸每帧刷新湿身（如保持 0.6s）；踩酸液池/酸雨滴到也施加
   - 显示：略蓝灰 modulate 或小水滴（简单 modulate 即可，可并进 `_status_key`）
   - **电弧**：对 `_wet_t>0` 的目标伤害 **×2**（在 arc 结算处乘；与全局 rain arc_mult **叠乘可以**，但若手感过炸可改湿身 ×1.5 并写进 REPORT）。推荐：**湿身 ×2，保留雨天全局 1.35**
2. **碎冰**
   - 当 `_frozen_t>0` 且 `src in ["buckshot","beam"]`（霰弹/狙击）命中：额外一次 `amount * 0.5`（或总伤 ×1.5），然后 **提前结束冰冻**（清 `_frozen_t`/`_chill`），`fx.frost` + 字 **「碎冰」**
   - Boss 永不冻，故自然无效——OK
3. **淬火破甲**
   - 若目标当前 `_burn_t>0`，再被 `apply_chill` 推到冻结（或成功上 chill）：施加 `_quench_t ≈ 3.0s`
   - `_quench_t>0` 时：覆甲 `hit_floor` **视为关闭**；护盾兵可强制 `shield` 易碎或 `up=false` 一次（选简单：`absorb` 里 `_armored()` 额外要求 quench 未激活；精英盾 `blocks` 对淬火目标失效）
   - 飘字 **「淬火」**；点燃仍清冰的旧逻辑保留——淬火窗口在「先烧后冻」成功冻结的那一刻打开

Harness：arena 里造雨/湿身测 arc 伤害比；冻住+霰弹出碎冰；燃烧后冰冻出淬火且 SMG 能打进巨像（或阈值关闭）。

---

## Commit 3 — 危险等级 + 契约

### 流程 UI
标题「开始」→ 现有选图 → **新面板「行动准备」**（或并进 map_select 下一步）：
- 危险等级 0–5（0=现网难度；解锁：通关危险 N-1 的胜利才开 N；存 `Save.max_danger`）
- 契约列表可多选叠加，例（写进 `GameData.CONTRACTS`）：
  | id | 名 | 效果 | 分率 |
  |---|---|---|---|
  | no_smg | 禁冲锋枪 | 开局不给 smg；商店不能解锁/装备 smg | +0.30 |
  | no_turret | 禁炮塔 | 不能买炮塔 | +0.20 |
  | glass | 玻璃大炮 | 玩家最大生命 ×0.7 | +0.25 |
  | swarm | 尸潮契约 | 杂兵数量 ×1.2（count_scale） | +0.20 |
  | regen | 不灭 disturbs | 非 Boss 僵尸脱战缓慢回血（无冰火时） | +0.30 |
- 显示「当前倍率 ×1.xx」；确认后 `Save.danger` / `Save.contracts: Array` 写入，再进游戏
- Bot/flowtest：默认危险 0、无契约，**必须不挡**现有自动开局（`Harness._start_from_title` 跳过或自动点确认）

### 数值
- `GameData.danger_hp_mult(d)`、`danger_damage_mult`、`danger_elite_chance` 等：d=1 → 怪血×1.1；d=5 → ×1.5 左右，平滑即可
- 应用到 `hp_scale`/`damage_scale` 或 spawn 后乘一次；别把经济搞崩（金币可略增）

### 分数与排行
- 结算分 `score_final = floor(raw_score * danger_mult * contract_mult)`（危险本身也可带倍率：0→1.0 … 5→1.5）
- `Save.submit` 扩展字段：`danger`, `contracts`, `mult`；旧存档缺字段当 0
- 标题排行榜行：「1. 12345 分  第15波 胜  危3  ×1.8」
- `best_score` 仍按分数排序

### 契约落实
- `no_smg`：`player.setup` 后若契约激活则 smg level=0 且不进 loadout；商店 up_smg/装备禁用
- `no_turret`：`shop_buy("turret")` 失败
- 其它按表

---

## 测试清单（必须）
1. `fontcheck` 缺字 0
2. `flowtest` 全绿（改枪槽/新 UI 后更新断言）
3. `maptest` 抽测
4. 针对性：
   - 商店可见下一波情报与弱点相关文案
   - 满 4 槽无法再解锁第 5 把，除非卸下或扩容
   - 巨像：SMG「叮」、霰弹/狙击「弱点」
   - 湿身电弧伤害上升；碎冰；淬火
   - 危险 1 + 禁 SMG 契约开局无冲锋枪；胜利分带倍率进榜
5. 小样本 bot：`--bot --seed=3 --wave=1` 危险 0 能跑；可选 `--god` 快速摸高波（若项目支持）

查 god 模式：`grep -n god scripts/test`；有则用。

## README
更新试玩说明：枪槽、商店情报、元素联动、危险/契约各一句；波次 Boss 表不用改。

## 交付
`/tmp/zombie-siege-counter/REPORT.md` 写：commit hash、试玩 URL、四项验收、测试日志路径、遗留、字体情况。
合并部署后 stdout 最后一行总结。

---

## 追加（用户 2026-11-03）：武器进化也要做，同一 feature 包

在元素联动之后、危险等级前后实现均可。测完与四件套一起 merge/deploy。REPORT 必须单独列出进化配方表。

### 设计目标
枪 **满级（MAX_WEAPON_LEVEL=5）** + 指定条件 → 进化形态；每种进化 **专克一类题**，不是纯数值膨胀。

### 推荐 5 条配方（可微调数值，id/名/克制方向保持）

| id | 显示名 | 需求 | 进化效果（机制） | 专克 |
|---|---|---|---|---|
| frost_mine | 冰封雷 | cryo Lv5 + 背包有 sticky≥1（进化时消耗 1 粘弹） | 冰弹命中附着「冰雷」：短延迟小范围冻结爆炸（或强 chill 一片）；对未冻目标也可触发一次 AoE 冰 | 群加速/再生/需要控场的波 |
| saw_rang | 锯刃回旋 | boomerang Lv5 + 曾使用过伤害药水（本局 `damage` 道具用过即可）或 loadout 时持有 damage≥1（优先：进化时不强制消耗，标记 `used_damage_potion`） | 回旋镖伤害 +25%，**无视护盾朝向 / 不触发镜面反射**（src 可当 blast 或新 src `saw` 列入 FLOOR_EXEMPT 且 mirror 不反） | 护盾兵、镜面女皇正面 |
| storm_rod | 避雷针 | arc Lv5 + decoy≥1（消耗 1） | 电弧首跳伤害 +20%，湿身倍率再 ×1.25；主动：下次扔诱饵变成「导电诱饵」，电弧优先跳向它并连锁周围 | 密集导电群、暴雨波 |
| thermite | 铝热榴弹 | grenade Lv5 + frag 曾用或持有≥1（消耗 1 手雷） | 爆炸留下更久火池 + 对覆甲/坦克额外 +20%；爆炸 src 保持 blast | 覆甲巨像、坦克 |
| puncturer | 穿甲狙击 | sniper Lv5 + 击杀累计坦克+护盾兵+巨像 ≥8（本局）或 sticky≥1 消耗 | 光束对护盾/覆甲阈值伤害不减（已有部分豁免则再加易伤 ×1.2 vs armored/shield） | 铁壁波、巨像 |

（若实作时间紧，5 条做满；实在来不及可先落地 **frost_mine / saw_rang / thermite / puncturer** 四条，storm_rod 可简化为纯数值+湿身加成不改诱饵。）

### 实作要点
- `GameData.EVOLUTIONS` 表：`base`, `name`, `desc`, `need`（level/item/flag/kills）
- 商店武器页：满级且条件满足时出现 **「进化」** 按钮（花费可 0 或小额金币如 50）；进化后 `weapon_state[id]["evo"] = evo_id`，名称 HUD 显示进化名
- 进化是 **原地变种**（同一 weapon id），不要占新枪槽
- 条件检查与消耗写在 `shop_catalog` / `player.try_evolve`
- 开火逻辑读 `evo` 分支；中文 UI 记得进 font 裁剪
- Harness：造满级+道具 → 进化成功 → 打护盾/覆甲有差异；flowtest 不强制走进化，但商店页有按钮不炸
- README 补「满级武器可进化」一句

### 当前 WIP 进度（重开时接着做，勿回滚）
已在工作区未提交（勿 `git reset --hard`）：
- ✅ 下波预告 `wave_preview`、weak 标签、图鉴怕：、叮/弱点! cue、枪槽 4 可扩 5、装备/卸下
- 🟡 暴雨地块湿身（牵引/减速）已有；**湿身电弧×2、碎冰、淬火破甲可能未完** — 请核对 zombie/bullet_system 后补齐
- ❌ 危险等级 + 契约未做
- ❌ 武器进化未做
- 已有 commit：`691a680` 掘地领主小修复（可保留）
- c1_flow 曾 785 OK；以你重测为准

完成顺序建议：补齐元素联动 → 武器进化 → 危险/契约 → 总测 → merge main → deploy → push origin main + feature/counter-gameplay
