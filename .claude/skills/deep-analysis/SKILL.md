---
name: deep-analysis
description: 用于需要最深推理的硬分析任务——FSM 状态/转移分析、CDC 跨域路径与时序分析、时序收敛与关键路径分析、覆盖率未覆盖点根因分析、多端一致性(spec↔RTL↔SDC↔regmap↔TB)审计、架构级重构决策、复杂 bug 根因定位。当任务需要权衡多种设计可能、追踪跨模块跨域副作用、或确认"不可达"而非"没测到"时自动激活。
effort: max
---

# Deep Analysis — 深度分析模式

本 skill 的唯一作用是把推理强度顶到 **max**（覆盖会话基准 high）。
当遇到下列硬分析任务时自动加载，做完自动回退到会话基准。

> **机制**（官方 skills frontmatter）：`effort` 字段在该 skill 激活期间覆盖
> 会话 effort 级别。无需用户手动 `/effort max`。

## 何时自动加载

任务命中以下任一类别时，应加载本 skill：

| 类别 | 典型任务 |
|:--|:--|
| RTL 编码（核心） | CDC 同步器选型/级数、FSM 状态转移完备性、时序沿/时钟域归属、寄存器位域、组合逻辑深度与 latch、复位策略——rtl-generator 生成的全部设计决策 |
| 规格与设计决策 | 需求澄清、spec 生成、接口时序完备性、域归属表、验证计划制定、设计实现计划 |
| FSM 分析 | 状态/转移完备性、不可达转移判定、复位路径与组合路径区分、状态编码正确性 |
| CDC 分析 | 跨域路径同步器类型判定、同源同步时钟 vs 异步时钟区分、握手/Gray/FIFO 选型、复位 CDC |
| 时序分析 | 关键路径级数、建立/保持、半周期路径、综合约束可综合性 |
| 覆盖率根因 | 未覆盖点判定是"真不可达"(waiver) 还是"没测到"(补 case)、工具局限 vs 设计缺口 |
| 一致性审计 | spec↔RTL↔SDC↔regmap↔TB 五端矛盾溯源、G3 决策(先定 spec 真相) |
| 架构决策 | 寄存器架构重构、数据通路重构、域归属重画、多方案权衡与资源代价比较 |
| 复杂根因 | 跨模块/跨域 bug、NBA 时序竞态、force/stash 验证设计、重构副作用溯源 |
| testcase/tb 难点 | 约束设计、覆盖率关键/边界用例、时序检查点（非模板部分自动匹配） |

## 核心判定：RTL 编码是最该顶 max 的步骤

设计流程里 **rtl-generator(6a) 是唯一无安全网的创造步骤**——RTL 是要流片的产物，所有设计正确性都在此决定：CDC 同步器选错、FSM 转移漏分支、时钟域归属画错、寄存器位域错位、组合逻辑吃出 latch、复位策略不当……这些 bug 全在编码时烙入。

下游的 cdc-review/consistency-check/timing-review/coverage-analyze 都是**事后发现**（lint+review+UVM+覆盖率+一致性五道过滤），但 RTL 编码没有前置安全网。本项目历次 debug 根因全可回溯到编码决策：
- CDC 过同步（272 flop 浪费）— 编码时把同源同步时钟当 CDC
- overflow 检测域错位 → bit[23] waiver — 编码时域归属画错
- SW_TRIG 脉冲丢失 — 编码时漏跨域脉冲同步
- NBA 数据捕获错序 — 编码时忽略 NBA 时序
- EOC 首次捕获 0 — 编码时数据通路没加 pipeline

→ **RTL 编码顶 max 是投入产出比最高的**：一个编码期避免的 bug，省下游多个 review/coverage/UVM 循环。

对比，跑 make lint/vcs/sim/coverage、检查 PASS/FAIL、改脚本配置、grep 残留——这些是执行/观测，不创造正确性，保持 high 即可。

## 激活后的分析纪律

加载本 skill 意味着进入"最审慎"模式，遵守：

1. **不下快结论**：先穷举设计可能，再逐个排除，给推荐而非第一直觉。
2. **逐信号/逐状态验证**：FSM 逐状态审 next_st 组合逻辑；CDC 逐信号判 sync 属性；一致性逐端比对。
3. **区分事实与表象**：覆盖率报告的数字是表象，RTL 组合逻辑才是事实——表象与事实不符时(如 bit[23])，把两者都说清。
4. **不可达 vs 没测到**：覆盖率 hole 先 verify-completeness 确认性质，再决定 waiver/补 case/删死代码。
5. **追溯副作用**：重构改动的"重构前能覆盖/重构后不能"类副作用，要追溯到 VCS 提取逻辑变化等工具行为。
6. **留痕**：结论涉及 waiver/架构决策时，写入 doc 报告，不留在对话记忆。

## 与其他 skill 的区别

- 这是**推理强度旋钮**，不是工作流——不产出文档骨架，只确保分析过程用 max。
- 真正的分析内容仍按对应 skill 做：CDC 分析用 `/cdc-review`、覆盖率用 `/coverage-analyze`、一致性用 `/consistency-check`、RTL 编码用 `/rtl-generator`。本 skill 让那些步骤跑在 max 档（并行加载）。
- **RTL 编码（rtl-generator）时必加载**——编码是唯一无安全网的创造步骤，下游 review/cdc/consistency 都是事后发现。
- 简单任务(跑 make/批量替换/格式化/grep 残留/改脚本配置/看 PASS-FAIL)不要加载本 skill——会白耗 token。
