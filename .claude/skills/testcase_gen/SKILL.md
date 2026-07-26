---
name: testcase-gen
description: 根据测试点自动生成 UVM/SystemVerilog 测试用例
triggers:
  - 生成测试用例
  - testcase
  - 测试case
  - UVM test
---
# Testcase Generator — 测试用例生成器

根据测试点描述自动生成 UVM 或 SystemVerilog 测试用例骨架。

**设计原则：简洁优先。** 测试用例代码保持简单直白，杜绝过度设计。激励生成、结果检查逻辑应直接表达，不为单一测试场景引入不必要的继承层次、宏定义或设计模式。

**文件组织：按 test_case 分文件管理（M2 强制）。** 每个 test case 独立一个文件，禁止将所有测试用例堆到一个文件中。命名规范：`tb_<module>_<case_name>.sv`。Makefile/TCL 按 case 列表依次编译运行。

---

## UVM 验证环境架构

每个模块的 UVM 验证环境由标准组件组成：

```
tb/
├── tb_top.sv                    # 顶层 testbench（DUT 例化 + 接口绑定）
├── env/
│   └── <module>_env.sv          # 验证环境（组件的容器）
├── agent/
│   ├── <module>_agent.sv        # Agent（driver + monitor + sequencer）
│   ├── <module>_driver.sv       # 驱动 DUT 输入
│   ├── <module>_monitor.sv      # 监控 DUT 输入输出
│   └── <module>_sequencer.sv    # 序列管理器
├── sequence/
│   ├── <module>_base_seq.sv     # 基础 sequence
│   ├── <module>_reg_seq.sv      # 寄存器测试 sequence
│   ├── <module>_data_seq.sv     # 数据通路 sequence
│   └── <module>_error_seq.sv    # 异常注入 sequence
├── scoreboard/
│   └── <module>_sb.sv           # 记分板（结果比对）
├── coverage/
│   └── <module>_cov.sv          # 功能覆盖率
├── tests/
│   ├── <module>_base_test.sv    # 基础 test
│   ├── <module>_reg_test.sv     # 寄存器 test
│   ├── <module>_data_test.sv    # 数据通路 test
│   └── <module>_error_test.sv   # 异常 test
└── sim_cfg/
    └── sim.tcl                  # 仿真脚本
```

---

## 输入

- 测试点描述（YAML/Markdown/自然语言）
- RTL 模块接口信息
- UVM 验证环境结构（可选）

## 输出

- UVM test class / sequence / driver / monitor / scoreboard（.sv）

---

## UVM Test 模板

```systemverilog
// ============================================================================
// Test: <module>_<case>_test
// Description: <description>
// ============================================================================

class <module>_<case>_test extends <module>_base_test;
  `uvm_component_utils(<module>_<case>_test)

  <module>_<case>_seq  m_seq;

  //============================================================================
  // Constructor
  //============================================================================
  function new(string name = "<module>_<case>_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //============================================================================
  // Build Phase
  //============================================================================
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_seq = <module>_<case>_seq::type_id::create("m_seq");
  endfunction

  //============================================================================
  // Run Phase
  //============================================================================
  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info(get_type_name(), "Test started", UVM_LOW)

    m_seq.start(m_env.m_agent.m_seqr);

    `uvm_info(get_type_name(), "Test finished", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass
```

---

## UVM Sequence 模板

```systemverilog
// ============================================================================
// Sequence: <module>_<case>_seq
// Description: <description>
// ============================================================================

class <module>_<case>_seq extends <module>_base_seq;
  `uvm_object_utils(<module>_<case>_seq)

  // Transaction handle
  <module>_txn m_txn;

  //============================================================================
  // Constructor
  //============================================================================
  function new(string name = "<module>_<case>_seq");
    super.new(name);
  endfunction

  //============================================================================
  // Body
  //============================================================================
  task body();
    `uvm_info(get_type_name(), "Sequence started", UVM_MEDIUM)

    // Step 1: Reset
    `uvm_do_with(m_txn, { txn_type == RESET; })
    repeat (10) m_txn.wait_cycles(1);

    // Step 2: Configuration
    `uvm_do_with(m_txn, {
        txn_type == WRITE;
        addr      == 12'h000;
        data      == 32'h1;
    })

    // Step 3: Main test body
    repeat (100) begin
        `uvm_do_with(m_txn, {
            txn_type == WRITE;
            addr      inside {[12'h010:12'h01F]};
        })
    end

    // Step 4: Readback & check
    `uvm_do_with(m_txn, {
        txn_type == READ;
        addr      == 12'h000;
    })

    `uvm_info(get_type_name(), "Sequence completed", UVM_LOW)
  endtask

endclass
```

---

## UVM Driver 模板

```systemverilog
// ============================================================================
// Driver: <module>_driver
// Description: Drives DUT input signals via virtual interface
// ============================================================================

class <module>_driver extends uvm_driver #(<module>_txn);
  `uvm_component_utils(<module>_driver)

  virtual <module>_if  m_vif;

  //============================================================================
  // Constructor
  //============================================================================
  function new(string name = "<module>_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //============================================================================
  // Build Phase
  //============================================================================
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual <module>_if)::get(this, "", "m_vif", m_vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  //============================================================================
  // Run Phase
  //============================================================================
  task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req);
      drive_txn(req);
      seq_item_port.item_done();
    end
  endtask

  //============================================================================
  // Drive Transaction
  //============================================================================
  task drive_txn(<module>_txn txn);
    @(posedge m_vif.clk);
    case (txn.txn_type)
      RESET: begin
        m_vif.rst_n   <= 1'b0;
        repeat (5) @(posedge m_vif.clk);
        m_vif.rst_n   <= 1'b1;
      end
      WRITE: begin
        m_vif.wr_en   <= 1'b1;
        m_vif.addr    <= txn.addr;
        m_vif.wr_data <= txn.data;
        @(posedge m_vif.clk);
        m_vif.wr_en   <= 1'b0;
      end
      // ... other transaction types
    endcase
  endtask

endclass
```

---

## UVM Monitor 模板

```systemverilog
// ============================================================================
// Monitor: <module>_monitor
// Description: Monitors DUT I/O and sends transactions to scoreboard
// ============================================================================

class <module>_monitor extends uvm_monitor;
  `uvm_component_utils(<module>_monitor)

  virtual <module>_if   m_vif;
  uvm_analysis_port #(<module>_txn)  ap;

  //============================================================================
  // Constructor
  //============================================================================
  function new(string name = "<module>_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //============================================================================
  // Build Phase
  //============================================================================
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(virtual <module>_if)::get(this, "", "m_vif", m_vif))
      `uvm_fatal("NOVIF", "Virtual interface not found")
  endfunction

  //============================================================================
  // Run Phase
  //============================================================================
  task run_phase(uvm_phase phase);
    <module>_txn txn;
    forever begin
      @(posedge m_vif.clk);
      if (m_vif.wr_en) begin
        txn = <module>_txn::type_id::create("txn");
        txn.txn_type = WRITE;
        txn.addr     = m_vif.addr;
        txn.data     = m_vif.wr_data;
        ap.write(txn);
      end
      // ... other monitored signals
    end
  endtask

endclass
```

---

## UVM Scoreboard 模板

```systemverilog
// ============================================================================
// Scoreboard: <module>_scoreboard
// Description: Compares DUT output against expected results
// ============================================================================

class <module>_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(<module>_scoreboard)

  uvm_analysis_imp #(<module>_txn, <module>_scoreboard)  m_imp;

  int m_pass_cnt;
  int m_fail_cnt;

  //============================================================================
  // Constructor
  //============================================================================
  function new(string name = "<module>_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //============================================================================
  // Build Phase
  //============================================================================
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m_imp = new("m_imp", this);
  endfunction

  //============================================================================
  // Write (analysis port callback)
  //============================================================================
  function void write(<module>_txn txn);
    if (txn.txn_type == READ) begin
      if (txn.data == txn.expected) begin
        m_pass_cnt++;
        `uvm_info(get_type_name(), $sformatf("PASS: addr=0x%03h rdata=0x%08h",
                                              txn.addr, txn.data), UVM_MEDIUM)
      end else begin
        m_fail_cnt++;
        `uvm_error(get_type_name(), $sformatf("FAIL: addr=0x%03h got=0x%08h exp=0x%08h",
                                              txn.addr, txn.data, txn.expected))
      end
    end
  endfunction

  //============================================================================
  // Report Phase
  //============================================================================
  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(), $sformatf("PASS=%0d FAIL=%0d", m_pass_cnt, m_fail_cnt), UVM_LOW)
  endfunction

endclass
```

---

## 测试用例分类

| 类型 | 说明 | UVM 组件 |
|------|------|---------|
| 寄存器测试 | 读写/位域/默认值 | `_reg_seq` + `_reg_test` |
| 数据通路测试 | 传输/边界/背压 | `_data_seq` + `_data_test` |
| 控制逻辑测试 | FSM/中断/握手 | `_ctrl_seq` + `_ctrl_test` |
| 异常测试 | 错误注入/超时 | `_error_seq` + `_error_test` |
| 性能测试 | 吞吐量/延迟 | `_perf_seq` + `_perf_test` |

## UVM Phase 执行顺序

```
build_phase → connect_phase → end_of_elaboration_phase
                                              ↓
report_phase ← check_phase ← main_phase ← run_phase
                                              ↓
                                     extract_phase → final_phase
```

## 与其他 Skill 配合

```
spec_parser → testplan_gen → testcase_gen → vcs_sim（VCS+UVM 仿真，主力）
         assertion_gen ↗                ↘ modelsim_sim/verilator_sim（备选）
                                         ↘ coverage_analyze（覆盖率闭环）
```

> **仿真器选择**：Linux+VCS 项目用 `/vcs-sim`（主力）；Windows 或无 VCS 时用
> modelsim_sim/verilator_sim（备选）。

## Step N: 接入验证（生成后必须执行，防止死用例）

> **痛点来源**：生成的 test 若不加入 Makefile 的 test 列表，`make sim-uvm-regr`
> 不会跑它——死用例。与 tb_writer/assertion_gen 同类问题。

生成 test/sequence 后，逐项确认：

| # | 检查项 | 方法 | 不通过处理 |
|:-:|:--|:--|:--|
| 1 | test 类名在 Makefile test 列表 | `grep <test_name> Makefile` 非空 | 加入 Makefile 的 UVM_TESTS/test 列表变量 |
| 2 | 编译通过 | `make sim-uvm-compile` 或 `make sim-uvm-run TEST=<test>` PASS | 修复 test 类定义/sequence 引用 |
| 3 | 运行有结果 | `sim/log/<test>.log` 含 UVM_REPORT_SUMMARY | 修复 $finish/objection |
| 4 | 无 UVM_FATAL | grep log `UVM_FATAL :    0` | 修复 fatal 错误 |
| 5 | testplan 测试点追溯 | test 注释标注覆盖的 testplan ID（`// Covers: <ID>`） | 补注释，供 coverage-analyze 反向映射 |

**接入验证报告**：
```
testcase 接入验证 — <test>
✅ Makefile: UVM_TESTS 含 <test>
✅ 编译: make sim-uvm-compile PASS
✅ 运行: UVM_ERROR=0 UVM_FATAL=0
✅ 追溯: Covers <TEST_ID_1>, <TEST_ID_2>
→ test 已接入可运行
```

## Step N+1: 实现完整性自检（生成后必须执行，防"标 ✅ 但没真测"）

> **痛点来源**（示例：某项目曾发生）：testplan 标 63 个测试点全 ✅，但逐项核对
> sequence 发现 18 个"标 ✅ 但没测/测错"——完全未实现、实现的是别的场景（ID 错配）、
> 只发 [INFO] 无 PASS/FAIL 判定。接入验证只查"test 能跑"，不查"测试点语义真实现"。
> 本步骤查语义完整性。

生成/修改 sequence 后，对照 testplan 逐测试点自检：

| # | 检查项 | 方法 | 问题判定 |
|:-:|:--|:--|:--|
| 1 | 每个测试点 ID 在 sequence 命中 | `grep <ID> tb/uvm/sequence/` | 命中 0 → 完全未实现（标 ✅ 不合理） |
| 2 | sequence 语义匹配 testplan 描述 | 读 ID 命中处上下文 | 实现的是别的场景 → ID 错配/实现不符 |
| 3 | 有 PASS/FAIL 判定（非仅 INFO） | grep ID 命中处的 `[PASS]`/`[FAIL]`/`uvm_error` | 只 `[INFO]` → 伪实现，补判定 |
| 4 | 预期与 RTL 行为一致 | 对照 RTL 该路径 | RTL 无此逻辑 → 转交 verify-completeness 决策（G3） |
| 5 | 覆盖所有 P0 测试点 | testplan 中 P0 项逐个查 1-3 | 任一 P0 未实现 → 阻塞签收 |

**实现完整性自检报告**：
```
testcase 实现完整性 — <module>
测试点总数: 63
✅ 真实现: 45
❌ 完全未实现: 8 (SMP_003, SMP_012, SMP_019, SMP_021, REG_004, REG_008, ...)
⚠️ 实现不符: 3 (CAL_003 测的是清CAL_ST非校准中触发, CAL_004/005 语义错配, SMP_002 通道集合不符)
ℹ️ 伪实现(仅INFO): 4 (TRG_007/008/009, SMP_021)
🔴 P0 未实现: 3 (阻塞签收)
→ 需补/修正 15 个测试点，移交 verify-completeness 确认 G3 决策
```

> **与 verify-completeness 分工**：本自检是 testcase_gen 生成后的自我审查（第一
> 意见），verify-completeness 是独立的完整性审计（第二意见，覆盖 spec↔testplan
> 全链路）。两者互补：本自检聚焦"sequence 是否实现 testplan"，verify-completeness
> 聚焦"testplan 是否覆盖 spec + sequence 是否真实现"。

### 伪实现识别要点

`[INFO]` 不是验证，是观察。以下模式是伪实现，必须补 PASS/FAIL（示例）：
```systemverilog
// ❌ 伪实现：只发 INFO，无判定
`uvm_info(get_type_name(), "[INFO] <TP_ID>: <场景描述> (not runnable)", UVM_LOW)

// ❌ 伪实现：发了 PASS 但没真检查结果
`uvm_info(get_type_name(), "[PASS] <TP_ID>: <激励描述> sent", UVM_LOW)
// 上面"sent"只证明发了激励，没验证 DUT 响应——应补读寄存器检查结果位

// ✅ 真实现：发激励 + 检查结果 + PASS/FAIL
apb_read(`<REG>, rd);
if (rd[<VALID_BIT>]) `uvm_info(get_type_name(), "[PASS] <TP_ID>: <预期结果>", UVM_LOW)
else `uvm_error(get_type_name(), "[FAIL] <TP_ID>: <失败描述>")
```

## Sequence 编写规范（强制）

### 1. 每个 sequence 开头必须 SW_RST 清干净状态

> **痛点来源**（示例：某项目曾发生）：配置类信号去掉 CDC 同步后（按 rtl_generator
> §5 CDC 规范），开机后直接写使能位=1 再触发，analog model/FSM 状态不干净
> 导致结果无效。SW_RST 确保使能位先回到 0 再写 1，给配置信号足够稳定时间。

```systemverilog
// ✅ 正确：每个 sequence body() 开头（示例值，按实际寄存器/位定义替换）
task body();
    // SW_RST for clean CDC state
    apb_write(`<CTRL_REG>, 32'h0000_0002);  // SW_RST=1
    #2000;
    apb_write(`<CTRL_REG>, 32'h0000_0001);  // 使能位=1
    #200;
    // ... 然后开始测试 ...
```

### 2. 迭代测试每次触发前必须清 VALID

> **痛点来源**（示例）：多次触发同一序列位置不读数据寄存器，第二次触发命中 overflow
> 而非新 VALID=1。每次迭代前必须 SW_RST 或读取清除数据寄存器的 VALID。

### 3. overflow 测试必须序列长度=1

> **痛点来源**（示例）：overflow 检测在某时钟域，当同序列位置二次写时才触发。如果
> 序列长度为默认值，每次触发产生多个采样，slot 0 的二次写时序不可靠。必须设序列
> 长度=1 确保每次触发只写 slot 0。

### 4. 数据寄存器序列绑定时 scoreboard 数据值匹配不可靠

> **痛点来源**（示例）：数据寄存器从通道绑定改为序列绑定后，monitor 只导出通道号
> 不导出序列指针，scoreboard 无法区分不同来源的完成事件，用启发式猜 slot 产生假
> mismatch。此时 scoreboard 应改为只检查 VALID 标志，数据正确性由 sequence
> 独立验证（读寄存器后比对 data 域）。
