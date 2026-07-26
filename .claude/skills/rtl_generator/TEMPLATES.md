# RTL Generator — 按需模板与速查表

> 本文档从 `rtl_generator` SKILL.md 外迁的**按需内容**：纯实例模板与速查表。
> 生成 RTL 时不必每篇注入；只在用到对应 IP / 模式时按需 grep 本文档相应节。
>
> **核心规范（CDC 同步、寄存器位域、编码风格、FSM、可综合、Generate、时序/DFT/仿真）
> 仍在 SKILL.md 内，生成时随 skill 注入——不在本文件。**

---

## 1. 标准单元封装实例模板

功能 RTL 禁止直接用 `*`/`/`，必须用 `rtl/std_cell/` 封装（`<proj>_` 为项目前缀）。
封装清单与使用规则见 SKILL.md「标准单元封装」段；下面是实例模板，按需查阅。

### 除法器实例模板

```verilog
<proj>_div_pipe #
(
    .P_WIDTH_N (42  ),
    .P_WIDTH_D (12  ),
    .P_WIDTH_Q (42  ),
    .P_LATENCY (41  ),
    .P_CEIL    (1   )
)
u_div_x
(
    .core_clk   (core_clk    ),
    .rst_n      (rst_n       ),
    .din_vld    (div_start   ),
    .din_numer  (dividend    ),
    .din_denom  (divisor     ),
    .dout_vld   (div_done    ),
    .dout_quot  (div_result  ),
    .dout_ready (             )
);
```

### 乘法器实例模板

```verilog
// Unsigned
<proj>_mul_pipe #
(
    .P_WIDTH_A (12),
    .P_WIDTH_B (7 ),
    .P_LATENCY (0 )
)
u_mul_addr
(
    .core_clk (core_clk  ),
    .rst_n    (rst_n     ),
    .din_a    (row       ),
    .din_b    (cols      ),
    .dout     (addr_prod )
);

// Signed
<proj>_mul_pipe_s #
(
    .P_WIDTH_A (18),
    .P_WIDTH_B (18),
    .P_LATENCY (0 )
)
u_mul_affine
(
    .core_clk (core_clk   ),
    .rst_n    (rst_n      ),
    .din_a    (coeff_a    ),
    .din_b    (coord_u    ),
    .dout     (prod_au    )
);
```

### 时钟门控实例模板

```verilog
<proj>_clk_gate u_ckg_pipe0
(
    .clk_in  (core_clk             ),
    .en      (pipe0_active | ckg_dis),
    .te      (scan_mode            ),
    .clk_out (core_clk_gated_pipe0 )
);
```

### 条件编译策略

封装模块内部用 `ifdef` 保护，不定义宏时走行为模型，定义后走晶圆厂 IP：

| 宏定义 | 影响模块 |
|--------|----------|
| `<PROJ>_USE_FOUNDRY_DIV` | `<proj>_div_pipe` |
| `<PROJ>_USE_FOUNDRY_DSP` | `<proj>_mul_pipe`, `<proj>_mul_pipe_s` |
| `<PROJ>_USE_FOUNDRY_ICG` | `<proj>_clk_gate` |

流片时在综合脚本中定义对应宏即可切换，功能 RTL 无需修改。

---

## 2. SHELL_MODE 代码模板

SHELL_MODE 规范（设计意图 + 实现规范）见 SKILL.md「SHELL_MODE 空壳模式」段；
下面是完整代码模板与 tie-off 速查表，按需查阅。

### 完整代码模板

```verilog
module <module_name> #(
    parameter P_DATA_WIDTH  = 32,
    parameter P_SHELL_MODE  = 0      // 1 = shell mode, bypass all internal logic
) (
    input  wire                        core_clk,
    input  wire                        rst_n,
    // Upstream handshake
    input  wire                        pready,
    output wire                        pvalid,
    output wire [P_DATA_WIDTH-1:0]     pdata,
    // Downstream handshake
    output wire                        sready,
    input  wire                        svalid,
    input  wire [P_DATA_WIDTH-1:0]     sdata,
    // Status
    output wire                        interrupt
);

    //--------------------------------------------------------------------------
    // Shell Mode: tie outputs to safe fixed values, no internal logic
    //--------------------------------------------------------------------------
    generate
        if (P_SHELL_MODE) begin : gen_shell

            // Handshake: upstream — not ready to accept, no valid output
            assign sready  = 1'b0;                     // backpressure: not ready
            assign pvalid  = 1'b0;                     // no valid data produced
            assign pdata   = {P_DATA_WIDTH{1'b0}};     // data tied to 0

            // Status / interrupt
            assign interrupt = 1'b0;                   // no interrupt

            // Unused inputs are optimized away by synthesis

        //--------------------------------------------------------------------------
        // Active Mode: normal functional logic
        //--------------------------------------------------------------------------
        end else begin : gen_active

            // ... normal RTL implementation ...

            // Example handshake logic
            assign sready  = ~fifo_full;
            assign pvalid  = fifo_not_empty;
            assign pdata   = fifo_rdata;

            // ... submodule instantiations ...

        end
    endgenerate

endmodule
```

### 信号 tie-off 速查表

| 信号类型 | 方向 | SHELL_MODE 值 | 说明 |
|----------|------|---------------|------|
| `*ready` / `*rdy` | output | `1'b1` | 表示始终可接收，不阻塞上游 |
| `*valid` / `*vld` | output | `1'b0` | 表示无有效数据，下游不采样 |
| `*data` / `*addr` / `*len` / `*size` | output | `'0` | 数据总线接全零 |
| `*interrupt` / `*error` / `*err` | output | `1'b0` | 不触发中断/错误 |
| `*last` / `*end` | output | `1'b0` | 非最后一拍 |
| `*keep` / `*strobe` | output | `'0` | 字节使能全零 |
| `*id` / `*user` | output | `'0` | 侧带信号全零 |
| 总线主接口（如 AXI/AHB master） | output | 所有 output 按上述规则 tie-off | 等同于 master 空闲 |
| 寄存器配置输出（cfg_*） | output | `'0` | 配置值全零（默认值） |

> **注意**：特定模块可能有例外——如某些 ready 信号在 SHELL_MODE 下应接 `1'b0` 以阻断上游数据流。请在模块规格中明确说明例外情况。

### 顶层集成建议

在顶层 `<top_module>` 中，通过系统级宏定义统一控制所有子模块的 SHELL_MODE：

```verilog
// <top_module>.v
`ifdef <PROJ>_SHELL_MODE
    localparam LP_SHELL_MODE = 1;
`else
    localparam LP_SHELL_MODE = 0;
`endif

<module_a> #(
    .P_SHELL_MODE (LP_SHELL_MODE)
) u_module_a (
    ...
);

<module_b> #(
    .P_SHELL_MODE (LP_SHELL_MODE)
) u_module_b (
    ...
);
```

仿真时通过 `+define+<PROJ>_SHELL_MODE` 一键切换全系统空壳模式。也可以按模块粒度单独控制。

---

## 3. 生成示例（accumulator）

**输入 JSON**：

```json
{
  "modules": [{
    "name": "accumulator",
    "ports": [
      {"name": "clk", "direction": "input", "width": 1, "type": "clock"},
      {"name": "rst_n", "direction": "input", "width": 1, "type": "reset"},
      {"name": "data_in", "direction": "input", "width": 32},
      {"name": "data_valid", "direction": "input", "width": 1},
      {"name": "result", "direction": "output", "width": 32}
    ],
    "description": "累加器，每个valid周期累加输入数据"
  }]
}
```

**输出 Verilog**：

```verilog
// ============================================================================
// Module: accumulator
// Description: 累加器，每个valid周期累加输入数据
// ============================================================================

module accumulator #(
  parameter DATA_WIDTH = 32
) (
  input  wire                    clk,
  input  wire                    rst_n,
  input  wire [DATA_WIDTH-1:0]   data_in,
  input  wire                    data_valid,
  output reg  [DATA_WIDTH-1:0]   result
);

  //--------------------------------------------------------------------------
  // Internal Signals
  //--------------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] acc_reg;

  //--------------------------------------------------------------------------
  // Accumulator Logic
  //--------------------------------------------------------------------------
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      acc_reg <= {DATA_WIDTH{1'b0}};
      result  <= {DATA_WIDTH{1'b0}};
    end else begin
      if (data_valid) begin
        acc_reg <= acc_reg + data_in;
      end
      result <= acc_reg;
    end
  end

endmodule
```
