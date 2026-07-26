#!/bin/bash
# verdi_cov.sh — 一键加载 Verdi 覆盖率
# 主 database: sim/cov.vdb (VCS -cm_dir sim/cov 生成的合并库)
# test directories: sim/cov/ 下各 test 的 .vdb
# 用法: ./scripts/verdi_cov.sh

# 构建所有 test 的 vdb 路径列表
VDB_LIST=""
for vdb in sim/cov/*.vdb; do
    base=$(basename "$vdb" .vdb)
    # 跳过 merged 产物,只保留各 test 的 vdb
    if [[ "$base" == merged* ]]; then
        continue
    fi
    VDB_LIST="${VDB_LIST} ${vdb}"
done

echo "=== Verdi Coverage Loader ==="
echo "Main database: sim/cov.vdb"
echo "Test VDBs: $(echo $VDB_LIST | wc -w) files"
echo ""

verdi -cov -covdir sim/cov.vdb ${VDB_LIST} &

echo "Verdi launched (PID=$!)"
