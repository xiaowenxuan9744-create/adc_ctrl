# RTL 代码评审报告 — adc_seq_fsm.v SOC/MUXON 时序改动

## 基本信息

| 项目 | 内容 |
|:--|:--|
| **模块名** | adc_seq_fsm |
| **文件路径** | rtl/adc_seq_fsm.v |
| **评审日期** | 2026-07-05 |
| **评审范围** | SOC/MUXON 产生逻辑（line 312~386），新增 CDC 路径 |
| **评审类型** | 增量审查（非全量） |

## 评审结果汇总

| 维度 | Error | Warning | Info |
|:--|:--:|:--:|:--:|
| 文件结构与注释 | 0 | 0 | 1 |
| 命名规范 | 0 | 0 | 0 |
| 可综合性 | 0 | 0 | 0 |
| 时钟与复位 | 0 | 1 | 0 |
| 组合逻辑 | 0 | 0 | 0 |
| 时序逻辑 | 0 | 0 | 0 |
| **跨时钟域** | **0** | **0** | **0** |
| 资源与性能 | 0 | 0 | 0 |
| **总计** | **0** | **1** | **1** |

---

## 问题详情

### [WARNING-001] 复位 rst_adc_n 跨时钟域使用

- **位置**: Line 323, 352
- **代码**: `always @(posedge adc_clkn or negedge rst_adc_n)`
- **描述**: `rst_adc_n` 是在 `posedge adc_clk` 域产生的同步复位信号，被直接用在 `posedge adc_clkn` 的 always 块中。`adc_clkn` 与 `adc_clk` 是**同频反相关系**，`rst_adc_n` 在 `posedge adc_clk` 释放后，`posedge adc_clkn` 在半周期后采到其新值。
- **影响分析**:
  - 复位**断言**（release）时：`rst_adc_n` 高有效 → `adc_clkn` 域在半周期后采样到，寄存器同步退出复位
  - 复位**置位**（assertion）时：异步立即复位（敏感列表包含 `negedge rst_adc_n`），无时序问题
  - 这实际等价于在一个周期内完成同步，对于同频反相关来说足够可靠
- **建议**: 
  - 对于同频反相关这种处理是安全的。`rst_adc_n` 本身就是 `adc_rst_sync` 2级同步器输出的，无亚稳态风险。
  - 如果综合工具对此报异步复位移除（asynchronous reset removal）违例，可加约束标注 `adc_clkn` 与 `adc_clk` 的关系，或对 `rst_adc_n` 在 `adc_clkn` 域再做一级同步。

### [INFO-001] CDC 方案一致性

- **位置**: Line 334~349（SOC 同步）, Line 366~376（MUXON 同步）
- **描述**: SOC 用 2-stage + edge detect（脉冲信号），MUXON 用 2-stage（电平信号），策略正确。
- **说明**: SOC 产生在 `posedge adc_clkn`，同步到 `posedge adc_clk` 域输出。由于两时钟同频反相，SOC 脉冲在 `adc_clkn` 域产生后，经过 2-stage 同步器（`soc_s1`, `soc_s2`）回到 `adc_clk` 域，再通过 `soc_dly` 做边沿检测恢复单周期脉冲。这种方案对同频反相域来说裕量很大（信号稳定半周期后才被采样）。

---

## CDC 路径检查

| 路径 | 类型 | 处理 | 状态 |
|:--|:--:|:--|:--:|
| `soc_req_set` → `adc_clkn` 域 | 组合→反相沿 | 直接使用（~8.3ns 建立窗口） | ✅ 安全 |
| `soc_pulse_clkn` → `adc_clk` 域 | 脉冲→同相沿 | 2-stage + edge detect | ✅ 正确 |
| `muxon_reg` → `adc_clk` 域 | 电平→同相沿 | 2-stage 同步器 | ✅ 正确 |
| `spt_done` / `preempt_abort` → `adc_clkn` 域 | 组合→反相沿 | 直接使用（~8.3ns 建立窗口） | ✅ 安全 |

---

## 代码质量评分

| 维度 | 评分 |
|:--|:--:|
| 可综合性 | ⭐⭐⭐⭐⭐ |
| CDC 设计 | ⭐⭐⭐⭐⭐ |
| 注释完整性 | ⭐⭐⭐⭐☆ |
| **综合评分** | **95/100** |

**结论: ✅ 通过** (0 Error, 1 Warning, 1 Info)
