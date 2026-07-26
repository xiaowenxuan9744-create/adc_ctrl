//==============================================================================
// adc_params_check.vh — ADC 控制器参数化 elaboration 合法范围断言
//
// 在 module body 内（端口列表之后、内部逻辑之前）`include 本文件，引入
// initial 块做主参数范围断言。仿真 elaboration 阶段非法参数会 $error。
// 综合时 SYNTHESIS 宏定义下跳过（initial 不可综合且无意义）。
//==============================================================================
`ifndef ADC_PARAMS_CHECK_VH
`define ADC_PARAMS_CHECK_VH

`ifndef SYNTHESIS
initial begin
  if (ADC_NUM_CH < 4 || ADC_NUM_CH > 32)
    $error("ADC_NUM_CH=%0d out of range [4,32] (HP seq_ptr 需 2bit, N>=4 保证 W_CH_SEL>=W_HP_SEQ_PTR)", ADC_NUM_CH);
  if (ADC_DATA_W < 1 || ADC_DATA_W > 16)
    $error("ADC_DATA_W=%0d out of range [1,16] (DATA register field fixed 16-bit)", ADC_DATA_W);
end
`endif

`endif // ADC_PARAMS_CHECK_VH
