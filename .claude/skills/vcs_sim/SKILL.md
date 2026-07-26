---
name: vcs_sim
description: VCS+UVM 仿真流程（编译/sim-uvm-regr/FSDB 波形/Verdi 查看）——Linux 项目主力仿真器
triggers:
  - VCS仿真
  - UVM回归
  - sim-uvm-regr
  - FSDB波形
  - Verdi查看
  - VCS编译
  - 仿真流程
---

# VCS Sim — VCS+UVM 仿真流程

Linux 环境下用 VCS 编译 RTL + UVM testbench、跑回归、生成 FSDB 波形、用 Verdi
查看。这是 VCS+UVM 项目的主力仿真 skill。

> **定位**：项目主力仿真器。modelsim_sim / verilator_sim 为备选（Windows 环境
> 或无 VCS 时）。本 skill 假设项目 Makefile 已有 `sim`/`sim-uvm-regr`/
> `sim-uvm-run`/`verdi`/`wav` 等 target。

## 前置条件

- VCS 已安装（`which vcs`，确认版本，如 O-2018.09-SP2）
- Verdi 已安装（`which verdi`，用于波形查看）
- 项目 Makefile 已配置 VCS 编译 target（`make info` 可见工具版本）
- RTL filelist（`rtl/filelist.f`）+ UVM filelist（`tb/uvm/uvm.flist`）就绪

## 仿真流程

### Step 1: 编译检查（快速）

```bash
make lint    # iverilog 组编译语法检查（秒级）
make vcs     # VCS 编译 RTL（不含 TB）
```
两者都 PASS 才算语法检查通过（iverilog 和 VCS 严格度不同，互补）。详见 `/lint-manager`。

### Step 2: 单元测试（轻量预检）

```bash
make test-unit   # 跑 tb/unit/tb_*.v，iverilog 优先 VCS fallback
```
单元 TB 用于模块级快速验证，不依赖 UVM。

### Step 3: 全功能仿真（VCS + 波形 + log）

```bash
make sim         # VCS 编译 RTL + TB + 运行仿真 + 生成 FSDB 波形 + log
```
产物：`sim/simv`、`sim/waveform.fsdb`、`sim/log/sim_<timestamp>.log`。

### Step 4: UVM 回归（一次编译跑全部用例）

```bash
make sim-uvm-regr   # 编译一次 simv_uvm，跑所有 UVM test
```
产物：`sim/simv_uvm`、`sim/log/<test>.log`、`sim/waveforms/<test>.fsdb`。
- 一次编译 + 多次运行（run-many），效率高
- 多个 test 依次跑，每个独立 log + 波形

> **跑回归用 `run_in_background: true`**——主会话不阻塞，跑完自动唤醒。
> 醒后**只 grep 摘要**，绝不 Read 整篇 log（见下方"log 读取铁律"）。

### Step 5: 调试单个 UVM 用例

```bash
make sim-uvm-run TEST=<uvm_test_name>   # 调试单个 test（替换为实际 test 名）
```
用于定位某个 test 的失败原因，单独跑 + 单独波形。

> **根因 debug 留主会话 + 自动加载 `/deep-analysis` 顶 max**——不外包 subagent
> （verdi 波形无头看不了、丢主会话 spec/CDC/FSM 上下文、只回摘要看不见推理、
> 打断 run→fail→analyze→fix→rerun 紧耦合循环）。详见 CLAUDE.md「仿真回归 debug 模式」。

## log 读取铁律（防 token 失控）

仿真/编译/覆盖率 log 巨大（单次回归可达数 MB / 数万行），全篇 Read 会瞬间撑爆上下文。
**反例**：一次 cat 大 log / Read 不带 limit 的 .log，单次吃掉数万 token。

| 文件 | ❌ 禁止 | ✅ 必须 |
|:--|:--|:--|
| `sim/log/*.log`（UVM 仿真 log） | Read 整篇 / `cat` 全文 | `grep -E "UVM_ERROR\|UVM_FATAL\|FAIL\|--- UVM Report" log` 抽报告段 |
| `sim/build/*.log`（编译 log） | Read 整篇 | `grep -iE "error\|warning" compile.log`；或 `tail -n 50` 看结尾 |
| `sim/cov/` 覆盖率报告（urg HTML/XML） | Read HTML/XML 全文 | `scripts/cov_report.py` 文本摘要；或 grep 具体模块/行 |
| 确需看 log 中段特定行 | — | `grep -n` 定位行号 → Read 带 `offset`+`limit` 只读那一段 |

**总原则**：先 `grep`/`tail`/`wc -l` 量大小 → 只把关键摘要进上下文 → 需要上下文时用 Read 的 `offset`+`limit` 精读片段。禁止把任何 `sim/` 下产物整篇读入。

### Step 6: 覆盖率收集（签收前）

```bash
make sim-uvm-regr-cov   # 编译带覆盖率 + 跑回归收集覆盖率
make coverage           # 合并覆盖率数据 + 生成 urg report
```
覆盖率数据在 `sim/cov/`，urg report 在 `sim/cov/report/`。
覆盖率分析（定位未覆盖点、补 case）见 `/coverage-analyze`。

> **覆盖率报告读取同样遵守 log 读取铁律**——urg HTML/XML 不整篇 Read，
> 用 `scripts/cov_report.py` 拿文本摘要（已与 Verdi 对齐校准）。

## 波形查看

### Verdi 打开 RTL + 单元 TB
```bash
make verdi    # verdi -f filelist.f -top <tb_top>（单元 TB）
```

### Verdi 打开 UVM 工程
```bash
make wav                       # 列出可用 UVM 波形
make wav TEST=<uvm_test_name>  # 打开指定 UVM test 波形
```
UVM 波形用 `-uvm -sv -f uvm.flist -top tb_top -ssf <test>.fsdb`。

## 常用 VCS flags（项目 Makefile 已配，调试时参考）

| flag | 用途 |
|:--|:--|
| `-full64 -sverilog` | 64 位 + SystemVerilog |
| `-timescale=1ns/1ps` | 时间精度 |
| `-debug_access` | 调试访问（波形 dump） |
| `-ntb_opts uvm-1.2` | UVM 1.2 支持 |
| `-cm <line/branch/...>` | 覆盖率收集 |
| `-l <log>` | 编译 log 文件 |
| `+fsdb_file=<path>` | FSDB 波形输出路径 |
| `+UVM_TESTNAME=<test>` | 指定 UVM test |
| `+ntb_random_seed=<n>` | 随机种子 |

## VCS O-2018.09 已知限制（见 env_bug）

- nested generate scope 歧义 → 拍平 generate
- DT_NEEDED 缺失 → `-LDFLAGS "-Wl,--allow-shlib-undefined"`
- 运行时 symbol lookup → `LD_LIBRARY_PATH` + `LD_PRELOAD`
- 增量编译不一致 → 删 `simv_uvm.daidir` 重编译（见 uvm_debug #9）

## FSDB vs VPD

项目用 **FSDB**（Verdi 原生格式），TB 里用 `$fsdbDumpfile`/`$fsdbDumpvars`，
不是 VPD（`$vcdpluson`）。生成 TB 时注意波形 dump 风格与项目一致（见 `/tb-writer`）。

## 与其他 Skill 配合

```
rtl_generator → 生成 RTL
testcase_gen  → 生成 UVM test/sequence
      ↓
vcs_sim       → 编译 + 仿真 + 回归 + 波形
      ↓
coverage_analyze → 覆盖率分析 + 补 case（闭环）
lint-manager → 编译检查（lint + vcs）
```

> **与 modelsim_sim / verilator_sim 分工**：本 skill 是 Linux+VCS 主力；
> modelsim_sim 是 Windows/ModelSim 备选；verilator_sim 是 Windows/Verilator
> 备选（仅无 UVM 的 unit 仿真）。同一项目不要混用主力与备选。

## 何时调用

- CLAUDE.md Step 9c/9d（仿真执行）
- 提交前 `make check`（lint + vcs + test-unit + sim-uvm-regr）
- 调试单个用例
- 签收前覆盖率收集
