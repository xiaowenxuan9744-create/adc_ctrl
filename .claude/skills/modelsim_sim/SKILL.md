---
name: modelsim_sim
description: |
  ModelSim/Questa UVM 仿真环境搭建与执行。覆盖 UVM 测试用例生成、SystemVerilog
  testbench 编写、TCL 脚本编写、ModelSim 仿真运行与调试的完整流程。

  触发场景：用户提到 "ModelSim"、"Questa"、"modelsim"、"vsim"、"vlog"、
  "UVM"、"SV testbench"、"仿真" 等关键词；要求为 RTL 模块建立 ModelSim 仿真
  环境；要求编写 UVM/SystemVerilog 测试用例。
---

# ModelSim 仿真 Skill（备选仿真器）

为 RTL 模块建立 ModelSim/Questa UVM 仿真环境。

> **定位：备选仿真器**。本项目主力仿真用 VCS+UVM（见 `/vcs-sim`）。本 skill
> 仅在以下场景使用：VCS 不可用 / Windows 环境 / 轻量调试。Linux + VCS 项目
> 优先用 vcs-sim，不要调用本 skill 的 `make modelsim` 目标（项目 Makefile
> 通常无此目标）。

**设计原则：简洁优先。** UVM 环境保持最小组件集，不为简单 DUT 引入不必要的 agent 层级或 sequence 嵌套。能够用一个 flat sequence 验证的功能，不拆成多层 virtual sequence。

## 前置条件

- ModelSim/Questa 已安装（确认 `vsim` 在 PATH 中）
- 模块已有 RTL 代码和 spec
- 可选：模块已有 Verilator 仿真环境

## 工作流程

### Step 1: 创建目录结构

**每个 test case 独立文件管理，禁止所有 case 堆到一个文件中（M2 强制）。**

```
sim/unit/<module>/
├── Makefile
├── verilator/                    # 已有 Verilator 环境（保持不变）
│   ├── tb_<module>_reset.cpp
│   ├── tb_<module>_reg_rw.cpp
│   └── tb_<module>_data_path.cpp
└── modelsim/                     # 新建 ModelSim UVM 环境
    ├── tb_top.sv                 # 顶层（DUT 例化 + interface 绑定）
    ├── env/
    │   └── <module>_env.sv       # UVM 环境
    ├── agent/
    │   ├── <module>_agent.sv     # Agent
    │   ├── <module>_driver.sv    # Driver
    │   └── <module>_monitor.sv   # Monitor
    ├── sequence/
    │   ├── <module>_base_seq.sv
    │   ├── <module>_reset_seq.sv
    │   ├── <module>_reg_seq.sv
    │   └── <module>_data_seq.sv
    ├── scoreboard/
    │   └── <module>_sb.sv        # Scoreboard
    ├── tests/
    │   ├── <module>_base_test.sv
    │   ├── <module>_reg_test.sv
    │   └── <module>_data_test.sv
    └── sim.tcl                   # ModelSim TCL 批处理脚本
```

### Step 2: 编写 UVM testbench

详见 `references/testbench_template.md`，关键要点：

1. **virtual interface**：在 `tb_top` 中定义 interface，通过 `uvm_config_db` 传递给 UVM 组件
2. **时钟生成**：`initial begin clk = 0; forever #(HALF_PERIOD) clk = ~clk; end`
3. **tick() 任务**：`repeat (n) begin @(posedge clk); #1; end` — `#1` 让出时间确保 DUT NBA 已稳定。详见 [[verification-lessons]]
4. **复位初始化**：必须在 tb_top 中显式设置 `rst_n = 0`，避免 `logic` 类型默认 X 导致复位被跳过
5. **VCD 导出**：`$dumpfile` / `$dumpvars`
6. **通过率统计**：Scoreboard 统计 PASS/FAIL，在 `report_phase` 输出汇总

### Step 3: 编写 ModelSim TCL 脚本

```tcl
# 设置项目根目录
set RTL_ROOT  ../../rtl
set SIM_ROOT  .

# 创建 work 库
vlib work
vmap work work

# 编译 RTL
vlog -work work +acc -sv ${RTL_ROOT}/<module>.v

# 编译 UVM 库
vlog -work work +acc +define+UVM_NO_DPI -sv ${UVM_HOME}/src/uvm_pkg.sv

# 编译 UVM 环境组件
vlog -work work +acc -sv ${SIM_ROOT}/tb_top.sv
vlog -work work +acc -sv ${SIM_ROOT}/env/<module>_env.sv
vlog -work work +acc -sv ${SIM_ROOT}/agent/<module>_agent.sv
vlog -work work +acc -sv ${SIM_ROOT}/agent/<module>_driver.sv
vlog -work work +acc -sv ${SIM_ROOT}/agent/<module>_monitor.sv
vlog -work work +acc -sv ${SIM_ROOT}/sequence/*.sv
vlog -work work +acc -sv ${SIM_ROOT}/scoreboard/<module>_sb.sv
vlog -work work +acc -sv ${SIM_ROOT}/tests/*.sv

# 加载并运行
vsim -c -do "run -all; quit -f" work.tb_top \
    +UVM_TESTNAME=<module>_reg_test \
    +UVM_VERBOSITY=UVM_MEDIUM

# 查看波形（GUI 模式）
# vsim -gui -do "do wave.do; run -all" work.tb_top
```

关键点：
- 使用**绝对路径**，避免相对路径歧义
- 编译用 `+acc` 获取全部信号访问权限
- `+define+UVM_NO_DPI` 避免 UVM DPI 编译依赖
- `+UVM_TESTNAME` 命令行指定运行的 test
- `add wave` 分 Divider 组织信号

### Step 4: 更新 Makefile

```makefile
MDL_DIR    ?= modelsim
MDL_WORK   ?= $(MDL_DIR)/work
VSIM       ?= vsim
UVM_HOME   ?= C:/modeltech_64/uvm-1.2

modelsim:
	@echo "Running ModelSim UVM (batch)..."
	cd $(MDL_DIR) && $(VSIM) -c -do sim.tcl

modelsim-gui:
	@echo "Running ModelSim UVM (GUI)..."
	cd $(MDL_DIR) && $(VSIM) -gui -do sim.tcl &

clean-mdl:
	rm -rf $(MDL_WORK)
	rm -f $(MDL_DIR)/transcript $(MDL_DIR)/*.wlf
	rm -f $(MDL_DIR)/*.vcd
	@echo "ModelSim files cleaned."
```

### Step 5: 运行仿真

```bash
make modelsim          # 批处理模式
make modelsim-gui      # GUI 交互模式
cd modelsim && vsim -c -do sim.tcl   # 直接运行
make clean-mdl         # 清理
```

### Step 6: 生成仿真报告（必须）

仿真通过后**必须**生成验证报告，输出到 `sim/unit/<module>/reports/verification_report.md`。

详见 `references/report_template.md`，必须包含以下章节：

1. **测试用例清单** — 表格列出每个 test 的配置、检查项、结果
2. **发现的问题** — 分 "RTL 功能 Bug" 和 "Testbench 问题" 两类，每条包含：位置、现象、根因、修复
3. **修改记录** — 表格列出所有修改的文件和内容
4. **验证环境** — UVM 组件列表、仿真器版本、时钟频率
5. **结论** — 通过率、覆盖率汇总

## 常见问题

### 时序偏移（PASS/FAIL 差 1 cycle）

**现象**：dout 在应该为 1 时读出 0，应该为 0 时读出 1，整体偏移 1 个时钟周期。

**根因**：testbench 的 `@(posedge clk)` 和 DUT 的 `always @(posedge clk)` 在同一个 time step 中竞争——check 可能在 DUT 的 NBA 更新前执行。

**修复**：在 `tick()` 任务的 `@(posedge clk)` 后加 `#1`：
```systemverilog
task automatic tick(input int n = 1);
    repeat (n) begin
        @(posedge clk);
        #1;  // 让出时间，确保 DUT 的 NBA 已处理
    end
endtask
```

### 复位后输出异常

**现象**：复位释放后第一个 test 仍失败。

**根因**：`logic` 类型默认值为 `X`（4-state），`rst_n` 未显式赋 0 时 `if (!rst_n)` 为 `!X = X` → 取 else 分支，复位被绕过。

**修复**：在 tb_top 开头显式设置：
```systemverilog
initial begin
    rst_n = 0;  // 必须显式赋 0
    repeat (10) @(posedge clk);
    rst_n = 1;
end
```

### UVM 编译报错 (UVM_NO_DPI)

**现象**：UVM 库编译报 DPI 相关错误。

**根因**：Questa 某些版本默认启用 DPI 支持，但 Windows 下缺少 DPI 库。

**修复**：编译 UVM 库时添加 `+define+UVM_NO_DPI`。

## Verilator → ModelSim UVM 移植对照

| 维度 | Verilator (C++ TB) | ModelSim (UVM) |
|------|---------------------|-------------------|
| `tick(n)` | `clk=0;eval();clk=1;eval()` | `repeat(n) begin @(posedge clk); #1; end` |
| 驱动输入 | `top->din = 1;` | Driver 通过 virtual interface 驱动 |
| 采样输出 | `top->dout` | Monitor 通过 virtual interface 采样 |
| 结果比对 | `check("name", dout == expected, ...)` | Scoreboard `write()` → PASS/FAIL 统计 |
| 波形 | `VerilatedVcdC` API | `$dumpfile` / `$dumpvars` |
| 编译运行 | `verilator --cc → g++` | `vlog → vopt → vsim` |
| 激励 | C++ 循环 + 函数 | UVM sequence + constrained-random |

## 注意事项

- `vsim` 和 `vlog` 是 Windows 原生 exe，路径使用 `/` 而非 `\`
- TCL 中变量用 `${VAR}` 引用，`$env(VAR)` 读取环境变量
- `vsim -c` 为命令行模式（无 GUI），`vsim -gui` 启动图形界面
- 仿真到 `$finish` 后 `vsim -c` 自动退出，`vsim -gui` 保持窗口打开
- 通过 `+UVM_TESTNAME` 命令行参数选择运行的 test case
