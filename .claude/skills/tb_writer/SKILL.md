---
name: tb-writer
description: 根据设计规格生成结构化、自检查的 Verilog/SystemVerilog testbench
triggers:
  - 生成testbench
  - 生成TB
  - 测试平台
  - testbench编写
  - tb编写
  - 验证代码
---

# TB Writer — Testbench 代码生成器

根据设计规格生成自检查、结构化的 testbench 代码。

## 输入

- 模块规格说明（接口、时序、寄存器）
- 测试场景列表（功能点 / 边界条件 / 异常场景）
- 项目中已有的 `tb/` 目录下的辅助文件（如总线模型、行为模型等）
- RTL 源代码（用于模块例化）

## 输出

- Testbench 主文件（`tb_<module>.v`）
- 如有多个测试场景，可选输出分立的 test case 文件（`tc_<case>.v`）

## 约束与规范

### 1. 整体架构

```text
tb/
├── <module>/
│   ├── tb_<module>.v       # 主 testbench（harness，固定结构）
│   ├── tc_<case1>.v        # test case 1（可选拆分）
│   ├── tc_<case2>.v        # test case 2
│   └── ...
```

- 每个被验证模块一个独立目录
- 主 testbench 负责：例化 DUT、时钟/复位生成、波形 dump、仿真结束控制
- test case 文件（如拆分）只包含激励和检查逻辑

### 2. 自检查（Self-Checking）— 强制

所有 testbench 必须自动比对结果，输出 `PASS`/`FAIL`，**禁止裸跑无检查**：

```verilog
reg [31:0] expected;
reg [31:0] got;
integer pass, fail;

initial begin
    pass = 0; fail = 0;

    // Step 1: Write configuration register
    apb_write(8'h00, 32'h0000_0001);  // CTRL: EN=1

    // Step 2: Wait for DUT to process
    repeat (100) @(posedge clk);

    // Step 3: Read status register and check
    apb_read(8'h04, got);
    expected = 32'h0000_0001;         // expected value
    if (got === expected) begin
        $display("[PASS] STAT expected 0x%0h, got 0x%0h", expected, got);
        pass = pass + 1;
    end else begin
        $display("[FAIL] STAT expected 0x%0h, got 0x%0h", expected, got);
        fail = fail + 1;
    end

    // Summary
    $display("=== Results: %0d passed, %0d failed ===", pass, fail);
    $finish;
end
```

### 3. 仿真超时保护 — 强制

每个 testbench 必须设置超时 watchdog，配合 `all_done` 标志防止与主测试的 `$finish` 冲突：

```verilog
reg all_done;  // 全局仿真结束标志

initial begin
    #200_000;  // 200k 时间单位超时，根据实际场景调整
    if (!all_done) begin
        $display("[TIMEOUT] Simulation timed out");
        $display("[FAIL] Timeout");
        $finish;
    end
end

initial begin
    main_test();            // 执行主测试流程
    all_done = 1'b1;
    #100;
    $display("=== Results: %0d passed, %0d failed ===", pass, fail);
    $finish;
end
```

### 4. 控制接口驱动方式 — 根据项目接口类型选择

根据被验证模块的控制接口类型选择合适的驱动方式：

**方式 A：APB 总线接口（推荐用于寄存器配置型模块）**

如果模块通过 APB slave 接口配置，复用项目中已有的 APB 主设备模型，封装可直接使用的读写 task：

```verilog
// APB 驱动 task（复用项目中已有的 apb_master.v）
// 通过 apb_master 的信号接口驱动总线周期
task apb_write(input [31:0] addr, input [31:0] data);
    @(posedge PCLK);
    PADDR  = addr;
    PWDATA = data;
    PWRITE = 1'b1;
    PSEL   = 1'b1;
    @(posedge PCLK);
    PENABLE = 1'b1;
    @(posedge PCLK);
    PSEL    = 1'b0;
    PENABLE = 1'b0;
endtask

task apb_read(input [31:0] addr, output [31:0] data);
    @(posedge PCLK);
    PADDR  = addr;
    PWRITE = 1'b0;
    PSEL   = 1'b1;
    @(posedge PCLK);
    PENABLE = 1'b1;
    @(posedge PCLK);
    data    = PRDATA;
    PSEL    = 1'b0;
    PENABLE = 1'b0;
endtask
```

**方式 B：直接信号驱动（适用于无总线接口的子模块）**

如果模块没有 APB 等总线接口（如纯组合逻辑或同步寄存器子模块），直接用信号赋值驱动：

```verilog
// 直接信号驱动
initial begin
    #100;
    din = 1'b1;  // 给输入赋初值
    #40;
    din = 1'b0;
    // ...
end
```

> 生成 testbench 时先判断模块接口类型：有 APB 等总线接口 → 方式 A，纯组合/同步逻辑子模块 → 方式 B。

### 5. 时钟与复位

- **时钟生成**：使用带周期的 `always` 块，禁止 `#delay` 以外的时序控制（`#delay` 仅允许在 testbench 中使用）
- **时钟频率**：必须与 spec 一致
- **复位时序**：模拟真实的复位释放过程（释放后等待若干时钟再开始操作）

```verilog
initial begin
    rst_n = 1'b0;
    #100;
    rst_n = 1'b1;
    #100;
    // 开始测试...
end

always #10 clk = ~clk;  // 50 MHz example
```

### 6. 波形 dump 控制 — 对齐工具链

默认使用 VCS 生成 VPD 波形，iverilog 作为备选：

```verilog
initial begin
`ifdef VCS
    // VCS：生成 VPD 波形，配合仿真器 +vpdfile+path 选项使用
    $vcdpluson(0, tb_top);            // dump 全部层次
    // $vcdpluson(0, tb_top.u_dut);    // 可选：仅 dump DUT 层次
`else
    // iverilog 备选：生成 VCD 波形
    $dumpfile("waveform.vcd");
    $dumpvars(0, tb_top);
`endif
end
```

### 7. 行为模型对齐 spec

- 模拟行为模型的时序必须严格对齐设计规格
- 确认模型中关键延迟参数（如握手响应周期数）与 spec 一致
- 如需修改模拟行为，通过 parameter 或 `+define+` 控制，不硬编码

### 8. 激励生成规范

| 类型 | 方式 | 示例 |
|:--|:--|:--|
| 寄存器配置 | 调用 `apb_write` task | `apb_write(addr, data);` |
| 软件触发 | 写触发寄存器 | `apb_write(TRIG_ADDR, 1);` |
| 外部脉冲触发 | 模拟外部信号脉冲 | `ext_trig = 1; #20; ext_trig = 0;` |
| 随机数据 | `$random` 或约束随机 | `data = $random % (1 << DATA_WIDTH);` |
| 边界数据 | 直接赋值 | `data = 0; data = {DATA_WIDTH{1'b1}};` |

### 9. 覆盖率收集

- 收集功能覆盖率：指定的寄存器值组合、状态机状态序列
- 收集代码覆盖率：行覆盖、toggle 覆盖（VCS `-cm line+tgl`）
- 覆盖率未达标时输出报告

### 10. 错误注入与异常测试

- 验证**错误路径**而非仅验证**快乐路径**：
  - 配置非法寄存器地址
  - 在操作进行中重新触发
  - 条件不满足时触发操作
  - 握手信号超时不返回（模拟外部设备无响应）

### 11. 日志输出要求

- `[PASS]` / `[FAIL]` 前缀统一，便于 grep 统计
- 关键操作打印时间戳和数据
- 仿真结束打印汇总 `=== Results: X passed, Y failed ===`
- 避免在时钟边沿敏感的逻辑中使用 `$display`（会导致仿真变慢）
- 大量重复打印使用 `$write` 或条件打印

### 12. 设计约束

- TB 代码使用 **简洁直白** 的风格，禁止过度封装
- 每个 test case 只测一个功能点，避免"大杂烩"式 testbench
- testbench 不包含不可综合逻辑以外的设计代码
- 修改模拟模型行为时必须在注释中说明原因

## 示例结构

### 单一模块集成测试

```verilog
`timescale 1ns / 1ps
module tb_<module>;

    // ─── Signals ───
    reg         clk;
    reg         rst_n;
    reg  [31:0] apb_addr;
    reg  [31:0] apb_wdata;
    wire [31:0] apb_rdata;
    reg         apb_write;
    reg         apb_sel;
    wire        apb_ready;
    // ... other DUT signals

    // ─── Clock generation ───
    initial begin
        clk = 0;
        forever #10 clk = ~clk;  // 50 MHz
    end

    // ─── Reset ───
    initial begin
        rst_n = 1'b0;
        #100;
        rst_n = 1'b1;
        #200;
        main_test();
    end

    // ─── Timeout protection ───
    reg all_done;
    initial begin
        #200_000;
        if (!all_done) begin
            $display("[TIMEOUT] Simulation timed out");
            $finish;
        end
    end

    // ─── Waveform dump ───
    initial begin
    `ifdef VCS
        $vcdpluson(0, tb_top);
    `else
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_top);
    `endif
    end

    // ─── DUT instantiation ───
    <module> u_dut (
        .clk   (clk),
        .rst_n (rst_n),
        // ... connect DUT ports
    );

    // ─── Testbench helpers ───
    reg [31:0] pass, fail;

    task apb_write(input [31:0] addr, input [31:0] data);
        @(posedge clk);
        apb_addr  = addr;
        apb_wdata = data;
        apb_write = 1'b1;
        apb_sel   = 1'b1;
        @(posedge clk);
        apb_sel = 1'b0;
        apb_write = 1'b0;
    endtask

    task apb_read(input [31:0] addr, output [31:0] data);
        @(posedge clk);
        apb_addr  = addr;
        apb_write = 1'b0;
        apb_sel   = 1'b1;
        @(posedge clk);
        data      = apb_rdata;
        apb_sel   = 1'b0;
    endtask

    // ─── Main test flow ───
    task main_test;
        pass = 0; fail = 0;
        // tc_example();      // call test cases here
        all_done = 1'b1;
        #100;
        $display("=== Results: %0d passed, %0d failed ===", pass, fail);
        $finish;
    endtask

endmodule
```

### test case 示例（拆分式）

```verilog
// tc_<module>_<case>.v — 示例测试用例
task tc_example;
    reg [31:0] got;
    reg [31:0] expected;
    begin
        $display("=== Test: <case description> ===");

        // Step 1: Configure
        apb_write(8'h00, 32'h0000_0001);  // CTRL: EN=1
        repeat (10) @(posedge clk);

        // Step 2: Read & check
        apb_read(8'h04, got);
        expected = 32'h0000_0001;
        if (got === expected) begin
            $display("[PASS] got 0x%0h", got);
            pass = pass + 1;
        end else begin
            $display("[FAIL] expected 0x%0h, got 0x%0h", expected, got);
            fail = fail + 1;
        end
    end
endtask
```

## Step N: 接入验证（生成后必须执行，防止 TB 不被运行）

> **痛点来源**：生成的 `tb_<module>.v` 若不接入 Makefile 的 test 列表，
> `make test-unit` 不会编译运行它，TB 等于没写。

生成 `tb_<module>.v` 后，逐项确认：

| # | 检查项 | 方法 | 不通过处理 |
|:-:|:--|:--|:--|
| 1 | TB 在 unit 目录 | `ls tb/unit/tb_<module>.v` 存在 | 移到 `tb/unit/`（Makefile test-unit 扫描此目录） |
| 2 | Makefile 能发现 | `make test-unit` 列表含 tb_<module> | Makefile 用 `$(SIM_DIR)/unit/tb_*.v` glob，文件名须 `tb_*.v` |
| 3 | 编译通过 | `make test-unit` 对该 TB 编译 PASS | 修复端口/包含路径，确认 iverilog 显式文件列表含所需 RTL |
| 4 | 运行有结果 | 该 TB 日志含 `Passed: N  Failed: M` | 修复 $finish/超时 |

**接入验证报告**：
```
tb_writer 接入验证 — <module>
✅ 位置: tb/unit/tb_<module>.v
✅ 发现: make test-unit 列表含 tb_<module>
✅ 编译: iverilog + VCS 编译 PASS
✅ 运行: Passed: 8  Failed: 0
→ TB 已接入可运行
```

任一项不通过 → 报告并修复。若 Makefile 用显式 RTL 文件列表（非 -f filelist），
新增模块时需同步把 RTL 文件加进 test-unit 的 iverilog 命令行。
