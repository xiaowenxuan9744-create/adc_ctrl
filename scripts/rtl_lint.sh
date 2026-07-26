#!/bin/bash
# RTL Lint Check — Verilog/SystemVerilog 代码静态检查
# 用法: ./scripts/rtl_lint.sh [rtl_dir]
# 自动检测可用工具：verilator（优先）→ iverilog（备选）
# 支持文件：.v / .sv / .vh / .svh

set -e

# === 配置 ===
SRC_DIR="${1:-rtl}"
IVERILOG="$(which iverilog 2>/dev/null || echo '/usr/bin/iverilog')"
VERILATOR="$(which verilator 2>/dev/null || echo '')"

# === 颜色 ===
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================"
echo "  RTL Lint Check"
echo "  Source: $SRC_DIR"
echo "========================================"

# === 检测工具 ===
TOOL=""
if [ -n "$VERILATOR" ] && [ -x "$VERILATOR" ]; then
    TOOL="verilator"
    echo -e "${GREEN}Using: Verilator${NC}"
elif [ -n "$IVERILOG" ] && [ -x "$IVERILOG" ]; then
    TOOL="iverilog"
    echo -e "${GREEN}Using: Icarus Verilog${NC}"
else
    echo -e "${RED}Error: No lint tool found. Install with:${NC}"
    echo "  sudo apt install iverilog    # 轻量"
    echo "  sudo apt install verilator   # 推荐"
    exit 1
fi

TOTAL=0
PASSED=0
FAILED=0

# === 查找并检查 RTL 文件 ===
find "$SRC_DIR" -type f \( -name '*.v' -o -name '*.sv' -o -name '*.vh' -o -name '*.svh' \) | sort | while read -r file; do
    echo ""
    echo "  Checking: $file"
    echo "  ----------------------------------------"

    set +e
    if [ "$TOOL" = "verilator" ]; then
        # 收集 include 路径
        INC_DIRS=$(find "$SRC_DIR" -type d -name include 2>/dev/null | sed 's/^/+incdir+/' | tr '\n' ' ')
        $VERILATOR --lint-only -Wall $INC_DIRS -Wno-DECLFILENAME "$file" 2>&1
    else
        INC_DIRS=$(find "$SRC_DIR" -type d -name include 2>/dev/null | sed 's/^/-I/' | tr '\n' ' ')
        $IVERILOG -t null -Wall $INC_DIRS -o /dev/null "$file" 2>&1
    fi
    RC=$?
    set -e

    if [ $RC -eq 0 ]; then
        echo -e "  ${GREEN}[PASS]${NC}"
        PASSED=$((PASSED + 1))
    else
        echo -e "  ${RED}[FAIL]${NC}"
        FAILED=$((FAILED + 1))
    fi
    TOTAL=$((TOTAL + 1))
done

# === 汇总 ===
echo ""
echo "========================================"
echo "  Summary"
echo "========================================"
echo "  Total: $TOTAL"
echo -e "  Passed: ${GREEN}$PASSED${NC}"
echo -e "  Failed: ${RED}$FAILED${NC}"
echo ""

if [ "$FAILED" -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    exit 0
else
    echo -e "${RED}Some checks failed.${NC}"
    exit 1
fi
