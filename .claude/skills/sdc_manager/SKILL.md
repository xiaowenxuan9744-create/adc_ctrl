---
name: sdc-manager
description: 生成/维护 SDC 约束并做静态自检——从 RTL 端口+spec 时钟域表生成 SDC、校验 get_ports 名存在性、clock_groups/false_path 端点合法、端口增删同步
triggers:
  - SDC 约束
  - SDC 生成
  - SDC 检查
  - 时序约束
  - 综合约束
  - false_path
  - generated clock
  - SDC 同步
---

# SDC Manager — SDC 约束生成、维护与自检

管理 SDC 时序约束的完整生命周期：从 RTL 端口 + spec 时钟域表生成 SDC 初稿、
RTL 端口变更时同步 SDC、SDC 静态自检（端口名/时钟名/端点存在性）。

> **痛点来源**（示例：某项目曾发生）：
> - SDC 中 `get_ports` 引用了 RTL 不存在的端口名（SDC 写 `<port_a>`，RTL 实为
>   `<port_b>`），`get_ports` 匹配失败导致 output_delay 约束**静默失效**，综合
>   STA 漏约束。仿真阶段不暴露，综合阶段才发现，返工成本高。
> - 同步时钟对被误放进 `set_clock_groups -asynchronous` 异步分组，掩盖真实
>   半周期时序。
> - 项目工作流强调"SDC 约束前置""改时钟结构时同步更新 SDC"，但无 skill 机械化。
> - syn_handoff 只生成 SDC 初稿模板，timing_review 只读时序报告——SDC 无人专门管。

## 三大职责

| 职责 | 何时用 | 输出 |
|:--|:--|:--|
| **生成** | 新模块从 spec 进入 RTL 前 / 新建 SDC | SDC 初稿（时钟+IO delay+false_path） |
| **同步** | RTL 端口/时钟结构变更后 | 更新 SDC，报告改了哪些约束 |
| **自检** | 任何 SDC 修改后 / 综合前 / 签收前 | 自检报告（端口名/时钟名/端点存在性） |

## 输入

- RTL 顶层模块端口列表（`<top>.v` 的 module 端口声明）
- spec 时钟域表（`doc/project_config.md` 或 spec §2.2，含频率/相位/同步关系）
- 现有 SDC 文件（若有，用于同步/自检模式）
- CDC 报告（可选，cdc_review 输出，用于决定 false_path/clock_groups）

## 输出

- SDC 文件（`scripts/<module>_constraints.sdc`）
- 自检报告（Error/Warning 清单）
- 同步变更记录（改了哪些约束、为什么）

---

## 模式 1: 生成 SDC 初稿

### Step 1: 提取时钟域

从 spec 时钟域表提取：
- 每个时钟：端口名、频率（实际需求上限，非仿真配置）、来源（外部/PLL/分频）
- 同步关系：哪些时钟同源、相位关系（反相/同相/分频）
- **关键判定**：同源固定相位差 = **同步时钟**（非异步 CDC），不设 false_path，
  STA 做 generated-clock-with-invert 半周期分析（见 sync-clock-not-cdc memory）

### Step 2: 生成时钟定义

```sdc
# 实际需求上限频率（非仿真配置），综合 STA 必须在此频率闭合
create_clock -name pclk    -period <T_pclk>  [get_ports pclk]
create_clock -name adc_clk -period <T_adclk> [get_ports adc_clk]
# 同源反相：单独 create_clock + set_clock_relationship，不要 generate_clock
# （若是 RTL 内部分频才用 create_generated_clock）
create_clock -name adc_clkn -period <T_adclkn> [get_ports adc_clkn]
```

> **同步 vs 异步**：
> - 异步时钟（不同源）→ `set_clock_groups -asynchronous -group {...} -group {...}`
> - 同步时钟（同源相位差）→ `set_clock_relationship`，**不要** set_clock_groups，
>   **不要** set_false_path（会掩盖真实半周期时序）

### Step 3: 生成 IO delay

对 RTL 顶层每个端口，按其时钟域设 input/output delay：
- 每个端口必须能在 SDC 中找到对应约束（端口增删时同步）
- 保守初值（如 40% 时钟周期），注释说明"adjust per integration"

### Step 4: 生成 false_path / multicycle

依据 CDC 报告：
- 真正异步跨域（有同步器）→ `set_false_path -from [get_clocks A] -to [get_clocks B]`
- 同步跨相 → **不设** false_path
- 异步输入经 sync_cell → `set_false_path -to [get_clocks dst] [get_ports async_in]`

### Step 5: 自检（见模式 3）

---

## 模式 2: 同步 RTL 变更

RTL 端口或时钟结构变更后，同步 SDC：

### Step 1: diff RTL 端口

```
git diff <last>..HEAD -- rtl/<top>.v
提取: 新增端口 / 删除端口 / 端口方向变更 / 位宽变更
```
> `<last>` 取最近一次 SDC 同步或签收的 commit（若 SDC 文件进 git，可用
> `git log -1 -- scripts/<module>_constraints.sdc` 取上次 SDC 改动 commit）。

### Step 2: 映射到 SDC 改动

| RTL 变更 | SDC 同步动作（示例） |
|:--|:--|
| 新增 output `<port>`（`<clk>` 域） | 加 `set_output_delay -clock <clk> <T> [get_ports <port>]` |
| 删除端口 `<old_sig>` | 删所有引用 `<old_sig>` 的 set_input/output_delay / false_path |
| 端口改名 `<old>`→`<new>` | SDC 中所有 `<old>` 引用改名（含 get_ports 字符串） |
| 新增时钟端口 | 加 create_clock |
| 时钟结构变更（同步↔异步） | 调整 clock_groups / false_path / clock_relationship |

### Step 3: 自检 + 输出变更记录

```
SDC 同步变更记录：
- 新增: set_output_delay ... <port> (对应 RTL 新增端口)
- 改名: <old> → <new> (对应 RTL 端口改名)
- 删除: <old_sig> 相关约束 (对应 RTL 删端口)
```

---

## 模式 3: SDC 静态自检（核心价值）

不依赖综合工具，纯静态检查 SDC 引用的合法性。**这是防止"约束静默失效"的关键**。

### 检查项

| # | 检查项 | 方法 | 严重度 |
|:-:|:--|:--|:--:|
| 1 | **get_ports 名存在性** | SDC 所有 `get_ports("X")` / `get_port("X")` 中 X 必须在 RTL 顶层端口列表存在 | Error |
| 2 | **端口方向匹配** | `set_output_delay` 引用必须是 RTL output；`set_input_delay` 必须是 input | Error |
| 3 | **时钟名存在性** | `get_clocks("X")` 中 X 必须在 `create_clock -name` 定义集合中 | Error |
| 4 | **clock_groups 引用合法** | `set_clock_groups -group {A B}` 中 A、B（无论是否带 get_clocks）必须是已定义时钟名 | Error |
| 5 | **false_path 端点存在** | `set_false_path -from [get_clocks X] -to [get_clocks Y]` X、Y 必须已定义；`-from/-to [get_ports Z]` Z 必须存在 | Error |
| 6 | **同步时钟未误设 false_path / clock_groups** | 同源相位差时钟对之间不应有 set_false_path（应走 clock_relationship）；**且不应被放进 `set_clock_groups -asynchronous` 异步分组**（会掩盖真实半周期时序） | Error |
| 7 | **端口覆盖完整性** | RTL 顶层每个非复位/非时钟端口都有对应 IO delay 约束 | Warning |
| 8 | **通配符展开** | `get_ports "<bus>*"` 等通配符至少匹配一个真实端口 | Warning |

> **检查项 6 的两种误用都要查**：同步时钟对之间既不能 set_false_path，也不能
> 被纳入 `set_clock_groups -asynchronous`。后者更隐蔽——把同步时钟放进异步
> 分组会让 STA 跳过它们之间的真实半周期路径分析。判定依据：clock-domain-table
> 标为"同步域"的时钟对，不得出现在 false_path 或 -asynchronous group 中。

### 检查方法

```bash
# 1. 提取 RTL 顶层端口
grep -E '^\s*(input|output|inout)' rtl/<top>.v  →  端口名+方向+位宽集合 PORTS

# 2. 提取 SDC 引用
grep -oE 'get_ports\("?[^")]*"?\)' scripts/*.sdc  →  引用端口名集合 SDC_PORTS
grep -oE 'get_clocks\("?[^")]*"?\)' scripts/*.sdc →  引用时钟名集合 SDC_CLKS
grep -oE 'create_clock -name (\S+)' scripts/*.sdc →  定义时钟名集合 DEF_CLKS
# clock_groups 直接写时钟名（不带 get_clocks）也要抓：
grep -A2 'set_clock_groups' scripts/*.sdc → -group {A B} 里的时钟名

# 3. 集合 diff
SDC_PORTS − PORTS  →  Error: SDC 引用但 RTL 无此端口（最关键，曾发生端口名不匹配）
PORTS − SDC_PORTS  →  Warning: RTL 有端口但 SDC 未约束
SDC_CLKS − DEF_CLKS →  Error: SDC 引用未定义时钟

# 4. 同步时钟误用检查（依 clock-domain-table 的同步域判定）
对每对同步时钟 (clkA, clkB)：
  grep 'set_false_path.*clkA.*clkB|set_false_path.*clkB.*clkA' → 命中则 Error
  grep -A3 'set_clock_groups -asynchronous' → 若 -group 同时含 clkA、clkB 则 Error
```

### 自检报告模板

**示例**：
```
SDC 自检报告 — <module> — <date>

[ERROR] SDC 引用端口 '<port_sdc>' 在 RTL 顶层不存在
        位置: scripts/<module>_constraints.sdc:<line>
        RTL 实际端口: <port_rtl> (<direction>)
        影响: set_output_delay 约束静默失效，综合 STA 漏约束
        建议: 改为 get_ports "<port_rtl>"

[ERROR] false_path 端点 '<clk>' 未定义
        位置: scripts/<module>.sdc:<line>
        建议: 检查 create_clock 是否定义 <clk>，或删除该 false_path

[WARNING] RTL 端口 '<port>' 无 IO delay 约束
        建议: 加 set_output_delay -clock <clk> <T> [get_ports <port>]

[ERROR] 同步时钟 <clkA>↔<clkB> 之间设了 false_path
        位置: scripts/<module>.sdc:<line>
        问题: 同源反相为同步时钟，false_path 掩盖真实半周期时序
        建议: 删除 false_path，改用 set_clock_relationship

[ERROR] 同步时钟 <clkA>、<clkB> 被放进 set_clock_groups -asynchronous
        位置: scripts/<module>.sdc:<line>
        问题: 同步时钟进异步分组会让 STA 跳过半周期路径分析
        建议: 从 -asynchronous group 移出，改用 set_clock_relationship

自检结论: N Error / M Warning — 必须修复 Error 后才能综合
```

---

## 与其他 Skill 配合

```
spec_parser          → 时钟域表 JSON
clock-domain-table   → 域归属表（CDC 路径清单）
rtl_generator        → RTL 顶层端口
      ↓
sdc-manager          → 生成/同步/自检 SDC
      ↓
consistency_check 4.5 → 校验 SDC↔RTL 端口一致（与本 skill 自检互补）
cdc_review           → 提供同步/异步判定，本 skill 据此设 false_path/clock_groups
timing_review        → 解析 PT/DC 时序报告（SDC 自检由本 skill 负责，不重叠）
syn_handoff          → 打包 SDC 进交付（本 skill 产出的 SDC 是其输入）
```

> **与 consistency_check 4.5 分工**：sdc-manager 自检更全（含时钟名、端点、
> 同步判定、覆盖完整性），consistency_check 4.5 是 spec↔RTL↔SDC 五端一致性
> 的一部分。两者互补，SDC 专项以 sdc-manager 为准。

## 何时调用

- 新模块进入 RTL 前（CLAUDE.md "SDC 约束前置"）
- RTL 端口/时钟结构任何变更后（同步模式）
- 综合前 / 签收前（自检模式，必须 0 Error）
- consistency_check 4.5 报 SDC 问题时（专项深查）
