# 数字 IC 前端设计验证 Skill 库

把设计→验证→签收全流程固化成可复用 skill 的方法论模板库。本文档是**高层概览**，
用于新人 onboarding 与跨项目复用时快速建立全景认知——不是逐 skill 目录，也不重述工作流。

## 能力总览

```
┌───────────────────────────────────────────────────────────────────────┐
│                          设计验证主线                                   │
│   规格 ──▶ RTL 设计 ──▶ 验证 ──▶ 评审/签收                             │
│  brainstorming  rtl_generator  testplan_gen   rtl_reviewer             │
│  spec_parser    regmap_gen     testcase_gen   cdc_review               │
│  doc_generator  lint_manager   tb_writer      timing_review            │
│  clock_domain_  rtl_reviewer   assertion_gen  consistency_check        │
│  table                         vcs_sim        verification-before-     │
│                               verify_flow     completion               │
│                               coverage_                                │
│                               analyze                                  │
│                               verify_                                  │
│                               completeness                             │
├───────────────────────────────────────────────────────────────────────┤
│  横切（贯穿各阶段，非阶段内步骤）                                       │
│   effort 调度  deep-analysis（硬分析步骤自动顶 max）                    │
│   一致性       consistency-check（五端 spec↔RTL↔SDC↔regmap↔TB）       │
│   综合         sdc-manager / syn-handoff                                │
│   项目知识     adc-design（设计知识与验证指南，记录类·项目专属）        │
│   问题沉淀     env-bug / uvm-debug / user-profile-posedge（记录类）      │
└───────────────────────────────────────────────────────────────────────┘
```

## Skill 分类一览

一句话定位，不复述 description；完整/最新清单以 `.claude/skills/` 目录 + harness 注入为准。

| 阶段 | skill | 一句定位 |
|:--|:--|:--|
| 规格 | `/brainstorming` `/spec-parser` `/doc-generator` | 需求澄清探索 / 文档→结构化 JSON / 各格式文档生成 |
| 规格 | `/clock-domain-table` | 写 RTL 前画域归属表（CDC/同步器） |
| RTL | `/rtl-generator` `/regmap-gen` | 结构化规格→可综合 RTL / 寄存器映射全套 |
| RTL | `/lint-manager` `/rtl-reviewer` | 统一 lint 入口 / RTL 评审（风格/综合/CDC/FSM） |
| 验证 | `/testplan-gen` `/testcase-gen` `/tb-writer` | 验证计划→UVM 用例→testbench |
| 验证 | `/vcs-sim`（主力）`/modelsim-sim` `/verilator-sim`（备选） | 三套仿真流程 |
| 验证 | `/assertion-gen` `/formal-prop-gen` | SVA 断言 / 形式化属性（二者去重） |
| 验证 | `/coverage-analyze` `/verify-completeness` `/verify-flow` | 覆盖率闭环 / 完整性 gap / 验证流程调度 |
| 验证 | `/verification-before-completion` | 声称"完成"前强制跑验证并确认输出 |
| 一致性 | `/consistency-check` | spec↔RTL↔SDC↔regmap↔TB 五端一致性 |
| 综合 | `/sdc-manager` `/syn-handoff` | SDC 维护+自检 / 综合交付包 |
| 评审 | `/cdc-review` `/timing-review` | 跨域深度检查 / 时序报告分析 |
| 横切 | `/deep-analysis` | effort 旋钮（硬分析自动顶 max，非工作流） |
| 项目 | `/adc-design` | 本项目设计知识库（SOC/EOC/序列/抢占/DMA/校准）·记录类·项目专属，不进通用模板 |
| 沉淀 | `/env-bug` `/uvm-debug` `/user-profile-posedge` | 环境/工具问题 / UVM 问题 / 用户风格经验 ·记录类，模板豁免 |
| 开发 | `/writing-plans` `/executing-plans` `/systematic-debugging` `/test-driven-development` | 多步计划/执行/调试/TDD |
| 开发 | `/subagent-driven-development` `/dispatching-parallel-agents` | 子代理驱动/并行调度 |
| 工具 | `/skill-creator` `/using-superpowers` `/using-git-worktrees` `/humanizer-zh` | 建改 skill / 发现机制 / worktree / 中文润色 |
| 图表 | `/drawio` | 图表生成 |

## 怎么用

- **调用**：`/<skill-name>`（如 `/vcs-sim`、`/rtl-generator`）。完整清单与触发见 harness 每次会话注入的 `available-skills` 列表。
- **发现**：skill 放在 `.claude/skills/<name>/SKILL.md` 即被 harness 自动发现并注入；新增无需手动登记。
- **何时用哪个**：按 CLAUDE.md 标准工作流各 Step 标注的 skill 执行；验证阶段按 `/verify-flow` 主线调度。
- **新建/改 skill**：走 `/skill-creator`，遵守其「项目规范更新模式」段（三层分层 + 跨文件同步，核心规范禁外迁）。

## 维护

- **新增 skill**：在上表对应阶段加一行定位即可；不在此复述 description（那是 harness 与各 SKILL.md 的事）。
- **结构大改**（阶段重划、横切调整）：才动能力总览图。
- **记录类 skill 不参与模板化**：env-bug / uvm-debug / adc-design / user-profile-posedge 是项目积累/项目专属/个人经验，随项目语境保留，不做去语境化处理。同步进通用模板时：env-bug/uvm-debug 清空成空容器（删项目案例，留规则头），adc-design/user-profile-posedge 不进模板（项目专属/个人，新项目自建）。
- **本文件不维护的内容**：逐 skill 详细描述（看各 SKILL.md frontmatter）、工作流编排（看 CLAUDE.md / `/verify-flow`）——这两处若在本文件重复，必腐烂。完整/最新清单以 `.claude/skills/` 目录 + harness 注入为准。
