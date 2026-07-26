#!/bin/bash
# Verilator 编译脚本 for Linux
# 用法: build.sh <module_name> <verilog_file> [testbench_cpp]

set -e

MODULE=$1
VFILE=$2
TBFILE=$3

if [ -z "$MODULE" ] || [ -z "$VFILE" ]; then
    echo "用法: build.sh <module_name> <verilog_file> [testbench_cpp]"
    echo "示例: build.sh counter counter.v sim_main.cpp"
    exit 1
fi

echo "=== Verilator 编译脚本 ==="
echo "模块: $MODULE"
echo "Verilog: $VFILE"
[ -n "$TBFILE" ] && echo "Testbench: $TBFILE"

# 检查文件存在
if [ ! -f "$VFILE" ]; then
    echo "错误: Verilog 文件不存在: $VFILE"
    exit 1
fi

# 检查 Verilator
VERILATOR=$(which verilator 2>/dev/null || echo '')
if [ -z "$VERILATOR" ]; then
    echo "错误: Verilator 未安装。请先安装: sudo apt install verilator"
    exit 1
fi

# Step 1: Verilator 编译
echo ""
echo "[1/1] Verilator 编译..."

if [ -n "$TBFILE" ]; then
    if [ ! -f "$TBFILE" ]; then
        echo "错误: Testbench 文件不存在: $TBFILE"
        exit 1
    fi
    # 带 testbench 编译（--build 自动调用 g++ 链接）
    verilator --cc "$VFILE" --exe "$TBFILE" --trace -Wall --build
    echo ""
    echo "=== 编译完成 ==="
    echo "运行仿真: ./obj_dir/V$MODULE"
else
    # 仅 lint 检查
    verilator --lint-only -Wall "$VFILE"
    echo ""
    echo "=== Lint 完成 ==="
fi
