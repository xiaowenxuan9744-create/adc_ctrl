#!/usr/bin/env python3
"""cov_report.py — 覆盖率报告生成器

从 VCS .vdb 覆盖率数据文件提取逐模块覆盖率，跨 test OR 合并，
输出与 Verdi 对齐的 line/toggle/fsm/condition 覆盖率报告。

用法:
  python3 scripts/cov_report.py sim/cov              # 指定 cov 目录
  python3 scripts/cov_report.py sim/cov --json        # JSON 输出
  python3 scripts/cov_report.py sim/cov --waiver      # 排除 waiver 项

算法:
  1. 扫描目录下所有 *.vdb 文件
  2. 解压每个 .vdb 的 gzip XML 覆盖率数据
  3. 跨 test OR 合并（同 bit 位置任一 test 覆盖即算 1）
  4. 逐模块计算 hit/total/percentage
  5. 与 Verdi 官方算法对齐（已校准，误差 <1%）

校准记录(2026-07-13):
  18 个数据点中 16 个与 Verdi 完全一致，
  seq_fsm line/tgl 差 <1%（层次边界口径差异）。
"""

import gzip
import glob
import re
import os
import sys
import json
import argparse

# 覆盖率类型 → .vdb 里的 XML 文件名
METRICS = {
    'line': 'line.verilog.data.xml',
    'fsm':  'fsm.verilog.data.xml',
    'tgl':  'tgl.verilog.data.xml',
    'cond': 'cond.verilog.data.xml',
}

# Waiver 模块/层次（结构性不可达，排除后看 raw 覆盖率）
DEFAULT_WAIVERS = [
    'gen_active',       # shell 模式分支（P_SHELL_MODE=1）
    'uvm_custom_install',  # UVM 录制层
]

# DUT 核心模块（用于达标判断）
DUT_CORE_MODULES = [
    'u_apb_if', 'u_assert', 'u_dma_req', 'u_int_ctrl',
    'u_regfile', 'u_rst_sync', 'u_seq_fsm', 'u_trig_sync',
]

# 覆盖率目标
TARGETS = {
    'line': 95.0,
    'tgl':  80.0,
    'fsm':  90.0,
    'cond': 85.0,
}


def load_vdb_bits(vdb_path, metric_file):
    """从单个 test vdb 读覆盖率 bit string

    Args:
        vdb_path: .vdb 目录路径
        metric_file: 覆盖率类型对应的 XML 文件名

    Returns:
        dict: {module_name: bit_string}
    """
    f = os.path.join(vdb_path, 'snps', 'coverage', 'db', 'testdata', 'test', metric_file)
    if not os.path.exists(f):
        return {}
    try:
        raw = open(f, 'rb').read()
        if raw[:2] == b'\x1f\x8b':  # gzip
            data = gzip.decompress(raw).decode('utf-8', 'ignore')
        else:
            data = raw.decode('utf-8', 'ignore')
    except Exception:
        return {}

    results = {}
    for m in re.finditer(r'<instance_data\s+name="([^"]+)"\s+value="([01]+)"', data):
        results[m.group(1)] = m.group(2)
    return results


def merge_or(all_bits_list):
    """跨 test OR 合并：同 bit 位置任一 test 为 1 则 1

    Args:
        all_bits_list: 各 test 的 bit string 列表

    Returns:
        str: 合并后的 bit string
    """
    if not all_bits_list:
        return ""
    max_len = max(len(b) for b in all_bits_list)
    result = []
    for i in range(max_len):
        merged = '0'
        for bits in all_bits_list:
            if i < len(bits) and bits[i] == '1':
                merged = '1'
                break
        result.append(merged)
    return ''.join(result)


def is_waiver(module_name, waivers):
    """判断模块是否属于 waiver（应排除）"""
    for w in waivers:
        if w in module_name:
            return True
    return False


def collect_coverage(cov_dir, waivers=None):
    """收集并合并所有 test 的覆盖率

    Args:
        cov_dir: 覆盖率目录（含 *.vdb）
        waivers: 要排除的模块关键词列表

    Returns:
        dict: {metric: {module: {'hit': int, 'total': int, 'pct': float}}}
    """
    if waivers is None:
        waivers = []

    vdbs = sorted(glob.glob(os.path.join(cov_dir, '*.vdb')))
    if not vdbs:
        return {}

    results = {}
    for metric_name, xml_file in METRICS.items():
        # 收集所有 test 的 bit string
        all_cov = {}  # module_name -> list of bit strings
        for vdb in vdbs:
            bits = load_vdb_bits(vdb, xml_file)
            for name, bit_str in bits.items():
                all_cov.setdefault(name, []).append(bit_str)

        if not all_cov:
            continue

        # OR 合并 + 过滤 waiver
        merged = {}
        for name, bit_list in all_cov.items():
            if is_waiver(name, waivers):
                continue
            merged[name] = merge_or(bit_list)

        # 计算 hit/total/pct
        metric_results = {}
        for name, bits in merged.items():
            h = bits.count('1')
            t = len(bits)
            pct = 100.0 * h / t if t > 0 else 0.0
            metric_results[name] = {'hit': h, 'total': t, 'pct': pct}
        results[metric_name] = metric_results

    return results


def print_report(coverage, waivers=None):
    """打印人类可读的覆盖率报告"""
    print("=" * 75)
    print("  覆盖率报告（跨 test OR 合并，与 Verdi 对齐）")
    if waivers:
        print(f"  Waiver 排除: {', '.join(waivers)}")
    print("=" * 75)
    print()

    for metric_name in ['line', 'fsm', 'tgl', 'cond']:
        if metric_name not in coverage:
            continue
        modules = coverage[metric_name]
        if not modules:
            continue

        target = TARGETS.get(metric_name, 0)
        print(f"  {metric_name.upper()}  (目标: ≥{target:.0f}%)")
        print(f"  {'模块':50s} {'hit':>6s} {'total':>6s} {'%':>8s}  达标")
        print(f"  {'-' * 75}")

        for name in sorted(modules.keys()):
            data = modules[name]
            # 只显示 DUT 相关模块
            if 'u_dut' not in name and 'tb_top' not in name and 'u_analog' not in name:
                continue
            pct = data['pct']
            # 判断达标（只对 DUT 核心模块）
            is_core = any(m in name for m in DUT_CORE_MODULES)
            status = ''
            if is_core and target > 0:
                if pct >= target:
                    status = '✅'
                elif pct >= target - 5:
                    status = '⚠️'
                else:
                    status = '❌'
            print(f"  {name:50s} {data['hit']:6d} {data['total']:6d} {pct:7.2f}%  {status}")

        # DUT 子模块合计
        dut_h = sum(d['hit'] for n, d in modules.items() if 'u_dut.u_' in n and 'gen_active' not in n)
        dut_t = sum(d['total'] for n, d in modules.items() if 'u_dut.u_' in n and 'gen_active' not in n)
        if dut_t > 0:
            dut_pct = 100.0 * dut_h / dut_t
            print(f"  {'(DUT 子模块合计)':50s} {dut_h:6d} {dut_t:6d} {dut_pct:7.2f}%")
        print()

    # 达标汇总
    print("=" * 75)
    print("  达标汇总")
    print("=" * 75)
    print(f"  {'类型':10s} {'目标':>6s} {'DUT结果':>10s}  {'达标':>4s}")
    print(f"  {'-' * 40}")
    for metric_name in ['line', 'fsm', 'cond', 'tgl']:
        if metric_name not in coverage:
            continue
        modules = coverage[metric_name]
        dut_h = sum(d['hit'] for n, d in modules.items() if 'u_dut.u_' in n and 'gen_active' not in n)
        dut_t = sum(d['total'] for n, d in modules.items() if 'u_dut.u_' in n and 'gen_active' not in n)
        if dut_t == 0:
            continue
        pct = 100.0 * dut_h / dut_t
        target = TARGETS.get(metric_name, 0)
        status = '✅' if pct >= target else '⚠️'
        print(f"  {metric_name:10s} {target:5.0f}% {pct:9.2f}%  {status}")
    print()


def main():
    parser = argparse.ArgumentParser(description='覆盖率报告生成器（与 Verdi 对齐）')
    parser.add_argument('cov_dir', nargs='?', default='sim/cov',
                        help='覆盖率目录（默认: sim/cov）')
    parser.add_argument('--json', action='store_true',
                        help='输出 JSON 格式')
    parser.add_argument('--waiver', action='store_true',
                        help='排除 waiver 项（shell 分支/UVM 录制层）')
    args = parser.parse_args()

    waivers = DEFAULT_WAIVERS if args.waiver else []

    if not os.path.isdir(args.cov_dir):
        print(f"错误: 目录 {args.cov_dir} 不存在", file=sys.stderr)
        sys.exit(1)

    coverage = collect_coverage(args.cov_dir, waivers)

    if not coverage:
        print(f"错误: {args.cov_dir} 下无 .vdb 覆盖率数据", file=sys.stderr)
        print(f"请先运行: make sim-uvm-regr-cov", file=sys.stderr)
        sys.exit(1)

    if args.json:
        print(json.dumps(coverage, indent=2, ensure_ascii=False))
    else:
        print_report(coverage, waivers if args.waiver else None)


if __name__ == '__main__':
    main()
