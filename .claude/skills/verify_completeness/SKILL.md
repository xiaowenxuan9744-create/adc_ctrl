---
name: verify-completeness
description: 验证完整性 gap 分析——spec↔testplan↔sequence 三层逐项核对，找出"标✅但没测/测错/spec有但无测试点"的缺口，输出补验清单
triggers:
  - 验证完整性
  - 验证充分性
  - gap分析
  - spec覆盖
  - 测试点覆盖
  - 验证缺口
  - 补验证
  - 验证评估
---

# Verify Completeness — 验证完整性 gap 分析

逐层核对 spec → testplan → sequence 三层覆盖关系，找出验证缺口。这是验证签收前
的完整性关卡——**testplan 标 ✅ ≠ 真验证**，必须确认每个 spec 功能点有测试点、
每个测试点有 sequence 真实现且语义正确。

> **痛点来源**（示例：某项目曾发生）：testplan 标 63 个测试点全 ✅，但逐项核对
> sequence 实际内容后发现 18 个"标 ✅ 但没测/测错"（实现不符、完全未实现、只发
> INFO 无 PASS/FAIL），10 个 spec 功能点无对应测试点，且覆盖率从未收集。功能
> PASS 的假象掩盖了验证缺口，差点签收。

## 何时调用

- **CLAUDE.md Step 9 收尾、签收前**——验证完整性强制关卡
- 重大 RTL 变更后回归完整性评估
- 怀疑"测试点标注与实现脱节"时
- coverage-analyze 报覆盖率不达标时（先查是 testplan 缺口还是 case 没覆盖）

## 与其他 Skill 配合

```
spec_parser        → spec 功能点结构化
testplan_gen       → 生成 testplan（本 skill 检查它的完整性）
testcase_gen       → 生成 sequence（本 skill 检查实现是否到位）
vcs_sim            → 跑回归（PASS/FAIL 基础）
verify_completeness→ 三层 gap 分析（本 skill）
      ↓
coverage_analyze   → 覆盖率闭环（gap 补完后再跑覆盖率）
verify_flow        → 调度主线（串起上述全过程）
```

> **分工**：testplan_gen 生成 testplan，本 skill **审计** testplan 与 sequence
> 的覆盖完整性。testplan_gen 不自审，本 skill 是独立第二意见。

## 输入

- spec 文档（`spec/<module>_spec.md`：§1 特性 + §2 接口 + §4 功能 + §3 寄存器）
- testplan 文档（`spec/testplan_<module>.md`：功能特性表 + 测试点清单 + 状态列）
- UVM sequence 目录（`tb/uvm/sequence/*.sv`）
- UVM test 目录（`tb/uvm/tests/*.sv`）
- RTL 源码（核对"标 ✅ 但 RTL 无此逻辑"的不一致）

## 输出

- **三层覆盖矩阵**：spec 功能点 → 测试点 ID → sequence 实现 → 真实现?
- **Gap 清单**（分三类）：
  - G1 spec 有功能点但 testplan 无测试点
  - G2 testplan 有测试点但 sequence 未实现/实现不符/只发 INFO
  - G3 testplan 预期与 RTL/spec 不符（需决策改谁）
- **补验清单**（P0/P1/P2 优先级）
- **完整性判定**：充分 / 基本充分有缺口 / 不充分

---

## 三层 gap 分析流程

### Step 1: 提取 spec 功能点（第一层）

从 spec 逐章提取所有"可验证功能点"：
- §1.1 特性列表 → 每条特性是一个功能点
- §2 接口定义 → 每个时序约束是一个功能点（如 SOC 单周期、preempt_rst_n 先于 HP SOC）
- §4 功能描述 → 每个子流程/异常路径是一个功能点
- §3 寄存器 → 每个寄存器的属性（RW/RO/W1C/WO/RSVD）是功能点

输出：`spec_features[]` 清单（功能点 | spec 位置 | 可验证性）

### Step 2: 提取 testplan 测试点（第二层）

从 testplan 提取所有测试点：
- 功能特性表（§2）→ 测试点 ID + 优先级
- 测试点清单（§3）→ 测试点 ID + 场景 + 预期 + 状态标记（✅/❌/⏸️/空）

输出：`testplan_points[]` 清单（ID | 场景 | 预期 | 状态）

### Step 3: 提取 sequence 实现（第三层）

从 UVM sequence 目录提取实际实现：
- grep 测试点 ID（`SMP_00x`/`REG_00x`/`CAL_00x` 等）在 sequence 中的命中
- 对每个命中，核对 sequence 代码语义是否匹配 testplan 描述
- 识别"只发 [INFO] 无 PASS/FAIL"的伪实现
- 识别"标 ID 但实现的是别的场景"（ID 错配）

**关键检查项**（逐测试点）：
| 检查项 | 方法 | 问题判定 |
|:--|:--|:--|
| ID 是否在 sequence 命中 | `grep <ID> tb/uvm/sequence/` | 命中 0 → 完全未实现 |
| 语义是否匹配 testplan | 读 sequence 上下文 | 实现的是别的场景 → 实现不符 |
| 有无 PASS/FAIL 判定 | grep `[PASS]`/`[FAIL]`/`uvm_error` | 只 `[INFO]` → 伪实现 |
| 预期与 RTL 是否一致 | 对照 RTL 该路径 | RTL 无此逻辑 → 需决策 |

输出：`sequence_impl{}` 映射（ID → 真实现状态）

### Step 4: 三层覆盖矩阵

交叉比对，生成矩阵：

| spec 功能点 | spec 位置 | 有测试点? | 测试点 ID | sequence 真实现? | gap 类型 |
|:--|:--|:--:|:--|:--:|:--|
| preempt_rst_n 先于 HP SOC 1 周期 | §4.4 | 否 | — | 否 | G1 |
| INTERVAL 时机抢占 | §4.4 | 部分 | SMP_006 | 间接 | G1 |
| DMA_HP_EOC 使能 | §3.12 | 否 | — | 否 | G1 |
| CAL_003 校准中触发 | §3.7 | 是 | CAL_003 | 实现不符（测的是清 CAL_ST） | G2 |
| SMP_003 26 通道全序列 | testplan | 是 | SMP_003 | 完全未实现 | G2 |
| 校准互斥 | §3.7 | 是 | CAL_003 | RTL 无此逻辑 | G3 |

### Step 5: Gap 分类与决策

**G1（spec 有 / testplan 无）**：
- 该功能点是否可测？可测 → 补测试点；不可测（芯片级时序/物理）→ 标"验证范围外"
- 是否 RTL 真有此逻辑？无 → 可能是 spec 超前，标"spec 待实现"

**G2（testplan 有 / sequence 未实现或不符）**：
- 未实现 → 补 sequence（调 testcase_gen）
- 实现不符 → 修正 sequence 或修正 testplan 预期（看哪个对）
- 伪实现（只 INFO）→ 补 PASS/FAIL 判定

**G3（testplan 预期 vs RTL/spec 不符）**：
- **决策三方对齐**：testplan 预期 / RTL 实现 / spec 定义，哪个是真相？
  - spec 是最高权威。spec 说"控制器不强制屏蔽"→ testplan 预期"互斥"是错的 → 改 testplan
  - spec 说"边沿触发一次"→ RTL 是电平跟随 → 改 RTL（或改 spec，看设计意图）
- **不允许"先改 RTL 后补 spec"**——先定 spec 真相，再改 testplan 或 RTL

### Step 6: 补验清单（P0/P1/P2）

按"阻塞签收程度"排序：

**P0（阻塞签收）**：
- spec 核心时序约束无验证（如 preempt_rst_n 时序）
- 多个独立功能位零覆盖（如 DMA 4 个使能位只测 1 个）
- 覆盖率从未收集（根本不知代码路径覆盖情况）
- 关键 FSM 路径无激励（如 INTERVAL 抢占时机）

**P1（影响覆盖率达标）**：
- 边界未测（26 通道/32 预留/ecc/tue 编码）
- 组合场景未测（CONT_MODE + HP 抢占）
- 实现不符需修正（CAL_003/004/005 语义错配）

**P2（实现完整性修正）**：
- 标 ✅ 但未实现的测试点补 sequence
- 伪实现（只 INFO）补 PASS/FAIL 判定
- ID 错配修正
- 全寄存器默认值/写后读覆盖不全

### Step 7: 完整性判定

| 判定 | 标准 |
|:--|:--|
| 充分 | G1/G2/G3 全部为 0 或仅 G2 的 P2 项 |
| 基本充分有缺口 | G1/G2 有 P0/P1 项，无 G3 矛盾 |
| 不充分 | G1/G2 有 P0 项，或 G3 有未决策矛盾 |

输出判定 + 必须补的验证项清单（移交 testcase_gen 实现、coverage_analyze 跑覆盖率）。

---

## 输出报告模板

```markdown
# 验证完整性 gap 分析报告 — <module> — <date>

## 三层覆盖矩阵
（Step 4 表格）

## Gap 清单
### G1 spec 有 / testplan 无
| # | 功能点 | spec 位置 | 可测? | 补测试点建议 |
...

### G2 testplan 有 / sequence 未实现或不符
| # | 测试点 ID | 状态 | 问题 | 修正方式 |
...

### G3 testplan 预期 vs RTL/spec 不符
| # | 测试点 | testplan 预期 | RTL 实现 | spec 定义 | 决策 |
...

## 补验清单
### P0（阻塞签收）
1. ...

### P1（影响覆盖率达标）
...

### P2（实现完整性修正）
...

## 完整性判定
❌ 不充分 / ⚠️ 基本充分有缺口 / ✅ 充分
必须补的验证项：...
```

## 关键原则

- **标 ✅ 不算数，要看 sequence 真实现**——这是本 skill 的核心立身之本
- **spec 是最高权威**——G3 矛盾先查 spec 怎么定义，再决定改 testplan 还是 RTL
- **G3 不允许"先改 RTL 后补 spec"**——先定 spec 真相
- **本 skill 只审计不生成**——补 sequence 转交 testcase_gen，跑覆盖率转交 coverage_analyze
- **覆盖率未收集时，本 skill 的 gap 分析是唯一完整性依据**——不能等覆盖率，先查三层覆盖
