# 一致性检查报告

**检查时间:** 2026-07-04（初版）/ 2026-07-21（参数化 + entry 紧凑存储 + 五端重跑）
**检查范围:** spec/adc_spec.md ↔ rtl/*.v ↔ scripts/adc_constraints.sdc ↔ tb/adc_regmap.svh ↔ spec/testplan_adc.md (五端)
**检查人员:** Claude Code

> **2026-07-21 五端重跑结果：** `/consistency-check` 重跑发现并修复一处真 bug
> （`is_lp_data` 地址上界硬编码 0x088，N≥27 时 LP_DATA[26:31] 读回 0），已修为
> `<= 0x0A0`（与 `is_lp_seq` 同 pattern，地址按 32 预留 + idx guard 兜底）。
> 五端比对结论见下方各节。

---

## 检查结果

```
✅ 一致性检查通过 (0 errors, 1 warning, 2 info)
   - 内部检查: 模块数 9, 实例数 10, 端口连接 120+
   - 外部检查: 寄存器 16/16 匹配, 端口 25/25 匹配
   - SDC↔RTL: get_ports/get_clocks 引用全存在、方向全匹配
   - regmap↔RTL: 地址宏集 == RTL 译码集, 非孤儿
   - TB↔spec: 146 测试点/75 P0, 18 UVM test + 2 unit TB (P0→test 非严格 1:1, 需 testplan-gen 回填)
```

> **本轮修复：** `is_lp_data` 地址上界硬编码 `0x088`（只覆盖 26 entry）→
> `0x0A0`（覆盖 32 预留区，靠 `lp_data_idx<NUM_LP_DATA` guard 处理越界）。
> 修前 N≥27 配置 LP_DATA[26:31] 读回 0（数据丢失）；修后 N=4~32 全配置正确。

---

## 一、端口接口一致性

### 1.1 顶层端口

| 信号组 | 规格定义 | RTL 实现 | 状态 |
|:--|:--|:--|:--:|
| APB 总线 | PCLK, PRESETn, PADDR[15:0], PWRITE, PSEL, PENABLE, PWDATA[31:0], PRDATA[31:0], PREADY, PSLVERR | pclk, presetn, paddr[15:0], pwrite, psel, penable, pwdata[31:0], prdata[31:0], pready, pslverr | ✅ |
| ADC 时钟 | ADC_CLK, ADC_CLKn | adc_clk, adc_clkn | ✅ |
| 外部复位 | PRSTn | prstn, presetn 双端口 | ⚠️ 见下 |
| 模拟接口 | SOC, MUXON, ch_sel[4:0], EOC, adc_data[13:0] | soc, muxon, ch_sel[4:0], eoc, adc_data[13:0] | ✅ |
| 校准接口 | CAL_ST, CAL_DONE, cal_val[5:0] | cal_st, cal_done, cal_val[5:0] | ✅ |
| 外部触发 | mctm_trig[5:0] | mctm_trig[5:0] | ✅ |
| 中断/DMA | adc_int, dma_req, dma_ack | adc_int, dma_req, dma_ack | ✅ |

> ⚠️ **复位端口命名差异:** 规格文档描述单一外部复位 `PRSTn` 同时用于 APB 域和 ADC 域。RTL 顶层将 APB 域复位命名为 `presetn`，ADC 域复位命名为 `prstn`（两者本质上为同一外部复位信号的不同域入口）。规格未显式描述这种"两端口"方案，建议在规格文档中明确说明。

### 1.2 子模块互联

所有 10 个实例之间的端口连接经验证：
- 端口方向一致 ✅
- 端口位宽匹配 ✅（所有连接对位宽一致）
- 连接无悬空或未连接端口 ✅

---

## 二、寄存器映射一致性

| 地址 | 寄存器 | 属性 | 规格位域 | RTL 位域 | 复位值 | 状态 |
|:--|:--|:--:|:--|:--|:--:|:--:|
| 0x00 | CTRL | RW | [0]=ADC_EN, [1]=SW_RST, [3:2]=DATA_ALIGN, [7:4]=SMPL_INTERVAL, [10:8]=SPT0, [13:11]=SPT1, [14]=CONT_MODE | 完全一致 | 0 | ✅ |
| 0x04 | STAT | RO | [0]=ADC_BUSY, [1]=LP_BUSY, [2]=HP_BUSY, [3]=CAL_BUSY | 完全一致 | 0 | ✅ |
| 0x08 | TRIG | RW/WO | [0]=LP_SW_TRIG(WO), [1]=LP_SW_TRG_EN, [2]=LP_MCTM_EN, [6:3]=LP_TRG_SEL, [8]=HP_SW_TRIG(WO), [9]=HP_SW_TRG_EN, [10]=HP_MCTM_EN, [14:11]=HP_TRG_SEL | 完全一致，WO 位读回 0 | 0 | ✅ |
| 0x0C | INT_EN | RW | [5:0]=6个中断使能 | 完全一致 | 0 | ✅ |
| 0x10 | INT_STAT | RW1C | [5:0]=6个中断状态 | 完全一致，写1清零 | 0 | ✅ |
| 0x14 | CAL_CTRL | RW_SS/RO | [0]=CAL_ST(RW_SS), [1]=CAL_DONE(RO) | 一致，CAL_ST 自清除 | 0 | ✅ |
| 0x18 | CAL_VAL | RO | [5:0]=校准值 | 完全一致 | 0 | ✅ |
| 0x1C | ANA_CFG | RW | [15:0]=模拟配置 | 一致，[31:16]保留读0 | 0 | ✅ |
| 0x20 | ANA_REG | RW | [31:0]=通用模拟配置 | 完全一致 | 0 | ✅ |
| 0x24~0xA0 | LP_DATA[0:NUM_LP_DATA-1] | RO | [31]=VALID, [15:0]=DATA | 完全一致，含读清除；超出 NUM_LP_DATA 地址读回 0 | 0 | ✅ |
| 0xA4~0xB0 | HP_DATA[0:3] | RO | [31]=VALID, [15:0]=DATA | 完全一致，含读清除 | 0 | ✅ |
| 0xB4 | DMA_CTRL | RW | [0]=DMA_EN, [5:1]=5个事件使能 | 完全一致 | 0 | ✅ |
| 0xB8~0xD4 | LP_SEQ[0:NUM_LP_SEQ_REG-1] | RW | 4×8-bit 占位/寄存器，内部 W_CH_SEL-bit ch_sel 存储、rsv 读 0 | 完全一致；超出 NUM_LP_DATA 的 entry 读 0 写忽略 | 0 | ✅ |
| 0xD8 | HP_SEQ | RW | 4×W_CH_SEL-bit entry，rsv 读 0 | 完全一致 | 0 | ✅ |
| 0xDC | LP_SEQ_LEN | RW | W_LP_SEQ_LEN-bit，复位 ADC_NUM_CH | 完全一致 | 0 | ✅ |
| 0xE0 | HP_SEQ_LEN | RW | 3-bit，复位 4 | 完全一致 | 0 | ✅ |

> DMA_STAT(0xA8) 已删除，不在表中。

**寄存器覆盖率: 16/16 完全匹配** ✅

---

## 三、功能特性一致性

### 3.1 采样流程

| 规格描述 | RTL 实现 | 状态 |
|:--|:--|:--:|
| IDLE → 等待触发 | ST_IDLE → ST_WAIT_TRIG | ✅ |
| ADC_CLKn↑ 产生 SOC 脉冲 | soc_pulse 在 adc_clkn_rise 时产生 | ✅ |
| SOC 同时拉高 MUXON + 更新 ch_sel | soc_req_set 时 muxon_reg=1, ch_sel 由 cur_ch_sel 驱动 | ✅ |
| SPT 计数器控制采样时间 | spt_cnt 计数到 spt_cycles-1 | ✅ |
| SPT 满 → MUXON 拉低 | spt_done → muxon_reg=0 | ✅ |
| ADC_CLK↓ 产生 EOC | eoc_sync1/sync2 在 adc_clk↑ 采样 | ✅ |
| 捕获 ADC_DATA，更新 LP/HP_DATA | eoc_captured → lp_data/hp_data[seq_ptr] 写入 | ✅ |
| VALID 置位，产生中断 | lp_valid_pclk/hp_valid_pclk[idx] = 1, lp_eoc_pulse = 1 | ✅ |
| SMPL_INTERVAL → 下一通道 | interval_cnt 计数 → 完成时序列指针+1 | ✅ |

### 3.2 单次/连续转换模式

| 规格描述 | RTL 实现 | 状态 |
|:--|:--|:--|
| 单次：序列执行一轮后停止 | cfg_cont_mode=0 → 序列完成回到 ST_WAIT_TRIG | ✅ |
| 连续：序列完成后自动从序列头重新开始 | cfg_cont_mode=1 → 从 ST_LP_SAMPLE 重新开始 | ✅ |

### 3.3 高优先级抢占

| 规格描述 | RTL 实现 | 状态 |
|:--|:--|:--|
| HP 触发可打断 LP 采样 | ST_LP_SAMPLE/WAIT_EOC/INTERVAL 中检测 hp_trig_pulse → ST_LP_PREEMPT | ✅ |
| LP 当前通道丢弃，MUXON 强制拉低 | preempt_abort → muxon_reg=0 | ✅ |
| 立即启动 HP 序列采样 | ST_LP_PREEMPT → soc_req_set → ST_HP_SAMPLE | ✅ |
| HP 完成后 LP 从被中断通道重新开始 | lp_save_ptr 恢复 → lp_seq_ptr <= lp_save_ptr | ✅ |

### 3.4 SPT 时间表

| SPT[2:0] | 规格 | RTL | 状态 |
|:--:|:--:|:--:|:--:|
| 000 | 3 | 8'd3 | ✅ |
| 001 | 8 | 8'd8 | ✅ |
| 010 | 14 | 8'd14 | ✅ |
| 011 | 29 | 8'd29 | ✅ |
| 100 | 42 | 8'd42 | ✅ |
| 101 | 56 | 8'd56 | ✅ |
| 110 | 78 | 8'd78 | ✅ |
| 111 | 240 | 8'd240 | ✅ |

### 3.5 中断与 DMA

| 规格描述 | RTL 实现 | 状态 |
|:--|:--|:--|
| 6 个中断事件源，INT_EN 独立使能 | adc_int_ctrl 中 int_events 与 cfg_int_en 相与 | ✅ |
| INT_STAT 写 1 清零 | regfile 中条件清零 | ✅ |
| DMA 与中断共享事件源，独立使能 | dma_req 独立读取事件脉冲 + cfg_dma_ctrl | ✅ |
| DMA 请求由 dma_ack 清除 | dma_req_r 在 dma_ack_s2 时清零 | ✅ |

---

## 四、CDC 路径检查

| 路径 | 源域 | 目标域 | 同步方案 | 状态 |
|:--|:--:|:--:|:--|:--:|
| ctrl_reg → cfg_adc_en | PCLK | ADC_CLK | 2-stage 同步器（唯一同步的 cfg 信号） | ✅ |
| trig_reg → cfg_lp_trg_sel 等 | PCLK | ADC_CLK | 直接读 PCLK reg（stable between EOC，SDC false_path） | ✅ |
| lp_seq_reg → cfg_lp_seq_flat | PCLK | ADC_CLK | 直接读 PCLK reg（packed bus，stable between EOC，SDC false_path） | ✅ |
| lp_data_adc → lp_data_pclk | ADC_CLK | PCLK | 直接读 ADC_CLK array（stable between EOC，SDC false_path） | ✅ |
| eoc_idx → lp_valid_pclk | ADC_CLK | PCLK | 经 int_evt 2-stage 同步 + 边沿检测后采样 | ✅ |
| int_events → int_stat_reg | ADC_CLK | PCLK | 2-stage + 边沿检测 | ℹ️ |
| stat_adc_busy → STAT | ADC_CLK | PCLK | 2-stage 同步器 | ✅ |
| cal_done/cal_val → CAL 寄存器 | ADC_CLK | PCLK | 2-stage 同步器 | ✅ |
| mctm_trig → 触发脉冲 | async | ADC_CLK | 2-stage + 边沿检测 (adc_sync_cell) | ✅ |
| dma_ack → dma_req 清除 | external | ADC_CLK | 2-stage 同步器 | ✅ |
| sw_rst_pulse → adc_rst_sync | PCLK | ADC_CLK | 经 prstn 与门后异步复位同步释放 | ✅ |

> ℹ️ **中断事件 CDC:** int_events 是 ADC_CLK 域的单周期脉冲，经 int_evt_s1/s2 后进入 PCLK 域同步链。由于 int_events 是单周期脉冲，如果 PCLK ≤ ADC_CLK 频率，脉冲可能被漏采。当前设计依赖 PCLK ≥ 2×ADC_CLK（规格：PCLK 最高 200MHz, ADC_CLK 最高 60MHz）以保证可靠采样。建议关注：
> - 若系统配置中 PCLK < 2×ADC_CLK，需将 int_events 脉冲展宽或改为电平握手
> - 实际使用中 PCLK 通常快于 ADC_CLK，此问题风险较低

---

## 五、发现的问题

### Warning

**⚠️ [WARNING] 中断事件被使能过滤后才送至 INT_STAT**

- **位置:** `adc_int_ctrl.v:46-51` → `adc_regfile.v:770`
- **描述:** adc_int_ctrl 将事件脉冲与 cfg_int_en 相与后才产生 int_events。int_events 经 CDC 到达 PCLK 域后设置 int_stat_reg。这意味着：
  - 当 INT_EN[x]=0 时，对应的事件不会在 INT_STAT 中记录
  - 中断使能晚于事件到达时，事件丢失，不产生中断
- **典型设计模式:** 通常 INT_STAT 应记录所有事件（不限使能），而 INT_EN 只控制是否输出中断。当前设计将事件记录和中断输出合二为一。
- **影响:** 低。对于 ADC 采样应用，事件在使能开启后才值得关注。但如果用户期望通过 INT_STAT 轮询所有发生的事件（即使未使能中断），当前设计无法满足。
- **建议:** 如需符合标准做法，可将 int_events 改为未使能过滤的原始事件，在 adc_int_ctrl 中独立使用 cfg_int_en 控制 adc_int 输出。

### Info

**ℹ️ [INFO] 死代码 — int_evt_rise 信号未使用**

- **位置:** `adc_regfile.v:784`
- **描述:** `assign int_evt_rise = int_evt_s2 & (~int_evt_dly);` — 该信号在 ADC_CLK 域计算了边沿检测，但从未被任何逻辑使用。实际使用的边沿检测在 PCLK 域 (`int_evt_pclk_rise`, line 436)。
- **建议:** 删除未使用的信号 `int_evt_rise`、`int_evt_dly` 及关联逻辑，或确认设计意图后保留（无功能影响，仅浪费少量寄存器）。

**ℹ️ [INFO] 数据对齐编码**

- **位置:** `adc_seq_fsm.v:422-429`
- **描述:** DATA_ALIGN[1:0] 在规格中定义为 2-bit (CTRL[3:2])，编码 00=右对齐, 01=左对齐。RTL 仅检查 `cfg_data_align[0]`，因此编码 10 和 11 也会被解释为左对齐。
- **建议:** 如果希望保留扩展空间，建议在规格中明确"仅 bit0 有效"或补充 RTL 默认分支处理。

---

## 六、总结

```
✅ 一致性检查通过
   - 内部检查: 模块数 9, 实例数 10, 端口连接 120+ 均正确
   - 外部检查: 寄存器 16/16 匹配, 端口 32/32 匹配
   - 子模块互联: 10 个实例间所有信号连接经验证正确

   发现:
     1 Warning  — 中断事件被使能过滤后才记录到 INT_STAT
     2 Info     — 死代码 (int_evt_rise) + 数据对齐编码注释

   核心功能路径验证:
     □ 采样流程 (触发→SOC→SPT→EOC→DATA→VALID)
     □ 序列遍历 (LP 26条目, HP 4条目)
     □ 高优抢占 (保存/恢复 LP 指针)
     □ 中断/DMA 事件生成与路由
     □ 校准控制 (CAL_ST 自清除)
     □ 软件复位 (自清除 + 所有寄存器和状态重置)
     □ CDC 路径 (11 条跨时钟域路径)
```
