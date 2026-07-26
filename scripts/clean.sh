#!/bin/bash
# clean.sh — 清理构建产物
# 使用方式: ./scripts/clean.sh

set -euo pipefail

echo "=== Clean ==="

rm -rf sim/simv sim/simv.daidir sim/csrc
rm -f sim/*.key sim/*.log sim/*.vpd
rm -f sim/log/*.log
rm -rf __pycache__/ .pytest_cache/
rm -rf *.egg-info/
rm -f coverage/.coverage*
rm -rf htmlcov/

echo "Clean complete."
