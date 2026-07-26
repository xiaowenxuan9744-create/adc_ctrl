# 从模板启动新项目 — 操作指引

## 一句话流程

```bash
cp -r project-template <你的新项目目录>
cd <你的新项目目录>
# 修改 CLAUDE.md 和 AGENTS.md 中的项目信息
# 开始开发
```

---

## Step 1: 复制模板

```bash
# 到模板所在目录
cd /path/to/pro_demo

# 复制到新项目（替换 <my-project> 为实际名称）
cp -r project-template <my-project>
cd <my-project>
```

---

## Step 2: 修改项目信息

### 2.1 打开 CLAUDE.md

**必须修改的占位内容**：

```markdown
## 项目概要

<!-- 在此描述项目核心功能、目标和关键约束 -->
```

替换为：

```markdown
## 项目概要

XXX 硬件 IP，用于 XXX 场景。核心功能：A → B → C，关键指标：XXX。
```

**其他需要根据项目调整的**：

| 位置 | 内容 | 说明 |
|------|------|------|
| `## 构建 & 开发命令` | 构建命令 | 改为你项目的实际构建命令 |
| `## 架构` | 模块层次图 | 替换为实际模块树 |
| `## 架构` | 关键接口 | 填写实际接口 |
| `## 编码规范` | 命名规则 | 确保与项目语言一致 |
| `## 规格文档` | spec 阅读顺序 | 改为实际 spec 文件 |

### 2.2 打开 AGENTS.md（Codex CLI 用户）

同上，修改 `## 项目概要`、`## 架构`、`## RTL 编码规范` 等占位内容。

### 2.3 打开 README.md

替换以下占位：

```markdown
# Project Name — 项目模板
```

→ `# XXX — XXX 硬件 IP 设计`

以及关键规格表格、架构描述、快速开始命令。

---

## Step 3: 初始化 Git 仓库

```bash
git init
git add .
git commit -m "chore: initial project from template"
```

---

## Step 4: 按项目需求调整目录

### 必须删掉的示例目录

```bash
# 删除模板中占位的示例模块目录
rm -rf rtl/module1 rtl/module2

# 改为实际模块
mkdir -p rtl/<实际模块1> rtl/<实际模块2>/sub_module
```

### 按需调整

| 目录/文件 | 操作 |
|-----------|------|
| `rtl/` | 按模块建子目录 |
| `sim/unit/` | 每模块建子目录，结构：`sim/unit/<module>/modelsim/` |
| `sim/integration/` | 集成测试放在这里 |
| `spec/` | 放架构设计文档 `architecture.md` 和各模块 spec |
| `doc/design/` | 放设计决策记录（ADR） |
| `doc/image/` | 放架构图 `.drawio` / `.png` |

### 必须修改的配置文件（新项目最易漏的三个坑）

1. **`doc/project_config.md`**（CLAUDE.md Step 0 要求每次会话先读它）：
   - 从模板的占位符版复制，填入本项目的模块层次 / 时钟域 / SDC 路径 / 验证环境 / 测试模式
   - 标题 `<模块名>` 替换为实际模块名（如 `uart_ctrl`）

2. **`Makefile` 顶部「★ 按需修改」块**（`make help` 会列出）：
   - `TOP` / `TB_TOP`：顶层模块名 / TB 顶层名
   - `UVM_TESTS`：本项目的 UVM test 列表（留空则 `make sim-uvm-regr` 跳过）
   - `UVM_SRCS`：UVM 顶层文件清单（接口/pkg/tb_top/bind/模型）
   - `FILELIST`：文件列表路径（默认 `rtl/filelist.f`，重填模块清单）

3. **`scripts/test.sh` 的 `TB_MODELS`**：
   - 默认 glob 自动发现 `tb/unit/*_model.v`；若模型文件在别处或命名不同，改 `TB_MODELS` 变量

4. **`scripts/<module>_constraints.sdc`**：
   - 不要照抄模板 SDC，用 `/sdc-manager` 从 RTL 端口 + spec 时钟域表生成

| `ref/` | 放参考资料（竞品分析、协议文档、参考代码） |
| `scripts/` | 修改 `build.sh`、`test.sh` 中的 TODO 为实际命令 |

---

## Step 5: 设置仿真环境

### QuestaSim 仿真

每个模块建一个仿真目录：

```bash
mkdir -p sim/unit/<module>/modelsim
```

目录下放：
- `tb_<module>.sv` — SystemVerilog testbench
- `sim.tcl` — 编译运行脚本（参考模板中已修复好的相对路径格式）

示例 `sim.tcl`：

```tcl
set RTL_ROOT ../../../../rtl
vlib work
vmap work work
vlog -work work +acc -sv ${RTL_ROOT}/<module>.v
vlog -work work +acc -sv tb_<module>.sv
vsim -voptargs=+acc work.tb_<module>
run -all
```

### VCS 仿真

```bash
vcs -full64 -sverilog -Irtl/include rtl/<module>.v -o simv
./simv
```

---

## Step 6: 使用 Skill 开发

开发过程中通过自然语言调用 skill：

```
# 写 spec 阶段
"/spec-parser 帮我解析这份设计文档"

# 生成 RTL
"/rtl-generator 根据这个接口定义生成模块代码"

# 审查代码
"/rtl-reviewer 评审我新写的模块"

# 验证
"/testplan-gen 为这个模块生成验证计划"
"/testcase-gen 生成测试用例"
"/modelsim-sim 帮我搭建仿真环境"

# 调试
"/systematic-debugging 这个 bug 出在哪"
```

---

## Step 7: 验证模板版本

```bash
make version
# 预期输出: Template rev: R4
```

确保 Makefile 模板版本是最新的。如果版本低于 R4，从模板重新复制 Makefile：

```bash
cp /path/to/project-template/Makefile .
```

---

## Step 8: Pre-commit 钩子

```bash
cp .githooks/pre-commit .git/hooks/
chmod +x .git/hooks/pre-commit
```

钩子会自动对暂存的 `.v/.sv` 文件运行 lint（优先 verilator，fallback 到 iverilog）。

---

## Step 9: 日常开发工作流

### 核心原则

```text
不确定命令 → make help
不确定流程 → 看 CLAUDE.md 14 步工作流
不确定用什么工具 → 查 CLAUDE.md 工具速查表
```

### 典型一天

```text
1. make help                 # 看所有可用命令
2. 按 CLAUDE.md 工作流步骤开发
   每步查工具速查表，找到对应的命令/skill
3. 每写完一个模块:
   make lint                  # 语法检查
   /rtl-reviewer              # 代码审查
4. 验证阶段:
   make test-unit             # 快速预检
   make sim                   # VCS 全编译+仿真
   make sim-uvm-regr          # UVM 回归
5. 提交前:
   make check                 # 一键验证
```

### 快速参考

| 场景 | 执行 |
|:--|:--|
| 看所有可用命令 | `make help` |
| 看工作流和工具表 | 打开 `CLAUDE.md` |
| 看初始化流程 | 重新看本指南 |
| 环境出问题 | `make info` 检查工具版本 |
| 模板有更新？ | `make version` 检查版本号 |

---

## 常见适配场景

### 场景 A：数字 IC 设计项目（RTL + 仿真 + 综合）

```bash
# 去掉不需要的
rm -rf ref/技术笔记

# 典型目录结构
rtl/<module>.v
sim/unit/<module>/modelsim/{tb_<module>.sv, sim.tcl}
syn/<module>.ys / syn.tcl
```

### 场景 B：软件开发项目（Python / C++ / JS）

```bash
# 适配目录名
mv rtl src
mv sim tests

# 修改脚本中的目录引用
# lint.sh 中 rtl/ → src/
# test.sh 中 sim/ → tests/

# 修改 .githooks/pre-commit，注释掉 Verilog 部分，启用 Python/JS 部分
```

### 场景 C：不适用某个 skill

Skill 在 `.claude/skills/` 下，不需要的 skill 目录可以直接删除，不影响其他功能：

```bash
rm -rf .claude/skills/cdc_review     # 不需要 CDC 检查
rm -rf .claude/skills/timing_review   # 不需要时序分析
```

---

## 快速参考

| 步骤 | 命令 |
|------|------|
| 复制模板 | `cp -r project-template <my-project>` |
| 初始化 git | `git init && git add . && git commit -m "init"` |
| RTL lint | `./scripts/rtl_lint.sh` |
| 运行测试 | `./scripts/test.sh` |
| 安装 pre-commit | `cp .githooks/pre-commit .git/hooks/ && chmod +x .git/hooks/pre-commit` |
| docx 转 markdown | `python3 scripts/docx_to_md.py input.docx images/ output.md` |
