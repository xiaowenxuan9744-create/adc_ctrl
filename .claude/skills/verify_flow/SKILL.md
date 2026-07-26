---
name: verify-flow
description: 验证流程调度主线——串起 testplan-gen→testcase-gen→vcs-sim→verify-completeness→coverage-analyze→补case循环，明确每步输入输出衔接，解决"有零件没图纸"
triggers:
  - 验证流程
  - 验证主线
  - 验证调度
  - 跑验证
  - 验证闭环
  - 验证从哪开始
---

# Verify Flow — 验证流程调度主线

把分散的验证 skill 串成一条主线：从 spec 到覆盖率闭环，明确每步调哪个 skill、
输入输出怎么衔接、何时循环。解决"有零件没图纸"——每个 skill 都能用，但该按
什么顺序调、衔接点在哪，靠本 skill 给出图纸。

> **痛点来源**：项目有 testplan-gen/testcase-gen/vcs-sim/coverage-analyze/
> verify-completeness 等验证 skill，但**没有主线调度**。执行者（包括 AI 助手）
> 遇到验证任务时容易跳过 skill 直接手做，或调错顺序、漏衔接。本 skill 是验证
> 阶段的"总入口"，CLAUDE.md Step 9 的调度器。

## 何时调用

- **进入验证阶段时**（CLAUDE.md Step 9 开始）——先看本 skill 拿图纸
- 不确定"下一步该调哪个验证 skill"时
- 验证任务复杂、跨多个 skill 时
- 新人/AI 助手接手验证任务时

## 验证主线

```
spec_parser
    ↓ (spec JSON)
testplan_gen ──────────────────────────┐
    ↓ (testplan 测试点清单)            │
testcase_gen                           │ 完整性审计
    ↓ (sequence + test)                │
vcs_sim (make sim-uvm-regr)            │
    ↓ (PASS/FAIL + log)                │
verify_completeness ──────────────────┘
    ↓ (gap 清单: 补什么 case)
    ├─ 有 gap → testcase_gen 补 case → 回 vcs_sim 重跑 (循环)
    └─ 无 gap → coverage 阶段
vcs_sim (make sim-uvm-regr-cov)  ← 覆盖率收集
    ↓ (sim/cov/ 覆盖率数据)
coverage_analyze (make coverage + urg)
    ↓ (未覆盖点 + 补 case 建议)
    ├─ 未达标 → testcase_gen 补 case → 回 vcs_sim 重跑 cov (循环)
    └─ 达标 → 签收阶段
verify_before_completion (make check)   ← 全绿确认
    ↓
签收报告输出 (Step H)   ← 强制留痕
    ↓ (doc/verification_report_<date>.md + doc/waiver.md)
    └─ 签收完成
```

## 每步衔接详解

### 阶段 1: 验证内容生成

**Step A: testplan 生成/更新**
- 调 `/testplan-gen`
- 输入：spec_parser 的 spec JSON + RTL 代码
- 输出：`spec/testplan_<module>.md`（功能特性表 + 测试点清单 + 覆盖率门禁）
- 衔接：testplan 的测试点清单是 testcase_gen 的输入

**Step B: testcase 生成**
- 调 `/testcase-gen`
- 输入：testplan 测试点清单
- 输出：`tb/uvm/sequence/*.sv` + `tb/uvm/tests/*.sv`
- 衔接：每个 test 加入 Makefile UVM_TESTS 列表 + adc_uvm_pkg.sv include
- **必做**：testcase_gen 的接入验证 Step N（防死用例）

### 阶段 2: 验证执行

**Step C: 跑回归（注意 token 与执行方式）**
- 调 `/vcs-sim`
- 命令：`make sim-uvm-regr`，**用 `run_in_background: true` 跑**，主会话不阻塞，跑完自动唤醒
- 输出：各 test 的 PASS/FAIL + log + 波形
- **log 读取铁律**（回归 log 巨大，全读撑爆上下文）：
  - ❌ 禁止 Read 整篇 `sim/log/*.log` / `sim/build/*.log` / `sim/cov/` 报告
  - ✅ 醒后只 grep 关键行：`grep -E "UVM_ERROR|UVM_FATAL|FAIL|--- UVM Report" sim/log/<test>.log`
  - ✅ 编译 log：`grep -iE "error|warning" sim/build/compile.log` 或 `tail -n 50`
  - ✅ 确需看中段：先 `grep -n` 定位行号，再 Read 带 `offset`+`limit` 精读片段
  - ✅ 覆盖率报告：用 `scripts/cov_report.py` 文本摘要，不读 HTML/XML 全文
- 衔接：PASS 是完整性审计的前提（FAIL 先修 bug，不在本流程）

> **回归 debug 的执行 vs 分析分离**（避免 token 失控 + debug 丢上下文）：
> - 跑回归 + 抽 FAIL 摘要 = 执行/观测，high，可 background Bash 外包，**不开 subagent**
> - 根因 debug = 分析/决策，**留主会话 + 自动加载 `/deep-analysis` 顶 max**——
>   不放 subagent（verdi 波形无头看不了、丢主会话 spec/CDC/FSM 上下文、
>   只回摘要看不见推理、打断 run→fail→analyze→fix→rerun 紧耦合循环）
> - 多 test 各自独立失败 → 才派 subagent **并行根因**，但 **fix 回主会话**改（改 RTL 是 max 创造步骤，要在可见处做）
> - 详见 CLAUDE.md「仿真回归 debug 模式」段（全文已在 `/vcs-sim`「log 读取铁律」段，此处只摘要）

### 阶段 3: 完整性审计（关键，易被跳过）

**Step D: gap 分析**
- 调 `/verify-completeness`
- 输入：spec + testplan + sequence 实际内容 + RTL
- 输出：三层覆盖矩阵 + Gap 清单（G1/G2/G3）+ 补验清单（P0/P1/P2）
- **这一步最容易被跳过**——"testplan 标 ✅ 就以为验证完了"，但标 ✅ ≠ 真测
- 衔接：有 gap → 回 Step B 补 case（循环）；无 gap → 进覆盖率阶段

> **G3（testplan 预期 vs RTL/spec 不符）决策**：在此步处理——先定 spec 真相，
> 再改 testplan 或 RTL。不允许"先改 RTL 后补 spec"。

### 阶段 4: 覆盖率闭环

**Step E: 跑覆盖率收集**
- 调 `/vcs-sim`（覆盖率模式）
- 命令：`make sim-uvm-regr-cov`（注意是 -cov 版，普通 sim-uvm-regr 不收集覆盖率）
- 输出：`sim/cov/<test>/` 各 test 独立覆盖率数据
- **常见错误**：跑了 `make sim-uvm-regr` 就以为有覆盖率——它不收集，必须 -cov 版

**Step F: 覆盖率分析**
- 调 `/coverage-analyze`
- 命令：`make coverage`（urg 合并 + 报告）
- 输入：`sim/cov/` 覆盖率数据
- 输出：未覆盖点清单 + 根因（缺用例/用例未覆盖/死代码）+ 补 case 建议 + 门禁判定
- 衔接：未达标 → 回 Step B 补 case → 回 Step E 重跑覆盖率（循环）；达标 → 签收

### 阶段 5: 签收

**Step G: 完成前强制验证**
- 调 `/verification-before-completion`
- 命令：`make check`
- 确认：lint + vcs + test-unit + sim-uvm-regr 全绿
- 配合：coverage-analyze 的门禁判定达标

**Step H: 输出验证签收报告（强制留痕）**
- 时机：Step G 全绿 + 覆盖率达标 + 完整性无 gap 之后，**提交/PR 之前**
- 输出文件：`doc/verification_report_<date>.md`
- **必含章节**：
  1. 签收结论（一句话 + 各维度结论表）
  2. 回归结果（make check 各项 + UVM 用例清单 + PASS 数）
  3. 验证完整性审计结论（引用 verify-completeness 报告 + 已补 gap 数）
  4. 覆盖率门禁表（四类覆盖率：标准 / 实际 / 判定）
  5. **Waiver 登记**（每项含：位置 / 覆盖类型 / 当前状态 / 功能验证证据 / 完整根因 / 结论）—— 详见下方"waiver 留痕规则"
  6. 未尽事项与后续建议
  7. 签收结论（通过/不通过）
- **为什么必须**：流程能跑到"全绿"，但若无签收报告，"测了什么 / 通过情况 / 覆盖率 / waiver 根因"就散落在代码注释和对话记忆里——换人接手即丢失。签收报告是**可留痕、可交接、可审计**的唯一载体。
- 衔接：报告输出后才能进入提交/PR（CLAUDE.md Step 14）

#### waiver 留痕规则（Step H 内执行）

签收前所有"覆盖率未达 100% 但确认为工具局限/不可达路径"的项，必须正式登记：

1. **在 `doc/verification_report_<date>.md` 第 5 节登记每项 waiver**（WAIVER-NNN 编号）：
   - 位置（文件:行 + RTL 结构）
   - 覆盖类型（FSM transition / branch / line / toggle）
   - 当前覆盖状态（未覆盖 / 部分覆盖）
   - 功能验证证据（哪个 test PASS / SVA cover 命中）—— 证明功能没问题，只是覆盖率数字没体现
   - **完整根因**（设计事实 / 报告表象 / 不可达原因 / 工具局限 / 重构副作用）—— 后续维护者看到 hole 时以此为准，无需重新分析
   - 结论（为何不补路径 / 为何不硬堆 case）
2. **同时在 `doc/waiver.md`（项目级 waiver 留痕文件）追加一条索引**：
   - `WAIVER-NNN | <模块> | <位置> | <类型> | <日期> | 详见 verification_report_<date>.md §5`
   - `doc/waiver.md` 跨签收周期累积所有 waiver，是项目级总账；各次验证报告是单次明细
3. **waiver 判定原则**（避免滥用）：
   - ✅ 可 waiver：异步复位路径、防御性 default、工具不追踪的覆盖类型、确认的不可达路径
   - ❌ 不可 waiver：缺用例（应补 case）、用例没覆盖到（应修 case）、死代码可删（应删而非 waiver）
   - **先 verify-completeness 确认是"真不可达"还是"没测到"**，再决定 waiver 还是补 case
4. **后续维护**：每次 RTL 变更回归后，复查 waiver 是否仍成立（原不可达路径可能因改动变可达 → 取消 waiver 补覆盖）

## 循环退出条件

**完整性循环（Step B→C→D）**：
- 退出：verify-completeness 判定"充分"（G1/G2/G3 的 P0/P1 全清）

**覆盖率循环（Step B→E→F）**：
- 退出：coverage-analyze 门禁判定达标（语句 100%/分支 100%/FSM 100%/翻转 ≥95%）

**两个循环都要退出才能签收**。完整性是"测对了没有"，覆盖率是"测够了没有"——
两者互补，不可互相替代。

**签收闭环（Step G→H）**：
- 前置：两个循环均退出 + Step G make check 全绿
- 完成：Step H 输出验证签收报告 + waiver 登记
- **无签收报告不算签收完成**——"全绿"只是必要条件，留痕才是充分条件

## 常见误区（本 skill 要纠的）

| 误区 | 纠正 |
|:--|:--|
| "testplan 标 ✅ 就算验证完" | 标 ✅ ≠ 真测，必须 verify-completeness 审计 sequence 实现 |
| "跑了 sim-uvm-regr 就有覆盖率" | 不收集，必须 sim-uvm-regr-cov |
| "功能 PASS 就能签收" | 还要覆盖率达标 + 完整性审计 + 签收报告 |
| "make check 全绿就能签收" | 全绿只是必要条件，还要 Step H 输出签收报告 + waiver 留痕 |
| "覆盖率不达标就硬堆 case" | 先 verify-completeness 查是 testplan 缺口还是 case 没覆盖 |
| "覆盖率 hole 直接标 waiver" | 先确认是真不可达（工具局限/异步复位）还是没测到——缺用例补 case，死代码删，只有真不可达才 waiver |
| "跳过 skill 直接手写 testcase" | 用 testcase-gen，它的接入验证防死用例 |
| "G3 矛盾先改 RTL" | 先定 spec 真相，spec 是最高权威 |

## 与 CLAUDE.md 的映射

CLAUDE.md Step 9 各子步骤对应本流程：
- 9a testplan-gen → Step A
- 9b testcase-gen → Step B
- 9c/9d vcs-sim → Step C/E
- 9e 结果检查 → Step C 输出
- **9e++ 完整性审计 → Step D**（CLAUDE.md 应补此步，调 verify-completeness）
- 9g coverage-analyze → Step F
- 12 verification-before-completion → Step G
- **签收报告输出 → Step H**（CLAUDE.md 应补此步，签收前强制留痕）

> 本 skill 是 Step 9 的调度器，确保每个子步骤调对应 skill、不跳过、顺序正确。
> **建议**：CLAUDE.md Step 9（或 Step 10/14 之间）补一行 [MUST] "签收前输出
> 验证报告（doc/verification_report_<date>.md + waiver 登记）"，使 Step H
> 成为流程强制步骤而非本 skill 的内部约定。
