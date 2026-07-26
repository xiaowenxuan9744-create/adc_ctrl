#==============================================================================
# pt_sta.tcl — ADC 控制器 PrimeTime STA（tt + ssg 双角）
# 用法：
#   export SYNOPSYS_LC_ROOT=/opt/synopsys/lc_2018.06/O-2018.06-SP1  # 修 PT-063
#   export ADC_PDK=/path/to/tsmc28  ADC_PROJ=/path/to/adc_new       # 库/项目路径
#   pt_shell -f syn/pt_sta.tcl [CORNER=tt|ssg] | tee syn/log/pt_sta_<corner>.log
#==============================================================================
if {[info exists env(ADC_PDK)] == 0}  { set env(ADC_PDK)  "/path/to/pdk" }
if {[info exists env(ADC_PROJ)] == 0} { set env(ADC_PROJ) "/path/to/adc_new" }
set LIBDIR $env(ADC_PDK)/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp12t40p140_180a

# CORNER 由环境变量传入（pt_shell 不接受 VAR=value 位置参数，CMD-012）。
# make gate-sdf 用 `CORNER=tt pt_shell -f ...` 注入；直接跑默认 tt。
if {[info exists env(CORNER)] == 0}  { set CORNER tt } else { set CORNER $env(CORNER) }

if {$CORNER eq "tt"} {
    set LIB    tcbn28hpcplusbwp12t40p140tt0p9v25c
    set OPCOND tt0p9v25c
    set NET    syn/out/adc_top.syn.v
} else {
    set LIB    tcbn28hpcplusbwp12t40p140ssg0p9v0c
    set OPCOND ssg0p9v0c
    set NET    syn/out/adc_top.ssg.syn.v
}
puts "==== PT STA CORNER=$CORNER LIB=$LIB ===="

set search_path [concat . $search_path $LIBDIR $env(ADC_PROJ)/rtl]
set link_path "* ${LIB}.db"

# --- 1. 读网表 ---
read_verilog $NET
current_design adc_top
link

# --- 2. 约束（统一 SDC）---
#    SDC 含 driving_cell/load + report_*（report_* 由 sdc_report 变量门控）
set_operating_conditions -library $LIB $OPCOND
set sdc_report 0   ;# PT 无 report_area/report_power，跳过 SDC 内 report
source scripts/adc_constraints.sdc

# --- 3. STA ---
update_timing
# -nworst/-max_paths 同义；PT 用 -max_paths。默认 report_timing 不含违例过滤，
# 这里按 slack 升序列前 20 条（含正 slack，便于看最紧路径）
redirect syn/reports/pt_${CORNER}_timing.rpt { report_timing -max_paths 20 -sort_by slack -nosplit }
redirect syn/reports/pt_${CORNER}_qor.rpt    { report_qor -summary }

# --- 3a. 导出 SDF（供后仿反标） ---
#   - significant_digits=3：延迟精度到 ps 级（与 1ns/1ps timescale 匹配）
#   - -version 3.0：PT O-2018 支持的最高 SDF 版本（3.1 不支持, CMD-031）
#   - -include SETUPHOLD,RECREM：含 setup/hold 与 recovery/removal 时序检查
#     （后仿违例报告所需；PT 合法值为 SETUPHOLD/RECREM/edge_specific_preset_clear）
#   写到 syn/out/adc_top.<corner>.sdf，Makefile gate-sim-sdf 按 CORNER 选取
if {[catch {
    write_sdf -version 3.0 \
              -significant_digits 3 \
              -include {SETUPHOLD RECREM} \
              syn/out/adc_top.${CORNER}.sdf
} msg]} {
    puts "WARN_WRITE_SDF: $msg"
} else {
    puts "OK_WRITE_SDF: syn/out/adc_top.${CORNER}.sdf"
}

# --- 摘要 ---
puts "==== $CORNER SUMMARY ===="
set p [get_timing_paths -max_paths 1]
puts "WNS(setup) : [get_attribute $p slack]"
set ph [get_timing_paths -delay min -max_paths 1]
puts "WNS(hold)  : [get_attribute $ph slack]"
puts "==== $CORNER DONE ===="
exit
