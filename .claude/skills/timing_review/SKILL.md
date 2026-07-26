---
name: timing-review
description: 时序报告分析助手，解析 PT/DC 报告，提取关键路径并给出修复建议
triggers:
  - 时序分析
  - timing报告
  - 时序违例
  - timing review
---

# Timing Review - 时序报告分析助手

解析 PrimeTime / Design Compiler 时序报告，提取关键路径并给出修复建议。

## 输入

- 时序报告文件（.rpt / .rpt.gz）
- 时钟定义（可选）
- 设计约束（可选）

## 输出

- 时序违例汇总
- Top 10 关键路径分析
- 修复建议

## 时序报告解析

### 1. Setup Time 违例

**报告格式识别**：
```
Startpoint: reg_a (rising edge-triggered flip-flop clocked by clk_sys)
Endpoint:   reg_b (rising edge-triggered flip-flop clocked by clk_sys)
Path Group: clk_sys
Path Type:  max

Point                        Incr       Path
---------------------------------------------------------------
clock clk_sys (rise edge)    0.00       0.00
clock network delay (ideal)  0.50       0.50
reg_a/CK (DFF)               0.00       0.50 r
reg_a/Q (DFF)                0.20       0.70 f
...
reg_b/D (DFF)                0.00       3.20 r
data arrival time                       3.20

clock clk_sys (rise edge)    4.00       4.00
clock network delay (ideal)  0.50       4.50
clock uncertainty           -0.30       4.20
reg_b/CK (DFF)               0.00       4.20 r
library setup time          -0.15       4.05
data required time                      4.05
---------------------------------------------------------------
data required time                      4.05
data arrival time           -3.20
---------------------------------------------------------------
slack (VIOLATED)                       -0.85
```

**关键信息提取**：
- 起点终点: `reg_a` → `reg_b`
- 违例量: -0.85ns
- 路径延迟: 3.20ns
- 时钟周期: 4.00ns (250MHz)

### 2. Hold Time 违例

**报告格式识别**：
```
Path Type:  min

slack (VIOLATED)                       -0.12
```

### 3. 关键路径分析

| 指标 | 含义 | 优化方向 |
|---|---|---|
| Data Path Delay | 数据路径延迟 | 逻辑优化/流水线 |
| Clock Network Delay | 时钟网络延迟 | CTS 优化 |
| Clock Uncertainty | 时钟不确定性 | PLL/时钟源优化 |
| Setup/Hold Time | 建立/保持时间 | 更换标准单元 |

## 违例修复策略

### 1. Setup 违例修复

| 方法 | 适用场景 | 效果 |
|---|---|---|
| 逻辑优化 | 组合逻辑过深 | 中 |
| 插入流水线 | 长数据通路 | 高 |
| 更换更快 cell | 关键路径 | 中 |
| 降低频率 | 临时方案 | 高 |
| 优化约束 | 约束过紧 | 低 |

**逻辑优化示例**：
```systemverilog
// ❌ 问题: 组合逻辑过深
assign out = (a & b) | (c & d) | (e & f & g) | (h & i & j & k);

// ✅ 优化: 拆分流水级
always @(posedge clk) begin
  stage1 <= (a & b) | (c & d);
  stage2 <= (e & f & g) | (h & i & j & k);
end
assign out = stage1 | stage2;
```

### 2. Hold 违例修复

| 方法 | 适用场景 | 效果 |
|---|---|---|
| 插入 buffer | 路径延迟过小 | 高 |
| 更换更慢 cell | 特定路径 | 中 |
| 调整时钟偏移 | 全局问题 | 高 |

**Hold 修复示例**：
```
// 原路径: data_path_delay = 0.3ns, hold_time = 0.4ns
// 违例: 0.3ns < 0.4ns (hold violated)

// 解决方案: 插入 buffer 增加延迟
// buffer_delay = 0.2ns
// 修复后: 0.3 + 0.2 = 0.5ns > 0.4ns (hold met)
```

### 3. 跨时钟域违例

| 类型 | 问题 | 处理 |
|---|---|---|
| 异步路径 | 无时序约束 | 转交 `/sdc-manager` 添加 false_path |
| 多周期路径 | 需要 2+ 周期 | 转交 `/sdc-manager` 添加 multicycle_path |
| 伪路径 | 逻辑不存在的路径 | 转交 `/sdc-manager` 添加 false_path |

> **SDC 约束改动转交 sdc-manager**：本 skill 职责是"解读时序报告 + 给 RTL
> 修复建议（流水线/cell 优化/buffer）"，SDC 约束的增删改由 `/sdc-manager`
> 负责（同步模式 + 自检）。识别出需 SDC 调整的违例后，输出"建议 SDC 改动
> 清单"转交 sdc-manager 执行，不在本 skill 内直接写 SDC。

**建议 SDC 改动清单示例**（转交 sdc-manager）：
```
- 异步路径 reg_a/Q → reg_b/D → 建议 set_false_path（转 sdc-manager 执行）
- 多周期路径 reg_c/Q → reg_d/D → 建议 set_multicycle_path 2 -setup（转 sdc-manager）
```

## 分析报告模板

```markdown
# 时序分析报告

## 概要
- **设计**: xxx
- **时钟**: clk_sys @ 250 MHz
- **分析日期**: YYYY-MM-DD

## 违例统计

| 类型 | WNS (ns) | TNS (ns) | 违例路径数 |
|---|---|---|---|
| Setup | -0.85 | -12.5 | 15 |
| Hold | -0.12 | -1.8 | 3 |

## Top 10 Setup 违例路径

| 排名 | 起点 | 终点 | Slack (ns) | 路径延迟 (ns) |
|---|---|---|---|---|
| 1 | reg_a | reg_b | -0.85 | 3.20 |
| 2 | reg_c | reg_d | -0.72 | 2.95 |
| 3 | reg_e | reg_f | -0.58 | 2.81 |

## 关键路径详情

### Path #1: reg_a → reg_b
```
违例量: -0.85 ns
时钟周期: 4.00 ns (250 MHz)
数据路径延迟: 3.20 ns

路径分解:
  reg_a/Q → logic_1: 0.50 ns (组合逻辑)
  logic_1 → logic_2: 0.80 ns (组合逻辑)
  logic_2 → logic_3: 0.90 ns (组合逻辑)
  logic_3 → reg_b/D: 1.00 ns (组合逻辑)

建议修复:
  1. logic_2 使用更快的 cell (AOI22 → AOI22_X1)
  2. 考虑在 logic_2 后插入流水级
```

## 修复建议汇总

| 优先级 | 问题 | 修复方案 | 预期改善 |
|---|---|---|---|
| P0 | reg_a→reg_b | 插入流水级 | +1.0 ns |
| P1 | reg_c→reg_d | 更换快速 cell | +0.3 ns |
| P2 | Hold违例 | 插入 buffer | +0.2 ns |

## 下一步行动
1. 修复 P0 级别 setup 违例
2. 重新综合并检查时序
3. 解决 hold 违例
```

## 快速命令

```
分析范围:
  - 分析单文件: "分析 timing.rpt"
  - 找最差路径: "提取 Top 10 违例路径"
  - SDC 改动建议: "输出需 SDC 调整的违例清单（转交 sdc-manager 执行）"
```
