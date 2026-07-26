---
name: spec-parser
description: 解析设计文档（PDF/Word/Excel/Markdown/DrawIO），提取模块名、端口、参数、协议、寄存器、时序等关键信息，输出结构化JSON
triggers:
  - 解析规格
  - 提取端口
  - 生成模块定义
  - spec解析
  - 读取PDF
  - 解析文档
  - 提取信息
  - 分析参考手册
  - 文档分析
  - 读取Word
  - 读取Excel
---

# Spec Parser - 规格解析器

解析多种格式的设计文档，提取结构化信息，为后续 RTL 生成和验证提供基础。

## 输入

| 格式 | 说明 |
|---|---|
| PDF | 芯片参考手册 (TRM)、算法论文、协议规范 |
| Word (.docx) | 设计规格书、接口定义文档 |
| Excel (.xlsx/.csv) | 寄存器列表、pinout 表、时序参数表 |
| Markdown (.md) | 设计文档、README、技术笔记 |
| DrawIO (.drawio) | 架构框图、时序图、状态机图 |

## 输出

结构化 JSON，格式如下：

```json
{
  "schema_version": "1.0",
  "top_module": "top_name",
  "modules": [
    {
      "name": "mod_a",
      "type": "submodule",
      "ports": [
        {"name": "clk", "direction": "input", "width": 1, "type": "clock", "clock_domain": "clk_sys"},
        {"name": "rst_n", "direction": "input", "width": 1, "type": "reset", "active": "low", "async": true},
        {"name": "data_in", "direction": "input", "width": 32, "clock_domain": "clk_sys", "sample_edge": "posedge clk_sys"},
        {"name": "data_out", "direction": "output", "width": 32, "clock_domain": "clk_peri", "drive_edge": "posedge clk_peri"}
      ],
      "parameters": [
        {"name": "DATA_WIDTH", "default": 32}
      ],
      "protocol": {
        "name": "AXI4-Lite",
        "handshake": "VALID-READY",
        "assertions": [
          "VALID must remain asserted until READY",
          "Data must be stable during handshake"
        ]
      },
      "clock_domain": "clk_sys",
      "description": "Module function"
    }
  ],
  "registers": [
    {"name": "CTRL", "offset": "0x00", "bits": "[0]", "attr": "RW", "reset": "1'b0", "desc": "Module enable"}
  ],
  "connections": [
    {"from_module": "mod_a", "from_port": "data_out", "to_module": "mod_b", "to_port": "data_in"}
  ],
  "clock_domains": [
    {"name": "clk_sys", "frequency": "100MHz", "type": "primary"},
    {"name": "clk_peri", "frequency": "50MHz", "type": "derived", "source": "clk_sys", "relation": "div2"}
  ],
  "timing_requirements": [
    {"type": "setup",       "description": "Data setup time before clock",     "value": "2ns", "signal_ref": "<signal>"},
    {"type": "hold",        "description": "Data hold time after clock",      "value": "1ns", "signal_ref": "<signal>"},
    {"type": "latency",     "description": "Input to output latency",         "max_cycles": 8, "from_signal": "<sig_in>", "to_signal": "<sig_out>"},
    {"type": "pulse_width", "description": "Trigger pulse minimum width",     "min_cycles": 2, "signal_ref": "<signal>", "drive_edge": "posedge <clk>"},
    {"type": "timeout",     "description": "Handshake timeout",               "max_cycles": 16},
    {"type": "edge",        "description": "Signal drive/sample edge",        "signal_ref": "<signal>", "drive_edge": "posedge <clk_a>", "sample_edge": "posedge <clk_b>", "detail": "驱动沿/采样沿 + 时钟域"},
    {"type": "other",      "description": "Free-form fallback for other timing constraints", "detail": "Skew between clk_sys and clk_peri must be < 500ps"}
  ],
  "dataflow": {  // optional — only extract when source doc has explicit performance numbers
    "throughput": {"input": "100Mbps", "output": "50Mbps"},
    "latency": {"input_to_output": "1us"},
    "burst_size": {"max": 16}
  }
}
```

## 流程

### Step 1: 识别格式并读取文档

| 文档格式 | 首选方法 | 备用方法 |
|---|---|---|
| Markdown (.md) | `Read` 工具直接读取 | — |
| PDF (<10页) | `Read` 工具直接读取 | `pdftotext -layout <file> -` |
| PDF (>10页) | `Read` 工具分页读取（≤20页/次） | `pdftotext -layout <file> -` |
| Word (.docx) | 导出为 PDF 后读取 | 解压 docx 提取 XML |
| Excel (.xlsx/.csv) | `Read` 工具直接读取 | 用 Python pandas 解析 |
| DrawIO (.drawio) | `Read` 工具读取 XML | 提取 mxCell 节点解析层次关系 |

**PDF 读取最佳实践**：
- 使用 `Read` 工具时指定 `pages` 参数分页读取，每次不超过 20 页
- 当 `Read` 工具无法解析 PDF 时，改用 `pdftotext -layout <file> -` 提取纯文本
- 使用 `-layout` 选项保留表格和缩进格式

### Step 2: 提取模块信息

1. 识别顶层模块名称
2. 列出所有子模块及其层级关系
3. 提取每个模块的功能描述

### Step 3: 提取端口信息

1. 端口名称、方向、位宽
2. 端口类型标记（clock / reset / data / control）
3. 接口协议识别（AXI/AHB/APB/TileLink/自定义握手）

### Step 4: 提取参数和寄存器

**参数提取**：
1. parameter / localparam 名称
2. 默认值
3. 参数用途说明

**寄存器提取**：
1. 寄存器名、偏移地址
2. 位域定义、属性 (RW/RO/W1C/W0C)
3. 复位值、功能描述

### Step 5: 分析连接关系

1. 模块间信号连接
2. 顶层端口到子模块的映射
3. 识别跨时钟域连接

### Step 6: 提取时序要求

1. 时钟频率和相位关系
2. 关键路径时序约束
3. 协议时序要求

## 脱敏规则

**输出中禁止出现参考方案的具体型号和公司名称，仅描述技术特征。**

## 示例

**输入**：读取设计规格文档

**输出**：
```json
{
  "modules": [{
    "name": "data_processor",
    "ports": [
      {"name": "clk", "direction": "input", "width": 1, "type": "clock", "clock_domain": "clk_sys"},
      {"name": "rst_n", "direction": "input", "width": 1, "type": "reset", "active": "low", "async": true},
      {"name": "data_in", "direction": "input", "width": 32, "clock_domain": "clk_sys"},
      {"name": "data_valid", "direction": "input", "width": 1, "clock_domain": "clk_sys"},
      {"name": "result", "direction": "output", "width": 64, "clock_domain": "clk_sys"},
      {"name": "result_valid", "direction": "output", "width": 1, "clock_domain": "clk_sys"}
    ],
    "description": "对输入数据进行乘累加运算"
  }],
  "registers": [
    {"name": "CTRL", "offset": "0x00", "bits": "[0]", "attr": "RW", "reset": "1'b0", "desc": "模块使能"},
    {"name": "CFG", "offset": "0x04", "bits": "[7:0]", "attr": "RW", "reset": "8'h00", "desc": "配置寄存器"}
  ]
}
```

## 下游 Skill

解析结果通常传递给：
- `rtl-generator` — 生成对应的 RTL 代码
- `regmap-gen` — 生成寄存器映射
- `testplan-gen` — 生成验证计划
- `tb-writer` — 生成 testbench
- `assertion-gen` — 生成接口断言
- `formal-prop-gen` — 生成形式化验证属性
- `consistency-check` — 检查设计与文档一致性

## 注意事项

1. 如果文档中有多个模块，确保层级关系正确
2. 位宽缺失时默认为 1
3. 复位类型需要明确（同步/异步、高/低有效）
4. 标注所有跨时钟域信号
5. 输出中避免出现参考方案的具体型号和公司名称，仅描述技术特征
6. `timing_requirements.type` 优先使用预设类型（setup/hold/latency/pulse_width/timeout/edge），不属于这些的用 `"type": "other"` + `description` 保留原始描述。`edge` 类型用于记录信号的驱动沿/采样沿/时钟域（含 `signal_ref`/`drive_edge`/`sample_edge` 字段），供 doc_generator 接口时序表自动生成子流程消费
7. `dataflow` 字段为可选，仅当源文档中有明确的吞吐量/延迟/突发长度指标时提取，不估算不编造
8. 输出 JSON 顶层加 `"schema_version": "1.0"` 字段，刷新模式 diff 时作为版本基线
9. 输出 JSON 默认写到 `spec/<module>.json`，下游 rtl_generator/doc_generator 据此路径查找

## 刷新模式（防止 JSON 腐烂）

> **痛点来源**：spec_parser 输出的 JSON 供 rtl_generator/regmap_gen/testplan_gen
> 消费，但 spec 文档变更后 JSON 不会自动重生成。下游用旧 JSON 生成 RTL/testplan，
> 导致 spec↔JSON↔RTL 链路腐烂。

### 触发刷新的条件

- spec 源文档 mtime > JSON mtime（spec 改了 JSON 没更新）
- 用户显式要求重新解析
- 下游 skill（rtl_generator/regmap_gen）调用前自检发现 spec 比 JSON 新

### 刷新流程

1. 对比 spec 文件 mtime vs 已有 JSON mtime
2. spec 更新 → 重新解析整个文档生成新 JSON
3. diff 新旧 JSON，输出变化项清单：
   ```
   spec→JSON 变更：
   - 新增端口: <port> (<direction>, <width>-bit)
   - 删除端口: <old_sig>
   - 寄存器变更: <REG> 位域调整
   - 时序要求新增: <timing_req>
   ```
4. 提示下游受影响 skill 需重跑（rtl_generator / regmap_gen / testplan_gen）

### 与下游 skill 的约定

下游 skill 消费 JSON 前应先检查 mtime：
- JSON 比 spec 旧 → 提示"spec 已更新，请先 /spec-parser 刷新 JSON"
- 避免用过期 JSON 生成 RTL/测试计划
