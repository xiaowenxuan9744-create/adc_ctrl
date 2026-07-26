# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目配置

**Start each session by reading `doc/project_config.md`** for project-specific context:
module hierarchy, clock domains, verification environment, and test patterns.

## 标准工作流程

每个功能模块的开发遵循以下步骤。每一步先检查是否有可用的 skill，再执行操作。

标记说明：
- `[MUST]` — 强制步骤，不可跳过
- `[MUST IF ...]` — 满足条件时必须执行
- `[RECOMMENDED]` — 强烈推荐执行
- `[OPTIONAL]` — 根据项目需求选择执行

```text
 0. [MUST] 环境与配置检查 — 启动会话后、进入工作流前
       ├── make info（确认 EDA 工具链可用）
       ├── 读取 doc/project_config.md（模块层次、时钟域、验证环境）
       └── 读取项目主 spec（确认 spec 为最新版本，与 RTL 一致；路径见 doc/project_config.md）
       此步骤确保整个会话在正确的项目上下文和工具环境中进行。

 1. [MUST] spec/ — 检查 spec/ 目录是否已有规格文档
       无   → 快速梳理已知需求，记录待讨论项，进入下一步
       有   → 阅读现有 spec，提取关键信息，记录不明确项和缺失项
             （初版/非结构化的列表式描述也可接受）

 2. [RECOMMENDED] /brainstorming — 需求澄清与设计讨论
       针对 step 1 中记录的缺失项和不明确项进行讨论
       用户在此过程中补充完善需求
       如有必要，可在讨论中调用 /drawio 辅助梳理架构

 3. [MUST] 生成正式 spec 文档 — 基于 step 1+2 的信息，输出规范格式的 spec
       初版 spec 不规范或原本无 spec → 此时生成规范化文档
       已有规范 spec → 确认是否需要更新（需求是否在讨论中发生变化）
       /doc-generator — 按模板生成完整 spec 文档（含时序图/复位/SDC/CDC 等章节）
       /spec-parser   — 解析已有文档为结构化 JSON（导入已有 spec 时使用）

 3a. [MUST] 接口时序完备性检查 — 进入 RTL 前的最后关卡
       对 spec 中每个接口信号逐条确认：
         □ 驱动沿（posedge/negedge）和时钟域
         □ 采样沿和时钟域（输入）或脉冲宽度（输出）
         □ 接收方的时序要求（建立/保持/检测沿）
       输出：接口时序表（markdown 表格，按信号逐行）
       方法：设计者 + 架构师/领域专家双人评审
       参考：[[spec-timing-checklist]]（项目 memory 中的模板）
       /doc-generator 含接口时序表自动生成子流程（从 spec-parser JSON 拼骨架）

 3a+. [MUST IF 多时钟域] /clock-domain-table — 写 RTL 前生成域归属表
       逐信号标注时钟域、CDC 路径、同步器类型
       落实"写 RTL 前先画域归属表"，供 /cdc-review 与 /sdc-manager 消费
       单时钟域模块可跳过

 3b. [MUST] 数模接口验证计划 — 在 RTL 实现前明确验证要求
       对所有数模接口信号，分两类制定验证方案：
       
       ① 寄存器配置接口（从 APB 寄存器到模拟顶层接口的连接）
          验证每一条从寄存器配置到模拟顶层接口的路径：
          □ 寄存器位域定义与模拟接口的映射关系正确
          □ 连接路径上的组合/时序逻辑没有接错或遗漏
          □ 不同配置组合下的连通性（随机测试）
         例：ch_sel 通道号要通过 LP_SEQ/HP_SEQ 寄存器 → seq_fsm → 模拟接口，
             验证需要覆盖所有通道号，确认寄存器写入值与 ch_sel 线上信号一致。
       
       ② 有时序要求的接口信号
          对每个带时序约束的信号（SOC、MUXON、EOC、ch_sel 等）：
          □ 严格按 spec 定义的驱动沿/采样沿检查
          □ 验证正常路径和异常路径（preempt/reset/overrun）下的时序行为
          □ 验证覆盖不能只依赖数据正确性间接验证——必须有独立的时序检查点
       
       输出：数模接口验证列表（标记每个信号的验证方式）
       前置：Step 3a 已完成（接口时序附录已定义）

 4. [MUST] /writing-plans — 制定设计实现计划
       包含：模块依赖分析，列出所有模块，标注依赖关系
       确定并行开发路径和串行开发路径，排定开发顺序

 5. [MUST] /executing-plans — 执行计划（生成文档、测试框架等，不含 RTL 代码）

 6. [MUST] RTL 开发 — 按依赖顺序逐模块迭代

   ┌─── 对每个模块（先叶子后父级，顶层最后）──────────────┐
   │                                                        │
   │ 6a. [MUST] /rtl-generator — 生成当前模块               │
   │     规则：所有 RTL 代码必须通过此 skill 生成，禁止手动  │
   │ 6b. [MUST] make lint — 立即语法检查                   │
   │     统一走 /lint-manager（组编译，禁逐文件 iverilog）  │
   │ 6b+. [MUST] make vcs — VCS 编译检查          │
   │     lint ≠ compile（见「设计约束」该条），两者都通过才算语法检查通过  │
   │ 6c. [MUST IF 多时钟域] /cdc-review                    │
   │     检查设计中是否有多个时钟域                         │
   │     有 → 执行 CDC 检查，确保同步器正确                 │
   │     RTL 改动涉及 CDC 路径时 → /cdc-review refresh 刷新│
   │     报告（避免快照型报告腐烂）                         │
   │     无 → 跳过此步                                     │
   │ 6d. [MUST] 模块级验证                                 │
   │     复杂模块（FSM/寄存器/校准/跨域）：                 │
   │       /tb-writer 生成轻量自检查 TB                    │
   │     简单模块（同步器/复位/纯组合逻辑）：                │
   │       lint + 代码审查通过即视为验证通过                 │
   │ 6e. [MUST] /rtl-reviewer — 模块代码评审               │
   │     写完即审，尽早发现结构性问题                       │
   │     含 /lint-manager 的 lint 维度                     │
   │                                                        │
   │ ── 修改检查清单（每次修改后逐项确认）──               │
   │                                                        │
   │ 6f. [MUST] 删除残留检查                               │
   │     grep 原信号/模块名确认无残留驱动或死代码           │
   │ 6g. [MUST IF 端口/位宽/地址变化] 影响范围检查          │
   │     改端口→ grep 所有实例化处                          │
   │     改位宽→ grep 所有相关位宽定义                      │
   │     改地址→ grep spec/TB/脚本中的旧地址                │
   │ 6h. [MUST IF 接口/时序变化] 配套文件同步               │
   │     改 RTL → 确认 TB / UVM driver / spec 同步更新      │
   │     改 spec → 确认 RTL 已实现                         │
   │ 6i. [RECOMMENDED] 改 K 时考虑 O                       │
   │     新增组合逻辑时检查级数，避免时序关键路径增长       │
   │     新增逻辑分支时确认无 latch 推断                    │
   │     新增跨域路径时确认综合约束能识别 sync cell         │
   │                                                        │
   └────────────────────────────────────────────────────────┘

   [MUST IF 含寄存器接口] /regmap-gen — 寄存器映射
     扫描判定：检测 RTL 中存在 addr_decode + reg 信号即触发
     在第一个含寄存器的模块验证前执行，仅需一次
     生成后必须执行接入验证（防孤儿文件，见 skill Step N）
   [RECOMMENDED] /assertion-gen — 关键控制模块断言
     推荐用于：多状态 FSM（状态数≥4）、跨域握手信号、仲裁逻辑
     不适用：同步器、复位、纯组合逻辑
     生成后必须执行接入验证（加入 filelist + 编译 + cover 命中）

 7. [MUST] /consistency-check — 五端一致性检查
     spec↔RTL↔SDC↔regmap↔TB（含 SDC 端口名/regmap 地址集/测试点数）

 8. [OPTIONAL] 形式化验证（推荐 FSM/仲裁/序列控制等关键控制模块）
       对关键控制模块，调用 /formal-prop-gen 生成 SVA 属性
       做 property checking，验证状态转移完备性
       生成后必须执行接入验证（bind 加入编译 + cover reachable + assert proven）

 9. [MUST] 集成仿真与验证 — 走 /verify-flow 调度主线

   ─── 阶段一：验证内容生成 ───
     9a. [MUST] /testplan-gen — 生成顶层验证计划
         制定验证点、覆盖目标、回归策略，指导 UVM 用例生成
         生成后必须执行 vs Spec Gap 分析（spec 功能点逐项查测试点覆盖）
     9b. [MUST] /testcase-gen — UVM 测试用例生成
         根据 testplan 生成带随机约束和覆盖率的 UVM 测试
         生成后必须执行接入验证 + 实现完整性自检（防"标✅但没真测"）

   ─── 阶段二：验证执行 ───
     9c. [MUST] make test-unit — 轻量预检

     9d. [MUST] 全功能仿真三部曲（按顺序执行）：
          ① make sim — 全编译 + 仿真 + 波形 + log
          ② make sim-uvm-regr — UVM 回归测试（一次编译跑全部用例）
          ③ (可选) make sim-uvm-run TEST=xxx — 调试单个 UVM 用例

   ─── 阶段三：结果闭环 ───
     9e. [MUST] 检查结果 — PASS/FAIL 分析

     9e++. [MUST] 验证完整性审计 — /verify-completeness
         功能 PASS 不等于验证充分。逐项核对 spec↔testplan↔sequence 三层覆盖：
           - spec 功能点是否都有测试点？
           - testplan 标 ✅ 的测试点 sequence 是否真实现且语义正确（非[INFO]伪实现）？
           - testplan 预期与 RTL/spec 是否一致（G3 矛盾先定 spec 真相）？
         输出 gap 清单，有缺口回 9b 补 case 循环，无缺口进覆盖率阶段
         **这一步最易被跳过——"标 ✅ 就以为验证完"，但标 ✅ ≠ 真测**

     9e+. [MUST] spec 同步检查 — 仿真通过后、进入下一步前
         本次仿真涉及的任何设计修改（RTL/端口/参数/时序），都要逐一分析：
           - spec 是否需要同步更新？
           - 更新后是否需要双方确认？
         需要则改完 spec 后再进入 9f/10/commit。
         不允许"先改 RTL，后面再补 spec"。

     9f. [MUST IF bug] 修复流程：

          ① 根因分析：bug 是 spec 问题还是 RTL 实现问题？

             ├── spec 定义错误（如位宽/地址/功能描述错误）
             │   → 先修正 spec，再进入下方修复 RTL
             │
             ├── spec 定义不全（如遗漏时序要求/异常行为）
             │   → 先补充 spec 定义，再进入下方修复 RTL
             │
             └── RTL 实现错误（如 NBA 语义/CDC 遗漏）
                 → 确认 spec 足够完善后进入下方修复 RTL
                 → 如发现 spec 也因此缺漏则先补充 spec

          ② 记录 bug 到对应的 skill：

             类型判断：
               ├── 设计问题（CDC/状态机/时序/寄存器等）→ 项目设计 skill
               ├── 环境/工具/脚本问题（VCS/iverilog/Makefile等）→ `/env-bug`
               └── 用户风格/经验教训 → `/user-profile-posedge`

             记录内容：场景、根因、修复方式。
             追加后检查该 skill 上次整理以来的新增条数：
               ≥5 条 → 立即触发整理更新（合并同类、补充根因、更新预防措施）
               <5 条 → 继续

          ③ [MUST IF 根因涉及 spec] 同步更新 spec 文档
             修改或补充完成后在 spec 中标注修订记录

          ④ 修复 RTL（改完后执行 /consistency-check）

          ⑤ [MUST] 补充回归测试用例（防止回退）

          ⑥ 轻量调试：make lint → make vcs → make run → make verdi

          ⑦ 全回归：make clean → make test-unit → make sim → make sim-uvm-regr

          ⑧ 返回 9c
     9g. [MUST] 覆盖率收集 + 分析 — /coverage-analyze（循环驱动器）
          先 make sim-uvm-regr-cov 收集覆盖率（注意：make sim-uvm-regr 不收集！）
          再 make coverage 生成 urg report → /coverage-analyze 分析未覆盖点
          分析 VCS 覆盖率报告，定位未覆盖点，映射 testplan 测试点
          未达标 → /testcase-gen 补 case → make sim-uvm-regr-cov → 再分析（循环）
          达标   → 进入下一步
          **前置：9e++ 完整性审计已通过——语义没测对，覆盖率数字无意义**
     9g+. [MUST] Waiver 留痕 — 覆盖率达标后、签收报告前
          对所有"未达 100% 但确认为工具局限/不可达"的覆盖率 hole 正式登记：
            □ 先 /verify-completeness 确认是"真不可达"还是"没测到"
              （缺用例补 case / 死代码删 / 只有真不可达才 waiver）
            □ 在 doc/verification_report_<date>.md §5 登记 WAIVER-NNN
              （位置/类型/功能验证证据/完整根因/结论）
            □ 在 doc/waiver.md 追加索引（项目级总账，跨周期累积）
            □ 标注复查触发条件（哪些 RTL 改动/工具升级需重查 waiver）
          不允许"覆盖率 hole 默默留着不登记"——留痕才可交接、可审计
     9h. [OPTIONAL] 波形调试 → make verdi
     9i. [MUST] 确认 spec 与 RTL 一致
         步骤 9f ③ 已处理涉及 spec 的修改；对于纯 RTL 修复，需确认：
           - 功能行为变化是否需更新 spec？（如控制逻辑/寄存器行为改变）
           - 接口时序变化是否需更新 spec？
           - 工程配置（project_config.md）中的测试模式/检查点是否需更新？
         如有任何变化 → 同步更新对应文档

     9j. [RECOMMENDED] 编写用户指南 — doc/user_guide.md
       仿真验证通过后、签收验收前编写
       包含：接口定义、寄存器映射、初始化流程、使用示例
       供软件/系统集成工程师参考

10. [MUST] /rtl-reviewer — RTL 代码评审（签收前二次审查，作为验收记录）

10a. [RECOMMENDED] /timing-review — 时序分析与可综合性检查
       检查关键路径、时钟/复位约束、综合 timing constraints 初稿
       SDC 约束本身正确性由 /sdc-manager 自检（端口名/时钟名/端点存在性）
       RTL 端口/时钟变更后 → /sdc-manager 同步模式更新 SDC

11. [OPTIONAL] 综合签收（如需交付综合流程）
       调用 /syn-handoff 生成综合交付包：
       - RTL freeze 副本 + 扁平的 filelist.f
       - SDC 时序约束（由 /sdc-manager 维护，自检 0 Error 后打包）
       - 交付说明 README.md
       - 签收版本打 tag

12. [MUST] /verification-before-completion — 完成前强制验证
       自动运行 make check（= lint + vcs + test-unit + sim-uvm-regr 全流程）
       （lint ≠ compile，详见「设计约束」该条）

12a. [MUST] 输出验证签收报告 — 签收留痕（提交/PR 前）
       Step 12 全绿 + 覆盖率达标 + 完整性无 gap 之后执行
       输出 doc/verification_report_<date>.md，必含：
         □ 签收结论 + 回归结果（make check 各项 + UVM 用例 PASS 数）
         □ 验证完整性审计结论（引用 verify-completeness 报告 + 已补 gap 数）
         □ 覆盖率门禁表（四类覆盖率：标准/实际/判定）
         □ Waiver 登记（9g+ 已登记的 WAIVER-NNN，含完整根因）
         □ 未尽事项与后续建议 + 签收结论
       配套 doc/waiver.md（9g+ 已建，项目级 waiver 总账）
       **无签收报告不算签收完成——"全绿"是必要条件，留痕是充分条件**

13. [OPTIONAL] 后仿（仅综合签收后需要）
       综合后网表仿真，反标 SDF 时序
       确认无综合引入的 bug

14. [MUST] 完成 — 提交代码、创建 PR，或进入下一个模块开发
```

---

## 构建 & 开发命令

### 快速入门（Makefile — 推荐）

```bash
make help                 # 显示所有可用目标
make lint                 # RTL 语法检查（iverilog，秒级）
make vcs                  # VCS 编译 RTL
make sim                  # VCS 编译 + 运行仿真 + 波形
make verdi                # Verdi 查看波形
make test-unit            # 运行单元测试
make test-integration     # 运行集成测试
make test                 # 运行全部测试
make check                # lint + test + UVM regr（提交前验证）
make clean                # 清理构建产物
make info                 # 显示已安装 EDA 工具版本
```


## 架构

完整架构设计见 `doc/design/` 目录：
   有   → 直接阅读，了解模块层次、接口、时钟域、寄存器映射
   无   → 引导生成，按项目需求补充架构设计文档

## 设计参数速查（写 RTL 前确认）

关键参数先在此确认，避免设计假设错误：

- **时钟域**：记录本模块涉及的所有时钟，标注异步/同步关系
- **复位**：异步/同步、高有效/低有效
- **接口时序**：关键握手信号的时钟域、脉冲宽度、建立/保持要求
- **可配参数**：寄存器配置的位宽、默认值、有效范围
- **跨时钟域**：涉及 CDC 的路径必须标注同步器类型（2 级/3 级/脉冲同步）

## 编码规范

代码规范已在 `/rtl-generator` skill 中完整定义（命名、缩进、注释、时序/组合逻辑、模块化等），
编写 RTL 代码时自动调用该 skill 生成，无需在 CLAUDE.md 中重复。

## 设计约束

### RTL 编码约束

- **简洁优先**：代码保持简单直白。禁止过度设计（over-engineering），禁止为单一用途引入不必要的抽象层或参数化
- **精确修改，不动 Golden IP**：只改必须改的模块。不顺手"优化"原有代码，保持与原有代码风格和命名约定一致
- **先复现再修复**：修 bug 前先用测试复现旧行为的失败 case，修复后验证通过
- **所有模块必须 lint-clean**：提交前必须通过 `make lint` 检查，无 error + 无 warning（可豁免的 warning 需行内注释说明，格式 `// lint_waive: <原因>`）
- **lint ≠ compile**：`make lint`（iverilog）和 `make vcs`（VCS）都通过才算语法检查通过。iverilog 和 VCS 检查严格程度不同，两者不互相替代——这是本条的**权威定义**，工作流 Step 6b+/12 处的引用都指向此条
- **SDC 约束前置**：时钟定义（频率、相位关系）在 SDC 中定义。改时钟结构时同步更新 SDC

### 跨域设计约束

- **写 RTL 前先画域归属表**：列出每个信号所属的时钟域、CDC 路径
- **使能、状态、输出逻辑必须属于同一个时钟域**
- 如果一个方案需要加额外的 CDC 来凑，说明域归属画错了——停下来重新想，不要继续凑

### 操作约束

- **临时还原验证用 stash 不用 checkout**：需要临时还原代码验证原始行为时，用 `git stash push -m "说明"` 暂存，验证完后 `git stash pop` 恢复。禁止使用 `git checkout -- <file>` 做临时验证。只有确定要丢弃某个文件时才用 `git checkout --`

### 推理强度（effort）调度

会话基准 `effortLevel: high`（GLM-5.2 映射 high）。按任务难度自动提档，无需手动 `/effort`。
**判定轴不是"分析 vs 生成"，而是"该步骤创造/决定正确性，还是只是执行/观测"**——创造正确性的步骤（哪怕产出是代码）顶 max，执行/观测的步骤保持 high。

- **顶 max（设计创造 + 决策 + 分析）**：自动加载 `/deep-analysis`（frontmatter `effort: max` 覆盖会话基准，该步骤全程 max，做完回退 high）
  - **RTL 编码（核心，bug 在此烙入）**：`/rtl-generator`(6a)——CDC 同步器选型/级数、FSM 状态转移、时序沿/时钟域归属、寄存器位域、组合逻辑深度/latch、复位策略都在此决定。编码是唯一无前置安全网的创造步骤（下游 review/cdc/consistency 全是事后发现）——理由详见 `/deep-analysis`「核心判定」
  - 规格与设计决策：`/brainstorming`(2)、`/doc-generator` spec(3)、3a 接口时序完备性、`/clock-domain-table`(3a+)、3b 数模接口验证计划、`/writing-plans`(4)
  - RTL/设计分析与评审：`/cdc-review`(6c)、`/rtl-reviewer`(6e/10)、`/consistency-check`(7)、`/formal-prop-gen`(8)、`/timing-review`(10a)
  - 验证设计与根因：`/testplan-gen`(9a)、`/verify-completeness`(9e++)、bug 根因(9f)、`/coverage-analyze` 根因(9g)、waiver 判定(9g+)
- **保持 high（执行 + 观测 + 机械）**：不加载 `/deep-analysis`，避免为机械任务白烧 max 档 token
  - 跑工具：`make lint`(6b)、`make vcs`(6b+)、`make test-unit`(9c)、`make sim`/`sim-uvm-regr`(9d)、`make coverage` 收集(9g)、`make check`(12)、后仿(13)
  - 观测/核对：检查 PASS/FAIL(9e)、`grep` 残留检查(6f-6i)、环境/spec 存在性检查(0/1)
  - 脚本/配置：改 Makefile/脚本/配置文件
- **默认 high、难点自动顶 max**：`/testcase-gen`(9b)、`/tb-writer`(6d)——生成验证产物，常规模板部分 high；约束设计/覆盖率关键/边界用例等难点由 `/deep-analysis` description 自动匹配顶 max（验证产物错误成本低于 RTL，且有 verify-completeness/coverage/review 多重 max 下游把关）
- **机制**：`/effort` 命令只能手动触发；模型通过 skill/subagent frontmatter `effort` 字段提档。`/deep-analysis` 是"强度旋钮"非工作流，与硬分析 skill 并行加载（CDC 分析 = `/cdc-review` + `/deep-analysis` 同时）。
- **应急**：手动 `/effort max` 即时生效，不受本规则约束。
- **生效前提**：env 段 `CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=1` 已设，强制每次请求带 effort 参数到 GLM 网关（需会话启动时加载，改 env 需重启）。

### 仿真回归 debug 模式（Step 9d/9e 执行约束）

回归 log 巨大（数 MB / 数万行），全篇读撑爆上下文。两类工作分离（判定轴同 effort 调度）：

- **跑回归 + 抽 FAIL 摘要（执行/观测，high）**：`make sim-uvm-regr` 用 `run_in_background: true` 跑，醒后只 grep 关键行，不 Read 整篇 log——可外包 background Bash，不开 subagent
- **根因 debug（分析/决策，max）**：留主会话 + 自动加载 `/deep-analysis`——不放 subagent（verdi 波形无头看不了、丢 spec/CDC/FSM 上下文、打断 run→fail→analyze→fix→rerun 循环）
- **多 test 各自独立失败**：才派 subagent 并行根因，但 **fix 回主会话**（改 RTL 是 max 创造步骤）

log 读取铁律（逐文件 grep 命令表）、回归执行细节见 **`/vcs-sim`「log 读取铁律」段** 与 **`/verify-flow` Step C**。禁止把任何 `sim/` 下产物整篇 Read。

### token 纪律（防上下文膨胀）

实践中 token 大户**往往不是 log**（读 log 走 grep，健康），而是下列项。
按此约束执行，recurring 节省最大：

- **P1 RTL/大文件先 grep 定位再精读**：
  - 想看某段逻辑 → 先 `grep -n "<关键词>" <file>.v` 定位行号，再 Read 带 `offset`/`limit` 只读那 ~20 行
  - **禁止**为看一个函数/一段逻辑就 Read 整个 800+ 行 RTL 文件（regfile 766/seq_fsm 843/top 等）
  - 整篇读仅限"第一次理解新模块"做一次，之后一律 grep+片段
- **P2 不重复注入已加载 skill**：
  - skill 调一次，其规则/规范已在上下文。写第二个/更多模块时**直接复用**，不再调 `/rtl-generator`
  - harness 提示"看到 `<command-name>` 标签说明 skill 已加载，直接执行别再调"——遵守
- **P3 多 agent fan-out 前估成本**（最大隐性 token 放大器）：
  - N 个 subagent × (skill+RTL+spec 底噪) = N 倍底噪。8 个 agent ≈ 24 万 token 纯底噪
  - **机械扫描/逐个修** → 用 background Bash + grep 串行做，零底噪，**不开 subagent**
  - **真 fan-out**（广度审计/多源搜索/多独立根因）才开 subagent，且每个 agent 喂**窄切片**（指明文件+行范围），不让它重读全库
  - 开 subagent 前**先估**：这个任务并行收益 > N×底噪成本吗？不确定就别开
- **P6 Bash/Read 输出封顶**：
  - `find`/`ls`/`grep` 大目录加 `| head -n 20` 或重定向文件后再 grep 摘要
  - 命令输出超预期大时重定向到临时文件，`grep`/`tail` 取摘要进上下文，不直接吞全输出
- **P5 按阶段分会话（提醒用户）**：
  - meta 讨论（流程/配置/skill 优化）和模块开发分不同 session，防长会话滚雪球
  - 这是用户操作习惯，模型无法自动切——见下方"提醒用户"段

> **token 大户治理优先级**：P3(fan-out) > P1(RTL精读) > P2(skill复用) > P6(输出封顶) > P5(分会话)
> 比 log 铁律更该盯——log 已健康，这些才是 recurring 大户。

## 模块理解指引

接触一个新模块时，按以下顺序阅读文件：

1. `spec/` — 规格定义，了解模块的功能需求和时序要求
2. `doc/design/` — 了解模块在整体架构中的位置
3. RTL 文件头注释 — 了解模块的接口和功能
4. RTL 实现代码 — 了解具体逻辑

## Skill 使用

可用 skill 的**完整目录**（name + description）由 harness 每次会话自动注入（见 `available-skills` 列表），运行时据此判断该调哪个——无需在此重复枚举。下表只列**harness description 没有的项目级路由/取舍**：

| Skill | 项目级路由（harness desc 未含） |
| :-- | :-- |
| `/vcs-sim` | 本项目仿真主力；`/modelsim-sim`（Windows/无 VCS）、`/verilator-sim`（无 UVM unit）为备选——仿真器间的选择关系，各 desc 独立表达不了 |
| `/formal-prop-gen` | 与 `/assertion-gen` **去重**——同为 SVA 生成，按 formal/assertion 路径二选一（两个 desc 都没提对方） |
| `/deep-analysis` | effort 旋钮非工作流，详见「推理强度（effort）调度」段（desc 无法指向 CLAUDE 内部锚点） |
| `/skill-creator` | 更新既有 skill 的规范/结构必读其「项目规范更新模式」段（项目特加章节，通用 desc 不含） |

> 提示：调用 skill 用 `/skill-name` 格式；工作流正文按 Step 标注的 skill 执行。
> （adc-design 的项目知识库定位、env-bug↔uvm-debug 边界、using-superpowers 的发现机制，harness description 已各自说清，不在此重复。）

## 问题积累与 Skill 更新规则

每次项目过程中遇到的新问题，按类别记录到对应的 skill 中：

| 问题类别 | 记录到 | 说明 |
|:--|:--|:--|
| **环境/工具/脚本问题** | `/env-bug` | VCS/iverilog/Makefile 兼容性问题 |
| **设计问题** | 项目对应的设计 skill | CDC 遗漏、状态机缺陷、寄存器定义错误等 |
| **用户风格与经验** | `/user-profile-posedge` | 用户的做事风格、设计哲学、关注点、经验总结 |

**更新触发条件**：
- **每次追加新问题后，检查该 skill 上次整理以来的新增条数，≥5 则立即触发整理更新**
- `/user-profile-posedge`：**每个项目阶段结束时**，回顾本阶段的协作情况，补充新的经验、风格观察和关注点
- 用户也可以随时说"更新我的 skill"来触发
- 必须触发整理更新：合并同类问题、补充根因描述、更新预防措施
- 更新后可重置计数器，继续在新项目中使用

> **记录类 skill 的模板化豁免**：env-bug / uvm-debug / adc-design / user-profile-posedge 是
> 「记录类」skill（问题记录/项目专属领域知识/个人经验），内容随项目积累、绑定项目语境。
> **不参与通用 skill 的模板化/去语境化处理**——同步进通用模板（ic_rtl_template）时：
> env-bug/uvm-debug 清空成空容器（删项目案例，留规则头）；adc-design（项目专属）/user-profile-posedge（个人经验）不进通用模板，新项目自建。详见 `/skill-creator`「项目规范更新模式」段。

**结构性/流程级规范更新**（非 bug 记录，如 CDC 新分类、寄存器新规约、effort 调度、
token 纪律、签收报告等）走另一条路径：
- **必经 `/skill-creator`**——更新既有 skill 的规范/结构时，遵守其「项目规范更新模式」段
- 该段定义三层分层（核心规范常驻 / 按需模板外迁 / 记录类）+ 跨文件同步清单 + 禁忌
- **禁止把核心规范外迁**省 token（外迁后生成时不可见，规范违反型 bug 回来）
- **改 skill 必同步**：CLAUDE.md 对应段 / 调度 skill
  衔接 / 外迁处留指引——不允许只改一处（新 skill 放 `.claude/skills/<name>/SKILL.md` 即被 harness 自动发现，无需手动入索引）
- 流程级规范同时更新项目记忆，跨项目不忘

此规则在所有项目中执行。

## Git 规范

- **分支策略**：
  - `main` — 主分支，稳定版本
  - `develop` — 开发分支
  - `feature/*` — 功能分支
  - `bugfix/*` — 修复分支
  - `docs/*` — 文档更新
- **提交格式**：`<type>: <subject>`
  - 类型：`feat`、`fix`、`docs`、`style`、`refactor`、`test`、`chore`
  - 示例：`feat: add user authentication module`
- **PR 规范**：PR 标题遵循提交格式，描述需包含背景、改动内容、测试说明
