# ADC 控制器 — 项目配置

## 目录说明

| 目录 | 用途 |
|:--|:--|
| `rtl/` | RTL 源代码（含 `rtl/std_cell/` 标准单元模型） |
| `tb/` | testbench 源码（模拟模型、总线模型、测试用例、断言、形式化属性） |
| `sim/` | 构建产物（编译结果、波形、日志），`sim/log/` 存放仿真日志 |
| `spec/` | 需求 / 规格文档 |
| `doc/` | 设计文档、架构图、审查报告、签收报告 |
| `scripts/` | 构建/测试/Lint 脚本、SDC 约束、综合 tcl |
| `syn/` | 综合交付件（DC tcl / PT STA tcl / Formality tcl / 网表 / SDF / 日志） |
| `ref/` | 参考资料 |

## 模块层次

```text
adc_top
├── adc_params.vh     — 参数化派生 localparam 集中定义（ADC_NUM_CH/ADC_DATA_W/ADC_SPT1_CH_MASK）
├── adc_rst_sync     — 异步复位同步器
├── adc_apb_if       — APB 32-bit 零等待接口
├── adc_regfile      — 双时钟域，参数化 LP_DATA/LP_SEQ 寄存器数，CDC sync
├── adc_trig_sync    — MCTM + SW 触发同步 + 源选择
├── adc_seq_fsm      — 核心 FSM，含 HP 抢占，SOC/MUXON 时序，参数化 ch_sel/seq_ptr/位宽
├── adc_int_ctrl     — 中断控制器
├── adc_dma_req      — DMA 请求控制器
├── adc_calib        — 已废弃 stub（逻辑移入 regfile PCLK 域，已从 filelist 移除）
└── adc_sync_cell    — 2-stage sync + edge detect
```

> **参数化：** 通道数 `ADC_NUM_CH`（默认 26，4~32）/ ADC 数据位宽 `ADC_DATA_W`
> （默认 14，1~16）/ SPT1 通道位图 `ADC_SPT1_CH_MASK`（默认 CH21/CH22）可配，
> 默认值与原固定设计一致，向后兼容。改参数只动 `rtl/adc_params.vh` 或实例化
> override。详见 `spec/adc_spec.md` §3.0 与 `doc/design/2026-07-20-parameterization-design.md`。

## 时钟域

| 时钟域 | 实际需求上限 | 仿真配置 | 同步关系 | CDC 要求 | 说明 |
|:--|:--:|:--:|:--|:--:|:--|
| PCLK | 200 MHz | 50 MHz (周期 20ns) | — | — | APB 总线时钟（与 ADC_CLK 异步） |
| **ADC_CLK + ADC_CLKn** | 60 MHz | 25 MHz (周期 40ns) | 同源反相（180° ± 0°） | ❌ 不需要 | ADC 工作时钟，两者为同步时钟 |

> **频率说明：** "实际需求上限"为器件需支持的最高工作频率，SDC
> （`scripts/adc_constraints.sdc`）按此约束综合，时序必须在该频率下闭合。
> "仿真配置"为当前 TB（`tb_adc_top.v` / `tb_top.sv`）所用时钟，低于上限，
> 用于功能验证；仿真通过不代表满足上限时序，上限时序由综合 STA 确认。

> **ADC_CLK ↔ ADC_CLKn 不是 CDC。** 两者来自同一 PLL，同频、固定相位差 180°，
> 综合时定义为 generated clock with invert，STA 做半周期路径分析。
> 跨这两个时钟域的信号只需 1 级采样寄存器，不需要 2 级同步器。
> RTL 中所有 adc_clkn → adc_clk 的跨域路径已按此实现（`adc_seq_fsm.v` muxon_clk 等）。

### 跨域信号归属

| 时钟域 | 信号 |
|:--|:--|
| **PCLK** | APB 接口、寄存器配置（CTRL/TRIG/INT_EN/INT_STAT/CAL_CTRL/CAL_VAL）、`int_stat`、`adc_int`、**校准控制**（`cal_st` 寄存器位、`CAL_DONE` 2 级同步读、`cal_val` 锁存） |
| **ADC_CLK** | FSM、`ch_data_adc[]`、`cfg_*`（PCLK→ADC_CLK CDC）、事件脉冲、DMA `dma_ndreq`、ch_sel（源于 ADC_CLKn） |
| **ADC_CLKn**（与 ADC_CLK 同步） | SOC 脉冲、MUXON 寄存器、SPT 计数器 |

> ADC_CLK 与 ADC_CLKn 为同步时钟域，路径之间只需 1 级跨域采样，不需要 2 级同步器。

## 开发流程

RTL 开发遵循 `CLAUDE.md` 标准工作流程。关键关卡：

- **Step 3a** — spec 接口时序完备性检查：spec 完成后，逐信号确认驱动沿/采样沿/时钟域后，方可进入 RTL 设计
- **Step 9i** — 每次设计修改仿真通过后，先分析是否需要同步更新 spec，需要则改完 spec 再进入下一步。不允许"先改 RTL，后面再补 spec"
- **Step 6b+** — `make vcs`（[MUST]）：lint 不替代 VCS 编译，两者都通过才算语法检查通过
- **Step 13** — 后仿（[OPTIONAL]）：本项目已完成零延迟 + SDF (tt/ssg) + UVM gate sim 全链路签收，详见 `doc/post_sim_report_2026-07-22.md`

## SDC 约束

时钟定义（频率、相位关系）在 `scripts/adc_constraints.sdc` 中。综合约束与 SDC
均由该文件定义，DC 编译、PT STA 共用同一约束源。

### 综合/STA 流程

本项目已完成全签收综合链路：

| 步骤 | 工具 | 角 | 结果 |
|:--|:--|:--:|:--:|
| 综合 | **DC** (TSMC28HPC+ PDK) | tt + ssg | ✅ 0 setup DRC 违例 |
| STA | **PT** | tt + ssg | ✅ 0 setup/hold 违例 |
| 形式验证 | **Formality** | tt | ✅ 1003 compare points |
| 后仿（零延迟） | VCS + gate netlist | — | ✅ 35/35 + UVM 18/18 |
| 后仿（SDF） | VCS + SDF | tt + ssg | ✅ 35/35（hold 伪违例已抑制） |

详见 `syn/dc_compile.tcl`、`syn/pt_sta.tcl`、`syn/fm_formality.tcl`，签收报告见
`doc/post_sim_report_2026-07-22.md`

## 验证环境

| 层级 | 方式 | 工具 | 波形 |
|:--|:--|:--:|:--|
| 单元测试 | `make test-unit` (verilog) | iverilog/VCS | `.vcd` / `.fsdb` |
| UVM 回归 | `make sim-uvm-regr` (18 case) | VCS | `.fsdb` |
| VCS 回归 | `make sim` | VCS | `.fsdb` |
| **后仿（零延迟）** | `make gate-sim` | VCS + gate netlist | `.fsdb` |
| **后仿（SDF）** | `make gate-sim-sdf` | VCS + SDF | `.fsdb` |
| **UVM 门级回归** | `make gate-sim-uvm-regr` (18 case) | VCS + gate netlist | `.fsdb` |

> 后仿需要 TSMC28HPC+ 标准单元 Verilog 仿真模型（含 specify 块），PDK 路径见
> `doc/post_sim_report_2026-07-22.md` §2。后仿目标自动判断工具有无 SDF 与
> gate 库，无则提示跳过。

## 测试模式（unit TB）

| # | 名称 | 检查点 | 时间窗口 |
|:--:|:--|:--:|:--:|
| 1 | APB Register RW | 6 | 0 ~ 2.5 us |
| 2 | Single Sample | 3 | 2.5 ~ 51 us |
| 3 | Interrupt | 2 | 51 ~ 77 us |
| 4 | Calibration | 4 | 77 ~ 83 us |
| 5 | SW Reset | 3 | 83 ~ 89 us |
| 6 | DMA | 1 | 89 ~ 98 us |
| 7 | HP/LP 序列采样与抢占 | 8 | 79 ~ 138 us |
| 8 | HP 在 LP SAMPLE 时抢占 | 4 | 138 ~ 174 us |
| 9 | HP 在 LP WAIT_EOC 时抢占 | 4 | 174 ~ 207 us |

详见 `doc/test_pattern_list.md`。
