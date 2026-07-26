---
name: formal-prop-gen
description: 根据 FSM 状态定义和关键控制信号生成形式化验证属性（SVA assert/cover）
triggers:
  - 生成形式化属性
  - formal property
  - 形式化验证
  - SVA属性
  - property checking
---

# Formal Property Generator — 形式化验证属性生成器

根据 FSM 和控制逻辑定义，生成 SVA 属性（assertion / cover / assume），用于形式化验证工具（JasperGold / VC Formal 等）。

> **与 assertion_gen 分工**：基础 SVA 语法、bind 机制、协议/时序断言、仿真
> 接入验证见 `/assertion-gen`。本 skill 只保留**形式化专属**内容：assume 约束
> 输入、cover reachable 判定、assert proven、形式化工具流程、FSM 状态可达性
> 与转移完备性。两者不合并（trigger 不同：仿真断言→assertion-gen；FSM/形式化
> →本 skill）。

## 输入

- FSM 状态定义（状态名、编码、转移条件）
- 关键控制信号列表
- 模块端口和接口时序
- 需验证的安全属性描述

## 输出

- SVA 属性文件（`<module>_formal.sv`）
- 属性清单说明

## 输出规范

### 1. FSM 状态覆盖属性

确保每个状态可达，不存在死锁或非法状态：

```systemverilog
// Formal properties template — 从 RTL 提取实际状态名，禁止照抄示例状态名
module <module>_formal;
    // ─── 1. Import FSM state definitions ───
    // 从 RTL 提取实际状态名和编码（勿硬编码示例 ST_IDLE/ST_BUSY/ST_DONE）
    parameter ST_<X> = <N>'d<enc>;  // 按 RTL 实际状态填
    // parameter ST_xxx = 3'd3;
    // ...

    // ─── 2. Cover: all states reachable ───
    cover property (@(posedge clk) curr_st == ST_<X>);  // 对每个实际状态

    // ─── 3. Assert: no illegal states ───
    assert property (@(posedge clk) disable iff (!rst_n)
        curr_st inside {ST_<X>, ST_<Y>, ...});  // 列出所有有效状态

    // ─── 4. FSM transition completeness ───
    // 每个状态对所有输入组合都有定义
    assert property (@(posedge clk) disable iff (!rst_n)
        case (curr_st)
            ST_IDLE : next_st inside {ST_IDLE, ST_BUSY};
            ST_BUSY : next_st inside {ST_BUSY, ST_DONE};
            ST_DONE : next_st inside {ST_DONE, ST_IDLE};
            // default : ... 所有未定义转移
        endcase);
endmodule
```

### 2. 时序约束断言（配合 assume）

时序超时类属性在形式化中必须配合输入假设，否则会因缺少环境约束而失败：

```systemverilog
// ─── 正确做法：assume + assert 配对 ───

// 约束 1（assume）：在外部环境中，输入 req 不会连续保持超过 100 拍
assume property (@(posedge clk) disable iff (!rst_n)
    req |-> ##[1:100] !req);

// 属性（assert）：设计在收到 req 后 5 拍内输出 ack
assert property (@(posedge clk) disable iff (!rst_n)
    req |-> ##[1:5] ack);

// ─── 常见错误：缺少 assume，形式化引擎找不到反例起点 ───
// assert property (@(posedge clk) disable iff (!rst_n)
//     (state == ST_BUSY) |-> ##[1:16] (state != ST_BUSY));
// ❌ 形式化中如果没有 assume 约束 exit 条件，引擎可能让 state 永远卡在
//    ST_BUSY，导致此属性占用大量资源直到超时
```

### 3. 互斥与安全属性

```systemverilog
// 两个忙信号不能同时为高
assert property (@(posedge clk) disable iff (!rst_n)
    !(busy_a && busy_b));

// 请求与应答一对一匹配
assert property (@(posedge clk) disable iff (!rst_n)
    req |-> ##[1:10] ack);

// 应答后请求必须在下一拍释放
assert property (@(posedge clk) disable iff (!rst_n)
    req && ack |=> !req);
```

### 4. FSM 转移完整性

确保所有状态对所有输入条件都有定义。按项目 FSM 修改状态名：

```systemverilog
// 检查状态转移是否完备（不遗漏任何状态+输入的组合）
// 按项目 FSM 修改状态名和转移条件
assert property (@(posedge clk) disable iff (!rst_n)
    case (curr_st)
        ST_IDLE : next_st inside {ST_IDLE, ST_BUSY};
        ST_BUSY : next_st inside {ST_BUSY, ST_DONE};
        ST_DONE : next_st inside {ST_DONE, ST_IDLE};
        // default : 未定义转移处理
    endcase);
```

## 设计约束

- 属性文件以 `_formal.sv` 后缀，存放在 `tb/<module>/` 目录下
- 属性通过 `bind` 注入 DUT，不修改 RTL 源码（参见下方 bind 示例）
- 确保属性可综合（仅使用 SVA 关键字，不使用 `$assert` 等不可综合结构）
- 超时周期参数化（如 `MAX_TIMEOUT_CYCLES = 16`），不硬编码
- 每个属性标注类型：`assert` / `cover` / `assume`

## Bind 到 DUT

通过 `bind` 将形式化属性注入 DUT，无需修改 RTL：

```systemverilog
// bind_<module>_formal.sv
bind <module> <module>_formal_properties u_formal (.*);
```

```bash
# 编译时包含属性文件和 bind 文件
vcs -full64 -sverilog rtl/<module>/*.v tb/<module>/bind_*.sv \
    -o sim/simv
```

## Step N: 接入验证（生成后必须执行，防止死代码）

> **痛点来源**：形式化属性文件生成后若不接入编译/形式化工具流程，等于白写。
> 与 assertion_gen 同类问题——生成 ≠ 启用。

生成 `_formal_properties.sv` + bind 文件后，逐项确认：

| # | 检查项 | 方法 | 不通过处理 |
|:-:|:--|:--|:--|
| 1 | bind 文件加入编译列表 | `grep 'bind_<module>_formal' Makefile/filelist` 非空 | 加入 filelist 或 Makefile 形式化编译命令 |
| 2 | 仿真编译通过 | `make vcs`（含 bind）PASS | 修复 bind 实例路径/状态名 |
| 3 | 形式化工具可加载 | JasperGold/VCFormal 能读入属性文件并运行 | 确认 -sverilog + 属性文件路径 |
| 4 | cover 可达性 | 形式化运行后 cover 全部 reachable（非 unreachable） | unreachable → FSM 状态不可达或 assume 过紧 |
| 5 | assert 求证 | assert 全部 proven（非 fail/unknown） | fail → 真问题；unknown → 加 assume 约束 |

**接入验证报告**：
```
formal 接入验证 — <module>
✅ bind: bind_<module>_formal.sv 已加入编译
✅ 编译: make vcs PASS
✅ 工具: JasperGold 加载 12 属性
✅ cover: 8/8 reachable
✅ assert: 4/4 proven (0 fail, 0 unknown)
→ 形式化属性已生效
```

任一项不通过 → 报告并修复。形式化工具不可用时至少完成 1-2（仿真编译层接入）。
