---
name: cdc-review
description: 跨时钟域检查助手，分析 CDC 路径并给出同步策略建议；支持刷新模式同步 RTL 变更
triggers:
  - CDC检查
  - 跨时钟域
  - 时钟域检查
  - CDC review
  - CDC刷新
  - 同步器检查
---

# CDC Review - 跨时钟域检查助手

分析 RTL 代码中的跨时钟域路径，识别潜在问题并给出同步策略建议。

> **两种运行模式**：
> - **首次模式**（默认）：全量扫描 RTL，生成 `cdc_review_report.md`
> - **刷新模式**（`/cdc-review refresh` 或指定 `--refresh`）：RTL 变更后只重审
>   受影响路径，更新报告并追加变更记录。**避免报告腐烂**（见下方痛点）。
>
> **痛点来源**（示例：某项目曾发生）：早期只有首次模式，报告是一次性快照。
> RTL 变更后旧报告未刷新——某跨域信号已从 2-stage 同步改为 1-stage 采样
> （同源反相同步时钟），报告仍写 "2-stage 同步器"，误导后续 CDC 决策。
> 刷新模式解决此问题。

## 输入

- RTL 代码文件
- 时钟域定义（时钟信号列表）
- 约束文件（可选）
- **刷新模式额外输入**：已有的 `cdc_review_report.md` + git diff（自上次报告以来的 RTL 变更）

## 输出

- CDC 路径分析报告（`cdc_review_report.md`）
- 同步器缺失警告
- 修复建议
- **刷新模式**：变更记录段（记录本次刷新了哪些路径、为什么）

## CDC 问题分类

### 1. 单比特信号跨域

| 类型 | 风险 | 解决方案 |
|---|---|---|
| 控制信号 | 中 | 双触发器同步器 |
| 使能信号 | 中 | 双触发器同步器 + 边沿检测 |
| 握手信号 | 高 | 握手协议同步 |

**双触发器同步器**：
```systemverilog
// 双触发器同步器（适用于单比特控制信号）
module sync_2ff (
  input  wire clk_dst,
  input  wire rst_n,
  input  wire data_in,
  output reg  data_out
);
  reg data_sync1;
  
  always @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n) begin
      data_sync1 <= 1'b0;
      data_out   <= 1'b0;
    end else begin
      data_sync1 <= data_in;
      data_out   <= data_sync1;
    end
  end
endmodule
```

**边沿检测同步器**：
```systemverilog
// 边沿检测同步器（适用于脉冲信号）
module sync_edge_det (
  input  wire clk_dst,
  input  wire rst_n,
  input  wire pulse_in,
  output wire pulse_out
);
  reg [2:0] sync_chain;
  
  always @(posedge clk_dst or negedge rst_n) begin
    if (!rst_n)
      sync_chain <= 3'b000;
    else
      sync_chain <= {sync_chain[1:0], pulse_in};
  end
  
  // 上升沿检测
  assign pulse_out = sync_chain[1] & ~sync_chain[2];
endmodule
```

### 2. 多比特信号跨域

| 类型 | 风险 | 解决方案 |
|---|---|---|
| 数据总线 | 高 | 异步 FIFO |
| 计数器 | 高 | Gray 码计数器 |
| 状态向量 | 高 | 握手协议 |

**异步 FIFO**：
```systemverilog
// 异步 FIFO 示例（使用 Gray 码指针）
module async_fifo #(
  parameter DATA_WIDTH = 32,
  parameter DEPTH      = 16
) (
  // Write domain
  input  wire                  wr_clk,
  input  wire                  wr_rst_n,
  input  wire                  wr_en,
  input  wire [DATA_WIDTH-1:0] wr_data,
  output wire                  full,
  
  // Read domain
  input  wire                  rd_clk,
  input  wire                  rd_rst_n,
  input  wire                  rd_en,
  output wire [DATA_WIDTH-1:0] rd_data,
  output wire                  empty
);
  // Gray code pointers for CDC
  // Pointer sync logic
  // Memory array
  // ... implementation
endmodule
```

**握手协议**：
```systemverilog
// 握手协议同步（适用于多比特数据）
// TX domain -> RX domain
// 1. TX asserts valid with data
// 2. RX syncs valid, captures data
// 3. RX asserts ack
// 4. TX syncs ack, deasserts valid
```

### 3. 快时钟到慢时钟

| 问题 | 风险 | 解决方案 |
|---|---|---|
| 信号丢失 | 高 | 脉冲展宽 |
| 采样失败 | 高 | 握手协议 |

**脉冲展宽**：
```systemverilog
// 脉冲展宽电路（快到慢）
module pulse_stretch (
  input  wire clk_src,
  input  wire clk_dst,
  input  wire rst_n,
  input  wire pulse_in,
  output wire pulse_out
);
  reg stretch_reg;
  reg ack_sync;
  
  // Source domain: stretch pulse until ack
  always @(posedge clk_src or negedge rst_n) begin
    if (!rst_n)
      stretch_reg <= 1'b0;
    else if (pulse_in)
      stretch_reg <= 1'b1;
    else if (ack_sync)
      stretch_reg <= 1'b0;
  end
  
  // Destination domain: sync and detect
  // ack feedback sync
endmodule
```

## CDC 检查流程

### 模式选择

```
首次模式（无已有报告，或用户要求全量重审）:
  → 完整执行 Step 1-5，生成全新 cdc_review_report.md

刷新模式（已有报告 + RTL 有变更，/cdc-review refresh）:
  → 执行 Step 0 读取旧报告 + git diff
  → 只对受影响路径重审（Step 2 限定范围）
  → 更新报告对应段落 + 追加变更记录
```

### Step 0: 刷新模式 — 识别受影响路径（仅刷新模式）

```
1. 读取已有 cdc_review_report.md，提取每条 CDC 路径标注的 RTL 位置
   （文件名:行号 或 信号名）
2. git diff <上次报告 commit>..HEAD -- rtl/ 找出变更的 RTL 文件
3. 交叉匹配：旧报告中涉及的信号/文件是否在本次 diff 中变更
   - 变更的路径 → 标记"需重审"
   - 未变更的路径 → 保留旧报告结论（不重复审）
4. 若无任何受影响路径 → 报告"CDC 路径无变更，报告无需刷新"，退出
```

> **关键**：刷新模式不重写整份报告，只更新受影响段落 + 追加变更记录，
> 保留历史结论的可追溯性。

### Step 1: 识别时钟域
```
时钟域分析:
  clk_sys   : 系统主时钟  (100 MHz)
  clk_peri  : 外设时钟    (50 MHz)
  clk_slow  : 慢速时钟    (10 MHz)
```

> **同步时钟识别**：同源、固定相位差（如反相 180°）的时钟为**同步时钟**，
> 非异步 CDC。此类路径只需 1 级采样，不需要 2-stage 同步器。务必在报告里
> 明确标注"同步域"而非"CDC 路径"，避免综合时误设 false_path 掩盖真实时序。
> （示例：某项目同源反相时钟对为同步域）

### Step 2: 扫描跨域路径
```
跨域信号扫描:
  [WARNING] sig_ctrl -> clk_sys -> clk_peri (无同步器)
  [OK]      data_bus  -> clk_sys -> clk_peri (使用异步FIFO)
  [OK]      status    -> clk_peri -> clk_sys (双触发器同步)
```

### Step 3: 分析同步策略
| 路径 | 信号类型 | 当前策略 | 建议 |
|---|---|---|---|
| ctrl → peri | 单比特控制 | 无 | 添加双触发器 |
| sys → peri | 数据总线 | 异步FIFO | ✓ 正确 |
| peri → sys | 状态向量 | 握手 | ✓ 正确 |

## 常见 CDC 错误

### 错误 1: 直接跨域连接
```systemverilog
// ❌ 错误: 直接跨域连接
always @(posedge clk_a) begin
  data_a <= data_b;  // data_b 来自 clk_b 域
end

// ✅ 正确: 使用同步器
sync_2ff u_sync (
  .clk_dst  (clk_a),
  .rst_n    (rst_n),
  .data_in  (data_b),
  .data_out (data_b_sync)
);

always @(posedge clk_a) begin
  data_a <= data_b_sync;
end
```

### 错误 2: 多比特直接跨域
```systemverilog
// ❌ 错误: 多比特直接跨域
always @(posedge clk_a) begin
  cnt_a <= cnt_b;  // 8-bit 计数器直接跨域
end

// ✅ 正确: 使用 Gray 码或握手
// 方案1: Gray 码计数器
// 方案2: 握手协议
// 方案3: 异步 FIFO
```

### 错误 3: 同步器位置错误
```systemverilog
// ❌ 错误: 同步器在源域
always @(posedge clk_src) begin
  data_sync <= data_in;  // 应该在目标域同步
end

// ✅ 正确: 同步器在目标域
always @(posedge clk_dst) begin
  data_sync <= data_in;
end
```

## SpyGlass CDC 检查流程（可选）

如果环境已安装 SpyGlass，可按以下流程进行自动化 CDC 检查。

### 准备 SpyGlass CDC 运行脚本

创建 `scripts/spyglass_cdc.tcl`，按项目修改占位符：

```tcl
# SpyGlass CDC 检查脚本
# 使用方式: spyglass -project build/<project>.prj \ 
#                    -batch scripts/spyglass_cdc.tcl

# ─── 读取设计 (按项目修改路径) ───
read_file -type sourcelist {<filelist_path>}
read_file -type source {<tb_model_file>}  ;# testbench 模型（如有）

# 设置顶层模块
current_design <top_module>

# 自动时钟检测
clock -auto

# 设置异步时钟域分组（按项目修改时钟名）
# set_clock_group -asynchronous \
#     -group {<clk_a>} \
#     -group {<clk_b>}

# 运行 CDC 检查
check_cdc

# 输出报告
report_cdc -summary -file <report_dir>/spyglass_cdc_summary.rpt
report_cdc -details  -file <report_dir>/spyglass_cdc_details.rpt

exit
```

### 运行方式

```bash
# 运行 SpyGlass CDC
spyglass -project build/<project>.prj -batch scripts/spyglass_cdc.tcl

# 查看报告
cat <report_dir>/spyglass_cdc_summary.rpt
```

### 检查要点

1. 所有跨时钟域路径必须有同步器（2 级或 3 级触发器）
2. 多比特信号跨域必须使用异步 FIFO 或握手协议
3. 同步器输出不得有组合逻辑再跨域
4. 同频反相时钟域应被标记为同步域（SpyGlass 可能误报）

## 检查报告模板

```markdown
# CDC 检查报告

## 时钟域定义
| 时钟 | 频率 | 来源 |
|---|---|---|
| clk_sys | 100 MHz | PLL |
| clk_peri | 50 MHz | 分频 |
| clk_slow | 10 MHz | 外部 |

## CDC 路径统计
| 类型 | 数量 | 有同步器 | 无同步器 |
|---|---|---|---|
| 单比特 | 12 | 10 | 2 |
| 多比特 | 3 | 3 | 0 |
| 总线 | 2 | 2 | 0 |

## 问题详情

### [CDC-001] 缺少同步器
- **信号**: ctrl_valid
- **源域**: clk_sys
- **目标域**: clk_peri
- **类型**: 单比特控制信号
- **建议**: 添加双触发器同步器

### [CDC-002] 多比特跨域风险
- **信号**: status_bus[7:0]
- **源域**: clk_peri
- **目标域**: clk_sys
- **类型**: 多比特状态向量
- **建议**: 使用握手协议或 Gray 编码
```

## 变更记录段（刷新模式追加）

刷新模式在报告末尾追加变更记录，保留可追溯性。

> **首次报告必须记录"对应 commit"**，刷新模式 Step 0 据此定位上次报告基线。
> 首次报告模板的"时钟域定义"段前加一行：`> 对应 commit: <hash>（git rev-parse HEAD）`。

**示例（来自某 ADC 项目）**：
```markdown
## 变更记录

### <date> 刷新（自 commit <hash>）

**触发**：rtl/<module>.v 变更（<信号> 跨域采样重构）

**重审路径**：
| 路径 | 旧结论 | 新结论 | 变更原因 |
|---|---|---|---|
| <sig> → <sig_out> (<clk_a>→<clk_b>) | 2-stage 同步器 | 1-stage 采样 | RTL 改为单级；<clk_a>/<clk_b> 同源反相为同步时钟，非 CDC，无需 2-stage |

**未受影响路径**：其他路径保留旧结论（本次 diff 未涉及）。

**同步时钟判定更新**：本次明确 <clk_a>↔<clk_b> 为同步域（同源 180°），
报告中所有相关路径从"CDC"改标"同步域跨相"，SDC 不应设 false_path。
```

## 与其他 Skill 配合

```
clock-domain-table → 写 RTL 前生成域归属表（CDC 路径清单来源）
rtl_generator      → 生成 RTL（含 CDC 同步器）
      ↓
cdc_review         → 首次生成报告 / 刷新模式同步 RTL 变更
      ↓
consistency_check 4.4 → 复核 CDC 报告新鲜度（报告标注 commit vs HEAD diff）
sdc-manager        → 据报告设定/调整 false_path、clock_groups（同步域不设）
```

> **与 consistency_check 4.4 分工**：4.4 检查"CDC 报告新鲜度"（报告是否过期
> 需刷新），cdc_review 自身负责"刷新动作"。4.4 提示过期，cdc_review 执行刷新。
> 报告新鲜度判定：报告标注的 commit 之后若有涉及 CDC 信号的 RTL 变更 → 过期。

> **刷新触发时机**（建议写入项目 CLAUDE.md 6c）：
> - RTL 改动涉及任何 CDC 路径信号（同步器增删、跨域信号增删、时钟域归属变更）
> - 时钟结构变更（新增/删除时钟、相位关系变化）
> - 每次模块签收前
> 首次报告后不刷新 → 报告腐烂 → 误导 CDC 决策（本项目曾发生）。
