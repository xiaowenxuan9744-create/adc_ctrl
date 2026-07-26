# ADC 控制器 — 数字 IC 设计项目

本 ADC（模数转换器）数字控制器项目，使用 AI 辅助设计（Claude Code）完成从规格定义到综合签收的全流程数字前端设计。设计方法论与可复用 skill 资产见 [`CLAUDE.md`](CLAUDE.md) 与 `.claude/skills/`。

## 项目状态

| 阶段 | 状态 |
|:--|:--:|
| RTL 设计 | ✅ 9 模块（~2,609 行） |
| 单元测试 | ✅ 3 TB（26ch/8ch/32ch） |
| UVM 回归 | ✅ 18 case, 0 failed |
| 覆盖率 | ✅ Line 98.51%, FSM 96.97% |
| 签收报告 | ✅ 3 份（07-15 / 07-20 / 07-21）+ 后仿报告 |
| DC 综合（TSMC28HPC+） | ✅ tt + ssg 双角, 0 setup DRC 违例 |
| PT STA | ✅ tt + ssg, 0 setup/hold 违例 |
| Formality | ✅ 1003 compare points |
| 后仿（零延迟 + SDF） | ✅ tt/ssg, 35/35 + UVM 18/18 |

## 关键规格

| 项目 | 规格 |
| :-- | :-- |
| 开发语言 | Verilog / SystemVerilog |
| 仿真工具 | iverilog 11 / VCS O-2018.09-SP2 |
| 波形查看 | Verdi O-2018.09 |
| 综合工具 | Design Compiler O-2018.06 (TSMC28HPC+ PDK) |
| STA | PrimeTime O-2018.06 |
| 形式验证 | Formality O-2018.06 |
| AI 辅助 | Claude Code（AI 辅助设计） |

## 功能特性

- **参数化设计**：通道数 4~32、数据位宽 1~16、SPT1 通道位图可配
- **双优先级采样**：普通优先（N 条目） + 高优先（4 条目），HP 可抢占 LP
- **多种触发**：软件触发 / MCTM 硬件触发，LP/HP 各独立配置
- **双时钟架构**：PCLK（最高 200 MHz）+ ADC_CLK/ADC_CLKn（最高 60 MHz，同源反相）
- **DMA 请求**：单次完成 / 序列完成
- **中断**：6 个事件源，独立使能
- **自校准** + VALID 标志 + 溢出检测

## 模块层次

```
adc_top
├── adc_params.vh     — 参数化派生 localparam 集中定义
├── adc_rst_sync      — 异步复位同步器
├── adc_apb_if        — APB 32-bit 零等待接口
├── adc_regfile       — 双时钟域寄存器堆（参数化 LP_DATA/LP_SEQ 数）
├── adc_trig_sync     — MCTM + SW 触发同步与源选择
├── adc_seq_fsm       — 核心序列 FSM（HP 抢占、SOC/MUXON 时序）
├── adc_int_ctrl      — 中断控制器
├── adc_dma_req       — DMA 请求控制器
├── adc_calib         — 已废弃 stub（逻辑移入 regfile PCLK 域）
└── adc_sync_cell     — 2 级同步器 + 边沿检测
```

## 快速开始

```bash
make help              # 显示所有可用目标
make lint              # RTL 语法检查（iverilog，15 模块）
make vcs               # VCS 编译
make test-unit         # 运行单元测试
make sim               # VCS 编译 + 仿真 + 波形
make sim-uvm-regr      # UVM 回归（18 case）
make gate-sim          # 后仿（零延迟）
make gate-sim-sdf      # 后仿（SDF 反标）
make gate-sim-uvm-regr # UVM 门级回归
make check             # lint + vcs + test-unit + sim-uvm-regr 全流程
```

## 验证结果

| 检查项 | 结果 |
|:--|:--:|
| `make lint`（iverilog -g2012，15 模块） | ✅ 0 error, 0 warning |
| `make vcs` | ✅ PASS |
| `make test-unit`（3 TB） | ✅ 3/3 PASS |
| `make sim-uvm-regr`（18 case） | ✅ 18 passed, 0 failed |
| Line Coverage | 98.51% |
| FSM Coverage | 96.97%（1 waiver） |
| Condition Coverage | 94.74% |
| Toggle Coverage | 96.03% |
| 后仿（unit TB 35 检查点） | ✅ 35/35 PASS |
| 后仿（UVM gate sim） | ✅ 18/18 PASS |

## 文档

| 文档 | 说明 |
|:--|:--|
| [`spec/adc_spec.md`](spec/adc_spec.md) | 完整规格文档（接口定义、寄存器映射、时序） |
| [`spec/testplan_adc.md`](spec/testplan_adc.md) | 144 测试点验证计划 |
| [`doc/user_guide.md`](doc/user_guide.md) | 用户指南（接口/寄存器/初始化流程） |
| [`doc/project_config.md`](doc/project_config.md) | 项目配置（模块层次/时钟域/验证环境） |
| [`doc/cdc_review_report.md`](doc/cdc_review_report.md) | CDC 检查报告 |
| [`doc/consistency_check_report.md`](doc/consistency_check_report.md) | 五端一致性检查报告 |
| [`doc/verification_report_20260715.md`](doc/verification_report_20260715.md) | 验证签收报告（v1） |
| [`doc/verification_report_2026-07-20.md`](doc/verification_report_2026-07-20.md) | 参数化签收报告 |
| [`doc/verification_report_2026-07-21.md`](doc/verification_report_2026-07-21.md) | 增量签收报告 |
| [`doc/post_sim_report_2026-07-22.md`](doc/post_sim_report_2026-07-22.md) | 后仿真签收报告 |
| [`doc/waiver.md`](doc/waiver.md) | Waiver 留痕总账 |

## 经验资产

本项目沉淀了 **41 个设计/验证 skill**（`.claude/skills/`），可在后续数字 IC 项目中复用：

| 类别 | 技能 |
|:--|:--|
| 设计生成 | rtl_generator, doc_generator, regmap_gen, testplan_gen |
| 设计检查 | rtl_reviewer, cdc_review, consistency_check, lint_manager, timing_review |
| 验证 | tb_writer, testcase_gen, verify_flow, coverage_analyze, verify_completeness |
| 工具链 | vcs_sim, sdc_manager, syn_handoff |

## 参考

- [CLAUDE.md](CLAUDE.md) — 项目工程规范与工作流
- `doc/design/2026-07-20-parameterization-design.md` — 参数化设计文档
