---
name: assertion-gen
description: 根据时序图和协议描述生成 SVA 断言，覆盖关键行为检查
triggers:
  - 生成断言
  - SVA
  - assertion
  - 时序检查
---

# Assertion Generator - 断言生成器

根据时序图和协议描述生成 SystemVerilog Assertion (SVA) 断言。

**设计原则：简洁优先。** 断言代码应聚焦关键时序行为和协议违规检测，禁止为每个信号都写冗余断言。一条精准覆盖核心行为的断言优于十条"为写而写"的模板断言。

## 输入

- 时序图描述（Markdown/ASCII art/文字描述）
- 协议规范（AXI/AHB/APB/自定义）
- RTL 接口信号列表

## 输出

- SVA 断言代码块（可嵌入 RTL 或独立文件）
- Cover property 定义
- 断言覆盖矩阵

## 常用断言模板

### 1. 握手协议断言

**VALID-READY 握手**：
```systemverilog
// VALID-READY handshake assertions

// 1. VALID asserted until READY acknowledged
property p_valid_until_ready;
  @(posedge clk) disable iff (!rst_n)
    valid |-> ##[0:$] (ready && valid);
endproperty
assert property (p_valid_until_ready)
  else $error("VALID not held until READY");

// 2. Data stable during handshake
property p_data_stable;
  @(posedge clk) disable iff (!rst_n)
    valid && !ready |-> $stable(data);
endproperty
assert property (p_data_stable)
  else $error("Data changed during handshake");

// 3. Cover: handshake completion
cover property (@(posedge clk) valid && ready);
```

### 2. FIFO 断言

```systemverilog
// FIFO assertions

// 1. No overflow: write when full is illegal
property p_no_overflow;
  @(posedge clk) disable iff (!rst_n)
    full |-> !write_en;
endproperty
assert property (p_no_overflow)
  else $error("FIFO overflow detected");

// 2. No underflow: read when empty is illegal
property p_no_underflow;
  @(posedge clk) disable iff (!rst_n)
    empty |-> !read_en;
endproperty
assert property (p_no_underflow)
  else $error("FIFO underflow detected");

// 3. FIFO count within bounds
property p_count_valid;
  @(posedge clk) disable iff (!rst_n)
    fifo_count >= 0 && fifo_count <= FIFO_DEPTH;
endproperty
assert property (p_count_valid)
  else $error("FIFO count out of bounds");

// 4. Read data matches written data
property p_data_integrity;
  @(posedge clk) disable iff (!rst_n)
    (write_en && !full) |-> ##(read_latency) 
    (read_en && read_data == $past(write_data, read_latency));
endproperty
assert property (p_data_integrity)
  else $error("FIFO read data mismatch");
```

### 3. 状态机断言

```systemverilog
// State machine assertions

// 1. Valid state transition
property p_valid_transition;
  @(posedge clk) disable iff (!rst_n)
    (state == IDLE) |-> ##1 (state inside {IDLE, ACTIVE, DONE});
endproperty
assert property (p_valid_transition)
  else $error("Invalid state transition from IDLE");

// 2. State reachability cover
cover property (@(posedge clk) state == ACTIVE);

// 3. State duration constraint
property p_max_duration;
  @(posedge clk) disable iff (!rst_n)
    (state == ACTIVE) |-> ##[1:MAX_CYCLES] (state != ACTIVE);
endproperty
assert property (p_max_duration)
  else $error("State ACTIVE exceeded max duration");
```

### 4. AXI4-Lite 断言

```systemverilog
// AXI4-Lite write channel assertions

// 1. AWVALID must remain asserted until AWREADY
property p_awvalid_hold;
  @(posedge aclk) disable iff (!aresetn)
    awvalid && !awready |=> awvalid;
endproperty
assert property (p_awvalid_hold)
  else $error("AWVALID not held during wait");

// 2. WVALID must remain asserted until WREADY
property p_wvalid_hold;
  @(posedge aclk) disable iff (!aresetn)
    wvalid && !wready |=> wvalid;
endproperty
assert property (p_wvalid_hold)
  else $error("WVALID not held during wait");

// 3. Write response after address and data
property p_bvalid_after_aw_w;
  @(posedge aclk) disable iff (!aresetn)
    (awvalid && awready && wvalid && wready) |-> ##[1:16] bvalid;
endproperty
assert property (p_bvalid_after_aw_w)
  else $error("BVALID not received after write");

// 4. Cover: successful write transaction
cover property (@(posedge aclk)
  awvalid && awready && wvalid && wready && bvalid && bready);
```

### 5. APB 总线断言

```systemverilog
// APB write assertion

// 1. PSEL must be asserted during PENABLE
property p_psel_during_penable;
  @(posedge PCLK) disable iff (!PRESETn)
    PENABLE |-> PSEL;
endproperty
assert property (p_psel_during_penable)
  else $error("PENABLE without PSEL");

// 2. PENABLE must deassert after one cycle when PSEL deasserts
property p_penable_after_psel;
  @(posedge PCLK) disable iff (!PRESETn)
    PSEL && PENABLE |=> !PENABLE;
endproperty
assert property (p_penable_after_psel)
  else $error("PENABLE stuck asserted");

// 3. PWRITE stable during transfer
property p_pwrite_stable;
  @(posedge PCLK) disable iff (!PRESETn)
    PSEL |=> $stable(PWRITE);
endproperty
assert property (p_pwrite_stable)
  else $error("PWRITE changed during transfer");

// 4. Write data stable during transfer
property p_wdata_stable;
  @(posedge PCLK) disable iff (!PRESETn)
    PSEL && PWRITE |=> $stable(PWDATA);
endproperty
assert property (p_wdata_stable)
  else $error("PWDATA changed during transfer");

// 5. Read back data valid after transfer
property p_prdata_valid;
  @(posedge PCLK) disable iff (!PRESETn)
    PSEL && PENABLE && !PWRITE |-> $stable(PRDATA);
endproperty
assert property (p_prdata_valid)
  else $error("PRDATA not stable at end of read");

// 6. No address change during transfer
property p_addr_stable;
  @(posedge PCLK) disable iff (!PRESETn)
    PSEL |-> $stable(PADDR);
endproperty
assert property (p_addr_stable)
  else $error("PADDR changed during transfer");

// 7. No unexpected PSEL pulse (glitch)
property p_no_psel_glitch;
  @(posedge PCLK) disable iff (!PRESETn)
    PSEL |-> ##1 PSEL || $fell(PSEL);
endproperty
assert property (p_no_psel_glitch)
  else $error("PSEL glitch detected");
```

### 6. 复位断言

```systemverilog
// Reset assertions

// 1. All registers reset to known values
property p_reset_value;
  @(posedge clk or negedge rst_n)
    !rst_n |=> register == RESET_VALUE;
endproperty
assert property (p_reset_value)
  else $error("Register not reset to correct value");

// 2. Reset duration cover
cover property (@(posedge clk) !rst_n [*MIN_RESET_CYCLES]);
```

### 7. 时钟门控断言

```systemverilog
// Clock gating assertions

// 1. Clock enable only changes when clock is low
property p_clk_gating_safe;
  @(negedge clk) disable iff (!rst_n)
    $changed(clk_en) |-> clk == 0;
endproperty
assert property (p_clk_gating_safe)
  else $error("Clock enable changed during active clock");

// 2. No glitches during clock gating
property p_no_glitch;
  @(posedge clk) disable iff (!rst_n)
    1 |-> !$isunknown(gated_clk);
endproperty
assert property (p_no_glitch)
  else $error("Glitch detected on gated clock");
```

## 断言放置规范

| 类型 | 位置 | 说明 |
|:--|:--|:--|
| **bind 模块** | `tb/<module>/bind_<module>.sv` | **推荐** — 独立文件，通过 `bind` 注入，不影响 RTL |
| RTL 内联 | RTL 文件内 `ifdef ASSERTION` | 少量关键断言，需条件编译保护 |
| testbench 内 | testbench 的 initial 块 | 时序检查、数据比对 |

**推荐方式：bind 模块**，通过 `bind` 将断言注入 DUT，无需修改 RTL：

```systemverilog
// bind_<module>.sv — 通过 bind 注入断言到 DUT
// 编译时包含此文件即可启用断言

module bind_<module>_assertions;
    // 绑定到 DUT 实例
    bind <module> <module>_assertions u_assert (.*);

    // 断言写在这里，直接引用 DUT 信号
    property p_example;
        @(posedge clk) disable iff (!rst_n)
            valid |-> ##[1:5] ready;
    endproperty
    assert property (p_example) else $error("...");
endmodule
```

```bash
# 编译时需要 bind 文件和设计文件一起编译
vcs -full64 -sverilog rtl/adc_controller/*.v tb/bind_*.sv -o sim/simv
```

## 形式化验证属性

若断言用于形式化验证（JasperGold/VCFormal），`assume`/`assert` 区分见
`/formal-prop-gen`（assume 约束输入环境、assert 验证输出行为）。本 skill 聚焦
仿真断言，形式化专属内容（assume 配对、cover reachable、assert proven、工具
流程）由 formal-prop-gen 负责，不在此重复。

## 多时钟域断言

跨时钟域信号不能用同一时钟采样，需用 `$stable` 或 `$past` 的跨时钟变体：

```systemverilog
// 错误：跨时钟域直接断言
assert property (@(posedge clk_a) a_req |-> ##[1:10] b_ack);  // ❌ b_ack 在 clk_b 域

// 正确：同步后再断言
wire b_ack_sync;
<proj>_sync_2stage u_sync (.clk(clk_a), .din(b_ack), .dout(b_ack_sync));  // 项目同步器封装

assert property (@(posedge clk_a) disable iff (!rst_n)
    a_req |-> ##[1:20] b_ack_sync);  // ✅ 同步到同一时钟域后断言

// 多时钟域 cover：确认某个事件在另一个域被收到
cover property (@(posedge clk_b) b_ack);  // 确认 b_ack 在 clk_b 域发生过
```

## 断言密度指南

不同的验证阶段需要不同的断言密度：

- **模块级验证**：关键控制信号 + 协议接口 → 每个关键路径至少 1 个
- **集成验证**：跨模块接口 + 总线协议 → 每条总线至少覆盖一次
- **形式化验证**：FSM 状态转移 + 时序约束 → 每个状态转移方向至少 1 个

## 断言分类

| 类型 | 用途 | 关键字 |
|---|---|---|
| 协议检查 | 总线协议合规 | `valid`, `ready`, `ack` |
| 数据完整性 | 数据正确性 | `stable`, `past`, `changed` |
| 状态机 | 状态转换 | `inside`, `sequence` |
| 边界检查 | 溢出/下溢 | `count`, `full`, `empty` |
| 时序检查 | 时序约束 | `##n`, `##[a:b]` |
| 覆盖收集 | 功能覆盖 | `cover property` |

## 使用建议

1. **首选 bind 方式**：断言写在独立 bind 模块中，不污染 RTL 源码
2. **断言密度**：关键控制信号 + 协议接口每个至少一个，内部数据通路按需添加
3. **覆盖率**：使用 `cover property` 收集功能覆盖事件
4. **可读性**：使用命名 property（`p_<name>`），禁用匿名断言
5. **可调试性**：每条断言添加 `$error` 消息，描述违例场景
6. **`$past` 注意事项**：`$past` 默认退 1 拍，多拍用 `$past(sig, n)`；需确保 `$past` 采样时已过足够时钟周期
7. **disable iff 对齐复位**：异步复位用 `negedge rst_n`，同步复位只用 `posedge clk` 不加 `or negedge`

## 与其他 Skill 配合

```
spec_parser -> testcase_gen -> assertion_gen
                         ↓
                    rtl_generator (嵌入断言)
```

## Step N: 接入验证（生成后必须执行，防止死代码）

> **痛点来源**：断言写了不编译 = 死代码。生成的 `bind_<module>.sv` 若不加入
> filelist/Makefile，编译时不参与，断言永远不会触发，等于白写。

生成断言 + bind 文件后，逐项确认：

| # | 检查项 | 方法 | 不通过处理 |
|:-:|:--|:--|:--|
| 1 | bind 文件加入编译 | `grep 'bind_<module>' <uvm.flist> Makefile` 非空 | 加入 filelist 或 Makefile sim-assert 编译命令；注意项目可能在 Makefile 目标里硬编码 bind 路径而非读 filelist，需同步更新该目标 |
| 2 | 编译通过 | `make vcs` 或 `make sim-assert` PASS | 修复 bind 实例路径/信号名 |
| 3 | 仿真中断言被纳入 | 仿真日志无 "assertion off" / 编译报告显示 bind 已绑定 | 确认 bind 实例层次正确 |
| 4 | 至少一个 cover 命中或无 violation | 跑回归，grep 日志 cover 命中 / 无 assertion error | 若 cover 全 0 → 用例未触发该场景，补 case；有 violation → 真问题 |

**接入验证报告**：
```
assertion 接入验证 — <module>
✅ filelist: tb/bind_<module>_assert.sv 已加入 Makefile sim-assert（或 filelist）
✅ 编译: make sim-assert PASS
✅ 绑定: bind <top>.u_assert 层次正确
✅ 仿真: N 条 cover 命中，0 violation
→ 断言已生效
```

任一项不通过 → 报告并修复，不允许"生成即结束"。
