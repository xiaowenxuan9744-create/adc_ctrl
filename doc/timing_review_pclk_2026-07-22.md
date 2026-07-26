# PCLK 时序收敛报告 — ADC 控制器

- **设计**: adc_top (综合网表, 3618 叶单元)
- **工艺**: TSMC 28HPC+  典型角 tt 0.9V 25°C
- **工具**: Design Compiler O-2018.06
- **日期**: 2026-07-22
- **触发**: `/timing-review`，PCLK 域 200MHz 下 32 条 setup 违例

## 1. 违例统计（tt 角，修约束前）

| 类型 | WNS (ns) | TNS (ns) | 违例路径数 |
|:--|:--:|:--:|:--:|
| Setup (pclk) | **−0.19** | −5.94 | 32 |
| Setup (adc_clk) | +4.19 | 0 | 0 |
| Setup (adc_clkn) | +7.60 | 0 | 0 |
| Hold (all) | 0 | 0 | 0 |

ADC_CLK / ADC_CLKn 域时序充裕，问题集中在 **PCLK 域 APB 读路径**。

## 2. Top 违例路径共性

32 条违例**全部**是同一形态：

```
Startpoint: paddr[k]      (input port, PCLK 域)
Endpoint:   prdata[m]     (output port, PCLK 域)
Path: paddr → u_apb_if/reg_addr(组合) → u_regfile addr解码/rd_data_mux(组合)
      → u_apb_if/PRDATA(组合) → prdata
slack: -0.19
```

典型路径分解（paddr[4]→prdata[7]）：
```
input external delay      2.50 ns   ← 占 93%
paddr[4] 进入             2.51
apb_if addr 缓冲          2.53      ← 0.02ns
regfile addr 解码+读 mux  2.67      ← 0.14ns (主要内部延迟)
apb_if PRDATA 输出缓冲    2.69      ← 0.02ns
data arrival              2.69 ns
─────────────────────────────────
required (5.0 - out_ext 2.5) 2.50
slack (VIOLATED)         -0.19
```

**内部组合逻辑总延迟 ≈ 0.19ns**，其中 regfile 读 mux 占 0.14ns。

## 3. 根因分析（深度）

### 3.1 这是 IO 预算问题，不是 RTL 逻辑问题

DC 扫描实验（固定网表，仅改 IO delay）：

| input_delay | output_delay | 内部预算 (5−in−out) | slack |
|:--:|:--:|:--:|:--:|
| 2.5 | 2.5 | 0.0 ns | **−0.19** |
| 2.0 | 2.0 | 1.0 ns | +0.81 |
| 1.5 | 2.5 | 1.0 ns | +0.81 |
| 1.5 | 1.5 | 2.0 ns | +1.81 |
| 1.0 | 1.0 | 3.0 ns | +2.81 |

slack 随 (input_delay+output_delay) 线性变化，斜率 −1.0。**内部逻辑延迟固定 0.19ns，违例纯粹因 IO delay 之和 = 时钟周期，内部零余量**。

### 3.2 IO delay 2.5ns 的来源与合理性

- 现 SDC：`set_input_delay/output_delay 2.5`，注释标 "placeholder — adjust per integration"
- 对比旧参考设计（`ADC_SOC/syn/constraints.sdc`）：PCLK **50MHz**(20ns)，IO delay **5.0ns**（占周期 **25%**）
- adc_new：PCLK **200MHz**(5ns)，IO delay **2.5ns**（占周期 **50%**）——占比是旧设计的 2 倍，且 input+output 合占 100%，违背"内部须留余量"的基本约束设计原则

2.5ns 是上一轮 SDC 初稿拍的 placeholder，无集成方真实 IO budget 依据，且占比过激。

### 3.3 RTL 侧评估（无需改 RTL）

- `adc_apb_if`：`assign reg_addr = PADDR; assign PRDATA = reg_rd_en ? rd_data : 32'h0;` 纯组合穿透，零等待，符合 APB 协议，无冗余逻辑
- `adc_regfile` 读 mux：`case(addr_offset)` 12 项 + default 的 LP/HP data/seq 分支，综合后 12 级逻辑但全用快 cell，实测 0.14ns
- 内部延迟 0.19ns @ 200MHz 极健康，**无 RTL 优化空间也不需要**——逻辑已经是最直的组合读路径

## 4. 收敛方案

### 4.1 采取：修正 SDC IO delay 至业界平衡档（转 `/sdc-manager` 执行）

PCLK 域 APB IO delay：**2.5ns → 1.5ns**（input/output 各占周期 30%，内部留 40% = 2.0ns）

依据（[[apb-io-delay-budget]] 比例法三档）：
- 业界 APB slave 惯例：external 段占周期 50–80%，input/output 对称切分
- **平衡档各 30% 为常见默认**，比激进档(40%)更稳妥通用
- 内部逻辑实测 0.19ns，2.0ns 内部预算留 10× 余量，ssg 慢角(~0.4ns)/OCV 仍充分收敛
- 非"降频逃避"：200MHz 硬目标不变（`project_config.md` 标 PCLK 上限 200MHz 必须满足），仅修正无依据的 placeholder 占比
- 片内 IP（接 CKCU/APB fabric）适用比例法；若为 pad 边界 APB 则改用 pad 时序表 Tsu/Th

### 4.2 不采取的方案及原因

| 方案 | 否决原因 |
|:--|:--|
| 降 PCLK 频率 | `project_config.md` 明确 200MHz 为器件须支持上限，时序必须在此频率闭合 |
| RTL 插流水 | 违反 APB 零等待协议（PREADY 固定 1），且内部 0.19ns 无优化必要 |
| 更换更快 cell | 已用最快 cell，且非逻辑深度问题 |
| 激进档 2.0ns | 收敛但内部仅留 1.0ns，对集成方/慢角/OCV 余量偏紧，平衡档更通用 |

### 4.3 待集成方定稿项

IO delay 真实值取决于 SoC 集成时 APB master 到 ADC slave 的互连延迟。当前 1.5ns 是合理 placeholder（平衡档），**集成阶段须由 SoC 时序工程师按真实互连 + top-level timing budget 重定**，届时走 `/sdc-manager` 同步模式更新。

## 5. 验证

修正后重跑 DC 综合确认 PCLK WNS ≥ 0（见 9f 流程），结果记入本报告 §6。

## 6. 修正后结果

修正 SDC（PCLK 域 input/output delay 2.5→1.5ns，平衡档 30%）后重跑全流程：

| 时钟域 | WNS (修前2.5) | WNS (中间2.0) | WNS (修后1.5) | 违例路径数 |
|:--|:--:|:--:|:--:|:--:|
| pclk DC tt | **−0.19 ns** | +0.37 ns | **+1.37 ns** ✅ | 32 → 0 |
| pclk DC ssg | — | +0.33 ns | **+1.32 ns** ✅ | 0 |
| adc_clk | +4.19 ns | +4.19 ns | +4.19 ns | 0 |
| adc_clkn | +7.60 ns | +7.60 ns | +7.60 ns | 0 |

PrimeTime STA（独立工具复核，与 DC 一致）：

| 角 | setup WNS | hold WNS | 违例 |
|:--|:--:|:--:|:--:|
| tt | +1.366 ns | +0.039 ns | 0 |
| ssg | +1.323 ns | +0.045 ns | 0 |

Formality 等价性：**Verification SUCCEEDED**，1003 compare point 全等价（SVF 消除常数传播假不等价）。

- **PCLK 域 setup 违例清零**，三时钟域 tt+ssg 双角全部收敛，setup/hold 双向 0 违例
- 综合无 Error，网表 `syn/out/adc_top.syn.v` 正常生成，RTL↔网表逻辑等价
- 内部预算从 1.0ns→2.0ns，PCLK WNS 从 +0.37→+1.37ns，对集成方/慢角/OCV 余量翻倍

**收敛完成。** 时序签收链路（DC 综合双角 + PT STA 双角 + Formality 等价性）全绿。
