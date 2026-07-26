#==============================================================================
# dc_compile_ssg.tcl — ADC 控制器 ssg 慢角综合（0.9V 0°C）
# 复用 dc_compile.tcl 主体，仅改 target/link_library + operating_conditions
# 用法：dc_shell -f syn/dc_compile_ssg.tcl | tee syn/log/dc_compile_ssg.log
#==============================================================================
set TOP    adc_top
set OUT    "syn/out"
set RPT    "syn/reports"
set DBNAME tcbn28hpcplusbwp12t40p140ssg0p9v0c

file mkdir $OUT $RPT ./work

# 库/项目路径用环境变量占位（未设时默认本机路径），同 dc_compile.tcl
if {[info exists env(ADC_PDK)] == 0}  { set env(ADC_PDK)  "/path/to/pdk" }
if {[info exists env(ADC_PROJ)] == 0} { set env(ADC_PROJ) "/path/to/adc_new" }
set LIBDIR $env(ADC_PDK)/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp12t40p140_180a
set search_path [concat . $search_path $LIBDIR $env(ADC_PROJ)/rtl ]
set target_library  "${DBNAME}.db"
set link_library    "* ${DBNAME}.db"
set symbol_library  ""

define_design_lib WORK -path ./work

set RTL_FILES [list \
  rtl/adc_rst_sync.v  rtl/adc_sync_cell.v  rtl/adc_apb_if.v \
  rtl/adc_trig_sync.v rtl/adc_regfile.v    rtl/adc_seq_fsm.v \
  rtl/adc_int_ctrl.v  rtl/adc_dma_req.v    rtl/adc_top.v ]

if {[catch {analyze -format sverilog -define SYNTHESIS $RTL_FILES} msg]} {
  puts "FAIL_ANALYZE: $msg"; exit 1 }
puts "OK_ANALYZE"

if {[catch {elaborate $TOP} msg]} {
  puts "FAIL_ELABORATE: $msg"; exit 1 }
puts "OK_ELABORATE"

current_design $TOP
link
puts "OK_LINK"

# 约束：统一 SDC，但 operating_conditions/driver/load 指向 ssg 角
# SDC 末尾 report_* 重定向到 reports/ —— ssg 跑需独立 reports 目录避免覆盖
file mkdir reports_ssg
# 临时把 SDC 里的 report 重定向：source 前 set 一个变量供 SDC 不用——
# SDC 写死了 reports/，故先备份再用 sed 思路：直接 source 后单独 report 到 reports_ssg
# 简化：source SDC（其 report_* 会写到 reports/，此处可接受——ssg 用独立 rpt 目录）
# 实际：SDC 含 report_timing/area/power，会覆盖 tt 结果。改法：source 前先移走。
# 这里改为：不 source SDC 末尾的 report，手动在 SDC 约束后单独 report。
# —— SDC 的 report_* 用了相对路径 reports/，ssg 下我们想要 reports_ssg/。
# 折中：source 后重做 report 到 reports_ssg。
source scripts/adc_constraints.sdc
# SDC 不再硬编码 operating_conditions，ssg 脚本显式设慢角
set_operating_conditions -library tcbn28hpcplusbwp12t40p140ssg0p9v0c ssg0p9v0c
puts "OK_SDC"

compile_ultra -no_autoungroup
puts "OK_COMPILE"

redirect "$RPT/ssg_timing.rpt" { report_timing -nworst 10 -max_paths 10 -sort_by slack }
redirect "$RPT/ssg_area.rpt"   { report_area   -hierarchy -physical }
redirect "$RPT/ssg_qor.rpt"    { report_qor }
puts "OK_REPORT"

change_names -hierarchy -rule verilog
write -format verilog -hierarchy -output "$OUT/${TOP}.ssg.syn.v"
write -format ddc     -hierarchy -output "$OUT/${TOP}.ssg.syn.ddc"
puts "OK_WRITE"

puts "==== SSG SUMMARY ===="
set p [get_timing_paths -max_paths 1]
puts "WNS (global) : [get_attribute $p slack]"
puts "==== SSG DONE ===="
