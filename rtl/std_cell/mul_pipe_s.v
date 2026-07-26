//*********************** Module Header ***************************************
// Module        : std_cell_mul_pipe_s
// Description   : 有符号流水线乘法器封装（行为模型占位）。
//                 功能 RTL 用此封装代替内联有符号 `*` 运算，流片时通过
//                 `STD_CELL_USE_FOUNDRY_DSP` 宏切换为晶圆厂 DSP IP。
//                 默认（不定义宏）走行为模型：P_LATENCY=0 组合输出。
// Parameters    : P_WIDTH_A  操作数 A 位宽（有符号）
//                 P_WIDTH_B  操作数 B 位宽（有符号）
//                 P_LATENCY  流水级数（0=组合）
// Clock         : clk（P_LATENCY>0 时使用）
// Reset         : rst_n（异步低有效，P_LATENCY>0 时使用）
//******************************************************************************
module std_cell_mul_pipe_s #(
    parameter P_WIDTH_A  = 16,
    parameter P_WIDTH_B  = 16,
    parameter P_LATENCY  = 0
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire signed [P_WIDTH_A-1:0]  a,
    input  wire signed [P_WIDTH_B-1:0]  b,
    output wire signed [P_WIDTH_A+P_WIDTH_B-1:0] product
);

`ifdef STD_CELL_USE_FOUNDRY_DSP
    // ─── 晶圆厂 DSP IP 实例（流片时替换） ───
    // foundry_mul_s u_foundry (
    //     .clk      (clk),
    //     .rst_n    (rst_n),
    //     .a        (a),
    //     .b        (b),
    //     .p        (product)
    // );
    initial begin
        $error("std_cell_mul_pipe_s: STD_CELL_USE_FOUNDRY_DSP defined but foundry IP not instantiated. Replace this with foundry_mul_s instance at tapeout.");
    end
`else
    // ─── 行为模型（功能仿真用，有符号） ───
    wire signed [P_WIDTH_A+P_WIDTH_B-1:0] mul_result;
    assign mul_result = a * b;

    generate
        if (P_LATENCY == 0) begin : gen_comb
            assign product = mul_result;
        end else begin : gen_pipe
            reg signed [P_WIDTH_A+P_WIDTH_B-1:0] p_reg;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) p_reg <= {P_WIDTH_A+P_WIDTH_B{1'b0}};
                else        p_reg <= mul_result;
            end
            assign product = p_reg;
        end
    endgenerate
`endif

endmodule
