#!/bin/bash
# lint.sh — 代码静态检查脚本
# 使用方式: ./scripts/lint.sh [--verilog|--python|--js]
# 支持 Verilog (iverilog)、Python、JavaScript 等

set -euo pipefail

MODE="${1:---auto}"

echo "=== Lint ==="

case "$MODE" in
  --verilog|--v)
    echo "Running Verilog lint..."
    IVERILOG=$(which iverilog 2>/dev/null || echo '')
    VERILATOR=$(which verilator 2>/dev/null || echo '')
    SRC_DIR="${SRC_DIR:-rtl}"

    if [ -n "$VERILATOR" ]; then
        find "$SRC_DIR" -name "*.v" -o -name "*.sv" 2>/dev/null | while read f; do
            echo "  $f"
            verilator --lint-only -Wall "$f" 2>&1
        done
    elif [ -n "$IVERILOG" ]; then
        find "$SRC_DIR" -name "*.v" -o -name "*.sv" 2>/dev/null | while read f; do
            echo "  $f"
            iverilog -t null -Wall "$f" 2>&1
        done
    else
        echo "  WARNING: No Verilog linter found (install iverilog or verilator)"
    fi
    ;;
  --python|--py)
    echo "Running Python lint..."
    if command -v ruff &> /dev/null; then
        ruff check rtl/ sim/
    elif command -v flake8 &> /dev/null; then
        flake8 rtl/ sim/
    elif command -v pylint &> /dev/null; then
        pylint rtl/
    else
        echo "  WARNING: No Python linter found"
    fi
    ;;
  --js|--javascript|--ts)
    echo "Running JS/TS lint..."
    if command -v eslint &> /dev/null; then
        eslint rtl/
    else
        echo "  WARNING: No JS linter found"
    fi
    ;;
  --auto|*)
    echo "Auto-detecting project type..."
    if ls rtl/*.v rtl/*.sv 2>/dev/null | head -1 > /dev/null 2>&1; then
        exec "$0" --verilog
    elif ls rtl/*.py 2>/dev/null | head -1 > /dev/null 2>&1; then
        exec "$0" --python
    elif ls rtl/*.js rtl/*.ts 2>/dev/null | head -1 > /dev/null 2>&1; then
        exec "$0" --js
    else
        echo "  No source files detected for linting."
    fi
    ;;
esac

echo ""
echo "Lint complete."
