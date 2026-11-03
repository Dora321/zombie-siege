# Phase 1 Boss 改动 — 实现 brief

设计全文：`docs/zombie-siege-boss-moves.md`（尤其 §A 波次表 + §B 裂颚先锋/屠夫/瘟疫 + §C 第1期）

## 范围 ONLY（不要越界）
1. 波次改成偶数波偏 Boss、奇数普通、15 终局（按 A 表能落地的部分）
2. 新 Mini-Boss「裂颚先锋」`vanguard` → **W2**
3. 屠夫前移 **W4**；HP 降到约 900；P2 `charge2` 蓄力中可被 **闪光** 或 **霰弹累计击退** 打断并硬直 ~0.8s
4. 瘟疫母体改 **W8** + 酸雨同波；Boss 存活时酸雨稀化（间隔×1.5、滴数−1）；P1 招式池去掉 `fog`、加 `rocks`（替 fog），保留 `fan`/`call`；P2 才 `fogring`

**禁止**：覆甲巨像 / 再生坟主 / 掘地领主 / 镜面女皇 / 尸王大改 / 新特色杂兵 / 双 Boss。尸王留 W15，配表可不动或极小注释即可。

## 波次落地策略（一期）
按 A 表改 `GameData.WAVES`：
- W1 普通先头
- **W2** Mini：`vanguard` 1 + 杂兵约原 W2 的 50%（如 walker~6 runner~2），hint 教红通道/红圈
- W3 毒液教学（略减）
- **W4** 屠夫 `boss` 1 + 杂兵约原 W5 的 70%
- W5 自爆+分裂预习（无 Boss）
- **W6** 一期尚无巨像 → 用高压普通/精英波占位（可参考旧「暗处的眼睛/铁壁」内容），**不要**加新 Boss kind；注释 TODO Phase2 巨像
- W7 铁壁/护盾预习
- **W8** 瘟疫 `plague` 1 + `special: acid_rain` + 合适杂兵 + hint（酸雨+毒母体）
- W9 火药桶向
- **W10** 一期无坟主 → 高压普通占位 + TODO
- W11 黑夜向
- **W12** 保留 `special: blackout`，一期无掘地 → 高压+潜伏者波 + TODO（别塞新 Boss）
- W13 尸潮略减
- **W14** 一期无镜面 → 高压墙波 + TODO
- **W15** 尸王 `overlord` 不变

Boss 波仍走现有 `boss_wave()` / `event_allowed`（禁随机天气）；8/12 剧本 special 保留。

## 裂颚先锋 `vanguard`
- `ZOMBIES`：`is_boss: true`，HP≈420，speed≈26，体型略大于 runner、小于屠夫；knock_res 高；coins/score 介于精英与屠夫之间
- `BOSSES["vanguard"]`：title「裂颚先锋」；warn 侧闪教学；drops armor/ammo；无 trophy 或小奖励即可
  - P1 at1.0「裂颚」gap[2.4,3.2] moves charge/slam
  - P2 at0.45「狂奔」speed↑ enter charge，moves charge2/rocks，rocks:2
- `boss_brain.gd`：现有 move 足够，无需新招式类型
- 美术：`enemy_art.gd` / `Art` 角色表给 `vanguard` 一个可辨认造型（可复用屠夫配色缩小 + 裂颚特征），并确保图鉴/sheet 不炸
- 文案：中文 name/desc/tip/title/warn/phase name；改完跑 `python3 tools/build_font.py`（若脚本需要字体路径，按 README / 现有习惯；字体找不到则更新 `tools/font_chars.txt` 并记录，勿瞎编路径）

## 屠夫打断（W4 + P2）
- 闪光：现有 `stun` → `on_stun` 已清 `_act`；确认 **蓄力阶段**（`_act_t>0`）也被取消。Boss 闪光晕极短；打断后希望硬直约 0.8s——可在 `on_stun` 或专用 interrupt 里对 charge2 蓄力额外 `stun(0.8)` / 设标志
- 霰弹：在 `charge2` **蓄力中**（未进入 `_charge_t` 冲刺），累计霰弹带来的击退意图；因 Boss `knock_res≈0.96`，需 **忽略/旁路 knock_res** 的 interrupt 计数。阈值建议：单次开火多丸合计 knock 意图 ≥ ~40–60（按现有 shotgun knock 62×pellets 设计一个合理门槛，贴脸一两枪能断）。达标 → 取消蓄力、清 lane 预警若可、硬直 0.8s，可 `Harness.note` 打日志
- 只对屠夫 P2 的 charge2 启用霰弹打断即可（或所有 Boss 的 charge2 蓄力都认闪光；霰弹阈值可限 `kind=="boss"` 且 phase 狂怒）。别改坏普通晕眩

## 瘟疫 + 酸雨稀化
- WAVES W8：`plague:1` + `special:"acid_rain"` + hint
- `game.gd` `_tick_special`：若本波 acid_rain 且 `boss_list` 非空，则 `gap = ACID_RAIN_GAP * 1.5`，`count = max(1, ACID_RAIN_COUNT - 1)`
- `BOSSES["plague"]` P1 moves：`["fan", "call", "rocks"]`（去掉 fog）；P2 保持 fogring/fog/...

## 其它
- 更新 README 里「第 5、10、15 波 Boss」等过时描述 → 偶数波/一期说明
- `font_chars.txt` / `build_font.py`：新汉字必须进子集
- 在 **feature/boss-wave-phase1** 分支改；清晰 commit（可用 HEREDOC）
- **不要** merge main、**不要** deploy（父代理测过再决定）
- 小样本测试：
  - `godot --headless --path . --fixed-fps 60 -- --flowtest --seed=1`（若太慢可缩短，但至少跑通启动/商店）
  - 或 `--bot --god --godbase --wave=2 --seed=1` 等针对性波（看 Harness 是否支持从某波起；支持则测 W2/W4/W8）
  - 失败修一次；**两次失败就停**，把日志写到 `/tmp/zombie-siege-phase1/`

## 成功标准
- feature 分支有清晰 commit
- W2 出裂颚先锋可打；W4 屠夫；W8 瘟疫+稀酸雨
- 屠夫 P2 charge2 可被闪/霰弹打断（bot note 或代码路径正确）
- 中文不缺字（font 已 rebuild 或说明阻塞）
- 报告：改了哪些文件、怎么测的、遗留问题 → 写 `/tmp/zombie-siege-phase1/REPORT.md`
