# ModelSim TCL 脚本模板

AGDC 模块 ModelSim 仿真的 TCL 批处理脚本模板。

## 文件命名

`sim/unit/<module>/modelsim/sim.tcl`

## 完整模板

```tcl
#******************************************************************************
# File:       sim.tcl
# Description: ModelSim simulation script for <module>
# Usage:      vsim -c -do sim.tcl         (batch)
#             vsim -gui -do sim.tcl       (GUI, keep window open)
#******************************************************************************

#----------------------------------------------------------
# Paths — use absolute paths to avoid relative-path issues
#----------------------------------------------------------
set RTL_ROOT     ../../rtl
set MODULE       <module>

#----------------------------------------------------------
# Create library and compile
#----------------------------------------------------------
if {[file exists work]} {
    vdel -lib work -all
}
vlib work
vmap work work

# Compile RTL
vlog -work work +acc -sv ${RTL_ROOT}/${MODULE}.v

# Compile testbench
vlog -work work +acc -sv tb_${MODULE}.sv

#----------------------------------------------------------
# Load design
#----------------------------------------------------------
vsim -voptargs=+acc work.tb_${MODULE}

#----------------------------------------------------------
# Waveform signals
#----------------------------------------------------------
add wave -divider "Clock & Reset"
add wave -hex /tb_${MODULE}/clk
add wave -hex /tb_${MODULE}/rst_n

add wave -divider "DUT I/O"
add wave -hex /tb_${MODULE}/din
add wave -hex /tb_${MODULE}/dout
add wave -hex /tb_${MODULE}/dout_pulse

add wave -divider "DUT Internal"
add wave -hex /tb_${MODULE}/u_dut/*

add wave -divider "Test Stats"
add wave -hex /tb_${MODULE}/total_tests
add wave -hex /tb_${MODULE}/passed_tests

#----------------------------------------------------------
# Run
#----------------------------------------------------------
run -all

#----------------------------------------------------------
# Keep GUI open; quit when batch (-c mode)
#----------------------------------------------------------
if {[batch_mode] == 0} {
    # GUI mode: don't quit, let user interact
    puts "Simulation complete. Wave window is open for inspection."
} else {
    quit
}
```

## 关键配置说明

### 路径策略

**必须使用绝对路径**引用 RTL 文件。ModelSim 的 CWD 不一定等于 TCL 脚本所在目录（尤其是从 Makefile 调用时），相对路径易出 ENOENT 错误。

```tcl
# 正确：相对于项目根目录
set RTL_ROOT ../../rtl
vlog -work work +acc -sv ${RTL_ROOT}/${MODULE}.v

# 避免：相对路径（除非确认 CWD 正确）
# vlog -work work +acc -sv ../../../rtl/module.v
```

跨机器迁移时，可改为环境变量：

```tcl
set RTL_ROOT [file normalize $env(RTL_ROOT)]
```

### TCL 变量引用

TCL 中变量用 `${VAR}` 引用（与 Makefile `$(VAR)` 不同）。

### 波形组织

用 `add wave -divider "组名"` 将波形分区域显示：

```tcl
add wave -divider "Clock & Reset"
add wave -hex /tb_<module>/clk
add wave -hex /tb_<module>/rst_n
```

### 内部信号访问

`+acc` 编译选项允许访问 DUT 内部信号：

```tcl
add wave -hex /tb_<module>/u_dut/*     # 展开 DUT 所有内部信号
```

### 模式判定

```tcl
if {[batch_mode]} {
    quit          # -c 模式：仿真结束自动退出
} else {
    # -gui 模式：保持窗口打开供用户浏览波形
}
```

## Makefile 集成

```makefile
# ModelSim
MDL_DIR    ?= modelsim
MDL_WORK   ?= $(MDL_DIR)/work
VSIM       ?= vsim

modelsim:
	@echo "Running ModelSim (batch)..."
	cd $(MDL_DIR) && $(VSIM) -c -do sim.tcl

modelsim-gui:
	@echo "Running ModelSim (GUI)..."
	cd $(MDL_DIR) && $(VSIM) -gui -do sim.tcl &

clean-mdl:
	rm -rf $(MDL_WORK)
	rm -f $(MDL_DIR)/transcript $(MDL_DIR)/*.wlf
	rm -f $(MDL_DIR)/*.vcd
	@echo "ModelSim files cleaned."
```

## 常用 TCL 调试命令

| 命令 | 说明 |
|------|------|
| `restart -f` | 重新加载设计，时间归零 |
| `run 100us` | 运行指定时间 |
| `run -all` | 运行到 $finish |
| `add wave *` | 添加所有信号 |
| `force /signal 1` | 强制驱动信号 |
| `examine /signal` | 查看信号当前值 |
| `log -r /*` | 记录所有信号供事后查看 |
| `quit -sim` | 退出仿真（GUI 保持打开） |
