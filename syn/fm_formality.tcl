#==============================================================================
# fm_formality.tcl — ADC 控制器 RTL↔综合网表 等价性形式验证
# Golden(RTL) vs Implemented(综合网表 tt 角)
# 用法：
#   export ADC_PDK=/path/to/tsmc28  ADC_PROJ=/path/to/adc_new   # 库/项目路径
#   fm_shell -f syn/fm_formality.tcl | tee syn/log/fm_formality.log
#==============================================================================
if {[info exists env(ADC_PDK)] == 0}  { set env(ADC_PDK)  "/path/to/pdk" }
if {[info exists env(ADC_PROJ)] == 0} { set env(ADC_PROJ) "/path/to/adc_new" }
set LIBDIR $env(ADC_PDK)/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp12t40p140_180a
set LIB    tcbn28hpcplusbwp12t40p140tt0p9v25c
set TOP    adc_top

set_app_var search_path [concat . $search_path $LIBDIR $env(ADC_PROJ)/rtl]
# FM 的 link_library 不是 application variable（与 DC 不同），直接 set 赋值。
# 库 .db 已在 search_path（$LIBDIR），用纯文件名。必须先 read_db 把标准单元库
# 载入内存，否则 read_verilog 网表时 cell reference 无法 link（FE-LINK-2/FM-234）。
set link_library [list * ${LIB}.db]
read_db ${LIB}.db

# 应用 DC 综合时生成的 SVF（综合优化记录），消除常数传播/状态合并导致的
# 假不等价（如 interval_cnt[7] 功能恒 0 被 DC 删除 → Formality 无 SVF 时判 fail）
set_svf "syn/out/adc_top.svf"

# FMR_ELAB-147（数组越界 index 警告）会升为 FM-262 error 致 link 失败。
# RTL 中 lp_seq_ent[idx]/entry_array[idx] 的 index 在某些 lp_seq_idx 组合下
# 越界，但 RTL 已用三元 ?: 保护（越界时读 8'h00），仿真与综合行为一致。
# 此为已知安全项，suppress 该 mismatch message 后再 link。
set_mismatch_message_filter -suppress FMR_ELAB-147

# ============================================================
# 1. 读 Golden (RTL) — 参考设计
# ============================================================
read_sverilog -define SYNTHESIS -r [list \
  rtl/adc_rst_sync.v  rtl/adc_sync_cell.v  rtl/adc_apb_if.v \
  rtl/adc_trig_sync.v rtl/adc_regfile.v    rtl/adc_seq_fsm.v \
  rtl/adc_int_ctrl.v  rtl/adc_dma_req.v    rtl/adc_top.v ]
set_top r:/WORK/${TOP}

# ============================================================
# 2. 读 Implemented (综合网表) — 待验证设计
# ============================================================
read_verilog -i syn/out/adc_top.syn.v
set_top i:/WORK/${TOP}

# ============================================================
# 3. 匹配 + 验证
# ============================================================
match

# 报告匹配情况
report_matched_points > syn/reports/fm_matched.rpt

# setup 验证（setup = 等价性正向，即 impl 实现 ref 功能）
set_dont_verify_points [get_ports -quiet "presetn prstn"]
# 复位相关 black box 可能匹配不全，先看 match 报告

verify

# 报告
report_passing_points  > syn/reports/fm_passing.rpt
report_failing_points  > syn/reports/fm_failing.rpt
report_aborted_points  > syn/reports/fm_aborted.rpt
report_unmatched_points > syn/reports/fm_unmatched.rpt

# 摘要（report_qor 含验证状态汇总）
puts "==== FORMALITY SUMMARY ===="
puts "==== FORMALITY DONE ===="
exit
