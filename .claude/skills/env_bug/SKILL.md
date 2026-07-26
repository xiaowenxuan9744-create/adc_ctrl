---
name: env-bug
description: 环境/工具/脚本问题记录（VCS/iverilog/Makefile/文件系统兼容性问题及修复方式）；UVM 环境问题归 uvm-debug
triggers:
  - 环境问题
  - 工具问题
  - 脚本问题
  - VCS报错
  - iverilog报错
  - Makefile报错
  - 编译错误
  - 链接错误
  - 仿真报错
  - EDA工具
---

# Env Bug — 环境/工具/脚本问题记录

> **skill 性质：记录类（模板豁免）。** 内容是项目积累的环境/工具问题案例，绑定具体项目
> 语境。**不参与 skill 模板化/去语境化处理**——通用 skill（rtl_generator 等）做模板化时，
> 本 skill 保持原样。同步进通用模板（ic_rtl_template）时**清空成空容器**（只留本性质说明
> + 职责边界 + 累积规则，删项目专属案例），新项目从空容器开始积累自己的问题。

记录本项目开发过程中遇到的环境、工具链、脚本问题及修复方式。
每个问题累积到 **5 条后** 应整理并更新此 skill，避免同类问题重复排查。

> **职责边界**：本 skill 只记录 VCS / iverilog / Makefile / 文件系统类问题。
> **UVM 环境问题**（run_test / analysis_imp / config_db / delta cycle / 多驱动等）
> 统一归 `/uvm-debug`，不在本 skill 重复记录。（原 #10-14 UVM 条目已迁出）

## 计数规则

- 遇到新问题 → 追加到此文件
- 累计 **≥5 条** 时 → 触发更新（合并同类、补充根因、优化描述）
- 更新后重置计数器

---

## 问题列表

### 1. VCS 在共享文件夹上符号链接失败

- **场景**: 项目在 VMware hgfs 共享目录下开发
- **根因**: vboxsf 文件系统不支持 VCS 编译时创建的符号链接和特殊权限位
- **解决**: 移动到本地 ext4 文件系统后问题消失
- **预防**: 确认项目在 ext4/NTFS（本地）上，不在 VM 共享目录中运行 VCS

### 2. VCS O-2018.09-SP2 — nested generate 展开失败

- **场景**: `adc_sync_cell.v` 中模块级 `always` 条件引用参数，底部又有 `generate-if` 再判断同一参数
- **根因**: VCS 在 generate 内外对同一信号的引用存在 scope 歧义，iverilog 无此问题
- **解决**: 拍平为单一 generate `if-else if-else` 结构，每个分支自包含
- **已写入规范**: `rtl_generator` skill 中 Generate 块规范 规则 1（M2 强制）

### 3. VCS O-2018.09-SP2 — generate 内 reg 跨 always 引用失败

- **场景**: `adc_seq_fsm.v` 中 `reg` 声明在嵌套 generate 内部，被多个 `always` 块引用
- **根因**: VCS 展开嵌套 generate 时无法将信号引用正确链接回声明所在的分支实例
- **解决**: 信号声明提升到模块级，generate 内只使用不声明
- **已写入规范**: `rtl_generator` skill 中 Generate 块规范 规则 2（推荐）

### 4. VCS O-2018.09-SP2 — 链接阶段 undefined reference

- **场景**: `make sim` → RTL parsing/elab 通过 → 链接失败
- **报错**: `libvcsnew.so: undefined reference to vfs_set_dir_map / snpsReallocFunc / ZsExecuteNBAs` 等 93 个符号
- **根因**: `libvcsnew.so` DT_NEEDED 未声明依赖 `libvfs.so`、`libsnpsmalloc.so` 等库，binutils 2.34 默认 `--no-allow-shlib-undefined` 严格检查
- **解决**: `VCS_FLAGS` 加 `-LDFLAGS "-Wl,--allow-shlib-undefined"`
- **注意**: 这是 VCS 安装或版本本身的问题（不一致的共享库依赖声明），新版 VCS 无此问题

### 5. VCS O-2018.09-SP2 — 运行时 symbol lookup error

- **场景**: 链接通过后运行 `simv` 时报错
- **报错**: `sim/simv: symbol lookup error: libvcsucli.so: undefined symbol: snpsReallocFunc`
- **根因**: 运行时动态链接器无法解析 `libvcsucli.so` 对 `libsnpsmalloc.so` 的依赖（同 4，也是 DT_NEEDED 缺失）
- **解决**: `LD_LIBRARY_PATH` + `LD_PRELOAD` 预加载缺失的 VCS 库
- **Makefile 配置**:
  ```makefile
  VCS_LD_PATH := $(dir $(shell which vcs))../linux64/lib
  # 运行时:
  LD_LIBRARY_PATH="$(VCS_LD_PATH):$$LD_LIBRARY_PATH" \
  LD_PRELOAD="libsnpsmalloc.so:libvfs.so:libzerosoft_rt_stubs.so:libvirsim.so:libsimprofile.so:libuclinative.so" \
  $(SIMV) $(VCS_RUN_FLAGS) $(VPD_OPTS)
  ```

### 6. Makefile — 循环依赖 sim target

- **场景**: `make sim` 报循环依赖错误
- **根因**: `$(BUILD_DIR)` 作为 order-only prerequisite 时，若 Makefile 自身也有规则生成 `$(BUILD_DIR)`，低版本 Make 会检测到循环
- **解决**: 改用 `.mkdir` stamp 文件模式
  ```makefile
  sim: | $(BUILD_DIR)/.mkdir
  $(BUILD_DIR)/.mkdir:
      mkdir -p $(BUILD_DIR)
      touch $@
  ```

### 7. Makefile — `tb/*.v` glob 在 TB 子目录下失效

- **场景**: TB 文件放在 `tb/unit/` 子目录下，非直接在 `tb/` 下
- **报错**: VCS 报 `Source file "tb/*.v" cannot be opened`
- **解决**: glob 路径改为 `$(SIM_DIR)/unit/*.v`
- **扩展**: 同时集成为 test-unit / test-integration 各自的目录路径

### 8. Makefile — VCS 对空 glob 模式报错

- **场景**: `tb/integration/` 目录无 `.v` 文件时 VCS 报错
- **报错**: `Source file "tb/integration/*.v" cannot be opened for reading due to 'No such file or directory'`
- **根因**: VCS 不处理 shell glob，字面解释 `*` 为文件名的一部分，找不到文件则报错
- **解决**: 使用 GMake 的 `$(wildcard ...)` 函数展开，空时自动忽略
  ```makefile
  vcs ... $(wildcard $(SIM_DIR)/unit/*.v) $(wildcard $(SIM_DIR)/integration/*.v) ...
  ```

### 9. Iverilog — 单文件 lint 误报子模块未定义

- **场景**: 对 `adc_top.v` 或 `adc_trig_sync.v` 单独运行 `iverilog -t null -Wall` lint
- **报错**: `error: Unknown module type: adc_rst_sync / adc_sync_cell` 等
- **根因**: 单文件编译不包含子模块定义，本质不是代码问题
- **判断方式**: `make lint` 中的组编译（`iverilog -c filelist.f`）PASS 即表示代码无问题
- **机制化**: 已由 `/lint-manager` 统一管理（组编译入口 + 误报白名单），pre-commit
  hook 已改为调 `make lint` 而非逐文件，见 lint-manager skill

### 10. Iverilog -g2005 不支持 ANSI 参数列表内 localparam（参数化重构）

- **场景**: 参数化重构中，`adc_params.vh` 用 `localparam integer W_CH_SEL = $clog2(...)`
  在 module ANSI 参数列表 `#(...)` 内 `include`，供端口位宽引用
- **报错**: `error: Local parameters in module parameter port lists requires SystemVerilog`
- **根因**: Verilog-2005 (`-g2005`) 不允许 `localparam` 出现在 ANSI 参数端口列表 `#(...)`
  内，这是 SystemVerilog 特性。iverilog 默认 `-g2005`
- **解决**: iverilog 编译改 `-g2012`（SystemVerilog）。Makefile 的 lint / test-unit /
  单文件 lint 全改 `-g2012`。VCS 本身 `-sverilog` 已支持，无需改
- **替代方案**（若必须保 -g2005）：localparam 放 module body 内（端口后声明），端口
  位宽用主参数表达式内联 `[$clog2(N)-1:0]`。但 iverilog body-localparam 在 generate
  块内引用有 scope 问题（见 #11），且端口不能引用 body localparam，故本项目选 -g2012
- **已写入规范**: 参数化派生 localparam 集中 `.vh` 文件 + iverilog/VCS 需 SV 模式

### 11. Iverilog — `include` 宏文件加 `ifndef 守卫导致多 module 共享时第二个起 Unable to bind

- **场景**: 参数化重构中 `adc_params.vh` 加 `` `ifndef ADC_PARAMS_VH / `define / `endif ``
  守卫，regfile / seq_fsm / top 三个 module 各自 `include`
- **报错**: `error: Unable to bind parameter 'W_CH_SEL' in 'adc_top.u_regfile'`（第一个
  module 编译 OK，第二个起报 localparam 未声明）
- **根因**: iverilog 的 `` `define `` 是**全局**的（编译单元级），首个 module include
  时 `define ADC_PARAMS_VH` 生效，后续 module 的 `include` 被 `ifndef` 跳过，导致
  localparam 声明缺失。这与 C 预处理守卫"防重复包含"的语义不同——Verilog 守卫
  防的是**同一编译单元内同一文件被多次 include**，但多 module 各自 include 同一
  `.vh` 时，守卫会误伤第二个
- **解决**: **`.vh` 文件不加 `ifndef 守卫**。每个 module 各自完整 include，localparam
  在各自 module 作用域内声明，互不冲突（localparam 不可 override，重复声明同值安全）
- **验证**: 去守卫后三 module 共享 `adc_params.vh` 编译通过
- **反直觉点**: C 背景下 `.h` 必加 `ifndef` 守卫，但 Verilog `.vh` 在多 module
  共享时**不能加**守卫。单 module 独占 `.vh` 时守卫无害但也无必要

### 12. Iverilog `-f filelist` 末行无换行导致最后一个文件被漏

- **场景**: 参数化重构后跑 `make test-unit`，`iverilog -f rtl/filelist.f tb/unit/...`
  报 `error: Unknown module type: adc_top`（adc_top.v 是 filelist 最后一行）
- **报错**: `Unknown module type: adc_top` + `These modules were missing: adc_top`
- **根因**: `rtl/filelist.f` 末尾**无换行符**，iverilog 的 `-f` 文件列表解析器不认
  末行无换行的最后一个条目，导致 `adc_top.v` 被漏掉
- **解决**: `printf '\n' >> rtl/filelist.f` 补末尾换行
- **判断方式**: `tail -c 30 filelist.f | cat -A` 看末行是否有 `$`（换行符标记）
- **预防**: filelist 末行务必有换行；CI/pre-commit 可加 `[ -z "$(tail -c1 filelist.f)" ]` 检查
- **隐蔽性**: 该问题在 filelist 末行是非顶层模块时不暴露（漏掉的是被实例化的模块，
  单文件 lint 用 `-c filelist` 组编译时其他模块顶上来不报错），只有末行是 top
  模块且 TB 引用它时才报 Unknown module type

### 13. VCS/UVM 编译缺 `+incdir+rtl` 导致 `include "adc_params.vh"` 找不到

- **场景**: 参数化重构后跑 `make sim-uvm-regr`，VCS 报
  `Error-[SFCOR] Source file "adc_params.vh" cannot be opened`
- **根因**: `adc_params.vh` 在 `rtl/` 下，RTL 文件用 `` `include "adc_params.vh" ``，
  VCS 默认 include 搜索路径不含 `rtl/`（只含当前文件目录 + `+incdir+` 指定）
- **解决**: Makefile 的 `vcs` / `sim-uvm-compile` / `sim-uvm-compile-cov` 行加
  `+incdir+rtl`；`tb/uvm/uvm.flist` 顶部加 `+incdir+rtl`（Verdi 用）。iverilog 用
  `-Irtl`（lint/test-unit 行同步加）
- **机制化**: 参数化引入 `.vh` 后，所有仿真器编译命令都要加 include 路径。Makefile
  三处 vcs 命令 + uvm.flist 已统一加 `+incdir+rtl`

> **注**：原 #10-14 为 UVM 环境问题（run_test / analysis_imp / config_db /
> delta cycle / 多驱动），已迁至 `/uvm-debug` 统一管理，本 skill 不再记录 UVM 问题。

---

## 常见排查流程

遇到 EDA 工具报错时按以下顺序排查：

1. **解析/elaboration 错误** → 检查语法、generate 展开、scope 引用 → 尝试 `iverilog` 先验证语法
2. **链接错误 (undefined reference)** → 检查 VCS 安装完整性、binutils 版本、DT_NEEDED → 加 `--allow-shlib-undefined`
3. **运行时错误 (symbol lookup)** → 检查 `LD_LIBRARY_PATH` → 加 `LD_PRELOAD`
4. **文件系统错误** → 确认在本地 ext4 上运行，非 VM 共享目录
5. **Makefile 错误** → 确认目录结构匹配、通配符正确、无循环依赖

---

## 已知 VCS O-2018.09-SP2 限制汇总

| 问题类型 | 症状 | 是否可修 |
|:--|:--|:--:|
| Generate scope 展开 | elab 报错 nested generate 歧义 | ✅ 代码规避 |
| DT_NEEDED 缺失 | 链接 undefined reference | ✅ `--allow-shlib-undefined` |
| DT_NEEDED 缺失 | 运行时 symbol lookup error | ✅ `LD_PRELOAD` |
| TB glob 字面解释 | 空 glob 报错 | ✅ `$(wildcard)` |

## 已知 Iverilog 限制汇总

| 问题类型 | 症状 | 是否可修 |
|:--|:--|:--:|
| ANSI 参数列表内 localparam | `requires SystemVerilog` | ✅ 改 `-g2012` |
| `.vh` 共享加 ifndef 守卫 | 第二个 module `Unable to bind` | ✅ 去守卫 |
| `-f filelist` 末行无换行 | 末行文件被漏、`Unknown module type` | ✅ 补末尾换行 |
| 缺 include 路径 | `Include file not found` | ✅ `-Irtl` / `+incdir+rtl` |
