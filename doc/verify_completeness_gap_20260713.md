# 验证完整性 gap 分析报告 — adc_top — 2026-07-13

> 由 `/verify-completeness` skill 生成。基于 spec↔testplan↔sequence 三层逐项核对。
> G3 矛盾已决策：CAL_003 改测并行不冲突、CAL_004/005 改测电平跟随（spec §3.7 为最高权威）。

## 完整性判定

**❌ 不充分** —— G1/G2 有 P0 项，覆盖率从未收集。testplan 标 63 点全 ✅ 但 18 点未真实现/测错，10 个 spec 功能点无测试点。

---

## Gap 清单

### G1 spec 有 / testplan 无（10 项）

| # | 功能点 | spec 位置 | 可测? | 补测试点建议 |
|:--|:--|:--|:--:|:--|
| G1.1 | preempt_rst_n 先于 HP SOC 至少 1 周期 | §2.3+§4.4 | 是 | 补 SVA（bind_adc_assert.sv）+ 定向 cover |
| G1.2 | INTERVAL 时机抢占（ST_LP_INTERVAL→PREEMPT） | §4.4 FSM 转移表 | 是 | 补 SMP_020_INTERVAL 独立测试点 |
| G1.3 | TRG_SEL=ecc(4'h7)/tue(4'h8) 触发源 | §3.4+§4.5 | 是 | 补 TRG_010/TRG_011 |
| G1.4 | 60MHz/3Msps 采样率上限 | §1.1+§2.2 | 否 | 标"验证范围外"（仿真 25MHz，上限由 STA 确认） |
| G1.5 | 32 通道预留边界 CH_DATA[26:31]/LP_SEQ_LEN 27~32 | §1.1+§3.11+§3.14 | 是 | 补 SMP_022（26 通道全序列）+ REG_009（CH_DATA[26:31]） |
| G1.6 | preempt_hold 防回退独立验证 | §4.4 ch_sel 切换 | 是 | 补 SMP_023（抢占后 muxon_fall 不回退 lp_ch_sel） |
| G1.7 | CAL_INTRG 校准与采样并行 | §3.7 | 是 | 改 CAL_003 预期为"并行不冲突"（G3.1 决策） |
| G1.8 | 任意通道 overflow 共享同一 OVERRUN | §3.11 | 是 | 补 INT_010（多通道 overflow 共享） |
| G1.9 | SPT1（CH21/CH22 采样时间档位） | §3.2 | 是 | 补 SMP_024（SPT1≠SPT0 + CH21/CH22） |
| G1.10 | DMA 4 个独立使能位（LP_SEQ/HP_EOC/HP_SEQ/OVERRUN） | §3.12 | 是 | 补 DMA_007~DMA_010 |

### G2 testplan 有 / sequence 未实现或不符（18 项）

| # | 测试点 ID | 状态 | 问题 | 修正方式 |
|:--|:--|:--|:--|:--|
| G2.1 | REG_001 | ✅ | 只测 8 个寄存器默认值，缺 CH_DATA[0:31]/LP_SEQ[0:7]/STAT/INT_STAT/CAL_CTRL/DMA_STAT | 扩展 adc_reg_seq 覆盖全寄存器 |
| G2.2 | REG_002 | ✅ | 缺 LP_SEQ1~7 写后读 | 扩展 write_read_reg 循环 LP_SEQ0~7 |
| G2.3 | REG_004 | ✅ | WO 自清零（TRIG SW_TRIG 读回 0）未验证 | 触发 SW_TRIG 后读 TRIG 验证 bit0/bit8=0 |
| G2.4 | REG_007 | ✅ | 跨域 VALID 清零时序未验证（仅 PCLK 域） | 补 ADC_CLK 域 VALID 清零时序检查 |
| G2.5 | REG_008 | ✅ | CH_DATA RO 写保护未测 | 补 adc_boundary_seq CH_DATA 写保护 |
| G2.6 | RST_001 | ✅ | 无独立硬件复位测试点（仅上电间接） | 补独立 hw_reset + 全寄存器复位值检查 |
| G2.7 | SMP_002 | ✅ | 随机 3 通道，非 testplan 指定 {CH5,CH10,CH15} | 修正 adc_sequence_seq 用 {CH5,CH10,CH15} |
| G2.8 | SMP_003 | ✅ | 26 通道全序列完全未实现 | 补 LP_SEQ_LEN=26 + LP_SEQ[0:6] 全配置 |
| G2.9 | SMP_012 | ✅ | LP+HP 混合序列未实现 | 补 LP 序列完成→HP 序列 |
| G2.10 | SMP_013 | ✅ | ID 错配（功能在 DATA_002 实现） | 统一 ID：DATA_002 改标 SMP_013 |
| G2.11 | SMP_019 | ✅ | EOC 电平粘着完全未实现 | 补 ovrd_force_eoc 多周期高 + 检查只触发一次 |
| G2.12 | SMP_021 | ✅ | 非法 FSM 状态直接跳过（[INFO] not runnable） | 补 force 注入 4'h9~F + 验证回 IDLE |
| G2.13 | CAL_003 | ✅ | 实现不符（测的是清 CAL_ST，非校准中触发） | 改预期为"并行不冲突"（G3.1）+ 补并行测试 |
| G2.14 | CAL_004 | ✅ | 实现不符（测的是重校准，非电平粘着） | 改预期为"电平跟随"（G3.2）+ 补多周期电平检查 |
| G2.15 | CAL_005 | ✅ | 实现不符（测的是 ADC_EN=0，非 sticky 位） | 改预期为"CAL_DONE 跟随 cal_st 电平"（G3.2） |
| G2.16 | TRG_007 | ✅ | 伪实现（只 [INFO] 无 PASS/FAIL） | 补 mctm 毛刺过滤的 PASS/FAIL 判定 |
| G2.17 | TRG_008 | ✅ | 伪实现（只发触发未验证 CH_DATA VALID） | 补 apb_read CH_DATA 检查 VALID |
| G2.18 | TRG_009 | ✅ | 伪实现（未验证 HP 优先、LP 被屏蔽） | 补 HP 采样完成 + LP 未采样检查 |

### G3 testplan 预期 vs RTL/spec 不符（2 项，已决策）

| # | 测试点 | testplan 预期 | RTL 实现 | spec 定义 | 决策 |
|:--|:--|:--|:--|:--|:--|
| G3.1 | CAL_003 | 校准优先，采样等待 | FSM 不检查 cal_st，并行 | §3.7"控制器不强制屏蔽，软件责任" | **改 testplan**：测并行不冲突 |
| G3.2 | CAL_004/005 | CAL_DONE sticky 位 | 电平跟随 cal_done_s2 | §3.7"持续稳定电平" | **改 testplan**：测电平跟随 |

---

## 补验清单

### P0（阻塞签收）

1. **preempt_rst_n 时序 SVA**（G1.1）—— bind_adc_assert.sv 加 `p_preempt_rst_before_soc` 断言 + 纳入 UVM 回归编译
2. **INTERVAL 时机抢占**（G1.2）—— 补 SMP_020，LP 多通道+SMPL_INTERVAL 间隙触发 HP
3. **DMA 4 个独立使能位**（G1.10）—— 补 DMA_007(LP_SEQ)/DMA_008(HP_EOC)/DMA_009(HP_SEQ)/DMA_010(OVERRUN)
4. **26 通道全序列**（G2.8/G1.5）—— 补 SMP_003 真实现
5. **跑覆盖率收集**—— `make sim-uvm-regr-cov` + `make coverage`，先拿真实数字
6. **5 个 _full test 纳入回归**—— calib_full/reset_full/trig_full/int_full/dma_full 已编写但未在 UVM_TESTS

### P1（影响覆盖率达标）

7. **ecc/tue 触发源**（G1.3）—— 补 TRG_010/TRG_011，TRG_SEL=4'h7/4'h8 + mctm_trig[0]/[1]
8. **CAL_003 并行测试**（G2.13/G3.1）—— CAL_ST=1 + 触发采样，验证并行不冲突
9. **CAL_004 电平跟随**（G2.14/G3.2）—— cal_done 多周期高，验证 CAL_CTRL[1] 跟随
10. **CAL_005 电平跟随清零**（G2.15/G3.2）—— CAL_ST=0 后 CAL_CTRL[1] 跟随回 0
11. **SMP_019 EOC 电平粘着**（G2.11）—— ovrd_force_eoc 多周期高 + 只触发一次
12. **SMP_021 非法 FSM 状态**（G2.12）—— force 注入 4'h9~F + 验证回 IDLE
13. **SPT1 CH21/CH22**（G1.9）—— SPT0≠SPT1 + LP 含 CH21/CH22 + 测 MUXON 宽度
14. **CONT_MODE + HP 抢占组合**—— 连续模式下 HP 抢占，LP 恢复后仍循环
15. **preempt_hold 防回退**（G1.6）—— 抢占后 muxon_fall 不回退 lp_ch_sel
16. **6 中断源逐位门控反向**—— 使能位 X=1 其他=0，触发事件 Y≠X，验证 adc_int 不拉
17. **任意通道共享 OVERRUN**（G1.8）—— 多通道 overflow 触发同一 OVERRUN

### P2（实现完整性修正）

18. **REG_001 全寄存器默认值**（G2.1）—— 扩展 adc_reg_seq 覆盖全部寄存器
19. **REG_002 LP_SEQ1~7 写后读**（G2.2）
20. **REG_004 WO 自清零**（G2.3）—— 触发 SW_TRIG 后读 TRIG bit0/bit8=0
21. **REG_007 跨域 VALID 清零时序**（G2.4）
22. **REG_008 CH_DATA RO 写保护**（G2.5）
23. **RST_001 独立硬件复位**（G2.6）
24. **SMP_002 修正为 {CH5,CH10,CH15}**（G2.7）
25. **SMP_012 LP+HP 混合序列**（G2.9）
26. **SMP_013 ID 错配修正**（G2.10）—— DATA_002 改标 SMP_013
27. **TRG_007/008/009 补 PASS/FAIL 判定**（G2.16/17/18）
28. **CH_DATA[26:31] 边界**（G1.5）—— REG_009

---

## 必须补的验证项（签收前）

P0 全部 6 项 + P1 全部 11 项 + P2 全部 11 项 = 28 项补/修正。
执行顺序按 `/verify-flow` 主线：改 testplan → testcase_gen 补 case → vcs_sim 回归 → coverage 收集 → coverage_analyze 闭环。
