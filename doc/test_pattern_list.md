# 单元测试模式列表 — tb/unit/tb_adc_top.v

## 概述

- **文件**: `tb/unit/tb_adc_top.v`
- **工具**: iverilog / VCS
- **波形**: `sim/waveform.fsdb`（VCS 回归 `make sim` 生成）
- **检查点**: 35 个 PASS/FAIL 断言

## 测试模式对照表

| # | 名称 | 时间窗口 | 检查点 | 关键信号 |
|:--:|:--|:--:|:--:|:--|
| 1 | APB 寄存器 R/W | 0 ~ 2.5 us | 6 | `paddr`, `pwdata`, `prdata` |
| 2 | 单次采样 | 2.5 ~ 51 us | 3 | `soc`, `muxon`, `eoc`, `ch_sel`, `adc_data`, `CH_DATA0` |
| 3 | 中断 | 51 ~ 77 us | 2 | `adc_int`, `INT_STAT` |
| 4 | 校准 | 77 ~ 83 us | 4 | `cal_st`, `cal_done`, `cal_val` |
| 5 | 软件复位 | 83 ~ 89 us | 3 | `CTRL[1]`, `ANA_CFG` |
| 6 | DMA | 89 ~ 98 us | 1 | `dma_req`, `dma_ack` |
| 7 | HP/LP 序列采样与抢占 | 79 ~ 138 us | 8 | `ch_sel` (1→2→3→4→5→6→**8→9→10→11**→7→15), STAT[LP_BUSY/HP_BUSY] |
| 8 | HP 在 LP SAMPLE 时抢占 | 138 ~ 174 us | 4 | 长 SPT=240 cyc, HP 在 MUXON↑ 时触发, preempt_abort |
| 9 | HP 在 LP WAIT_EOC 时抢占 | 174 ~ 207 us | 4 | 短 SPT=3 cyc, HP 在 MUXON↓ 后 EOC 前触发 |

> **时间窗口** 基于 `-vcd` / `-ssf` 波形时间轴，在 Verdi 中可直接跳转到对应区间。

---

## 各模式波形观察指南

### 模式 1：APB Register R/W

**时间**: 仿真开始 ~ 2.5 us

**检查项**：
- CTRL (0x00) → 写 0x7FF9，读回 0x7FF9
- TRIG (0x08) → 写 0x7F7E，读回 0x7E7E（bit 8 保留）
- INT_EN (0x0C) → 写 0x3F，读回 0x3F
- ANA_CFG (0x1C) → 写 0xA5A5，读回 0xA5A5
- LP_SEQ0 (0xAC) → 写 0x03020100，读回 0x03020100
- DMA_CTRL (0xA4) → 写 0x3F，读回 0x3F

**波形查看**：
- 加 `paddr`, `pwdata`, `prdata`, `psel`, `penable` 到波形
- 观察 paddr 遍历上述地址时，prdata 与写入值一致

---

### 模式 2：Software Trigger Single Sample

**时间**: ~2.5 us ~ 51 us（配置 LP_SEQ_LEN=1, SMPL_INTERVAL=15）

**检查项**：
- ✅ VALID=1：采样完成后 CH_DATA0[31]=1
- ✅ **数据正确性**：CH_DATA0[13:0] == adc_data（EOC 时的模拟输出值）
- ✅ VALID 清零：再次读 CH_DATA0 后 VALID=0

**波形查看**：
- 关键信号：`soc`, `muxon`, `eoc`, `ch_sel`, `adc_data`, `paddr`, `prdata`
- 时序路径：
  ```
  soc ↑ (posedge adc_clkn)
  muxon ↑ (与 SOC 同边沿)
  SPT 计数 (spt_cycles=3, 对应 spt_cnt=0→1→2)
  muxon ↓ (spt_done)
  模拟转换 ~14 周期
  eoc ↑ (negedge adc_clk) + adc_data 有效
  ```
- 数据路径：`adc_data`（EOC 时刻）→ `CH_DATA0` 寄存器（`paddr=0x24` 读回）

---

### 模式 3：Interrupt Test

**时间**: ~51 us ~ 77 us

**检查项**：
- ✅ LP_EOC 中断：采样完成后 `adc_int` 拉高，INT_STAT[0]=1
- ✅ W1C 清除：写 INT_STAT=1 → INT_STAT[0]=0，`adc_int` 拉低

**波形查看**：
- 加 `adc_int`, `paddr=0x10` 的读写
- 观察中断产生 → 读取 INT_STAT → W1C 清除 → 中断恢复

---

### 模式 4：Calibration

**时间**: ~77 us ~ 83 us

**检查项**：
- ✅ `cal_done` 在 cal_st 置位后固定 20 个 ADC_CLK 周期由模拟模型置 1（电平保持）
- ✅ `cal_val` 读取为 0x2A（`adc_analog_model.v` 固定校准码 6'h2A）

**波形查看**：
- 加 `cal_st`, `cal_done`, `cal_val`, `paddr=0x14/0x18`
- 时序路径：cal_st 在 posedge adc_clkn 拉高 → 模拟在 posedge adc_clk 计数 20 周期 →
  cal_done/cal_val 电平拉高 → 控制器 posedge adc_clkn 采样 → 锁存 cal_val、清 cal_st →
  模拟 cal_done 跟随回 0

---

### 模式 5：Software Reset

**时间**: ~83 us ~ 89 us

**检查项**：
- ✅ ANA_CFG 写入非零值后，SW_RST 使其回到 0
- ✅ SW_RST 自清除（CTRL[1] 写 1 后自动归 0）

**波形查看**：
- 先写 ANA_CFG=0xA5A5 → 读回确认
- 写 CTRL[1]=1（SW_RST）→ 观察 ANA_CFG 复位
- 读 CTRL[1] 确认已自清除

---

### 模式 6：DMA Request

**时间**: ~89 us ~ 98 us

**检查项**：
- ✅ 采样完成后 `dma_req` 断言

**波形查看**：
- 加 `dma_req`, `dma_ack`，观察 EOC 后 dma_req 是否拉高

---

### 模式 7：HP/LP Sequence Sampling with Preemption

**时间**: ~79 us ~ 138 us

**检查项**（8 项）：
- ✅ HP 通道（CH8~CH11）全部 VALID=1
- ✅ HP 数据正确：CH8[13:0]、CH11[13:0] == EOC 时的 adc_data
- ✅ LP 通道（CH1~CH7, CH15）全部 VALID=1
- ✅ LP 数据正确：CH1（抢占前）、CH4（被抢占）、CH7（恢复后）、CH15（恢复后）

**配置**：
```
LP_SEQ0 = 0x04030201 → LP: CH1, CH2, CH3, CH4
LP_SEQ1 = 0x0F070605 → LP: CH5, CH6, CH7, CH15
LP_SEQ_LEN = 8
HP_SEQ  = 0x0B0A0908 → HP: CH8, CH9, CH10, CH11
HP_SEQ_LEN = 4
CTRL    = 0x0000_0201 → ADC_EN=1, SPT0=2 (14 cycles)
```

**波形查看**：
- 关键信号：`ch_sel`, `soc`, `muxon`, `eoc`, `stat_lp_busy`, `stat_hp_busy`
- 观察 ch_sel 切换序列：1→2→3→4→5→6 → **8→9→10→11** → 7→15
- HP 触发后 `ch_sel` 立即跳到 CH8（ch_sel 在 preempt_abort 时切换）
- LP_BUSY=1 → HP_BUSY=1（抢占期间两者同时为 1）→ LP_BUSY=1（恢复）→ 全部=0
- MUXON 在 preempt_abort 时提前拉低，然后重新拉高开始 HP SPT

---

### 模式 8：HP Preempt During LP SAMPLE

**时间**: ~138 us ~ 174 us

**目的**：验证 HP 在 LP 正在采样时（ST_LP_SAMPLE，MUXON↑）触发，FSM 走 `preempt_abort` 路径。

**检查项**（4 项）：
- ✅ LP CH1 VALID=1（preempt_abort 强制 MUXON↓，模拟模型开始转换）
- ✅ LP CH1 数据正确
- ✅ HP CH8 VALID=1（HP SOC 在 preempt 后立即触发）
- ✅ HP CH8 数据正确

**配置**：
```
LP_CH = CH1 (单通道)
HP_CH = CH8 (单通道)
CTRL  = 0x0000_0701 → ADC_EN=1, SPT0=7 (240 cycles = 9.6us 采样时间)
```

**时序流**：
```
LP trigger → wait 2us → HP trigger (MUXON still high)
  LP state: ST_LP_SAMPLE → ST_LP_PREEMPT → ST_HP_SAMPLE
  preempt_abort → MUXON↓ → analog samples LP CH1 → conversion starts
  → HP SOC fires → HP CH8 samples → HP CH8 EOC → LP CH1 EOC (from preempted conversion)
```

---

### 模式 9：HP Preempt During LP WAIT_EOC

**时间**: ~174 us ~ 207 us

**目的**：验证 HP 在 LP 等待 EOC 时（ST_LP_WAIT_EOC，SPT 完成，EOC 未到）触发。

**检查项**（4 项）：
- ✅ LP CH1 VALID=1（LP 转换已在 preempt 前启动，EOC 正常到达）
- ✅ LP CH1 数据正确
- ✅ HP CH8 VALID=1（HP 在 WAIT_EOC 时抢占）
- ✅ HP CH8 数据正确

**配置**：
```
LP_CH = CH1 (单通道)
HP_CH = CH8 (单通道)
CTRL  = 0x0000_0001 → ADC_EN=1, SPT0=0 (3 cycles = 120ns 采样时间)
```

**时序计算**：
```
LP trigger @ T=0
  SPT done   @ T=120ns  → MUXON↓, LP enters ST_LP_WAIT_EOC
  EOC arrives @ T≈680ns (120ns SPT + 560ns conversion)
HP trigger @ T=300ns → LP still in WAIT_EOC, EOC not yet arrived
  → HP preempts from ST_LP_WAIT_EOC
  → HP CH8 runs → HP CH8 EOC → LP CH1 EOC (already in flight)
```

---

## 32 通道 smoke — tb/unit/tb_adc_top_32ch.v

> 定向闭合 b75842f 验证缺口（N>=27 时 LP_DATA[26:31] @0x8C~0xA0 读回有效）。
> 聚焦缺口，不做全回归（中断/校准/sw复位/DMA/抢占由 26ch+8ch TB 覆盖）。

- **文件**: `tb/unit/tb_adc_top_32ch.v`
- **配置**: `ADC_NUM_CH=32` / `ADC_DATA_W=14` / `ADC_SPT1_CH_MASK=0`
- **工具**: `make test-unit` 自动发现（iverilog -g2012 / VCS）
- **检查点**: 79 个 PASS/FAIL 断言

| # | 名称 | 检查点 | 关键信号/地址 |
|:--:|:--|:--:|:--|
| 1 | APB RW（N=32 适配） | 9 | LP_SEQ_LEN 复位=0x20 + 6bit RW、CTRL/TRIG/INT_EN/ANA_CFG/LP_SEQ0/DMA_CTRL 读写 |
| 2 | 32 条目 LP 扫描（b75842f 闭合） | 64 | LP_DATA[0:31] VALID+data，[26:31] @0x8C~0xA0 显式 GAP-CLOSE 证据 |
| 3 | 边界 + LP_SEQ_RSV + LP_SEQ_LEN | 6 | 0xA0/0xA4 边界、LP_SEQ7 @0xD4、rsv 高位读 0（0xFFFFFFFF 读 0x1F1F1F1F） |

Test 2 缺口闭合要点：编程 LP_SEQ0..LP_SEQ7 = CH0..CH31、LP_SEQ_LEN=32，SW 触发后
读回全部 32 个 LP_DATA。LP_DATA[26:31] 对应地址 0x8C/0x90/0x94/0x98/0x9C/0xA0，
正是 b75842f 修复前被 is_lp_data 旧上界 0x088 排除、走 default 读 0 的地址。
修复后上界 0x0A0 + lp_data_idx<NUM_LP_DATA guard 覆盖完整 32 预留区，6 行
GAP-CLOSE b75842f 日志逐条打印 VALID=1 + data 匹配 exp。
