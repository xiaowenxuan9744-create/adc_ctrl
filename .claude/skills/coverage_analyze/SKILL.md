---
name: coverage-analyze
description: 分析 VCS 覆盖率报告，定位未覆盖点，映射到 testplan 测试点，建议补充用例并回填状态——关闭验证覆盖率闭环
triggers:
  - 覆盖率分析
  - 覆盖率闭环
  - coverage 分析
  - 未覆盖
  - 覆盖率未达标
  - 补用例
  - cov hole
---

# Coverage Analyze — 覆盖率分析与闭环（循环驱动器）

跑完仿真拿到覆盖率报告后，定位"哪里没覆盖到、为什么、补什么用例"，并把结果
回填到 testplan。这是 testplan_gen（定义门禁）→ testcase_gen（生成用例）→
仿真 → **本 skill（分析 hole + 补 case）** 的闭环最后一步。

> **本 skill 是循环驱动器，不是一次性报告**。每次补 case 重跑后都要重跑本 skill，
> 直到门禁达标。流程：跑覆盖率 → 本 skill 分析 hole → testcase_gen 补 case →
> 重跑覆盖率 → 再本 skill …… 循环退出条件是门禁达标。

> **痛点来源**：testplan_gen 定义了覆盖率门禁（语句 100% / 分支 100% / 条件
> ≥90% / FSM 全覆盖），但门禁无人执行——CLAUDE.md 9g "覆盖率分析 未达标→补
> case" 是人工步骤，没有 skill 支撑。门禁形同虚设。另一个痛点：跑了
> `make sim-uvm-regr` 就以为有覆盖率——它不收集，必须 `make sim-uvm-regr-cov`。

> **与 verify-completeness 的关系**：两者都是完整性把关，但维度不同——
> verify-completeness 查"测对了没有"（spec↔testplan↔sequence 语义覆盖），
> 本 skill 查"测够了没有"（代码路径覆盖）。**先 verify-completeness 补完语义
> 缺口，再跑本 skill 收覆盖率**——语义都没测对，覆盖率数字无意义。两者都达标
> 才能签收。详见 `/verify-flow` 调度主线。

## 输入

- VCS 覆盖率数据目录（默认 `sim/cov/`，由 `make coverage` 生成 urg report）
- testplan 文档（`spec/testplan_<module>.md`，含测试点 ID + 优先级 + 覆盖率映射）
- RTL 源码（定位未覆盖行的语义）
- 可选：UVM test/sequence 文件清单（判断现有用例是否已覆盖某场景）

## 输出

- **未覆盖清单**：文件 + 行号 + 覆盖类型（语句/分支/条件/FSM 状态/翻转）
- **根因分析**：每条未覆盖点为何没覆盖（缺用例 / 用例未触发该路径 / 死代码）
- **testplan 映射**：未覆盖点对应哪个测试点 ID，或标记"需新增测试点"
- **补 case 建议**：建议补充的 UVM sequence 描述（约束、触发条件、预期）
- **门禁判定**：是否达标，未达标项 + 差距
- **回填**：更新 testplan 测试点状态列（✅/❌/⏸️）

## 流程

### Step 1: 提取覆盖率报告

```bash
# 前置：已跑 make sim-uvm-regr-cov 或 make sim-cov 收集覆盖率
make coverage   # 生成 urg HTML 报告 + cov_report.py 逐模块覆盖率
```

读取：
- `scripts/cov_report.py` 输出（逐模块 line/tgl/fsm/cond 覆盖率，与 Verdi 对齐）
- `sim/cov/report/dashboard.html`（urg HTML 总览）
- 可选：`make cov` 用 Verdi GUI 查看源码 + 覆盖率关联

> **cov_report.py 算法**：跨 test OR 合并 .vdb 的 gzip XML bit string，
> 同 bit 位置任一 test 覆盖即算 1。已与 Verdi 官方数字校准（18 个数据点
> 中 16 个完全一致，seq_fsm line/tgl 差 <1% 为层次边界口径差异）。
> 支持 `--waiver` 排除 shell 分支等结构性不可达，`--json` 机器可读输出。

### Step 2: 定位未覆盖点

逐类提取未覆盖项：

| 覆盖类型 | 报告来源 | 提取内容 |
|:--|:--|:--|
| 语句 (line) | cov_report.py / Verdi | 未覆盖的模块 + hit/total |
| 分支 (branch) | Verdi GUI 源码关联 | 未覆盖的 if/case 分支 |
| 条件 (condition) | cov_report.py cond 行 | 未覆盖的逻辑组合 |
| 翻转 (toggle) | cov_report.py tgl 行 | 未翻转的信号位 |
| FSM (state) | cov_report.py fsm 行 | 未到达的状态 / 未走的转移 |

### Step 3: 根因分析（每条未覆盖点）

对每条未覆盖的 RTL 行/分支，回 RTL 源码看语义，归入三类根因：

| 根因 | 判定 | 处理 |
|:--|:--|:--|
| **缺用例** | 该场景无任何 test/sequence 触发 | 建议新增 sequence（Step 5） |
| **用例未覆盖** | 有用例但约束未触发该路径 | 调整现有 sequence 约束 |
| **死代码/不可达** | RTL 逻辑上不可达（防御性 default、保留分支） | 标记 waiver 或简化 RTL |

> **关键**：不要为凑覆盖率数字堆用例。死代码应 waiver 或删，不该硬补用例。
> （呼应 testplan_gen "简洁优先，禁止为覆盖率堆砌无意义测试点"）

### Step 4: 映射 testplan 测试点

对每条"缺用例"的未覆盖点：
1. 读 testplan，找该 RTL 路径对应的测试点 ID
2. 若有对应测试点且状态非 ✅ → 标记该测试点为 ❌（未真正覆盖）
3. 若无对应测试点 → 建议新增测试点（Step 5 一并建议）

### Step 5: 补 case 建议

对每个"缺用例"项，输出结构化建议：

**示例**：
```
[补 case 建议]
  未覆盖点: rtl/<module>.v:<line>  <ST_A> → <ST_B> 转移
  覆盖类型: FSM state transition
  根因: 无用例在 <状态> 触发 <场景>
  建议测试点: <TEST_ID> (新增) 或扩展 <existing_TEST_ID>
  建议 sequence:
    - 配置 <触发条件>
    - 在 <时机> 触发 <事件>
    - 预期: FSM 走 <ST_A> → <ST_X> → <ST_B>
  对应 testplan ID: <TEST_ID>
```

### Step 6: 门禁判定

对照 testplan_gen 的门禁标准判定：

| 门禁项 | 标准 | 判定 |
|:--|:--|:--|
| 语句覆盖 | 100% | 当前 XX% / 差距 |
| 分支覆盖 | 100% | 当前 XX% / 差距 |
| 条件覆盖 | ≥90% | 当前 XX% / 差距 |
| FSM 覆盖 | 全状态+全转移 | 缺哪些 |
| P0 测试点 | 全 ✅ 或 ⏸️ | 哪些仍 ❌/空 |

输出门禁结论：**达标可签收** / **未达标，需补 N 个用例后重跑**。

### Step 7: 回填 testplan

更新 testplan 测试点状态列（沿用 testplan_gen 的状态标记）：
- 已覆盖且 PASS → ✅
- 应覆盖但未覆盖 → ❌
- 依赖 RTL bug → ⏸️

并在 testplan 末尾追加变更记录（"覆盖率回填：XX 个测试点状态更新"）。

## 输出报告模板

```markdown
# 覆盖率分析报告 <module> — <date>

## 门禁判定
| 项 | 标准 | 实际 | 判定 |
|:--|:--|:--|:--:|
| 语句 | 100% | 98% | ❌ |
| 分支 | 100% | 95% | ❌ |
| FSM | 全覆盖 | 缺 ST_X→ST_Y | ❌ |
**结论：未达标，需补 3 个用例**

## 未覆盖清单
| 文件:行 | 类型 | 根因 | testplan ID | 建议 |
|:--|:--|:--|:--|:--|
| <module>.v:<line> | FSM trans | 缺用例 | <TEST_ID>(新) | 见 Step5 |
| <module>.v:<line> | branch | 死代码 | — | waiver (防御 default) |

## 补 case 建议（3 条）
...（Step 5 格式）

## testplan 回填
- <TEST_ID>: 空 → ✅
- <TEST_ID_new>: 新增，状态空
- <TEST_ID>: ✅ → ✅（确认）

## waiver 建议
- <module>.v:<line> default 分支，防御性，不可达，建议 waiver
  （waiver 记录位置：项目级 waiver 文件或 testplan 的 waiver 段）
```

## 与其他 Skill 配合

```
testplan_gen   → 定义测试点 + 覆盖率门禁 + 映射规则
testcase_gen   → 生成 UVM 用例
make sim-uvm-regr-cov → 跑仿真收集覆盖率
      ↓
coverage_analyze → 分析 hole + 映射测试点 + 补 case 建议 + 回填状态
      ↓
（未达标）testcase_gen 补 case → 重跑 → coverage_analyze 循环
（达标）→ rtl_reviewer 签收
```

> **闭环关键**：coverage_analyze 不是一次性报告，是循环的驱动器——
> 每次补 case 重跑后都要重跑本 skill，直到门禁达标。

## 何时调用

- CLAUDE.md Step 9g（覆盖率分析，MUST）
- 每次新增 test/sequence 后重跑回归
- 模块签收前（门禁必须达标）
- RTL 变更后回归（确认未引入覆盖 hole）
