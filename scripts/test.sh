#!/bin/bash
# test.sh — RTL 测试运行脚本（VCS 主工具链）
# 使用方式: ./scripts/test.sh [--unit|--integration|--lint|--all]

set -euo pipefail

MODE="${1:---all}"
RTL_DIR="rtl"
BUILD_DIR="sim"
SIM_DIR="tb"
# TB 模型文件（模拟模型/总线模型等）——★ 按需修改：列出本项目 TB 依赖的模型文件
#   glob 自动发现 tb/unit/ 下的 *_model.v；若无模型文件留空
TB_MODELS="$(ls "$SIM_DIR"/unit/*_model.v 2>/dev/null || true)"
VCS="$(which vcs 2>/dev/null || echo '')"
IVERILOG="$(which iverilog 2>/dev/null || echo '')"
PASS=0
FAIL=0

mkdir -p "$BUILD_DIR"

echo "=== Test ($MODE) ==="

run_lint() {
    echo ""
    echo "--- RTL Lint Check ---"
    local result=0
    # 用 iverilog 做快速 lint（VCS 太重，不适合逐文件 lint）
    if [ -z "$IVERILOG" ]; then
        echo "  [SKIP] iverilog not installed"
        return
    fi
    # 全量编译检查（不生成可执行文件）
    echo "  Compiling: $RTL_DIR/*.v"
    if iverilog -t null -Wall -c "$RTL_DIR/filelist.f" -o /dev/null 2>&1; then
        echo "  [PASS] All modules compile cleanly"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] Compilation errors"
        FAIL=$((FAIL + 1))
        result=1
    fi
    # 独立模块 lint（跳过顶层和需要子模块的文件）
    echo "  --- Individual file lint ---"
    while IFS= read -r -d '' file; do
        local base=$(basename "$file")
        [ "$base" = "top.v" ] && continue
        if iverilog -t null -Wall "$file" -o /dev/null 2>/dev/null; then
            echo "  [PASS] $base"
            PASS=$((PASS + 1))
        else
            echo "  [FAIL] $base"
            FAIL=$((FAIL + 1))
            result=1
        fi
    done < <(find "$RTL_DIR" -type f \( -name '*.v' -o -name '*.sv' \) -print0 | sort -z)
    return $result
}

run_vcs_sim() {
    local tb="$1"
    local name="$(basename "$tb" .v)"
    local log="$BUILD_DIR/${name}.log"

    echo "  Running: $name"
    if [ -n "$VCS" ]; then
        # VCS 编译 + 运行
        vcs -full64 -sverilog \
            -f "$RTL_DIR/filelist.f" \
            "$tb" $TB_MODELS \
            -l "$BUILD_DIR/compile_${name}.log" \
            -o "$BUILD_DIR/$name" 2>&1 \
        && "$BUILD_DIR/$name" -l "$BUILD_DIR/log/${name}.log" 2>&1
    else
        # 备选：iverilog
        echo "  (VCS not found, using iverilog)"
        iverilog -c "$RTL_DIR/filelist.f" "$tb" \
            $TB_MODELS \
            -o "$BUILD_DIR/$name" 2>&1 \
        && "$BUILD_DIR/$name" > "$BUILD_DIR/log/${name}.log" 2>&1
    fi
}

run_unit() {
    echo ""
    echo "--- Unit Tests ---"
    local found=0
    for tb in "$SIM_DIR"/unit/tb_*.v; do
        [ -f "$tb" ] || continue
        found=1
        if run_vcs_sim "$tb"; then
            echo "  [PASS] $(basename "$tb" .v)"
            PASS=$((PASS + 1))
        else
            echo "  [FAIL] $(basename "$tb" .v)"
            FAIL=$((FAIL + 1))
        fi
    done
    if [ $found -eq 0 ]; then
        echo "  (no unit tests found in $SIM_DIR/unit/)"
    fi
}

run_integration() {
    echo ""
    echo "--- Integration Tests ---"
    local found=0
    for tb in "$SIM_DIR"/integration/tb_*.v; do
        [ -f "$tb" ] || continue
        found=1
        local name="$(basename "$tb" .v)"
        local log="$BUILD_DIR/${name}.log"

        echo "  Running: $name"
        if [ -n "$VCS" ]; then
            vcs -full64 -sverilog \
                -f "$RTL_DIR/filelist.f" \
                "$tb" $TB_MODELS \
                -l "$BUILD_DIR/compile_${name}.log" \
                -o "$BUILD_DIR/$name" 2>&1 \
            && "$BUILD_DIR/$name" -l "$BUILD_DIR/log/${name}.log" \
                +vpdfile+"$BUILD_DIR/waveform.vpd" 2>&1
        else
            iverilog -c "$RTL_DIR/filelist.f" "$tb" \
                $TB_MODELS \
                -o "$BUILD_DIR/$name" 2>&1 \
            && "$BUILD_DIR/$name" > "$BUILD_DIR/log/${name}.log" 2>&1
        fi

        if [ $? -eq 0 ]; then
            echo "  [PASS] $name"
            PASS=$((PASS + 1))
        else
            echo "  [FAIL] $name"
            FAIL=$((FAIL + 1))
        fi
    done
    if [ $found -eq 0 ]; then
        echo "  (no integration tests found in $SIM_DIR/integration/)"
    fi
}

case "$MODE" in
  --lint)
    run_lint
    ;;
  --unit)
    run_unit
    ;;
  --integration)
    run_integration
    ;;
  --all)
    run_lint
    run_unit
    run_integration
    ;;
  *)
    echo "Usage: $0 [--lint|--unit|--integration|--all]"
    exit 1
    ;;
esac

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
