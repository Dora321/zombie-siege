# Phase 2+3 Boss 剩余 — 实现 brief

设计全文：`docs/zombie-siege-boss-moves.md`（§A 波次 + §B 覆甲巨像/再生坟主/掘地领主/镜面女皇/尸王 + §C 第2–3期）
一期已上线：偶数波节奏、W2 裂颚先锋、W4 屠夫打断、W8 瘟疫稀酸雨；W6/10/12/14 仍是高压普通占位。

## 范围（本次必须做满）
1. **W6 覆甲巨像** `colossus`：伤害阈值 + 三阶段（外壳/裂甲盾/裸核取消阈值）
2. **W10 再生坟主** `graveborn`：无冰无燃回血 + 三阶段
3. **W12 掘地领主** `burrowlord` + 断电共存：地下子弹无效、火池/爆炸/闪光逼出、高对比黄圈/土堆预警
4. **W14 镜面女皇** `mirror`：正面子弹/狙击反弹；P3 `reflect_aura`
5. **W15 尸王** 按 moves.md 小改：P1 开局可出一次薄盾；号令池仍旧六精英即可（不要做新杂兵精英）；guard 逻辑保持现状

**禁止**：冲锋督军/电磁尸核/粘胶巨兽；新特色杂兵；双 Boss；大拆架构；改坏一期先锋/屠夫/瘟疫。

## 分支与流程
- 从最新 `main` 开 `feature/boss-wave-rest`
- 中文改完跑 `python3 tools/build_font.py <fusion-pixel 完整字体路径>`（若本机没有完整字体：先尽量更新 `tools/font_chars.txt` 收录新汉字；有完整 ttf 再 rebuild subset；找不到完整字体就记录阻塞，可用现有 subset 先测逻辑）
- 清晰 commit（HEREDOC）；**测过后再 merge main 并** `tools/deploy_pages.sh`
- 日志与报告写到 `/tmp/zombie-siege-boss-rest/`
- 同一动作失败 **两次就停**，把日志和阻塞写进 REPORT，不要死磕
- 代理（部署/网络需要时）：`export HTTPS_PROXY=http://127.0.0.1:7897 HTTP_PROXY=http://127.0.0.1:7897`

## 波次表（替换 TODO 占位）

按 A 表改 `GameData.WAVES`：

- W6：`{"name":"覆甲巨像", "walker":8, "runner":4, "tank":1, "colossus":1, "hint":"小伤害几乎打不动它，换成霰弹、狙击、榴弹或回旋镖"}`；少护盾兵；tank≤1
- W10：`{"name":"再生坟主", "walker":12, "runner":6, "spitter":2, "exploder":2, "graveborn":1, "hint":"先挂上冰或火压住再生，再集火"}`
- W12：在现有断电波上 **加** `burrowlord:1`，stalker 约 10→6，改 hint：「土堆和黄圈是掘地领主，断电时更难发现——用榴弹、火或闪光逼它出土」；保留 `special:"blackout"`
- W14：`{"name":"镜面女皇", "walker":14, "runner":10, "spitter":4, "exploder":4, "mirror":1, "hint":"别正面点射，绕后或用榴弹、电弧、火焰"}`；少 shielder
- W15：尸王保留；禁随机天气规则不动

更新 README 里仍写「占位/一期」的句子 → 八道 Boss 齐。

## 共用实现约定
- 每个新 Boss：`ZOMBIES[kind]`（`is_boss:true`）+ `BOSSES[kind]` 阶段表 + `enemy_art.gd` 可辨认造型 + 图鉴不炸
- 战利品进 `TROPHIES` + `player.apply_trophy`；效果可简化但要有拾取反馈
- 预警时长未注明沿用现网 WARN 表；新招式补进 `WARN` / `_can_use` / `_begin_move` / `_fire_move` / flowtest 的 expected moves 列表
- Boss 冰永不冻（已有）；闪光可断蓄力（已有 on_stun）
- `Harness.note` 关键机制触发（阈值减免、再生跳过、逼出、反射）方便 bot 日志（注意别每帧刷屏）

---

## 1) 覆甲巨像 `colossus` · W6
- HP 1100，speed 18，大体型，knock_res≈0.97，coins/score 介于屠夫与瘟疫
- **阈值**：在 `boss_brain.absorb`（或 take_damage 前）若该 Boss 启用 hit_floor：
  - 默认单次传入 `amount < 16` → 只结算 `amount * 0.1`
  - **例外算满**：爆炸/粘弹/榴弹 AoE、狙击 beam、回旋；以及让 **霰弹有用**
  - 霰弹：现网每丸独立 `take_damage(9)`。优先简单方案：**buckshot 丸绕过阈值**（整枪视为爆发），SMG/手枪仍吃阈值——必须保证「SMG 废、霰弹有用」
  - 火焰 DoT/`take_tick`：可按小额吃阈值
- 阶段：
  - 100% 外壳 gap[2.0,2.8] moves rocks/slam/charge；rocks:3
  - 60% 裂甲 enter shield，BOSSES shield≈0.16；moves rocks/slam/call[tank]；gap[1.6,2.4]
  - 30% 裸核：speed×1.4；**关闭阈值**；moves charge2/wave/slam；gap[1.2,1.8]
- 掉落 sticky, ammo_crate, armor；战利品 `plating`：对覆甲阈值 −4（floor 变 12）或粘弹+15%（实现一个即可）
- tip：小伤害无效，换重火力

## 2) 再生坟主 `graveborn` · W10
- HP 1500，speed 19，knock_res 高
- **再生**：存活且 **无 chill 且无 burn** 时每秒回 `regen_rate * max_hp`（P1/P2 默认 0.025；P3 崩坟 0.04）。有 `_chill_t>0` 或 `_burn_t>0` 则再生为 0。在 boss_brain.decide 或 zombie 状态 tick。
- 阶段 sub/warn 提示「维持冰或火」；可选头顶「再生中」
- 阶段：
  - 100% 腐土：call[walker×3], rocks×3, slam；gap[2.0,2.8]
  - 55% 冻土·焦土：enter shield（薄 shield≈0.10）, fogring/fan/shield；gap[1.5,2.2]
  - 25% 崩坟：wave/storm/call；regen→4%/s；gap[1.2,1.8]
- 掉落 ammo_crate/medkit；战利品 `ash`：冰与燃持续时间 +0.5s

## 3) 掘地领主 `burrowlord` · W12 + blackout
- HP 1600，speed 24；地下移动可 ×1.3
- **新状态 burrowed**（类 cloaked）：
  - 子弹/beam 伤害 **0**；爆炸/火池 DoT/闪光仍有效
  - 半透或只画土堆；AoE 仍可打到
  - 预警：黄圈（warn_ring 改色或 zone kind `burrow`）；移动撒土堆点
- 招式：
  - `burrow`：地下 2.5–4s，可朝玩家移动；结束或逼出 → `emerge_slam`
  - `emerge_slam`：出土黄圈 0.7s 后 ×1.3 slam
  - 仅出土可 rocks；地裂 wave/storm；30% enter call[stalker×2]，burrow 更频、地下更短
- **逼出**：地下被闪光、火焰地面或爆炸命中 → 强制出土 + 硬直 ~1.0s，`Harness.note`
- 断电时土堆/黄圈加亮
- 掉落 frag 等；战利品 `soil`：手雷/榴弹对 Boss +10%（简单全局亦可）
- WARN 加 burrow / emerge_slam；更新 flowtest expected moves

## 4) 镜面女皇 `mirror` · W14
- HP 1800，speed 21
- **正面反射**：朝向与子弹入射点积 `< -0.28` 时：
  - 普通子弹与狙击 beam：无伤害或极少，玩家挨 `min(伤害*0.25, ~12)` 或火花弹开；note 节流
  - **无视朝向**：火焰、电弧、榴弹/爆炸、粘弹、shockwave、绕背
- 钩子：`bullet_system` / `ordnance.beam` 命中前问 `_brain.reflect_bullet(...)`；AoE/火/电跳过
- 阶段：
  - 100% fan, rocks×4, slam；gap[1.9,2.7]
  - 55% enter shield；shield/fog/call[shielder], wave；gap[1.5,2.2]
  - 25% `reflect_aura`：红环蓄 1.0s → 1.5s 内任意非 AoE 直击反伤×0.5；闪光可打断；gap[1.2,1.7]
- 掉落 armor 等；战利品 `shard`：反射伤害再减半

## 5) 尸王 `overlord` · W15 小改
- P1「围城」moves 加入 `"shield"`（池子能抽到即可）
- elites 池保持旧六；不要加不存在的精英 kind
- 其余不动

---

## 测试（小样本，失败两次停下）
仓库根目录：

1. `godot --headless --path . --fixed-fps 60 -- --flowtest --seed=1`
2. 针对性：
   - `godot --headless --path . --fixed-fps 60 -- --bot --god --godbase --wave=6 --seed=1 --money=9999 --maxframes=18000`
   - 同上 `--wave=10` / `12` / `14`；可选 `15`
3. 有新字：`godot --headless --path . -- --fontcheck=$PWD/tools/font_chars.txt`
4. 通过后：merge `main`，`bash tools/deploy_pages.sh`（需要时带代理）

## 成功标准
- feature 清晰 commit；main 已含；Pages 已更新
- 四新 Boss 可打；波次对齐；尸王 P1 能出盾
- REPORT.md：文件列表、测试结果、commit、https://dora321.github.io/zombie-siege/、遗留

## 遗留可接受
土堆极简、反射只火花、战利品偏软、出怪间隔未×1.35、尸王号令不含新精英；**不要**留下 W6/10/12/14 TODO 占位。
