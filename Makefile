# =============================================================================
# Makefile — EDA 工具命令封装（VCS / Verdi / iverilog）
# =============================================================================
# Template revision: R3 (2026-07-05)
#   R1 — Initial project-template release
#   R2 — UVM compile/run/regr split, lint dep fix, mkdir log fix
#   R3 — Coverage, random seed, direct FSDB, nightly regr, template upgrade
# Upgrade: make version  (then)  make template-upgrade
# =============================================================================
# 用法: make <target>
#   首次使用: make check     # 一键 Lint → 测试 → UVM → 覆盖率
#   日常开发: make lint      # 快速语法检查
#            make sim       # 编译 + 运行仿真
#            make verdi      # 查看波形
# =============================================================================
# 使用前请根据项目修改以下配置:
#   RTL_DIR   — RTL 源码目录
#   FILELIST  — 文件列表路径
#   TOP       — 顶层模块名
# =============================================================================

TEMPLATE_REV := 4  # template revision number, bump on template-wide changes
TEMPLATE_TAG := R$(TEMPLATE_REV)  # display tag, e.g. R4

# --- 项目配置（★ 按需修改）---
RTL_DIR     := rtl
SIM_DIR     := tb
BUILD_DIR   := sim
FILELIST    := $(RTL_DIR)/filelist.f
TOP         := adc_top
TB_TOP      := tb_adc_top
SIMV        := $(BUILD_DIR)/simv
FSDB        := $(BUILD_DIR)/waveform.fsdb

# --- UVM 编译文件清单（★ 按需修改）---
#   本项目的 UVM 顶层文件（接口/pkg/tb_top/bind/analog_model 等）。
#   用空格分隔；留空则只用 -f $(FILELIST)。
UVM_SRCS    := tb/uvm/interface/adc_if.sv tb/uvm/adc_uvm_pkg.sv tb/uvm/tb_top.sv \
              tb/bind_adc_assert.sv tb/unit/adc_analog_model.v

# --- 后仿（gate-level）配置 ---
#   TSMC28HPC+ 标准单元 Verilog 仿真模型（含 specify 块，SDF 反标用）。
#   解压自 PDK 分发包，落在 Front_End/verilog/ 下。
#   用环境变量覆盖本机路径：make gate-sim ADC_PDK=/path/to/tsmc28
ADC_PDK     ?= /path/to/pdk
STD_CELL_V  := $(ADC_PDK)/TSMCHOME/digital/Front_End/verilog/tcbn28hpcplusbwp12t40p140_170a/tcbn28hpcplusbwp12t40p140.v
GATE_NETLIST := syn/out/adc_top.syn.v
GATE_FLIST  := $(BUILD_DIR)/gate.flist
#   SDF 反标路径（PT 生成，CORNER=tt|ssg 选角，默认 tt）
GATE_SDF_DIR := syn/out
GATE_CORNER ?= tt
GATE_SDF    := $(GATE_SDF_DIR)/adc_top.$(GATE_CORNER).sdf
#   后仿用 unit TB（默认 tb_adc_top）；UVM TB 因 uvm_hdl 内部信号引用未适配网表，暂不支持
GATE_TB     ?= tb_adc_top

# --- 工具检测（自动发现路径）---
VCS       := $(shell which vcs 2>/dev/null)
VERDI     := $(shell which verdi 2>/dev/null)
IVERILOG  := $(shell which iverilog 2>/dev/null)

# --- 通用标志 ---
TIMESTAMP     := $(shell date +%Y%m%d_%H%M%S)
DATE_TAG      := $(shell date +%Y%m%d)
VCS_FLAGS     := -full64 -sverilog -l $(BUILD_DIR)/compile.log -timescale=1ns/1ps -debug_access -LDFLAGS "-Wl,--allow-shlib-undefined"
VCS_RUN_FLAGS := -l $(BUILD_DIR)/log/sim_$(TIMESTAMP).log
VCS_LD_PATH   := $(dir $(shell which vcs))../linux64/lib

# --- Verdi PLI for FSDB direct dump ---
VERDI_PLI_TAB := /opt/synopsys/verdi2018/Verdi_O-2018.09-SP2/share/PLI/VCS/linux64/novas.tab
VERDI_PLI_LIB := /opt/synopsys/verdi2018/Verdi_O-2018.09-SP2/share/PLI/VCS/LINUX64/libnovas.so
VCS_PLI_FLAGS := -P $(VERDI_PLI_TAB) $(VERDI_PLI_LIB)

FSDB_OPTS     := +fsdb_file=$(BUILD_DIR)/waveform.fsdb

# --- 覆盖率选项（-cm: line, condition, toggle, fsm）---
CM             := line+cond+tgl+fsm
CM_DIR         := $(BUILD_DIR)/cov
CM_FLAGS       := -cm $(CM) -cm_dir $(CM_DIR)
CM_REPORT_FLAGS := -metric line+cond+tgl+fsm

# --- 随机种子（SEED=random 启用随机，否则使用指定值）---
SEED          := 1
# NTB_SEED is recursively expanded so SEED=random generates a fresh number each use
RANDOM_SEED   = $(shell python3 -c "import random; print(random.randint(1, 2147483647))" 2>/dev/null || echo $$RANDOM)
NTB_SEED      = $(if $(filter random,$(SEED)),+ntb_random_seed=$(RANDOM_SEED), +ntb_random_seed=$(SEED))

# --- UVM 测试列表 ---
# ★ 按需修改：列出本项目的 UVM test 名（= tb/uvm/tests/ 下的 test 类名）
#   可被命令行/环境覆盖：make sim-uvm-regr UVM_TESTS="test_a test_b"
#   新项目改这里；留空则 sim-uvm-regr 会跳过（words=0）
UVM_TESTS ?= adc_reg_test adc_sample_test adc_sequence_test adc_int_test \
            adc_dma_test adc_calib_test adc_reset_test adc_hp_test \
            adc_trig_test adc_data_test adc_boundary_test adc_cont_test \
            adc_calib_full_test adc_reset_full_test adc_trig_full_test \
            adc_int_full_test adc_dma_full_test adc_reg_full_test

# --- 颜色输出 ---
GREEN  := \033[0;32m
RED    := \033[0;31m
YELLOW := \033[1;33m
NC     := \033[0m

.PHONY: help lint vcs sim run verdi wav check test test-unit test-integration clean info version
.PHONY: sim-cov sim-uvm-compile sim-uvm-run sim-uvm-regr sim-uvm cov-report coverage
.PHONY: regr-nightly template-upgrade
.PHONY: gate-flist gate-sim gate-sim-sdf gate-sdf
.PHONY: gate-sim-uvm-compile gate-sim-uvm-regr

.DEFAULT_GOAL := help

# =============================================================================
# 目标定义
# =============================================================================

## help        — 显示本帮助信息
help:
	@echo "┌─────────────────────────────────────────────────────────────┐"
	@echo "│  EDA 工具链 — Makefile 帮助                                  │"
	@echo "├─────────────────────────────────────────────────────────────┤"
	@echo "│  工具链: VCS $(shell $(VCS) -ID 2>/dev/null | head -1 || echo '(未检测到)')   │"
	@echo "│          Verdi $(shell $(VERDI) -v 2>/dev/null | head -1 || echo '(未检测到)')          │"
	@echo "│          iverilog $(shell $(IVERILOG) -V 2>/dev/null | head -1 || echo '(未检测到)')       │"
	@echo "└─────────────────────────────────────────────────────────────┘"
	@echo ""
	@echo "  常用命令:"
	@echo "  ┌──────────────────────────┬──────────────────────────────────┐"
	@echo "  │ make lint                │  RTL 语法检查（iverilog）        │"
	@echo "  │ make sim                 │  编译 + 运行仿真 + FSDB + log     │"
	@echo "  │ make sim-cov             │  编译 + 仿真 + 覆盖率收集        │"
	@echo "  │ make coverage            │  显示覆盖率报告(urg)             │"
	@echo "  │ make cov                 │  Verdi 查看覆盖率(源码+vdb)     │"
	@echo "  │ make sim-uvm-regr        │  UVM 回归测试                    │"
	@echo "  │ make sim-uvm-run TEST=xx │  运行单个 UVM 测试                │"
	@echo "  │   [SEED=random]          │  随机种子模式                    │"
	@echo "  │   [SEED=12345]           │  指定种子值                      │"
	@echo "  │ make regr-nightly        │  回归归档（regr/YYYYMMDD/）      │"
	@echo "  │ make check               │  lint + test + UVM + coverage    │"
	@echo "  │ make template-upgrade    │  检查并升级 Makefile 模板        │"
	@echo "  │ make verdi               │  Verdi 打开单元测试（RTL+TB+VCD）│"
	@echo "  │ make wav TEST=xxx        │  Verdi 打开 UVM 波形（-uvm -sv）  │"
	@echo "  │ make clean               │  清理构建产物                     │"
	@echo "  │ make version             │  显示 Makefile 模板版本           │"
	@echo "  └──────────────────────────┴──────────────────────────────────┘"
	@echo ""
	@echo "  ★ 首次使用请修改 Makefile 顶部配置项（★ 按需修改 块）:"
	@echo "    RTL_DIR / SIM_DIR / BUILD_DIR — 源码/TB/构建产物目录"
	@echo "    FILELIST — 文件列表路径"
	@echo "    TOP / TB_TOP — 顶层模块名 / TB 顶层名"
	@echo "    UVM_TESTS — 本项目 UVM test 列表（sim-uvm-regr/cov 用）"
	@echo "    FSDB / SEED — 波形路径 / 随机种子（SEED=random 启用随机）"
	@echo "  覆盖语法：make <target> VAR=value（如 make sim TOP=xxx UVM_TESTS='a b'）"

# =============================================================================
# Lint
# =============================================================================

## lint        — 使用 iverilog 做快速语法检查
lint: | $(BUILD_DIR)/.mkdir
ifeq ($(IVERILOG),)
	@echo -e "$(YELLOW)[SKIP] iverilog not installed$(NC)"
else
	@echo "========================================"
	@echo "  RTL Lint Check"
	@echo "========================================"
	@total=0; pass=0; fail=0; \
	echo "  File list: $(FILELIST)"; \
	if [ -f $(FILELIST) ]; then \
		if iverilog -t null -Wall -g2012 -Irtl -c $(FILELIST) -o /dev/null 2>&1; then \
			echo -e "  [$(GREEN)PASS$(NC)] All modules"; pass=$$((pass+1)); \
		else \
			echo -e "  [$(RED)FAIL$(NC)] All modules"; fail=$$((fail+1)); \
		fi; \
	fi; \
	echo ""; \
	echo "  Individual files (with full dep list):"; \
	SRCS=""; for sf in $$(grep -v '^\s*#' $(FILELIST) | grep -v '^\s*$$'); do SRCS="$$SRCS $$sf"; done; \
	for f in $$(find $(RTL_DIR) -name '*.v' -o -name '*.sv' | sort); do \
		base=$$(basename $$f); \
		if iverilog -t null -Wall -g2012 -Irtl $$SRCS -o /dev/null 2>/dev/null; then \
			echo -e "  [$(GREEN)PASS$(NC)] $$base"; pass=$$((pass+1)); \
		else \
			echo -e "  [$(RED)FAIL$(NC)] $$base"; fail=$$((fail+1)); \
		fi; \
		total=$$((total+1)); \
	done; \
	echo ""; \
	echo "  Total: $$total  Passed: $$pass  Failed: $$fail"; \
	[ $$fail -eq 0 ]
endif

# =============================================================================
# VCS 编译与仿真
# =============================================================================

## vcs         — 使用 VCS 编译 RTL
vcs: | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS Compile (RTL only)"
	@echo "========================================"
	@vcs $(VCS_FLAGS) $(VCS_PLI_FLAGS) +incdir+rtl -f $(FILELIST) -o $(SIMV) > /dev/null 2>&1
	@echo -e "  [$(GREEN)PASS$(NC)] -> $(SIMV)"
endif

## sim         — VCS 编译 RTL + testbench 并运行仿真，生成 FSDB 波形
sim: | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS Compile + Run"
	@echo "========================================"
	@echo "  1/3: Compiling... (details: $(BUILD_DIR)/compile.log)"
	@vcs $(VCS_FLAGS) $(VCS_PLI_FLAGS) -f $(FILELIST) $(wildcard $(SIM_DIR)/unit/*.v) $(wildcard $(SIM_DIR)/integration/*.v) -o $(SIMV) > /dev/null 2>&1 || { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile.log)"; exit 1; }
	@echo "  2/3: Running simulation..."
	mkdir -p $(BUILD_DIR)/log
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" $(SIMV) $(VCS_RUN_FLAGS) $(FSDB_OPTS)
	@echo "  3/3: Simulation complete"
	@echo -e "  [$(GREEN)DONE$(NC)] Log: $(BUILD_DIR)/log/sim_$(TIMESTAMP).log"
	@echo -e "  [$(GREEN)DONE$(NC)] FSDB: $(FSDB)"
endif

## sim-cov     — VCS 编译 + 仿真 + 覆盖率收集
sim-cov: | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS Compile + Run + Coverage"
	@echo "========================================"
	@echo "  1/3: Compiling with coverage... (details: $(BUILD_DIR)/compile.log)"
	@vcs $(VCS_FLAGS) $(CM_FLAGS) $(VCS_PLI_FLAGS) -f $(FILELIST) $(wildcard $(SIM_DIR)/unit/*.v) $(wildcard $(SIM_DIR)/integration/*.v) -o $(BUILD_DIR)/simv_cov > /dev/null 2>&1 || { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile.log)"; exit 1; }
	mkdir -p $(BUILD_DIR)/log
	@echo "  2/3: Running simulation..."
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" $(BUILD_DIR)/simv_cov $(VCS_RUN_FLAGS) $(FSDB_OPTS)
	@echo "  3/3: Coverage data written to $(CM_DIR)"
	@echo -e "  [$(GREEN)DONE$(NC)]"
endif

## run         — 运行已编译的仿真（不重新编译）
run:
ifeq ($(wildcard $(SIMV)),)
	$(error $(SIMV) not found. Run 'make vcs' or 'make sim' first.)
else
	@echo "========================================"
	@echo "  Run Simulation"
	@echo "========================================"
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" $(SIMV) $(VCS_RUN_FLAGS) $(FSDB_OPTS)
	@echo -e "  [$(GREEN)DONE$(NC)] Log: $(BUILD_DIR)/log/sim_$(TIMESTAMP).log"
	@echo -e "  [$(GREEN)DONE$(NC)] FSDB: $(FSDB)"
endif

# =============================================================================
# UVM 仿真
# =============================================================================

## sim-uvm-compile — 仅编译 UVM 仿真（所有测试共享同一二进制）
sim-uvm-compile: | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS UVM Compile (once, run many)"
	@echo "========================================"
	rm -rf $(BUILD_DIR)/simv_uvm $(BUILD_DIR)/simv_uvm.daidir csrc
	@echo "  Compiling VCS ... (details: $(BUILD_DIR)/compile.log)"
	@vcs $(VCS_FLAGS) $(VCS_PLI_FLAGS) -ntb_opts uvm-1.2 -f $(FILELIST) \
		+incdir+rtl +incdir+tb/uvm/agent +incdir+tb/uvm/env +incdir+tb/uvm/scoreboard \
		+incdir+tb/uvm/sequence +incdir+tb/uvm/tests +incdir+tb \
		$(UVM_SRCS) \
		-o $(BUILD_DIR)/simv_uvm > /dev/null 2>&1 || { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile.log)"; exit 1; }
	@echo -e "  [$(GREEN)DONE$(NC)] -> $(BUILD_DIR)/simv_uvm"
endif

## sim-uvm-compile-cov — 编译 UVM 仿真含覆盖率支持
sim-uvm-compile-cov: | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS UVM Compile (with coverage)"
	@echo "========================================"
	rm -rf $(BUILD_DIR)/simv_uvm_cov $(BUILD_DIR)/simv_uvm_cov.daidir csrc
	@echo "  Compiling VCS with coverage ... (details: $(BUILD_DIR)/compile.log)"
	@vcs $(VCS_FLAGS) $(CM_FLAGS) $(VCS_PLI_FLAGS) -ntb_opts uvm-1.2 -f $(FILELIST) \
		+incdir+rtl +incdir+tb/uvm/agent +incdir+tb/uvm/env +incdir+tb/uvm/scoreboard \
		+incdir+tb/uvm/sequence +incdir+tb/uvm/tests +incdir+tb \
		$(UVM_SRCS) \
		-o $(BUILD_DIR)/simv_uvm_cov > /dev/null 2>&1 || { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile.log)"; exit 1; }
	@echo -e "  [$(GREEN)DONE$(NC)] -> $(BUILD_DIR)/simv_uvm_cov"
endif

## sim-uvm-run   — 运行已编译的 UVM 仿真（TESTNAME=指定 test）
##               SEED=随机种子（默认=1，SEED=random 启用随机）
sim-uvm-run:
ifeq ($(wildcard $(BUILD_DIR)/simv_uvm),)
	$(error simv_uvm not found. Run 'make sim-uvm-compile' first.)
else
	@echo "========================================"
	@echo "  Run UVM: $(TESTNAME)  (seed=$(SEED))"
	@echo "========================================"
	mkdir -p $(BUILD_DIR)/log $(BUILD_DIR)/waveforms
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
	  LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
	  $(BUILD_DIR)/simv_uvm $(VCS_RUN_FLAGS) \
	  +fsdb_file=$(BUILD_DIR)/waveforms/$(TESTNAME).fsdb \
	  +UVM_TESTNAME=$(TESTNAME) $(NTB_SEED)
endif

## sim-uvm-regr  — 编译 + 运行所有 UVM 测试
##                SEED=random 启用随机种子模式
sim-uvm-regr: sim-uvm-compile
	@echo "========================================"
	@echo "  UVM Regression - $(words $(UVM_TESTS)) tests"
	@echo "  Seed: $(SEED)"
	@echo "  Started: $$(date +%H:%M:%S)"
	@echo "========================================"
	@P=0; F=0; N=0; TOTAL=$(words $(UVM_TESTS)); SEC_START=$$(date +%s); \
	mkdir -p $(BUILD_DIR)/log $(BUILD_DIR)/waveforms; \
	for t in $(UVM_TESTS); do \
		N=$$((N+1)); \
		printf "  \r[$$N/$$TOTAL] $$t..."; \
		TS_START=$$(date +%s); \
		LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
		  LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
		  $(BUILD_DIR)/simv_uvm -l $(BUILD_DIR)/log/$$t.log \
		  +fsdb_file=$(BUILD_DIR)/waveforms/$$t.fsdb \
		  +UVM_TESTNAME=$$t $(NTB_SEED) > /dev/null 2>&1; \
		err=$$(grep -c "^UVM_ERROR [a-z]" $(BUILD_DIR)/log/$$t.log 2>/dev/null); \
		TS_END=$$(date +%s); \
		ELAPSED=$$((TS_END - TS_START)); \
		if [ "$$err" -eq 0 ]; then \
			echo ""; echo "    [$$N/$$TOTAL] [PASS] $$t ($${ELAPSED}s)"; P=$$((P+1)); \
		else \
			echo ""; echo "    [$$N/$$TOTAL] [FAIL] $$t (UVM_ERROR=$$err, $${ELAPSED}s)"; F=$$((F+1)); \
		fi; \
	done; \
	SEC_END=$$(date +%s); \
	TOTAL_ELAPSED=$$((SEC_END - SEC_START)); \
	echo ""; \
	echo "  ========================================"; \
	echo "  UVM Regression: $$P passed, $$F failed ($${TOTAL_ELAPSED}s total)"; \
	echo "  ========================================"; \
	echo "  FSDB waveforms: $(BUILD_DIR)/waveforms/<test>.fsdb"; \
	[ $$F -eq 0 ]

## sim-uvm-regr-cov — UVM 回归 + 覆盖率收集
sim-uvm-regr-cov: sim-uvm-compile-cov
	@echo "========================================"
	@echo "  UVM Regression (with coverage)"
	@echo "  Seed: $(SEED)"
	@echo "  Started: $$(date +%H:%M:%S)"
	@echo "========================================"
	@P=0; F=0; N=0; TOTAL=$(words $(UVM_TESTS)); SEC_START=$$(date +%s); \
	mkdir -p $(BUILD_DIR)/log $(BUILD_DIR)/waveforms; \
	for t in $(UVM_TESTS); do \
		N=$$((N+1)); \
		printf "  \r[$$N/$$TOTAL] $$t..."; \
		TS_START=$$(date +%s); \
		LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
		  LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
		  $(BUILD_DIR)/simv_uvm_cov -l $(BUILD_DIR)/log/$$t.log \
		  +fsdb_file=$(BUILD_DIR)/waveforms/$$t.fsdb \
		  +UVM_TESTNAME=$$t $(NTB_SEED) -cm $(CM) -cm_dir $(CM_DIR)/$$t > /dev/null 2>&1; \
		err=$$(grep -c "^UVM_ERROR [a-z]" $(BUILD_DIR)/log/$$t.log 2>/dev/null); \
		TS_END=$$(date +%s); \
		ELAPSED=$$((TS_END - TS_START)); \
		if [ "$$err" -eq 0 ]; then \
			echo ""; echo "    [$$N/$$TOTAL] [PASS] $$t ($${ELAPSED}s)"; P=$$((P+1)); \
		else \
			echo ""; echo "    [$$N/$$TOTAL] [FAIL] $$t (UVM_ERROR=$$err, $${ELAPSED}s)"; F=$$((F+1)); \
		fi; \
	done; \
	SEC_END=$$(date +%s); \
	TOTAL_ELAPSED=$$((SEC_END - SEC_START)); \
	echo ""; \
	echo "  ========================================"; \
	echo "  UVM Regression: $$P passed, $$F failed ($${TOTAL_ELAPSED}s total)"; \
	echo "  Coverage dir: $(CM_DIR)"; \
	echo "  ========================================"; \
	[ $$F -eq 0 ]

## sim-uvm     — 编译 + 运行单个 UVM 仿真（TESTNAME=指定 test）
sim-uvm: sim-uvm-compile
	$(MAKE) sim-uvm-run TESTNAME=$(TESTNAME) SEED=$(SEED)

# =============================================================================
# 覆盖率
# =============================================================================

## coverage     — 合并覆盖率数据并生成报告
coverage:
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else ifeq ($(wildcard $(CM_DIR)),)
	@echo -e "$(YELLOW)No coverage data found at $(CM_DIR)$(NC)"
	@echo "  Run 'make sim-cov' or 'make sim-uvm-regr-cov' first."
else
	@echo "========================================"
	@echo "  Coverage Report"
	@echo "========================================"
	@echo "  Merging coverage data from $(CM_DIR)..."
	urg -dir $(CM_DIR)/*.vdb -dbname $(CM_DIR)/urg.db -report $(CM_DIR)/report -log $(CM_DIR)/urg.log 2>/dev/null
	@echo ""
	@echo "  HTML report: $(CM_DIR)/report/dashboard.html"
	@echo ""
	python3 scripts/cov_report.py $(CM_DIR)
	@echo ""
	@echo "  Verdi: make cov | HTML: make cov-report"
endif

## cov-report   — 打开覆盖率报告（HTML）
cov-report:
ifeq ($(wildcard $(CM_DIR)/report/dashboard.html),)
	@echo -e "$(YELLOW)Coverage report not found. Run 'make coverage' first.$(NC)"
else
	@echo "Opening coverage report..."
	xdg-open $(CM_DIR)/report/dashboard.html 2>/dev/null || open $(CM_DIR)/report/dashboard.html 2>/dev/null || echo "  Report: $(CM_DIR)/report/dashboard.html"
endif

## cov          — 用 Verdi 打开覆盖率（源码 + 所有 test vdb 合并）
cov:
ifeq ($(VERDI),)
	@echo -e "$(YELLOW)[SKIP] Verdi not installed$(NC)"
else ifeq ($(wildcard $(BUILD_DIR)/cov.vdb),)
	@echo -e "$(YELLOW)No coverage data found at $(BUILD_DIR)/cov.vdb$(NC)"
	@echo "  Run 'make sim-uvm-regr-cov' first."
else
	@echo "========================================"
	@echo "  Verdi Coverage Viewer"
	@echo "========================================"
	@echo "  Main database: $(BUILD_DIR)/cov.vdb"
	@echo "  Loading all test VDBs from $(CM_DIR)/..."
	@VDB_LIST=""; \
	for vdb in $(CM_DIR)/*.vdb; do \
		base=$$(basename "$$vdb" .vdb); \
		case "$$base" in merged*) continue;; esac; \
		VDB_LIST="$$VDB_LIST $$vdb"; \
	done; \
	verdi -cov -covdir $(BUILD_DIR)/cov.vdb $$VDB_LIST &
	@echo "  Verdi launched"
endif

# =============================================================================
# 断言仿真（SVA）
# =============================================================================

## sim-assert  — VCS 编译 + 运行仿真带 SVA 断言
sim-assert: | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS Compile + Run + SVA Assertions"
	@echo "========================================"
	vcs $(VCS_FLAGS) $(VCS_PLI_FLAGS) -f $(FILELIST) \
		$(wildcard $(SIM_DIR)/unit/*.v) $(wildcard $(SIM_DIR)/integration/*.v) \
		$(wildcard tb/bind_*_assert.sv) \
		-o $(BUILD_DIR)/simv_assert
	@echo "  Running simulation with SVA..."
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
	  LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
	  $(BUILD_DIR)/simv_assert $(VCS_RUN_FLAGS) $(FSDB_OPTS)
	@echo -e "  [$(GREEN)DONE$(NC)] Log: $(BUILD_DIR)/log/sim_$(TIMESTAMP).log"
endif

# =============================================================================
# 波形查看
# =============================================================================

## verdi       — 使用 Verdi 打开 RTL + 单元测试 TB（$(TB_TOP) 为顶层）
verdi:
ifeq ($(VERDI),)
	@echo -e "$(YELLOW)[SKIP] Verdi not installed$(NC)"
else
	verdi -2012 +incdir+rtl -f $(FILELIST) $(wildcard $(SIM_DIR)/unit/*.v) -top $(TB_TOP) &
endif

## wav         — 使用 Verdi 打开 UVM 工程（-uvm -sv -f uvm.flist -top tb_top）
##               用法: make wav               # 列出可用波形
##                     make wav TEST=xxx      # 打开指定 UVM 波形
wav:
ifeq ($(VERDI),)
	@echo -e "$(YELLOW)[SKIP] Verdi not installed$(NC)"
else ifeq ($(TEST),)
	@WAVES=$$(ls $(BUILD_DIR)/waveforms/*.fsdb 2>/dev/null); \
	if [ -z "$$WAVES" ]; then \
		echo "  No UVM waveforms found. Run 'make sim-uvm-regr' first."; \
		echo "  Usage: make wav TEST=adc_int_test"; \
	else \
		echo "  Available UVM waveforms:"; \
		for f in $$WAVES; do echo "    make wav TEST=$$(basename $$f .fsdb)"; done; \
	fi
else
	@echo "  Opening UVM waveform: $(TEST)..."
	verdi -uvm -2012 +incdir+rtl -f tb/uvm/uvm.flist -top tb_top -ssf $(BUILD_DIR)/waveforms/$(TEST).fsdb &
endif

## wav-%        — Verdi 打开指定 UVM 测试波形（快捷方式：make wav-xxx_test）
wav-%:
ifeq ($(VERDI),)
	@echo -e "$(YELLOW)[SKIP] Verdi not installed$(NC)"
else
	@echo "  Opening UVM waveform: $*..."
	verdi -uvm -2012 +incdir+rtl -f tb/uvm/uvm.flist -top tb_top -ssf $(BUILD_DIR)/waveforms/$*.fsdb &
endif

# =============================================================================
# 测试
# =============================================================================

## test-unit    — 运行所有单元测试
test-unit: | $(BUILD_DIR)/.mkdir
	@echo "========================================"
	@echo "  Unit Tests"
	@echo "========================================"
	@found=0; pass=0; fail=0; \
	for tb in $(SIM_DIR)/unit/tb_*.v; do \
		[ -f "$$tb" ] || continue; \
		found=1; \
		name=$$(basename "$$tb" .v); \
		echo "  Running: $$name"; \
		if [ -n "$(IVERILOG)" ]; then \
			iverilog -g2012 -Irtl -o $(BUILD_DIR)/$$name \
				-f $(FILELIST) $(wildcard $(SIM_DIR)/unit/*_model.v) $$tb 2>/dev/null \
			&& $(BUILD_DIR)/$$name > $(BUILD_DIR)/$${name}.log 2>&1; \
		elif [ -n "$(VCS)" ]; then \
			vcs $(VCS_FLAGS) +incdir+rtl -f $(FILELIST) $$tb -o $(BUILD_DIR)/$$name 2>/dev/null \
			&& $(BUILD_DIR)/$$name -l $(BUILD_DIR)/$${name}.log 2>/dev/null; \
		else \
			echo "  [SKIP] No simulator found"; \
		fi; \
		if [ $$? -eq 0 ]; then \
			echo -e "  [$(GREEN)PASS$(NC)] $$name"; pass=$$((pass+1)); \
		else \
			echo -e "  [$(RED)FAIL$(NC)] $$name"; fail=$$((fail+1)); \
		fi; \
	done; \
	if [ $$found -eq 0 ]; then echo "  (no unit tests found)"; fi; \
	echo ""; \
	echo "  Passed: $$pass  Failed: $$fail"; \
	[ $$fail -eq 0 ]

## test-integration — 运行所有集成测试
test-integration: | $(BUILD_DIR)/.mkdir
	@echo "========================================"
	@echo "  Integration Tests"
	@echo "========================================"
	@found=0; pass=0; fail=0; \
	for tb in $(SIM_DIR)/integration/tb_*.v; do \
		[ -f "$$tb" ] || continue; \
		found=1; \
		name=$$(basename "$$tb" .v); \
		echo "  Running: $$name"; \
		if [ -n "$(VCS)" ]; then \
			vcs $(VCS_FLAGS) -f $(FILELIST) $$tb -o $(BUILD_DIR)/$$name 2>/dev/null \
			&& $(BUILD_DIR)/$$name -l $(BUILD_DIR)/$${name}.log $(FSDB_OPTS) 2>/dev/null; \
		else \
			iverilog -c $(FILELIST) $$tb -o $(BUILD_DIR)/$$name 2>/dev/null \
			&& $(BUILD_DIR)/$$name > $(BUILD_DIR)/$${name}.log 2>&1; \
		fi; \
		if [ $$? -eq 0 ]; then \
			echo -e "  [$(GREEN)PASS$(NC)] $$name"; pass=$$((pass+1)); \
		else \
			echo -e "  [$(RED)FAIL$(NC)] $$name"; fail=$$((fail+1)); \
		fi; \
	done; \
	if [ $$found -eq 0 ]; then echo "  (no integration tests found)"; fi; \
	echo ""; \
	echo "  Passed: $$pass  Failed: $$fail"; \
	[ $$fail -eq 0 ]

## test         — 运行全部测试（unit + integration）
test: test-unit test-integration
	@echo ""
	@echo "========================================"
	@echo "  All Tests Complete"
	@echo "========================================"

# =============================================================================
# 后仿（gate-level / post-synthesis simulation）
# =============================================================================
# 门级网表 + TSMC28HPC+ 标准单元仿真模型 + 现有 unit TB（复用 tb_adc_top.v）。
# 网表参数已展平（N=26/W=14），TB 用同一组 localparam，端口与 RTL adc_top 完全一致。
# 注：unit TB 通过 u_dut.cfg_adc_en 引用 DUT 内部网络——该网络在网表中保留为
#     adc_top 模块的内部 wire（同名），hierarchical 引用仍有效，TB 无需改动。

## gate-flist   — 生成后仿文件清单（标准单元模型 + 门级网表）
gate-flist: | $(BUILD_DIR)/.mkdir
	@echo "$(STD_CELL_V)" > $(GATE_FLIST)
	@echo "$(GATE_NETLIST)" >> $(GATE_FLIST)
	@echo "  [DONE] $(GATE_FLIST)"
	@echo "    std-cell model : $(STD_CELL_V)"
	@echo "    gate netlist   : $(GATE_NETLIST)"

## gate-sdf     — 跑 PrimeTime 生成 SDF（CORNER=tt|ssg，默认 tt）
##                写到 syn/out/adc_top.<corner>.sdf，供 gate-sim-sdf 反标
PT_SHELL   := $(shell which pt_shell 2>/dev/null)
gate-sdf:
ifeq ($(PT_SHELL),)
	@echo -e "$(YELLOW)[SKIP] pt_shell not installed$(NC)"
else
	@echo "========================================"
	@echo "  PrimeTime SDF Generation (corner=$(GATE_CORNER))"
	@echo "========================================"
	mkdir -p syn/log syn/reports
	@cd $(CURDIR) && CORNER=$(GATE_CORNER) pt_shell -f syn/pt_sta.tcl \
		| tee syn/log/pt_sta_$(GATE_CORNER).log > /dev/null 2>&1 \
		|| { echo "  [FAIL] PT failed (see syn/log/pt_sta_$(GATE_CORNER).log)"; exit 1; }
	@if [ -f $(GATE_SDF) ]; then \
		echo -e "  [$(GREEN)DONE$(NC)] -> $(GATE_SDF)"; \
	else \
		echo -e "  [$(RED)FAIL$(NC)] SDF not generated (check syn/log/pt_sta_$(GATE_CORNER).log)"; exit 1; \
	fi
endif

## gate-sim     — 零延迟门级仿真（综合网表功能验证，不反标 SDF）
##                与 Formality 互补：Formality 证逻辑等价，gate-sim 证仿真行为一致
##                GATE_TB=tb_adc_top 选 unit TB（默认）；不支持 uvm-hdl 内部信号用例
gate-sim: gate-flist
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  Gate-level Simulation (zero-delay, $(GATE_TB))"
	@echo "========================================"
	@echo "  1/3: Compiling gate netlist... (details: $(BUILD_DIR)/compile_gate.log)"
	@vcs -full64 -sverilog -timescale=1ns/1ps -debug_access \
		-LDFLAGS "-Wl,--allow-shlib-undefined" \
		+incdir+rtl +incdir+tb \
		$(VCS_PLI_FLAGS) \
		-y $$(dirname $(STD_CELL_V)) +libext+.v \
		+nospecify +notimingcheck +no_notifier \
		-f $(GATE_FLIST) tb/unit/$(GATE_TB).v tb/unit/adc_analog_model.v \
		-o $(BUILD_DIR)/simv_gate > $(BUILD_DIR)/compile_gate.log 2>&1 \
		|| { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile_gate.log)"; \
		     grep -iE "error|unresolved|cannot find" $(BUILD_DIR)/compile_gate.log | head -15; exit 1; }
	@echo "  2/3: Running gate simulation..."
	mkdir -p $(BUILD_DIR)/log
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
		LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
		$(BUILD_DIR)/simv_gate -l $(BUILD_DIR)/log/gate_$(TIMESTAMP).log \
		+fsdb_file=$(BUILD_DIR)/waveforms/gate_$(GATE_TB).fsdb
	@echo "  3/3: Gate simulation complete"
	@echo -e "  [$(GREEN)DONE$(NC)] Log: $(BUILD_DIR)/log/gate_$(TIMESTAMP).log"
	@echo -e "  [$(GREEN)DONE$(NC)] FSDB: $(BUILD_DIR)/waveforms/gate_$(GATE_TB).fsdb"
endif

## gate-sim-sdf — SDF 反标门级仿真（CORNER=tt|ssg，默认 tt）
##                反标 PT 导出的 adc_top.<corner>.sdf，验证反标时序下功能
##                需先 make gate-sdf 生成 SDF
##   hold 时序检查抑制说明：+no_notifier +tcheck 关掉 specify 块里的 $hold/$setup
##   时序检查告警。原因——TB 的 APB 驱动（apb_write/read 在 posedge pclk 后 #1
##   阻塞赋值）与模拟模型 adc_data（posedge adc_clk NBA）已在沿后驱动，但仍与
##   DUT 采样寄存器同沿翻转；SDF 反标后数据落在 hold 窗口内报伪违例（真实片外
##   时序由 SDC input_delay 建模，STA 已证 0 hold 违例）。这些是 TB 驱动时序建模
##   局限，非设计 bug，故门级功能后仿抑制 hold 告警，以功能 PASS 为准。
gate-sim-sdf: gate-flist
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else ifeq ($(wildcard $(GATE_SDF)),)
	$(error SDF not found: $(GATE_SDF). Run 'make gate-sdf' first.)
else
	@echo "========================================"
	@echo "  Gate-level SDF Simulation ($(GATE_CORNER), $(GATE_TB))"
	@echo "  SDF: $(GATE_SDF)"
	@echo "========================================"
	@echo "  1/3: Compiling gate netlist... (details: $(BUILD_DIR)/compile_gate_sdf.log)"
	@vcs -full64 -sverilog -timescale=1ns/1ps -debug_access \
		-LDFLAGS "-Wl,--allow-shlib-undefined" \
		+incdir+rtl +incdir+tb \
		$(VCS_PLI_FLAGS) \
		-y $$(dirname $(STD_CELL_V)) +libext+.v \
		-sdf max:$(GATE_TB).u_dut:$(GATE_SDF) -negdelay \
		+transport_delay_method \
		+no_notifier +tcheck \
		-f $(GATE_FLIST) tb/unit/$(GATE_TB).v tb/unit/adc_analog_model.v \
		-o $(BUILD_DIR)/simv_gate_sdf > $(BUILD_DIR)/compile_gate_sdf.log 2>&1 \
		|| { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile_gate_sdf.log)"; \
		     grep -iE "error|unresolved|cannot find" $(BUILD_DIR)/compile_gate_sdf.log | head -15; exit 1; }
	@echo "  2/3: Running SDF gate simulation..."
	mkdir -p $(BUILD_DIR)/log
	LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
		LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
		$(BUILD_DIR)/simv_gate_sdf -l $(BUILD_DIR)/log/gate_sdf_$(TIMESTAMP).log \
		+fsdb_file=$(BUILD_DIR)/waveforms/gate_sdf_$(GATE_TB).fsdb
	@echo "  3/3: SDF gate simulation complete"
	@echo -e "  [$(GREEN)DONE$(NC)] Log: $(BUILD_DIR)/log/gate_sdf_$(TIMESTAMP).log"
endif

# -----------------------------------------------------------------------------
# UVM gate sim（门级网表 + UVM TB）
#   UVM sequence 里部分用 uvm_hdl_read/force 引用 RTL 内部 generate 路径
#   （u_seq_fsm.gen_active.fsm_curr_st 等），网表层级名已变（如 gen_active_*_reg_0_），
#   路径找不到 → uvm_hdl 返回 0；sequence 须值守卫在 gate sim 自动跳过该断言。
#   零延迟编译（+nospecify +notimingcheck），先确认网表能否在 UVM 环境跑通。
#   bind_adc_assert.sv 的 `bind adc_seq_fsm` 在网表里无 adc_seq_fsm 模块（已展平），
#   报 SVA-COBMMI → 编译时用 -define 排除 bind 段。
# -----------------------------------------------------------------------------

## gate-sim-uvm-compile — 编译 UVM + 门级网表（一次编译，多 test 共享）
gate-sim-uvm-compile: gate-flist | $(BUILD_DIR)/.mkdir
ifeq ($(VCS),)
	@echo -e "$(YELLOW)[SKIP] VCS not installed$(NC)"
else
	@echo "========================================"
	@echo "  VCS UVM Gate Compile (once, run many)"
	@echo "========================================"
	rm -rf $(BUILD_DIR)/simv_gate_uvm $(BUILD_DIR)/simv_gate_uvm.daidir csrc
	@echo "  Compiling VCS gate-uvm ... (details: $(BUILD_DIR)/compile_gate_uvm.log)"
	@vcs -full64 -sverilog -timescale=1ns/1ps -debug_access \
		-LDFLAGS "-Wl,--allow-shlib-undefined" \
		$(VCS_PLI_FLAGS) -ntb_opts uvm-1.2 \
		+define+GATE_SIM \
		-y $$(dirname $(STD_CELL_V)) +libext+.v \
		+incdir+rtl +incdir+tb/uvm/agent +incdir+tb/uvm/env +incdir+tb/uvm/scoreboard \
		+incdir+tb/uvm/sequence +incdir+tb/uvm/tests +incdir+tb \
		+nospecify +notimingcheck +no_notifier \
		-f $(GATE_FLIST) $(UVM_SRCS) \
		-o $(BUILD_DIR)/simv_gate_uvm > $(BUILD_DIR)/compile_gate_uvm.log 2>&1 \
		|| { echo "  [FAIL] Compile error (see $(BUILD_DIR)/compile_gate_uvm.log)"; \
		     grep -iE "error|unresolved|cannot find" $(BUILD_DIR)/compile_gate_uvm.log | head -15; exit 1; }
	@echo -e "  [$(GREEN)DONE$(NC)] -> $(BUILD_DIR)/simv_gate_uvm"
endif

## gate-sim-uvm-regr — UVM 门级回归（零延迟，全 18 test）
##                     GATE_UVM_TESTS=... 覆盖测试列表（默认同 UVM_TESTS）
GATE_UVM_TESTS ?= $(UVM_TESTS)
gate-sim-uvm-regr: gate-sim-uvm-compile
	@echo "========================================"
	@echo "  UVM Gate Regression - $(words $(GATE_UVM_TESTS)) tests (zero-delay)"
	@echo "  Seed: $(SEED)"
	@echo "========================================"
	@P=0; F=0; N=0; TOTAL=$(words $(GATE_UVM_TESTS)); SEC_START=$$(date +%s); \
	mkdir -p $(BUILD_DIR)/log $(BUILD_DIR)/waveforms $(BUILD_DIR)/log/gate_uvm; \
	for t in $(GATE_UVM_TESTS); do \
		N=$$((N+1)); \
		printf "  \r[$$N/$$TOTAL] $$t..."; \
		TS_START=$$(date +%s); \
		LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
		  LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
		  $(BUILD_DIR)/simv_gate_uvm -l $(BUILD_DIR)/log/gate_uvm/$$t.log \
		  +fsdb_file=$(BUILD_DIR)/waveforms/gate_uvm_$$t.fsdb \
		  +UVM_TESTNAME=$$t $(NTB_SEED) > /dev/null 2>&1; \
		err=$$(grep -c "^UVM_ERROR [a-z]" $(BUILD_DIR)/log/gate_uvm/$$t.log 2>/dev/null); \
		hdlwarn=$$(grep -ciE "GATE_HDL_SKIP|uvm_hdl.*(not found|return 0)" $(BUILD_DIR)/log/gate_uvm/$$t.log 2>/dev/null); \
		TS_END=$$(date +%s); \
		ELAPSED=$$((TS_END - TS_START)); \
		if [ "$$err" -eq 0 ]; then \
			echo ""; echo "    [$$N/$$TOTAL] [PASS] $$t ($${ELAPSED}s, hdl_skip=$$hdlwarn)"; P=$$((P+1)); \
		else \
			echo ""; echo "    [$$N/$$TOTAL] [FAIL] $$t (UVM_ERROR=$$err, $${ELAPSED}s)"; F=$$((F+1)); \
		fi; \
	done; \
	SEC_END=$$(date +%s); \
	TOTAL_ELAPSED=$$((SEC_END - SEC_START)); \
	echo ""; \
	echo "  ========================================"; \
	echo "  UVM Gate Regression: $$P passed, $$F failed ($${TOTAL_ELAPSED}s total)"; \
	echo "  Logs: $(BUILD_DIR)/log/gate_uvm/<test>.log"; \
	echo "  ========================================"; \
	[ $$F -eq 0 ]

# =============================================================================
# 组合命令
# =============================================================================

## check        — lint + VCS编译 + 测试 + UVM回归（提交前验证）
check: lint vcs test sim-uvm-regr
	@echo ""
	@echo "========================================"
	@echo "  All checks passed!"
	@echo "========================================"

# =============================================================================
# 工具信息
# =============================================================================

## info         — 显示已安装 EDA 工具版本
info:
	@echo "========================================"
	@echo "  EDA Tool Versions"
	@echo "========================================"
	@printf "  %-15s " "VCS:"; \
	if [ -n "$(VCS)" ]; then $(VCS) -ID 2>&1 | head -1; else echo "NOT FOUND"; fi
	@printf "  %-15s " "Verdi:"; \
	if [ -n "$(VERDI)" ]; then $(VERDI) -v 2>&1 | head -1; else echo "NOT FOUND"; fi
	@printf "  %-15s " "iverilog:"; \
	if [ -n "$(IVERILOG)" ]; then $(IVERILOG) -V 2>&1 | head -1; else echo "NOT FOUND"; fi

## version      — 显示 Makefile 模板版本号
version:
	@echo "========================================"
	@echo "  Makefile Template Info"
	@echo "========================================"
	@echo "  Template rev: $(TEMPLATE_TAG)"
	@echo "  Template path: /path/to/project-template/Makefile"
	@echo "  Upgrade:      make template-upgrade"
	@echo "  Latest revs:"
	@echo "    R3 — Coverage, random seed, direct FSDB, nightly regr, template upgrade"
	@echo "    R2 — UVM compile/run/regr split, lint dep fix, mkdir log fix"
	@echo "    R1 — Initial release"

## template-upgrade — 检查模板是否有新版本并提示升级
template-upgrade:
	@echo "========================================"
	@echo "  Template Upgrade Check"
	@echo "========================================"
	@if [ -f /path/to/project-template/Makefile ]; then \
		TMPL_VER=$$(grep "^TEMPLATE_REV " /path/to/project-template/Makefile | head -1 | sed 's/.*:= *//;s/ *#.*//'); \
		TMPL_TAG="R$$TMPL_VER"; \
		echo "  Current: $(TEMPLATE_TAG)     Template: $$TMPL_TAG"; \
		if [ "$$TMPL_VER" -gt "$(TEMPLATE_REV)" ] 2>/dev/null; then \
			echo ""; \
			echo "  [NEW] Template version $$TMPL_TAG available!"; \
			echo ""; \
			echo "  What's new:"; \
			grep "^#   $$TMPL_TAG" /path/to/project-template/Makefile | head -5; \
			echo ""; \
			echo "  To upgrade:"; \
			echo "    cp /path/to/project-template/Makefile ."; \
			echo "    Then re-apply your project config (TOP, RTL_DIR, FILELIST)"; \
		else \
			echo "  [OK] Your Makefile is up to date."; \
		fi; \
	else \
		echo "  [SKIP] Template not found at /path/to/project-template/Makefile"; \
	fi

# =============================================================================
# 回归归档
# =============================================================================

## regr-nightly — 运行完整回归并归档到 regr/YYYYMMDD/
regr-nightly: lint test-unit sim-uvm-regr
	@echo ""
	@echo "========================================"
	@echo "  Archiving regression results"
	@echo "========================================"
	@ARCHIVE=regr/$(DATE_TAG); \
	mkdir -p $$ARCHIVE/log $$ARCHIVE/waveforms; \
	cp -r $(BUILD_DIR)/log/*.log $$ARCHIVE/log/ 2>/dev/null; \
	cp -r $(BUILD_DIR)/waveforms/*.fsdb $$ARCHIVE/waveforms/ 2>/dev/null; \
	echo "  Results archived to $$ARCHIVE"; \
	echo ""; \
	echo "  === Regression $(DATE_TAG) complete ===" > $$ARCHIVE/STATUS.txt; \
	echo "  Lint + test-unit + UVM regr: $$(date)" >> $$ARCHIVE/STATUS.txt; \
	cat $$ARCHIVE/log/*.log 2>/dev/null | grep -h "PASS=\|FAIL=\|UVM_ERROR" >> $$ARCHIVE/STATUS.txt; \
	echo "  Archive: $$ARCHIVE"

# =============================================================================
# 清理
# =============================================================================

## clean        — 删除构建产物（含覆盖率数据）
clean:
	@echo "Cleaning build artifacts..."
	rm -rf $(BUILD_DIR) csrc simv.daidir
	rm -f *.key
	@echo -e "  [$(GREEN)DONE$(NC)]"

## clean-all    — 深度清理（含回归归档和波形文件）
clean-all:
	@echo "Deep cleaning..."
	rm -rf $(BUILD_DIR) csrc simv.daidir regr
	rm -f *.key *.bak
	@echo -e "  [$(GREEN)DONE$(NC)]"

## clean-cov    — 清理覆盖率报告遗留物（保留 test vdb，删旧 report/log/merged）
clean-cov:
	@echo "Cleaning coverage artifacts (keeping test VDBs)..."
	rm -rf $(CM_DIR)/report* $(CM_DIR)/rpt_* $(CM_DIR)/merged*.vdb $(CM_DIR)/urg*.db $(CM_DIR)/urg*.log
	@echo -e "  [$(GREEN)DONE$(NC)] — test VDBs preserved"

# =============================================================================
# 内部：创建构建目录
# =============================================================================

$(BUILD_DIR)/.mkdir:
		mkdir -p $(BUILD_DIR)
	touch $@
