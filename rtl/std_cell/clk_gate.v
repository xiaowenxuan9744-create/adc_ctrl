//*********************** Module Header ***************************************
// Module        : std_cell_clk_gate
// Description   : 时钟门控封装（行为模型占位）。
//                 功能 RTL 用此封装做集成门控时钟（ICG），流片时通过
//                 `STD_CELL_USE_FOUNDRY_ICG` 宏切换为晶圆厂 ICG 单元。
//                 默认（不定义宏）走行为模型：en/te 控制 clk_out。
// Ports         : clk_in   输入时钟
//                 en       功能使能（功能模式 te=0 时由 en 控制门控）
//                 te       测试使能（接 scan_mode，功能模式 te=0）
//                 clk_out  门控后输出时钟
//******************************************************************************
module std_cell_clk_gate (
    input  wire clk_in,
    input  wire en,
    input  wire te,
    output wire clk_out
);

`ifdef STD_CELL_USE_FOUNDRY_ICG
    // ─── 晶圆厂 ICG 单元实例（流片时替换） ───
    // foundry_icg u_foundry (
    //     .clk     (clk_in),
    //     .en      (en),
    //     .te      (te),
    //     .clk_out (clk_out)
    // );
    initial begin
        $error("std_cell_clk_gate: STD_CELL_USE_FOUNDRY_ICG defined but foundry IP not instantiated. Replace this with foundry_icg instance at tapeout.");
    end
`else
    // ─── 行为模型（功能仿真用） ───
    // te=1（测试模式）: 时钟直通（不门控）
    // te=0（功能模式）: en=1 时钟通，en=0 时钟停
    // 注意：行为模型用 assign 模拟，综合时由 foundry ICG 保证无毛刺。
    //       RTL 阶段不关心毛刺，综合工具替换 ICG 后由库保证。
    assign clk_out = (te) ? clk_in : (en ? clk_in : 1'b0);
`endif

endmodule
