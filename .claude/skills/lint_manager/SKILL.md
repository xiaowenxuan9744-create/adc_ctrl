---
name: lint-manager
description: 统一 RTL lint 入口、管理 iverilog/VCS 差异与误报白名单、维护 waiver，并集成到 rtl_generator/reviewer——关闭质量闭环
triggers:
  - lint
  - lint 检查
  - lint clean
  - waiver
  - iverilog 误报
  - VCS iverilog 差异
  - 语法检查
  - lint_waive
---

# Lint Manager — RTL Lint 统一管理

统一 lint 入口、处理 iverilog/VCS 差异与误报、管理 waiver，并把 lint 集成进
rtl_generator（生成即 lint）和 rtl_reviewer（评审含 lint 维度）。

> **痛点来源**（示例：某项目曾发生）：
> - pre-commit hook 曾逐文件跑 `iverilog -t null -Wall <file>`，单文件无法解析
>   模块层次，顶层模块误报 "Unknown module type: <submodule>" 多处，正常提交被
>   拦截，被迫 `--no-verify`。根因：缺统一 lint 入口（必须组编译）+ 误报白名单机制。
> - env-bug #9 只是事后记录"单文件 iverilog 误报"，不是机制。
> - 项目无 waiver 文件，lint warning 靠人脑记，重复消耗时间。
> - 工作流要求"所有模块必须 lint-clean，无 error + 无 warning（可豁免需
>   `// lint_waive: <原因>`）"，但无 skill 支撑 waiver 登记与维护。

## 四大职责

| 职责 | 何时用 | 输出 |
|:--|:--|:--|
| **统一 lint** | 任何 lint 需求 | 调 `make lint`（组编译），禁止逐文件 |
| **误报判定** | iverilog 报错时 | 区分真错误 vs 已知误报，给白名单 |
| **waiver 管理** | 遇可豁免 warning | 登记 `// lint_waive:` + 项目级 waiver.f |
| **集成** | rtl_generator 生成后 / rtl_reviewer 评审 | 自动跑 lint 并纳入结果 |

## 输入

- RTL 源码（.v / .sv）
- filelist（`rtl/filelist.f`）
- 可选：已有 waiver 文件（`scripts/lint_waiver.f`）
- 可选：iverilog 与 VCS 输出对比

## 输出

- lint 报告（真错误 / 误报 / waiver 建议分类）
- waiver 更新建议
- lint-clean 判定

---

## 职责 1: 统一 lint 入口

**唯一正确方式：组编译，带 filelist。**

```bash
make lint   # = iverilog -t null -Wall -c rtl/filelist.f -o /dev/null
```

**禁止**：
- ❌ `iverilog -t null -Wall <single_file>` — 单文件无法解析子模块层次，
  顶层模块会误报 "Unknown module type: <submodule>"（env_bug #9）
- ❌ 只跑 iverilog 不跑 VCS — iverilog 和 VCS 严格度不同，两者都过才算语法通过
  （CLAUDE.md "lint ≠ compile"）

**配套**：lint 通过后必须 `make vcs`（VCS 编译）再确认。两者都 PASS 才算语法检查通过。

---

## 职责 2: iverilog/VCS 差异与误报白名单

iverilog 和 VCS 对某些构造的严格度/支持度不同。已知差异表（持续维护）：

| 构造 | iverilog | VCS | 判定 | 处理 |
|:--|:--|:--|:--|:--|
| 单文件顶层（无子模块定义） | 报 "Unknown module type" | — | **误报** | 用组编译，忽略单文件报错 |
| nested generate | 通过 | 可能 scope 歧义报错（env_bug #2/#3） | VCS 严 | 拍平 generate |
| `@*` 对数组敏感 | warning "sensitive to all N words" | 通过 | iverilog 噪声 | 可 waiver |
| `8'(signal)` cast | iverilog 11 支持 | 需 -sverilog | 差异 | 确认 VCS flags |
| SystemVerilog 部分 | 支持有限 | 完整 | VCS 全 | TB 用 VCS，RTL 用 iverilog 可 |

**误报判定流程**：
1. iverilog 报 error → 先确认是否单文件运行（是 → 切组编译重跑）
2. 组编译仍报 → 看是否在已知误报白名单（上表）
3. 不在白名单 → 当真错误处理
4. VCS 编译报错 iverilog 不报 → 通常 VCS 更严，按 VCS 修

---

## 职责 3: Waiver 管理

### 行内 waiver（首选，针对单行）

```verilog
reg [15:0] some_reg; // lint_waive: iverilog @* array-sensitivity noise, VCS clean
```

格式：`// lint_waive: <原因>`（CLAUDE.md 规定）。必须说明为什么可豁免。

### 项目级 waiver（针对系统性噪声）

iverilog 没有 waiver 文件机制（`-W` 是 warning 开关如 `-Wall`/`-Wno-<style>`，
不接受文件参数）。系统性噪声处理方式：

- **关特定 warning 类别**：`iverilog -Wno-<style>` 关闭某类 iverilog 噪声
  （如 `-Wno-sensitivity` 关 @* 数组敏感噪声）
- **行内 waiver（项目约定，非工具识别）**：`// lint_waive: <原因>` 注释
  供人工/评审识别，iverilog 不解析它，但项目流程据此跳过该行
- **VCS waiver**：VCS 可用 `+lint=...` 控制或 tcl waiver 文件，按 VCS 文档配置

```
# iverilog 系统性噪声关闭示例（非 waiver 文件，是 warning 开关）
iverilog -t null -Wall -Wno-sensitivity -c filelist.f
```

### Waiver 登记原则

- **只 waive 误报/噪声，不 waive 真问题**
- 每个 waiver 必须有原因注释
- waiver 要定期复审（RTL 演化后某些 waiver 可能失效）
- 真问题必须修代码，不能靠 waiver 藏

---

## 职责 4: 集成到生成/评审流程

### rtl_generator 集成

rtl_generator 生成 RTL 后，本 skill 自动：
1. 跑 `make lint`（组编译）
2. 有 error → 报告并定位，要求修复后才算生成完成
3. 有 warning → 区分误报/真问题，误报给 waiver 建议，真问题修复

### rtl_reviewer 集成

rtl_reviewer 评审时新增"lint 维度"：
- lint 是否 clean（make lint + make vcs 都 PASS）
- 所有 warning 是否都已 waiver 或修复
- waiver 原因是否合理
- 无"用 waiver 藏真问题"的情况

---

## 输出报告模板

```markdown
# Lint 报告 — <module> — <date>

## 总览
- make lint (iverilog 组编译): PASS / FAIL
- make vcs (VCS 编译): PASS / FAIL
- 语法检查结论: 通过 / 不通过

## 真错误（必须修）
[ERROR] <file>:<line> ... 
        建议: ...

## 误报（白名单，可忽略）
[NOISE] <top>.v 单文件 "Unknown module type" — 已知误报，组编译 PASS
[NOISE] <file>:<line> @* array sensitivity — iverilog 噪声，VCS clean

## Waiver 建议
[WAIVER] <file>:<line> — 建议加 // lint_waive: iverilog @* array noise, VCS clean

## lint-clean 判定
✅ 通过（0 真错误，2 误报已白名单，0 待 waiver）
或
❌ 不通过（N 真错误需修复）
```

---

## 与其他 Skill 配合

```
rtl_generator → 生成 RTL
      ↓
lint-manager  → 生成后立即 lint（集成职责）
      ↓
rtl_reviewer  → 评审含 lint 维度（集成职责）
      ↓
consistency_check → 一致性（不重叠，lint 管语法/可综合性，consistency 管多端一致）
```

> **与 env_bug 分工**：env_bug #9 等记录"iverilog 误报现象"（事后知识），
> lint-manager 把这些知识**机制化**（白名单 + 自动判定）。env_bug 保留现象记录，
> lint-manager 是执行机制。

## 何时调用

- rtl_generator 生成任何 RTL 后（自动）
- rtl_reviewer 评审时（lint 维度）
- CLAUDE.md Step 6b（make lint）、6b+（make vcs）
- 提交前（pre-commit hook 已改为调 make lint）
- 遇 iverilog/VCS 报错需判定真假时
