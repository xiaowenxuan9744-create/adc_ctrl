# SystemVerilog Testbench 模板

AGDC 模块 ModelSim 仿真的 SystemVerilog testbench 模板。

## 文件命名

`sim/unit/<module>/modelsim/tb_<module>.sv`

## 完整模板

```systemverilog
//******************************************************************************
// File:       tb_<module>.sv
// Description: SystemVerilog testbench for <module>
// Simulator:  ModelSim / Questa
//******************************************************************************

`timescale 1ns / 1ps

module tb_<module>;

    //--------------------------------------------------------------------------
    // Parameters
    //--------------------------------------------------------------------------
    localparam CLK_PERIOD_PS = 3333; // 300 MHz -> 3.333 ns

    //--------------------------------------------------------------------------
    // DUT Ports
    //--------------------------------------------------------------------------
    logic        clk;
    logic        rst_n;
    // ... 其他端口按需声明

    //--------------------------------------------------------------------------
    // DUT Instance
    //--------------------------------------------------------------------------
    <module> #(
        // .PARAM(VALUE)
    ) u_dut (
        .clk        (clk    ),
        .rst_n      (rst_n  )
        // ...
    );

    //--------------------------------------------------------------------------
    // Clock Generation
    //--------------------------------------------------------------------------
    initial begin
        clk = 0;
        forever #(CLK_PERIOD_PS / 2) clk = ~clk;
    end

    //--------------------------------------------------------------------------
    // VCD Dump (optional — ModelSim natively writes WLF)
    //--------------------------------------------------------------------------
    initial begin
        $dumpfile("<module>.vcd");
        $dumpvars(0, tb_<module>);
    end

    //--------------------------------------------------------------------------
    // Test Infrastructure
    //--------------------------------------------------------------------------
    int total_tests  = 0;
    int passed_tests = 0;

    // tick: wait n full clock cycles.
    // CRITICAL: 使用 @(negedge clk) 而非 #1——
    // negedge 时刻 NBA 更新一定已完成，采样可靠。
    task automatic tick(input int n = 1);
        repeat (n) begin
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    // check: auto PASS/FAIL with counter
    task automatic check(input string name, input logic pass,
                         input logic expected, input logic actual);
        total_tests++;
        if (pass) begin
            passed_tests++;
            $display("  [PASS] %s: 0x%0X", name, actual);
        end else begin
            $display("  [FAIL] %s: expected 0x%0X, got 0x%0X",
                     name, expected, actual);
        end
    endtask

    //--------------------------------------------------------------------------
    // Timeout
    //--------------------------------------------------------------------------
    initial begin
        #5000000; // 5us timeout
        $display("ERROR: Simulation timeout");
        $finish;
    end

    //--------------------------------------------------------------------------
    // Main Test Sequence
    //--------------------------------------------------------------------------
    initial begin
        $display("\n========================================");
        $display("  <MODULE> Unit Simulation (ModelSim)");
        $display("========================================\n");

        //----------------------------------------------------------------------
        // Init: apply async reset
        // CRITICAL: rst_n MUST be explicitly set to 0.
        //           logic defaults to X, !X = X → reset branch skipped.
        //----------------------------------------------------------------------
        // ... 设置输入默认值 ...
        rst_n = 0;
        tick(5);
        check("dout after reset", dout == 0, 1'b0, dout);

        // Release reset
        rst_n = 1;
        tick(3);
        check("dout after reset release", dout == 0, 1'b0, dout);

        //----------------------------------------------------------------------
        // TEST 1: <test name>
        //----------------------------------------------------------------------
        $display("\n[TEST 1] <test description>");
        // Drive inputs on negedge to avoid race
        @(negedge clk);
        din = 1;
        tick(2);
        check("<check name>", dout == 1, 1'b1, dout);

        // ... more tests ...

        //----------------------------------------------------------------------
        // Summary
        //----------------------------------------------------------------------
        $display("\n========================================");
        $display("  Simulation Complete");
        $display("========================================");
        $display("  Total:  %0d", total_tests);
        $display("  Passed: %0d", passed_tests);
        $display("  Failed: %0d", total_tests - passed_tests);
        $display("  Pass Rate: %.1f%%",
                 100.0 * passed_tests / total_tests);
        $display("========================================\n");

        tick(10);
        $finish;
    end

endmodule
```

## 关键编码规则

### 1. tick() 使用 `@(negedge clk)` 而非 `#1`

```systemverilog
task automatic tick(input int n = 1);
    repeat (n) begin
        @(posedge clk);
        @(negedge clk);  // ← negedge 时刻 NBA 已稳定
    end
endtask
```

**为什么**：`#1` 在 Active 区域执行，无法保证 DUT 的 NBA 更新（`<=`）已完成。改用 `@(negedge clk)`，在 negedge 时 posedge 触发的所有 NBA 必然已更新完毕，采样可靠。

### 2. 输入驱动用 `@(negedge clk)`

```systemverilog
@(negedge clk);  // 确保在上一个 posedge 的 NBA 完成后再修改输入
din = <new_value>;
tick(1);
```

### 3. 复位必须显式赋 0

```systemverilog
initial begin
    rst_n = 0;  // ← 必须！logic 默认 X，!X=X → DUT 复位分支不执行
    tick(5);
    ...
```

### 4. check() 使用阻塞赋值检查

```systemverilog
// tick() 返回时已过 #1，DUT 信号稳定，阻塞读取即可
check("name", dout == expected, expected, dout);
```

## Verilator C++ → SystemVerilog 移植映射

| C++ (Verilator) | SystemVerilog |
|-----------------|---------------|
| `top->din = 1;` | `din = 1;` |
| `tick(3);` | `tick(3);` (含 `#1`) |
| `top->dout` | `dout` |
| `top->rst_n = 0;` | `rst_n = 0;` |
| `top->clk = 0; top->eval(); ...` | (tick 内部处理) |
| `VerilatedVcdC* tfp = ...;` | `$dumpfile;$dumpvars;` |
| `check("x", cond, exp, act)` | `check("x", cond, exp, act)` |

## ModelSim 10.7 兼容注意事项

ModelSim 10.7 (2017) 对 SystemVerilog 支持有限，编写 TB 时需遵守：

| 规则 | 错误示例 | 正确示例 |
|------|---------|---------|
| 禁止 `for (int i=...)` | `for (int i = 0; ...)` | `int i; for (i = 0; ...)` |
| 声明在语句之前 | 在 `$display` 之后声明 `logic` | 所有声明放在 `begin` 块最开头 |
| 禁止 `$random[7:0]` | `$random[7:0]` | `$urandom_range(0,255)` |
| 禁止 `N'sd(-N)` | `18'sd(-16)` | `-18'sd16` |
| TCL `[N]` 转义 | `add wave .../sig[0]` | `add wave .../sig\[0\]` |
| `for` 内禁止声明 | `for (int i=0; ...)` 块内再声明变量 | 将变量提升到模块级或块开头 |

