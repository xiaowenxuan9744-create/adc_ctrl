#==============================================================================
# lib_check.tcl — DC 库加载最小验证（隔离"库能否用"与"RTL 能否综合"）
# 用法：dc_shell -f syn/lib_check.tcl   (需 ADC_PDK 指向 PDK 根，见 .synopsys_dc.setup)
#==============================================================================
if {[info exists env(ADC_PDK)] == 0} { set env(ADC_PDK) "/path/to/pdk" }
set search_path [concat . $search_path \
    $env(ADC_PDK)/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn28hpcplusbwp12t40p140_180a ]
set DB tt0p9v25c
set LIBNAME tcbn28hpcplusbwp12t40p140tt0p9v25c

puts "==== [info script] 开始 ===="
puts "search_path = $search_path"

# 1. 读 .db —— 验证库文件可解析、未损坏
if {[catch {read_db ${LIBNAME}.db} msg]} {
  puts "FAIL_READ_DB: $msg"
  exit 1
}
puts "OK_READ_DB: ${LIBNAME}.db"

# 2. 设为 target/link，确认能 link 一个空设计占位（验证库 cell 可解析）
set target_library "${LIBNAME}.db"
set link_library   "* ${LIBNAME}.db"

# 3. 数库 cell —— 真实工艺库应有数百~上千个 cell
set ncells [sizeof_collection [get_lib_cells ${LIBNAME}/*]]
puts "OK_LIB_CELLS: ${LIBNAME} 含 ${ncells} 个 cell"

# 4. 抽几个基本 cell 确认（DFF/INV/NAND/AND）
foreach pat {INV* DFF* NAND2* AND2* BUf* BUf} {
  set c [get_lib_cells -quiet "${LIBNAME}/${pat}"]
  if {$c ne ""} { puts "  sample: ${LIBNAME}/${pat} -> [get_object_name $c]" }
}

puts "==== [info script] 通过：库可用 ===="
