#!/bin/bash
# build.sh — RTL 项目构建脚本
# 使用方式: ./scripts/build.sh [options]
#   --rtl       编译 RTL（默认，使用 VCS）
#   --sim       编译 RTL + 仿真 testbench（使用 VCS）
#   --syn       启动综合
#   --clean     清理构建产物

set -euo pipefail

MODE="${1:---rtl}"
RTL_DIR="rtl"
BUILD_DIR="sim"
VCS="$(which vcs 2>/dev/null || echo '')"
IVERILOG="$(which iverilog 2>/dev/null || echo '')"

mkdir -p "$BUILD_DIR"

case "$MODE" in
  --rtl)
    echo "=== VCS Compile RTL ==="
    if [ -n "$VCS" ]; then
      vcs -full64 -sverilog \
          -f "$RTL_DIR/filelist.f" \
          -l "$BUILD_DIR/compile.log" \
          -o "$BUILD_DIR/simv" 2>&1
      echo "  -> $BUILD_DIR/simv"
    else
      echo "  VCS not found, falling back to iverilog..."
      iverilog -c "$RTL_DIR/filelist.f" -o "$BUILD_DIR/simv" 2>&1
    fi
    ;;

  --sim)
    echo "=== VCS Compile RTL + Testbench ==="
    if [ -n "$VCS" ]; then
      vcs -full64 -sverilog \
          -f "$RTL_DIR/filelist.f" \
          tb/*.v tb/integration/*.v \
          -l "$BUILD_DIR/compile.log" \
          -o "$BUILD_DIR/simv" 2>&1
      echo "  -> $BUILD_DIR/simv"
    else
      echo "  VCS not found, falling back to iverilog..."
      iverilog -c "$RTL_DIR/filelist.f" tb/*.v -o "$BUILD_DIR/simv" 2>&1
    fi
    ;;

  --syn)
    echo "Starting Design Compiler..."
    dc_shell -f scripts/syn.tcl | tee "$BUILD_DIR/dc.log"
    ;;

  --clean)
    echo "Cleaning build artifacts..."
    rm -rf "$BUILD_DIR"/*
    # VCS 还可能生成 csrc/ 和 simv.daidir/
    rm -rf csrc simv.daidir
    ;;

  *)
    echo "Usage: $0 [--rtl|--sim|--syn|--clean]"
    exit 1
    ;;
esac

echo "Build complete."
