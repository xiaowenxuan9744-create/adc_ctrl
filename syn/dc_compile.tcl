#==============================================================================
# dc_compile.tcl — ADC 控制器 Design Compiler 综合主脚本
# 工艺：TSMC 28HPC+  典型角 tt 0.9V 25°C
# 用法：dc_shell -f syn/dc_compile.tcl  | tee syn/log/dc_compile.log
#==============================================================================
set TOP    adc_top
set OUT    "syn/out"
set RPT    "syn/reports"
set DBNAME tcbn28hpcplusbwp12t40p140tt0p9v25c

file mkdir $OUT $RPT ./work

# --- 0. 库设置（保险重设，覆盖 .synopsys_dc.setup）---
# 库/项目路径用环境变量占位（未设时默认本机路径），clone 后按本机设：
#   export ADC_PDK=/path/to/tsmc28  export ADC_PROJ=/path/to/adc_new
if {[info exists env(ADC_PDK)] == 0}  { set env(ADC_PDK)  "/path/to/pdk" }
if {[info exists env(ADC_PROJ)] == 0} { set env(ADC_PROJ) "/path/to/adc_new" }
set LIBDIR $env(ADC_PDK)/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp12t40p140_180a
set search_path [concat . $search_path $LIBDIR $env(ADC_PROJ)/rtl ]
set target_library  "${DBNAME}.db"
set link_library    "* ${DBNAME}.db"
set symbol_library  ""

# --- 1. 读 RTL（SYNTHESIS 宏跳过 initial 参数检查块）---
define_design_lib WORK -path ./work

# SVF 记录 DC 优化（常数传播/状态合并），供 Formality 等价性验证消除假不等价。
# set_svf 是启用命令；svf_filename 非 app var，用 set_svf 而非 set_app_var。
set_svf "syn/out/adc_top.svf"

set RTL_FILES [list \
  rtl/adc_rst_sync.v  rtl/adc_sync_cell.v  rtl/adc_apb_if.v \
  rtl/adc_trig_sync.v rtl/adc_regfile.v    rtl/adc_seq_fsm.v \
  rtl/adc_int_ctrl.v  rtl/adc_dma_req.v    rtl/adc_top.v ]

if {[catch {analyze -format sverilog -define SYNTHESIS $RTL_FILES} msg]} {
  puts "FAIL_ANALYZE: $msg"; exit 1
}
puts "OK_ANALYZE"

# elaborate 顶层。用 RTL 默认参数（ADC_NUM_CH=26 / ADC_DATA_W=14 /
# ADC_SPT1_CH_MASK=32'h00600000，已在 module 声明中定义为 default）。
# 不加 -parameters：DC 会给设计名加参数后缀（adc_top_0_26_14_00600000），
# 导致后续 current_design adc_top 找不到；用默认值则设计名保持 adc_top。
if {[catch {elaborate $TOP} msg]} {
  puts "FAIL_ELABORATE: $msg"; exit 1
}
puts "OK_ELABORATE"

current_design $TOP
link
puts "OK_LINK"

# --- 2. 约束（统一 SDC：scripts/adc_constraints.sdc，DC/PT 通用）---
#    历史修订见 SDC 文件头注释。DC 衍生版 syn/dc_compile.sdc 已废弃合并。
#    SDC 末尾的 report_* 语句需 reports/ 目录存在；此处预先建。
file mkdir reports
source scripts/adc_constraints.sdc
# tt 典型角综合：SDC 不再硬编码 operating_conditions，此处显式设
set_operating_conditions -library tcbn28hpcplusbwp12t40p140tt0p9v25c tt0p9v25c
puts "OK_SDC"

# --- 3. 综合 ---
# --- 3. 综合 ---
compile_ultra -no_autoungroup
puts "OK_COMPILE"

# --- 4. 报告 ---
redirect "$RPT/timing.rpt" { report_timing -nworst 10 -max_paths 10 }
redirect "$RPT/area.rpt"   { report_area   -hierarchy -physical }
redirect "$RPT/power.rpt"  { report_power  -analysis_effort medium }
redirect "$RPT/qor.rpt"    { report_qor }
redirect "$RPT/cell.rpt"   { report_cell }
puts "OK_REPORT"

# --- 5. 输出网表 ---
change_names -hierarchy -rule verilog
write -format verilog -hierarchy -output "$OUT/${TOP}.syn.v"
write -format ddc     -hierarchy -output "$OUT/${TOP}.syn.ddc"
write_sdc "$OUT/${TOP}.syn.sdc"
puts "OK_WRITE"

# --- 摘要 ---
puts "==== SUMMARY ===="
puts "cell count   : [sizeof_collection [get_cells -hierarchical *]]"
puts "net count    : [sizeof_collection [get_nets -hierarchical *]]"
puts "WNS (setup)  : [get_attribute [get_timing_paths -max_paths 1] slack]"
puts "==== DONE ===="
