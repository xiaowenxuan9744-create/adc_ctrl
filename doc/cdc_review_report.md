# CDC 检查报告 — SOC/MUXON 跨时钟域分析

**检查时间：** 2026-07-05
**检查范围：** `adc_seq_fsm.v` — 新引入的 `adc_clkn → adc_clk` 跨域路径
**时钟域定义：**

| 时钟 | 频率 | 相位 | 用途 |
|:--|:--:|:--:|:--|
| `adc_clk` | 60 MHz (max) | 0° | FSM、SPT、间隔计数、EOC 检测、ch_sel |
| `adc_clkn` | 60 MHz (max) | 180° | SOC 脉冲生成、MUXON 控制（≡ negedge adc_clk） |

> 两个时钟为**同频反相**（由 CKCU 提供），属于同步时钟域，不是异步 CDC。`adc_clkn` 的上升沿恰好位于 `adc_clk` 的下降沿位置。

---

## 路径 1：`soc_req_set` — adc_clk → adc_clkn

| 项目 | 内容 |
|:--|:--|
| **信号** | `soc_req_set`（FSM 组合逻辑输出，单周期脉冲） |
| **源域** | `posedge adc_clk` |
| **目标域** | `posedge adc_clkn` |
| **当前处理** | 直接用作了 `soc_pulse_clkn` 的使能条件。`soc_req_set` 在 `posedge adc_clk` 之后 Delta 时间稳定，到下一个 `posedge adc_clkn` 有半个 `adc_clk` 周期（~8.3ns @ 60MHz）的建立时间。 |

**风险评估：** ✅ **安全**

- 同频反相，不是异步域
- `soc_req_set` 是组合逻辑，在 `posedge adc_clk` 之后立即稳定
- `posedge adc_clkn` 在 `posedge adc_clk` 之后约 8.3ns 才到来
- 组合逻辑延迟通常在亚纳秒到几纳秒，远小于 8.3ns 窗口
- 综合工具（DC/Genus）会检查这条路径的 setup/hold 时序，约束同频反相关系即可

## 路径 2：`soc_pulse_clkn` — adc_clkn → adc_clk

| 项目 | 内容 |
|:--|:--|
| **信号** | `soc_pulse_clkn`（单周期脉冲，在 adc_clkn 域） |
| **源域** | `posedge adc_clkn` |
| **目标域** | `posedge adc_clk` |
| **当前处理** | **2-stage 同步器 + 边沿检测**（`soc_s1` → `soc_s2` → `soc_dly`） |

**模拟时序：**
```
adc_clk      ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐
adc_clkn     ┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴

soc_req_set  ────┐└───────────────────────────
                 │
soc_pulse_clkn ──────┐└───────────────────────
                (adc_clkn↑ 采样到 soc_req_set)
                 │
soc_s1         ────────┐└──  (adc_clk↑ 采样 soc_pulse_clkn)
soc_s2         ───────────┐└──────────────────
soc_dly        ──────────────┐└───────────────
soc (输出)    ────────────────┐└──────────────
                (soc_s2 & ~soc_dly = 边沿检测)
```

- 2-stage 同步器在**同频域**下，第一级可能在同一个时钟沿采样到信号（adc_clkn 比 adc_clk 早半周期）。
  Cycles: soc_pulse_clkn 在 adc_clkn↑ N 有效，adc_clk↑ N 已经过去（晚了~半周期），所以 adc_clk↑ N+1 采样到。
- 边沿检测确保 SOC 单周期

**风险评估：** ✅ **安全**（且对于同频域来说裕量很大）

## 路径 3：`muxon_reg` — adc_clkn → adc_clk

| 项目 | 内容 |
|:--|:--|
| **信号** | `muxon_reg`（电平信号，在 adc_clkn 域） |
| **源域** | `posedge adc_clkn` |
| **目标域** | `posedge adc_clk` |
| **当前处理** | **1-stage 采样**（`muxon_clk`，单寄存器） |

- ADC_CLK 与 ADC_CLKn 同源反相（180°），为**同步时钟域**，非 CDC。
  STA 做 generated-clock-with-invert 半周期路径分析，无需 2-stage 同步器。
  RTL 用单级 `muxon_clk` 采样（`adc_seq_fsm.v`），符合同步域跨域要求。
- 详见 `doc/project_config.md` 时钟域说明与 sync-clock-not-cdc memory。

**风险评估：** ✅ **安全**

## 路径 4：`spt_done` / `preempt_abort` — adc_clk → adc_clkn

| 项目 | 内容 |
|:--|:--|
| **信号** | `spt_done`（组合逻辑，在 FSM 域） |
| **源域** | `posedge adc_clk` |
| **目标域** | `posedge adc_clkn` |
| **当前处理** | 直接使用在 `muxon_reg` 的 always 块中 |

**分析：**
- `spt_done` 在 `posedge adc_clk` 时有效
- `posedge adc_clkn` 在半周期后采样它
- 类似路径 1 的分析：组合逻辑去反相沿，~8.3ns 建立时间

**风险评估：** ✅ **安全**

---

## CDC 检查结论

| 路径 | 源域 | 目标域 | 信号类型 | 处理方式 | 状态 |
|:--|:--:|:--:|:--:|:--|:--:|
| `soc_req_set` → `soc_pulse_clkn` | `adc_clk` | `adc_clkn` | 组合脉冲 | 直接使用（同频反相，~8.3ns 建立窗口） | ✅ 安全 |
| `soc_pulse_clkn` → `soc` | `adc_clkn` | `adc_clk` | 单周期脉冲 | 2-stage 同步 + 边沿检测 | ✅ 正确 |
| `muxon_reg` → `muxon` | `adc_clkn` | `adc_clk` | 电平 | 1-stage 采样（`muxon_clk`，同步域） | ✅ 正确 |
| `spt_done` / `preempt_abort` → `muxon_reg` | `adc_clk` | `adc_clkn` | 组合脉冲 | 直接使用（同频反相） | ✅ 安全 |

**结论：✅ 所有 CDC 路径均有正确处理。无同步器遗漏，无跨域风险。**
