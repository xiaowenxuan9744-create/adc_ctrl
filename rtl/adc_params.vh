//==============================================================================
// adc_params.vh — ADC 控制器参数化派生 localparam 集中定义
//
// 本文件是【逗号前缀的 localparam 声明列表】，在 module 的 ANSI 参数列表
// #(...) 中 `include，紧跟主参数之后。需 SystemVerilog（iverilog -g2012 /
// VCS -sverilog）。localparam 在 ANSI 参数列表内声明后，端口列表可直接引用。
//
//   module adc_regfile #(
//       parameter P_SHELL_MODE = 0,
//       parameter ADC_NUM_CH = 26,
//       parameter ADC_DATA_W = 14,
//       parameter ADC_SPT1_CH_MASK = 32'h0060_0000
//   `include "adc_params.vh"     // , localparam integer W_CH_SEL = ...
//   ) ( ... 端口可用 W_CH_SEL/W_LP_SEQ_LEN/NUM_LP_DATA 等 ... );
//
// 主参数（ADC_NUM_CH/ADC_DATA_W/ADC_SPT1_CH_MASK）由各 module 参数列表声明，
// 派生 localparam 不可 override。各 module 各自 include（本文件不加 `ifndef
// 守卫——iverilog `define 全局，守卫会使第二个起 module 跳过声明）。
//
// elaboration 范围断言见 adc_params_check.vh（module body 内 `include）。
// 设计依据：doc/design/2026-07-20-parameterization-design.md
//==============================================================================

// ---- 派生 localparam（逗号前缀接入 #(...)；由主参数算出）----
, localparam integer W_CH_SEL       = $clog2(ADC_NUM_CH)        // ch_sel/LP seq_ptr 位宽（N≥4 → ≥2）
, localparam integer W_LP_SEQ_PTR   = W_CH_SEL                  // LP seq_ptr 0~N-1
, localparam integer W_HP_SEQ_PTR   = 2                         // HP seq_ptr 固定 0~3
, localparam integer W_LP_SEQ_LEN   = $clog2(ADC_NUM_CH + 1)    // 存 count 1~N：8→4, 26→5, 32→6
, localparam integer W_HP_SEQ_LEN   = 3                         // HP_SEQ_LEN 固定 1~4
, localparam integer NUM_LP_DATA    = ADC_NUM_CH                // LP_DATA 寄存器数
, localparam integer NUM_HP_DATA    = 4                         // HP_DATA 固定 4
, localparam integer NUM_LP_SEQ_REG = (ADC_NUM_CH + 3) / 4      // LP_SEQ 寄存器组数（每组 4 条 seq）
, localparam integer NUM_HP_SEQ_REG = 1                         // HP_SEQ 固定 1 组
, localparam integer W_LP_DATA_WEN  = ADC_NUM_CH                // lp_data_wr_en one-hot 宽
, localparam integer W_HP_DATA_WEN  = 4                         // hp_data_wr_en 固定
, localparam integer W_EOC_IDX      = W_CH_SEL                  // eoc_idx 宽（够索引 LP+HP）
, localparam integer HP_NUM_SEQ     = 4                         // HP 固定 4 条序列
, localparam integer LP_SEQ_LEN_RST = ADC_NUM_CH                // LP_SEQ_LEN 复位值 = ADC_NUM_CH（存 count）
, localparam integer DATA_FIELD_W   = 16                        // DATA 寄存器域固定 16bit
