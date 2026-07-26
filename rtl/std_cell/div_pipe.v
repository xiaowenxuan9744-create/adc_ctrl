//*********************** Module Header ***************************************
// Module        : std_cell_div_pipe
// Description   : 流水线除法器封装模板（行为模型占位）。
//                 这是模板文件——复制到项目后把模块名 std_cell_ 改为项目前缀
//                 （如 xxx_div_pipe），宏 STD_CELL_ 改为项目大写前缀
//                 （如 XXX_USE_FOUNDRY_DIV）。
//                 功能 RTL 用此封装代替内联 `/` 运算，流片时通过宏切换为
//                 晶圆厂 IP。默认（不定义宏）走行为模型：P_LATENCY=0 组合输出。
// Parameters    : P_WIDTH_N  被除数位宽
//                 P_WIDTH_D  除数位宽
//                 P_WIDTH_Q  商位宽
//                 P_LATENCY  流水级数（0=组合）
//                 P_CEIL     1=向上取整除法
// Clock         : clk（P_LATENCY>0 时使用）
// Reset         : rst_n（异步低有效，P_LATENCY>0 时使用）
//******************************************************************************
module std_cell_div_pipe #(
    parameter P_WIDTH_N  = 16,
    parameter P_WIDTH_D  = 8,
    parameter P_WIDTH_Q  = 16,
    parameter P_LATENCY  = 0,
    parameter P_CEIL     = 0
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [P_WIDTH_N-1:0]    dividend,
    input  wire [P_WIDTH_D-1:0]    divisor,
    output wire [P_WIDTH_Q-1:0]    quotient
);

`ifdef STD_CELL_USE_FOUNDRY_DIV
    // ─── 晶圆厂 IP 实例（流片时替换） ───
    // foundry_div u_foundry (
    //     .clk      (clk),
    //     .rst_n    (rst_n),
    //     .a        (dividend),
    //     .b        (divisor),
    //     .q        (quotient)
    // );
    // 占位：未接入 foundry IP 时编译会报错，提示流片时补实例
    initial begin
        $error("std_cell_div_pipe: STD_CELL_USE_FOUNDRY_DIV defined but foundry IP not instantiated. Replace this with foundry_div instance at tapeout.");
    end
`else
    // ─── 行为模型（功能仿真用） ───
    // P_LATENCY=0: 组合输出；P_LATENCY>0: 流水线寄存器（简化为单拍）
    wire [P_WIDTH_Q-1:0] div_result;
    assign div_result = (divisor == 0) ? {P_WIDTH_Q{1'b0}} :
                        (P_CEIL) ? ((dividend + divisor - 1) / divisor) :
                                   (dividend / divisor);

    generate
        if (P_LATENCY == 0) begin : gen_comb
            assign quotient = div_result;
        end else begin : gen_pipe
            reg [P_WIDTH_Q-1:0] q_reg;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) q_reg <= {P_WIDTH_Q{1'b0}};
                else        q_reg <= div_result;
            end
            assign quotient = q_reg;
        end
    endgenerate
`endif

endmodule
