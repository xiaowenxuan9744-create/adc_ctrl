# ADC 控制器项目 — Waiver 留痕总账

> 项目级 waiver 总账，跨签收周期累积所有覆盖率/验证 waiver。
> 每条 waiver 的**完整根因**在对应验证报告里，本文件只做索引。
> 维护规则：每次 RTL 变更回归后，复查 waiver 是否仍成立（原不可达路径可能因
> 改动变可达 → 取消 waiver 补覆盖）。

## Waiver 索引

| 编号 | 模块 | 位置 | 覆盖类型 | 登记日期 | 详见 |
|:--|:--|:--|:--|:--|:--|
| WAIVER-001 | adc_seq_fsm | FSM 状态寄存器，转移 ST_LP_PREEMPT(4'h8)→ST_IDLE(4'h0) | FSM transition | 2026-07-15 | `doc/verification_report_20260715.md` §5 |

---

## WAIVER-001：FSM bit[23] = ST_LP_PREEMPT → ST_IDLE

- **位置**：`rtl/adc_seq_fsm.v`，FSM 状态寄存器 `fsm_curr_st`
- **覆盖类型**：FSM transition（VCS FSM coverage bit[23]）
- **当前状态**：未覆盖（FSM 96.97%，32/33 转移覆盖，唯一未覆盖项）
- **功能验证证据**：EDGE_008 PASS（PREEMPT 时异步复位 → FSM 回 IDLE + 恢复正常）；SVA cover `bind_adc_assert.sv:317` 记录 FSM 曾到达 ST_LP_PREEMPT
- **结论**：异步复位路径，VCS O-2018 不追踪异步复位赋值，PREEMPT 单拍窗口无法在仿真中对准复位 → 标 waiver，无需补组合逻辑路径（补了会破坏 PREEMPT 无条件进 HP_SAMPLE 发 SOC 的设计意图）
- **完整根因**：见 `doc/verification_report_20260715.md` §5（设计事实 / 报告表象 / 时序窗口 / VCS 工具局限 / 重构副作用五段分析）

### 复查触发

- RTL 涉及 `adc_seq_fsm` 状态转移逻辑改动 → 复查本 waiver 是否仍成立
- VCS 版本升级（O-2018 → 更高）→ 复查新版本是否已支持异步复位转移覆盖，若支持则取消 waiver 补覆盖
- overflow 检测逻辑位置再次迁移 → 复查 VCS 是否重新提取该转移为可覆盖路径

### 复查记录

- **2026-07-21**（`doc/verification_report_2026-07-21.md` §6）：`10c2f57..b75842f`
  7 个提交中 `40c9648`/`9d4cd14`/`0a002eb` 触及 `adc_seq_fsm.v`，但改动为
  seq_ptr/entry 存储与位宽参数化，**未涉及 PREEMPT 状态转移逻辑**（FSM 状态机
  本身不变）。`sim-uvm-regr` 18 case PASS、`adc_boundary_test` 的 EDGE_008 用例
  无回归 → **WAIVER-001 仍成立，无需取消**。
