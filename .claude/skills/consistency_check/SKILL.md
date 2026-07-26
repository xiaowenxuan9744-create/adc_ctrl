---
name: consistency-check
description: 检查 RTL 内部一致性（端口/位宽/参数）及 spec↔RTL↔SDC↔regmap↔TB 五端一致性（寄存器/接口/功能/时钟/SDC端口/regmap地址/测试点数）
triggers:
  - 一致性检查
  - 端口检查
  - 位宽检查
  - 连接检查
  - 设计文档检查
  - 规格对比
  - RTL与文档对比
  - SDC一致性
  - regmap一致性
  - 测试点覆盖
---

# Consistency Check — 一致性检查器

检查 RTL 代码的内部一致性（端口连接、位宽、参数），以及 spec↔RTL↔SDC↔regmap↔TB 五端之间的外部一致性。

> **设计动机**：早期版本只查 spec↔RTL 两端，漏抓过三类真实 bug：SDC 引用了
> RTL 不存在的端口名（`dma_req` vs `dma_ndreq`）、regmap 头文件缺地址宏
> （0xD0/0xD4）、文档测试点数与 TB 实际用例数不符。故扩展为五端三角检查。

## 输入

- RTL 代码文件（.v / .sv）
- 规格定义 JSON / 设计文档 Markdown（可选，用于设计文档对比）
- spec-parser 输出的模块接口定义（可选）
- SDC 约束文件（可选，用于 SDC↔RTL 检查）
- regmap 头文件 `<module>_regmap.svh`（可选，用于 regmap↔RTL 检查）
- testplan 文档 + TB/UVM test 文件清单（可选，用于 TB↔spec 检查）

## 输出

- 检查报告（通过/警告/错误）
- 问题清单及修复建议

## 检查项

### 1. 端口声明检查

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 端口方向一致性 | 实例端口方向与模块定义一致 | Error |
| 端口位宽匹配 | 连接双方位宽相等 | Warning |
| 端口类型匹配 | 时钟/复位/数据类型正确 | Error |

### 2. 连接正确性检查

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 输出连接 wire | 模块输出只能连接到 wire | Error |
| 未连接端口 | 检查是否有悬空端口 | Warning |
| 多驱动检测 | 检查是否存在多驱动 | Error |

### 3. 参数一致性检查

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 参数位宽匹配 | 参数传递后位宽是否匹配 | Warning |
| 参数默认值 | 检查参数默认值是否合理 | Info |

### 4. 设计文档与 RTL 一致性检查

将设计文档（寄存器表、接口定义、功能描述）与 RTL 实现进行逐项对比。

#### 4.1 寄存器一致性

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 寄存器存在性 | 文档中每个寄存器在 RTL 中均有对应实现 | Error |
| 寄存器缺失 | RTL 中存在文档未定义的寄存器 | Warning |
| 位域匹配 | 位域位置和宽度与文档一致 | Error |
| 属性一致 | RW/RO/W1C 等属性与文档匹配 | Error |
| 复位值一致 | 复位值与文档定义一致 | Warning |
| 地址偏移一致 | 寄存器偏移地址与文档一致（如有时钟/地址映射） | Error |
| 地址连续性 | 寄存器地址连续排列，无空洞（删除寄存器后后续前移） | Warning |

**检查方法**：
1. 从设计文档/TRM 提取寄存器列表（可用 doc-parser）
2. 在 RTL 中搜索对应的寄存器定义和操作逻辑
3. 逐项对比名称、位域、属性和复位值

#### 4.2 接口一致性

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 端口名称一致 | 顶层端口名与设计文档定义一致 | Error |
| 端口方向一致 | input/output 方向与文档一致 | Error |
| 端口位宽一致 | 位宽与文档定义一致 | Error |
| 端口存在性 | 文档定义的端口在 RTL 中均存在 | Error |
| 多余端口 | RTL 中存在文档未定义的额外端口 | Warning |
| 协议信号完整 | AXI/AHB/APB 等协议信号集与文档一致 | Error |

#### 4.3 功能特性一致性

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 功能模块存在 | 文档描述的每个功能模块在 RTL 中有对应实现 | Error |
| 关键数据通路 | 数据通路的位宽变换、流水级数与文档一致 | Warning |
| 状态机覆盖 | 文档描述的状态机在 RTL 中完整实现 | Warning |
| 中断信号 | 文档定义的中断源在 RTL 中均有生成逻辑 | Error |
| 参数可配性 | 文档描述的可配参数在 RTL 中以 parameter 实现 | Warning |

#### 4.4 时钟与复位一致性

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 时钟域数量 | 时钟域数量与文档一致 | Error |
| 时钟频率关系 | 各时钟域频率关系符合文档描述 | Warning |
| 复位策略一致 | 复位类型（同步/异步）、有效电平与文档一致 | Error |
| 跨域同步方案 | 跨时钟域信号的同步方式与文档描述一致 | Warning |
| CDC 报告新鲜度 | 若有 cdc_review 报告，检查报告标注的检查 commit/时间 vs HEAD 涉及 CDC 信号的 RTL 变更，报告过期则提示刷新 | Warning |

#### 4.5 SDC ↔ RTL 一致性

> **痛点来源**（示例：某项目曾发生）：SDC 中 `get_ports` 引用了 RTL 不存在的
> 端口名（SDC 写 `<port_a>`，RTL 实为 `<port_b>`），`get_ports` 匹配失败导致
> output_delay 约束**静默失效**，综合 STA 漏约束。SDC 端口名错误不会在仿真
> 阶段暴露，综合阶段才发现成本高。

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| SDC 端口名存在性 | SDC 中所有 `get_ports("...")` / `get_port("...")` 引用的端口名必须在 RTL 顶层端口列表中存在 | Error |
| SDC 端口方向匹配 | `set_output_delay` 引用的必须是 RTL output，`set_input_delay` 引用的必须是 RTL input | Error |
| SDC 端口位宽匹配 | SDC 通配符（如 `<bus>*`）展开后覆盖的端口位宽与意图一致 | Warning |
| SDC 时钟名存在性 | `create_clock -name <clk>` 与 `set_clock_groups` / `set_false_path -from/-to [get_clocks <clk>]` 中引用的时钟名一致 | Error |
| SDC 端口同步性 | RTL 顶层新增/删除端口时，SDC 的 IO delay 约束同步增删 | Warning |

**检查方法**：
1. 从 RTL 顶层模块（`<top_module>`）提取完整端口名+方向+位宽列表
2. grep SDC 中所有 `get_ports` / `get_port` 引用，逐个核对存在性、方向
3. grep SDC 中所有 `get_clocks` 引用，与 `create_clock -name` 定义集合比对
4. 报告：SDC 引用但 RTL 无此端口（Error，最关键）、方向不匹配（Error）、RTL 有但 SDC 未约束（Warning）

> **与 sdc-manager 分工**：本节是五端一致性里的一环（跨端汇总）；SDC 专项
> 深查（含 clock_groups 误纳同步时钟、set_clock_relationship 语法覆盖、
> 端口覆盖完整性）由 `/sdc-manager` 自检负责。本节可调用 sdc-manager 自检
> 结果汇总，不重复实现 grep 流程。

**典型错误示例**（示例：某项目曾发生）：
```
SDC:  set_output_delay -clock <clk> <T> [get_ports "<irq> <port_sdc>"]
RTL:  output wire <port_rtl>,    // SDC 端口名与 RTL 不一致
→ [ERROR] SDC 引用端口 '<port_sdc>' 在 RTL 顶层不存在（RTL 为 '<port_rtl>'）
         该 output_delay 约束将静默失效，综合 STA 漏约束
         建议: SDC 改为 <port_rtl>
```

#### 4.6 regmap ↔ RTL 一致性

> **痛点来源**（示例：某项目曾发生）：regmap-gen 生成的 `<module>_regmap.svh`
> 曾缺地址宏（RTL 已实现某寄存器，regmap 未定义对应宏），导致 regmap 与 RTL
> 地址集不一致。若 TB 用 regmap 宏访问，会访问不到该寄存器。

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 地址集一致 | regmap.svh 中定义的地址宏集合 == RTL addr_decode 覆盖的地址集合 | Error |
| regmap 缺地址 | RTL 实现了但 regmap.svh 未定义的地址 | Error |
| regmap 多地址 | regmap.svh 定义了但 RTL 未实现的地址 | Warning |
| 地址值一致 | 同一寄存器 regmap 宏值 == RTL 译码值（位宽差异需对齐，如 `32'hXX` vs `12'h0XX`） | Error |
| regmap 启用检查 | regmap.svh 是否被至少一处 `` `include `` 且 filelist 有对应 +incdir+（孤儿检测） | Warning |

**检查方法**：
1. 从 RTL regfile 提取所有 `addr == <N>'hXXX` / `<N>'hXXX:` 译码地址集合 A
2. 从 regmap.svh 提取所有 `` `define <MODULE>_<REG> <N>'hXX `` 地址宏集合 B
3. 集合 diff：A−B（RTL 有 regmap 无，Error）、B−A（regmap 有 RTL 无，Warning）
4. grep 全仓 `` `include "<module>_regmap.svh" `` 确认非孤儿

**典型错误示例**：
```
RTL:   <N>'h<addr>: rd_data_mux = ... <reg> ...   // RTL 实现了该地址
regmap: (无对应宏)                                  // regmap 缺该地址宏
→ [ERROR] RTL 实现 <addr> (<REG>) 但 regmap.svh 未定义对应地址宏
         建议: regmap-gen 重新生成或手动补 `define <MODULE>_<REG> <N>'h<addr>
```

> **与 regmap-gen 分工**：regmap-gen 的接入验证 Step N 也含地址集一致检查，
> 本节是跨五端一致性里的复核，两者互补。

#### 4.7 TB ↔ spec 一致性

> **痛点来源**（示例：某项目曾发生）：文档声明的检查点数与 TB 实际 PASS 断言
> 数不符，且文档表头汇总数、明细段标注数、TB 代码实际数三方不一致，靠人工
> 难以发现。

| 检查项 | 说明 | 严重级别 |
|---|---|---|
| 测试点数一致 | testplan/spec 声明的测试点总数 == TB/UVM 实际 test/sequence 文件数或断言数 | Warning |
| 每模式检查点数 | 文档各模式检查点数 == 该模式 TB 代码中 `pass = pass + 1` / `[PASS]` 计数 | Warning |
| P0 测试点有 test | testplan 中每个 P0 优先级测试点都有对应的 UVM test/sequence 实现 | Error |
| 表头与明细一致 | 文档表头汇总数 == 文档各模式明细段标注数 == TB 实际数 | Warning |

**检查方法**：
**检查方法**：
1. 从 testplan 提取测试点清单（编号+优先级+所属模式）
2. 从 TB/UVM sequence 目录提取实际 test/sequence 文件清单
3. 核对每个 P0 测试点有对应实现；统计各模式实际 `[PASS]` 断言数（grep
   `pass = pass + 1` 或 `[PASS]` 计数）与文档声明比对
4. 三方数字不一致时报告（表头 vs 明细 vs 代码）

**典型错误示例**（示例）：
```
文档表头: 模式N 检查点=<X>
文档明细: 模式N 检查项（<X> 项）
TB 代码:  模式N 实际 <Y> 个 [PASS]
→ [WARNING] 模式N 检查点数三方不一致: 表头<X> / 明细<X> / 实际<Y>
         建议: 以 TB 代码实际数为准，同步更新表头与明细
```

> **与 testplan-gen / coverage-analyze 分工**：testplan-gen 维护测试点表+
> 回填机制，coverage-analyze 执行覆盖率闭环回填，本节是跨五端一致性里的
> 数字复核，三者互补。

## 输出格式

### 通过
```
✅ 一致性检查通过
   - 内部检查: 模块数 5, 实例数 12, 端口连接 48
   - 外部检查: 寄存器 16/16 匹配, 端口 32/32 匹配
```

### 有问题
```
❌ 一致性检查发现问题 (4 errors, 3 warnings)

—— 内部一致性 ——

[ERROR] Line 45: module_a.u_sub.data_out (8bit) -> module_b.data_in (16bit)
        位宽不匹配: 输出 8 位连接到输入 16 位
        建议: 检查信号位宽定义或添加位宽转换逻辑

—— 设计文档 vs RTL ——

[ERROR] 寄存器缺失: 文档定义的 FEC_STATUS (0x10) 在 RTL 中未找到
        建议: 添加 FEC_STATUS 寄存器实现

[ERROR] 位域不匹配: FEC_CTRL[7:4] 文档为 RESERVED，RTL 中用作 debug_mode
        建议: 对齐文档位域定义或更新文档

[WARNING] 复位值不匹配: FEC_CFG 复位值 文档=8'h00, RTL=8'h80
        建议: 检查复位值设计意图，统一文档与代码
```

## 示例

### 示例 1: 内部一致性 — 端口位宽

**检查前代码**：
```verilog
module top (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [15:0] data_in,
  output wire [15:0] data_out
);

  sub_module u_sub (
    .clk      (clk),
    .rst_n    (rst_n),
    .data_in  (data_in),      // 位宽不匹配
    .data_out (data_out)
  );

endmodule

module sub_module (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [7:0]  data_in,   // 8-bit
  output wire [7:0]  data_out   // 8-bit
);
```

**检查报告**：
```
❌ 一致性检查发现问题 (2 errors)

[ERROR] Line 9: top.u_sub.data_in 位宽不匹配
        连接: top.data_in[15:0] -> sub_module.data_in[7:0]
        问题: 16bit 连接到 8bit，高位将被截断
        建议: 检查设计意图，确认位宽定义

[ERROR] Line 10: top.u_sub.data_out 位宽不匹配
        连接: sub_module.data_out[7:0] -> top.data_out[15:0]
        问题: 8bit 连接到 16bit，高位将悬空
        建议: 检查设计意图，确认位宽定义
```

### 示例 2: 外部一致性 — 设计文档 vs RTL

**设计文档寄存器表**：
```
| 寄存器名 | 偏移 | 位域 | 属性 | 复位值 | 描述 |
|---|---|---|---|---|---|
| FEC_CTRL  | 0x00 | [0]    | RW | 1'b0 | 模块使能 |
| FEC_CTRL  | 0x00 | [7:4]  | RO | 4'h0 | 保留 |
| FEC_CFG   | 0x04 | [7:0]  | RW | 8'h00 | 插值模式 |
| FEC_STATUS| 0x08 | [3:0]  | RO | 4'h0 | 状态码 |
```

**RTL 代码**：
```verilog
// FEC_CTRL register
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fec_ctrl <= 8'h00;
    end else begin
        if (wr_en && addr == 8'h00)
            fec_ctrl <= wr_data;
    end
end
// NOTE: fec_ctrl[7:4] used as debug_mode internally
```

**检查报告**：
```
❌ 设计文档 vs RTL 一致性检查 (2 errors, 1 warning)

[ERROR] 寄存器缺失: 文档定义 FEC_STATUS (0x08) 在 RTL 中未找到
        建议: 实现 FEC_STATUS 状态寄存器

[ERROR] 位域不匹配: FEC_CTRL[7:4]
        文档: RO 保留位
        RTL: 实际用作 debug_mode
        建议: 更新文档描述或移除 debug_mode 功能

[WARNING] 复位值不匹配: FEC_CFG (0x04)
        文档: 8'h00
        RTL: 未找到 FEC_CFG 实现
        建议: 实现 FEC_CFG 或从文档中移除此寄存器
```

## 与其他 Skill 配合

```
doc_parser   → 提取文档中的寄存器表和接口定义
spec_parser  → 提取模块接口结构化定义
rtl_generator → 生成 RTL 代码
regmap_gen    → 生成 regmap.svh（被 4.6 检查）
sdc-manager   → 生成/维护 SDC（被 4.5 检查）
testplan_gen  → 生成 testplan（被 4.7 检查）
rtl_reviewer → 代码风格和可综合性审查（维度11 调用本 skill）
      ↓
consistency_check → 内部一致性（端口/位宽/参数）+ 外部五端一致性
                    （spec↔RTL↔SDC↔regmap↔TB）
```

> **五端覆盖**：4.1-4.4 查 spec↔RTL；4.5 查 SDC↔RTL；4.6 查 regmap↔RTL；
> 4.7 查 TB↔spec。任一端缺失对应输入文件时该子项跳过并提示"未提供 X，跳过 X 检查"。

