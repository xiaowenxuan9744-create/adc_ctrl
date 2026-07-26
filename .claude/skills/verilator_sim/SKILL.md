---
name: verilator_sim
description: |
  Verilator 仿真工具链。用于编译 Verilog/SystemVerilog 代码、运行仿真、生成波形并查看。

  触发场景：用户提到 "Verilator"、"仿真"、"simulation"、"波形"、"VCD"、"GTKWave"、
  "运行测试"、"编译 Verilog"、"数字电路仿真" 等关键词时使用此 skill。
---

# Verilator 仿真 Skill（备选仿真器）

在 Windows/MSYS2 环境下使用 Verilator 进行 RTL 仿真和波形查看。

> **定位：备选仿真器，仅用于无 UVM 的轻量 unit 仿真**。Verilator 对 UVM 支持
> 有限，不能跑 UVM 回归——UVM 回归必须用 VCS（见 `/vcs-sim`）。本项目主力
> 仿真用 VCS+UVM，本 skill 仅在 Windows 环境 / 无 VCS / 纯 Verilog unit test
> 时使用。Linux 项目优先用 vcs-sim 或 iverilog。

## 环境要求

- **MSYS2 UCRT64 环境**：Verilator 和 GTKWave 的运行环境
- **默认安装路径**：`C:\msys64`（用户可指定其他路径）

## 工作流程

### 1. 检查和安装环境

首先检查 MSYS2 和 Verilator 是否已安装：

```bash
# 检查 MSYS2 路径
ls -la /c/msys64 2>/dev/null || ls -la /d/msys64 2>/dev/null

# 检查 Verilator
ls -la <MSYS2_PATH>/ucrt64/bin/verilator*
```

**如果未安装，执行以下步骤：**

1. 下载并安装 MSYS2（推荐使用清华镜像加速）
2. 配置清华镜像源
3. 安装 Verilator 和依赖：
```bash
pacman -S --noconfirm mingw-w64-ucrt-x86_64-verilator \
                     mingw-w64-ucrt-x86_64-gcc \
                     mingw-w64-ucrt-x86_64-make \
                     mingw-w64-ucrt-x86_64-gtkwave \
                     perl-Pod-Parser
```

### 2. 编译 Verilog 代码

使用 Verilator 编译 Verilog 模块：

```bash
# 通过 MSYS2 Perl 运行 Verilator
"<MSYS2_PATH>/usr/bin/perl.exe" "<MSYS2_PATH>/ucrt64/bin/verilator" \
    --cc <module>.v \
    --exe <testbench>.cpp \
    --trace \
    -Wall

# 手动编译 C++ 文件
cd obj_dir
g++ -O3 -I. -I<MSYS2_PATH>/ucrt64/share/verilator/include \
    -c <source>.cpp -o <source>.o

# 编译 Verilator 运行时
g++ -O3 -I<MSYS2_PATH>/ucrt64/share/verilator/include \
    -c <MSYS2_PATH>/ucrt64/share/verilator/include/verilated.cpp \
    -o verilated.o
g++ -O3 -I<MSYS2_PATH>/ucrt64/share/verilator/include \
    -c <MSYS2_PATH>/ucrt64/share/verilator/include/verilated_vcd_c.cpp \
    -o verilated_vcd_c.o

# 链接生成可执行文件
g++ -o <module>.exe *.o
```

### 3. 运行仿真

执行生成的仿真程序：

```bash
cd obj_dir
./<module>.exe
```

仿真会生成 VCD 波形文件（如 `counter.vcd`）。

### 4. 查看波形

使用 GTKWave 打开波形文件：

```bash
"<MSYS2_PATH>/ucrt64/bin/gtkwave.exe" <waveform>.vcd
```

## Testbench 文件组织（M2 强制）

每个 test case 独立一个 C++ testbench 文件，禁止所有用例堆到一个 `tb_<module>.cpp` 中：

```
sim/unit/<module>/verilator/
├── Makefile                       # 按 case 列表编译运行
├── tb_<module>_reset.cpp          # reset 测试
├── tb_<module>_reg_rw.cpp         # 寄存器读写
├── tb_<module>_data_path.cpp      # 数据通路
├── tb_<module>_boundary.cpp       # 边界测试
└── tb_<module>_error_inject.cpp   # 异常注入
```

命名规范：`tb_<module>_<case_name>.cpp`。Makefile 中以 `TEST_CASES = tb_<module>_reset tb_<module>_reg_rw ...` 变量列出所有 case，逐个编译运行。

## C++ Testbench 模板

```cpp
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "V<module>.h"

// Required for Verilator
double sc_time_stamp() { return 0; }

int main(int argc, char** argv) {
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);

    V<module>* top = new V<module>{contextp};

    // Enable waveform output
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    top->trace(tfp, 99);
    tfp->open("<module>.vcd");

    // Simulation loop
    vluint64_t sim_time = 0;
    for (int i = 0; i < <cycles>; i++) {
        top->clk = 0;
        top->eval();
        tfp->dump(sim_time++);
        top->clk = 1;
        top->eval();
        tfp->dump(sim_time++);
    }

    tfp->close();
    delete top;
    delete contextp;
    return 0;
}
```

## 常用 Verilator 参数

| 参数 | 说明 |
|------|------|
| `--cc` | 生成 C++ 输出 |
| `--sc` | 生成 SystemC 输出 |
| `--exe` | 生成可执行文件 |
| `--trace` | 启用波形追踪（VCD） |
| `--trace-fst` | 启用 FST 波形（更小） |
| `-Wall` | 启用所有警告 |
| `--build` | 自动编译 |
| `-j N` | 并行编译数 |
| `--top-module <name>` | 指定顶层模块 |

## 注意事项

1. **Windows 路径问题**：Verilator 脚本需要通过 MSYS2 的 Perl 运行
2. **手动编译**：`--build` 选项在 Windows 下可能找不到 make，需要手动编译
3. **库文件**：需要手动编译 `verilated.cpp` 和 `verilated_vcd_c.cpp`
4. **sc_time_stamp**：C++ testbench 必须定义此函数

## 快速开始示例

```bash
# 1. 编译
perl /c/msys64/ucrt64/bin/verilator --cc counter.v --exe sim_main.cpp --trace -Wall

# 2. 进入 obj_dir 编译
cd obj_dir
g++ -O3 -I. -I/c/msys64/ucrt64/share/verilator/include -c ../sim_main.cpp -o sim_main.o
g++ -O3 -I. -I/c/msys64/ucrt64/share/verilator/include -c Vcounter.cpp -o Vcounter.o
# ... 编译其他 .cpp 文件
g++ -o counter.exe *.o

# 3. 运行
./counter.exe

# 4. 查看波形
/c/msys64/ucrt64/bin/gtkwave.exe counter.vcd
```
