# ADC 控制器参数化重构 增量验证签收报告

日期：2026-07-21
分支：feature/parameterization
基线报告：`doc/verification_report_2026-07-20.md`（覆盖到 `10c2f57`）
本次覆盖：`10c2f57..b75842f`（07-20 报告之后的 7 个提交）
HEAD：`b75842f`（2026-07-21 00:20）

## 1. 签收结论

**✅ 增量签收通过。** 07-20 报告之后的 7 个提交未引入回归，`make check` 全绿。
其中两项 RTL 修复（`0a002eb` regfile 位宽修正、`b75842f` `is_lp_data` 地址上界
修复）经本次 `make clean` 后全量重跑验证通过；entry 紧凑存储重构
（`40c9648`/`9d4cd14`）行为与 07-20 基线一致。本报告与 07-20 报告合起来构成
HEAD 的完整签收留痕。

## 2. 覆盖范围（07-20 报告之后的 7 个提交）

| 提交 | 类型 | RTL 改动 | 本次验证作用 |
|:--|:--|:--:|:--|
| `61aa91b` docs(skill) | 文档 | — | skill 记录，无 RTL，无需回归 |
| `0a002eb` fix regfile | **RTL** | ✅ | **回归重点**：W_CH_SEL 死分支/lp_seq 数组收缩/hp_valid 复位/删 HP_SEQ_LEN_RST |
| `bb82c50` docs 归档 | 文档 | — | design/cost/plan 归档，无 RTL |
| `40c9648` refactor entry | **RTL** | ✅ | **回归重点**：lp_seq/hp_seq 内部存储改 N×8bit entry + packed bus 端口 |
| `9d4cd14` refactor entry | **RTL** | ✅ | **回归重点**：存储位宽收紧到 W_CH_SEL bit（rsv 高位不存读回 0）+ UVM sb/seq 对齐 |
| `bbdcfc1` docs 同步 | 文档 | — | user_guide/consistency/regmap/testplan 同步，无 RTL |
| `b75842f` fix is_lp_data | **RTL** | ✅ | **回归重点**：地址上界硬编码 0x088 → 0x0A0（N≥27 LP_DATA[26:31] 读回 0 bug） |

4 个 RTL 改动提交（2 fix + 2 refactor）为本次回归重点；3 个文档提交无 RTL。

## 3. 回归结果（make check，2026-07-21 重跑）

`make clean` 后全量重跑 HEAD `b75842f`：

| 检查项 | 结果 |
|:--|:--|
| `make lint`（iverilog -g2012，15 模块） | ✅ 15/15 PASS |
| `make vcs`（VCS RTL 编译） | ✅ PASS → `sim/simv` |
| `make test-unit`（iverilog，2 TB） | ✅ 2/2 PASS（tb_adc_top + tb_adc_top_8ch） |
| `make sim-uvm-regr`（VCS UVM，18 case） | ✅ 18 passed, 0 failed（8s） |
| **总计** | **全绿** |

与 07-20 报告 §3 结果一致，无回归。

## 4. RTL 修复回归证据

### 4.1 `0a002eb` — regfile 参数化位宽修正

- **根因**：`W_EOC_IDX = W_CH_SEL` 既要索引 LP（0..N-1）又要承载 HP seq_ptr（固定
  2bit），N=2/3 时 `W_CH_SEL < 2` 导致 seq_fsm 负复制 elaboration fail；死分支
  `(N<=2)?1:$clog2(N)` 掩盖了下界问题。
- **修法**：合法范围收紧到 [4,32]，`W_CH_SEL = $clog2(N)`；`lp_seq` 数组
  `[0:7] → [0:NUM_LP_SEQ_REG-1]` 随 N 收缩（8ch 省 192 flop）；`hp_valid_pclk`
  复位参数化；删死参数 `HP_SEQ_LEN_RST`。
- **回归证据**：默认 26ch test-unit + sim-uvm-regr 全 PASS（本报告 §3）；
  8ch smoke PASS；iverilog 顶层 override N=4、N=32 elaboration 生成成功（commit
  说明）。默认 26 与 8ch 两个端点配置功能正确，下界 N=4 / 上界 N=32 elaboration
  通过，覆盖修正后的合法范围。

### 4.2 `b75842f` — is_lp_data 地址上界修复

- **根因**：`is_lp_data` 地址上界硬编码 `12'h088`（=0x24+25*4，只覆盖 26 entry），
  spec 声明 LP_DATA 0x24~0xA0 按 32 预留、N 可到 32。`ADC_NUM_CH=27~32` 时
  LP_DATA[26:31]（地址 0x8C~0xA0）落在 `is_lp_data` 范围外 → 走 default → 读回 0，
  采样数据读不出来。`is_lp_seq` 已按 `0xB8~0xD4` 全 8 组预留 + idx guard 做对，
  `is_lp_data` 未按同 pattern 参数化 → 不一致。
- **修法**：`is_lp_data = (addr_offset >= 12'h024) && (addr_offset <= 12'h0A0)`
  （覆盖完整 32 预留区），靠 `lp_data_idx < NUM_LP_DATA` guard 处理超出 N 的 entry
  读回 0、写忽略——与 `is_lp_seq` 同 pattern。已核对当前 RTL
  `rtl/adc_regfile.v:299` 实现即此。
- **为什么没被既有测试抓到**：默认 26ch（0x88 正好覆盖到 25=第26个 entry）、
  smoke 8ch（8<26 idx guard 兜底）都不触发；只有 N≥27 才断。
- **回归证据**：默认 26ch test-unit + sim-uvm-regr 全 PASS（本报告 §3），证明
  修复未破坏默认配置；N=32 elaboration 生成成功（commit 说明），证明上界修复后
  大配置可综合。**注**：N=27~32 的功能级 data 读回验证尚未有独立 TB 覆盖
  （见 §7 后续建议 1）——本次签收以"修复未回归默认配置 + elaboration 通过"为
  准，与 commit 当时的验证范围一致。

## 5. entry 紧凑存储重构回归证据（`40c9648` + `9d4cd14`）

两提交把 `lp_seq`/`hp_seq` 内部存储从扁平数组改为 N×8bit entry + packed bus
端口，再收紧到 `W_CH_SEL` bit（rsv 高位不存、读回 0），涉及 `adc_regfile.v` /
`adc_seq_fsm.v` / `adc_top.v` + UVM `adc_sb.sv` / `adc_reg_seq.sv` 对齐。

- **回归证据**：默认 26ch `sim-uvm-regr` 18 case 全 PASS（本报告 §3），含
  `adc_reg_seq`（LP_SEQ/LP_SEQ_LEN sweep）+ `adc_sb`（序列数据比对）两条路径，
  证明 entry 拆包/打包与 scoreboard 期望一致，紧凑存储未改变功能行为。
- **位宽收紧读回 0 语义**：rsv 高位不存读回 0，由 `9d4cd14` 同步进 spec
  `§3.11/§3.13` 与 UVM `adc_uvm_pkg.sv`，五端一致（见 §6）。

## 6. 一致性 / Waiver 复查

- **五端一致性**：`bbdcfc1` 已同步 user_guide 地址迁移 / consistency 过期行 /
  regmap 注释 / testplan / design 残留；`b75842f` 同步 spec §2 位宽标注 +
  consistency report。本次重跑未触发新的不一致。spec↔RTL↔SDC↔regmap↔TB 五端
  与 07-20 报告 §5 一致，无新增 gap。
- **Waiver 复查**：`doc/waiver.md` WAIVER-001（FSM bit[23] ST_LP_PREEMPT→ST_IDLE，
  2026-07-15 登记）触发条件为"adc_seq_fsm 状态转移逻辑改动"。本次 7 个提交中
  `40c9648`/`9d4cd14`/`0a002eb` 触及 `adc_seq_fsm.v`，但改动为 seq_ptr/entry
  存储与位宽参数化，**未涉及 PREEMPT 状态转移逻辑**（FSM 状态机本身不变）。
  本次 `sim-uvm-regr` 18 case PASS、EDGE_008 相关用例无回归 → WAIVER-001 仍成立，
  无需取消。**无新增 waiver。**

## 7. 未尽事项与后续建议

1. **N=27~32 LP_DATA 读回功能验证**（`b75842f` 修复的回归缺口）：当前只有默认
   26ch + 8ch smoke 两个配置有功能 TB，N=27~32 仅 elaboration 通过、无独立 data
   读回 TB。建议后续建一个 N=32（或 N=27）的 smoke TB，覆盖 LP_DATA[26:31] 写入
   读回，闭合 `b75842f` 修复的功能验证。本次签收不阻塞，因修复本身已由
   consistency-check 五端重跑发现并定位、默认配置无回归。

   > **[CLOSED 2026-07-21]** 新增 `tb/unit/tb_adc_top_32ch.v`（3 个聚焦测试，79 pass
   > slot）：32 条目 LP 序列扫描编程 LP_SEQ0..LP_SEQ7 = CH0..CH31、LP_SEQ_LEN=32、
   > SW 触发，读回全部 LP_DATA[0:31] 验 VALID+data；**LP_DATA[26:31] @0x8C~0xA0**
   > （b75842f 地址）显式断言 VALID=1 + data 匹配（6 行 `[GAP-CLOSE b75842f]` 证据）。
   > Test3 覆盖 0xA0/0xA4 边界、LP_SEQ7 @0xD4、PARAM_SEQ_RSV（rsv 高位读 0）、
   > LP_SEQ_LEN 6bit RW。`make test-unit` 现跑 3 个 TB（26ch/8ch/32ch）全 PASS，
   > `make check` 全绿。闭合 N=27~32 LP_DATA 读回功能缺口。
2. **多配置覆盖率**：与 07-20 报告 §9.2 相同，本次仍只对默认 26 配置收覆盖率，
   8ch smoke 只看 PASS。entry 紧凑存储重构后若需重收覆盖率，可单独建 cov run。
3. **合并 master**：`feature/parameterization` 领先 `master` 61 个提交，本报告 +
   07-20 报告构成 HEAD 完整签收留痕，可考虑合入 `master`。

## 8. 提交历史（本次覆盖）

```
61aa91b docs(skill): 记录参数化重构遇到的问题(env-bug #10-13 + adc-design #29-32)
0a002eb fix: regfile 参数化位宽修正(W_EOC_IDX 下界4/lp_seq 按NUM_LP_SEQ_REG收缩/hp_valid 复位参数化/删HP_SEQ_LEN_RST)
bb82c50 docs: 参数化设计文档/成本报告/实施计划归档
40c9648 refactor: lp_seq/hp_seq 内部存储改 N×8bit entry + packed bus 端口
9d4cd14 refactor: lp_seq/hp_seq 存储位宽收紧到 W_CH_SEL bit（rsv 高位不存读回0）
bbdcfc1 docs: 同步参数化+entry紧凑存储到全仓文档
b75842f fix: is_lp_data 地址上界硬编码 0x088 → 0x0A0（N>=27 配置 LP_DATA[26:31] 读回0 bug）
```

> 07-20 报告覆盖 `8583ca8..10c2f57`（参数化重构主体），本报告覆盖
> `10c2f57..b75842f`（增量修复 + entry 紧凑存储 + 文档同步）。两报告合起来
> 覆盖 `8583ca8..b75842f` 全部参数化提交，即 HEAD 的完整签收留痕。
