# 验证计划 — ADC 控制器（合并版）

> 由 /testplan-gen 重新生成 + 旧 testplan ID 映射 + sequence 实现状态回填。
> 生成方式：3 agent 并行分析（功能 115 + RTL 149 + 边界 27 = 144 测试点）。
> 状态回填：旧 ID 在 sequence 真命中且 PASS → ✅；未命中 → 空；实现不符 → ❌。
> 新增测试点（TIM_/EDGE_/部分 REG_）状态全空（待实现）。

## 1. 概述
- **模块名**: ADC 控制器（adc_top）
- **验证阶段**: 顶层集成验证
- **验证方法**: UVM 随机验证 + 定向测试 + SVA 断言

## 2. 功能特性

| 特性 | 描述 | 优先级 |
|:--|:--|:--:|
| 寄存器 | APB 32-bit 读写、复位默认值、RO/W1C/WO/RSVD 属性 | P0 |
| 接口 | SOC/EOC/MUXON/ch_sel/cal_st/cal_done/preempt_rst_n 时序 | P0 |
| 功能模式 | 单次/连续转换、LP/HP 序列、HP 抢占 | P0 |
| 时序 | 采样流程11步、SPT 档位、SMPL_INTERVAL、preempt 时序链 | P0 |
| 参数 | 参数化通道数/ADC位宽/SPT1位图，默认 26/14 向后兼容；3Msps、双时钟 | P1 |

## 3. 测试点清单

共 144 个测试点。状态：✅=已实现且 PASS | 空=待验证 | ❌=实现不符。

### 3.1 寄存器测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| REG_APB32 | REG_001/002 | APB 32-bit 零等待读写所有寄存器 | 全寄存器读写 | 读回=写入值 | P0 | §2.1,§3.1 | ✅ |
| REG_ADDR_MAP | REG_006 | 地址映射 0x00~0xD4 | 逐地址访问 | 有效地址返回数据，无效返回0 | P1 | §3.1,§7 | ✅ |
| REG_CTRL_ADC_EN | SMP_015 | ADC_EN 全局使能 | 采集中写 ADC_EN=0 | 当前序列完成后停止 | P0 | §3.2 | ✅ |
| REG_CTRL_SW_RST | RST_002 | SW_RST 软件复位自清零 | 写 CTRL[1]=1 | 复位所有寄存器，SW_RST 自清零 | P0 | §3.2,§6.1 | ✅ |
| REG_CTRL_DATA_ALIGN | SMP_013/REG_012 | DATA_ALIGN 左/右对齐 | 切换对齐方式采样 | 数据位域符合对齐 | P1 | §3.2 | ✅ |
| REG_CTRL_RSVD | REG_005 | CTRL 保留位读0写忽略 | 读 RSVD 位 | 返回0 | P1 | §3.2 | ✅ |
| REG_CTRL_SMPL_INTERVAL | SMP_009 | SMPL_INTERVAL 采样间隔 | interval=0/128 边界 | 间隔符合预期 | P1 | §3.2 | ✅ |
| REG_CTRL_SPT0 | SMP_008 | SPT0 采样时间档位0 | SPT0=0(3cyc)/7(240cyc) | MUXON 宽度符合 | P0 | §3.2 | ✅ |
| REG_CTRL_SPT1 | SMP_024 | SPT1 采样时间档位1(CH21/22) | SPT1≠SPT0，采样CH21/22 | CH21/22 用 SPT1 | P1 | §3.2 | ✅ |
| REG_CTRL_CONT_MODE | SMP_014 | CONT_MODE 连续模式 | CTRL[14]=1 触发 | 序列完成后自动重启 | P1 | §3.2 | ✅ |
| REG_STAT_ADC_BUSY | SMP_018 | STAT[0] ADC_BUSY | 采样中读 STAT | 正确反映 FSM 状态 | P1 | §3.3 | ✅ |
| REG_STAT_LP_BUSY | SMP_018 | STAT[1] LP_BUSY | LP 序列中读 | LP_BUSY=1 | P1 | §3.3 | ✅ |
| REG_STAT_HP_BUSY | SMP_018 | STAT[2] HP_BUSY | HP 序列中读 | HP_BUSY=1 | P1 | §3.3 | ✅ |
| REG_STAT_CAL_BUSY | — | STAT[3] CAL_BUSY | 校准中读 STAT | CAL_BUSY=1 | P1 | §3.3 | ✅ |
| REG_TRIG_LP_SW_TRIG | REG_004 | LP_SW_TRIG WO 自清零 | 写 TRIG[0]=1 | 触发采样，读回 bit0=0 | P0 | §3.4 | ✅ |
| REG_TRIG_HP_SW_TRIG | REG_004 | HP_SW_TRIG WO 自清零 | 写 TRIG[8]=1 | 触发HP采样，读回 bit8=0 | P0 | §3.4 | ✅ |
| REG_TRIG_LP_SW_TRG_EN | TRG_004 | LP_SW_TRG_EN 使能门控 | EN=0 写 SW_TRIG | 不触发 | P0 | §3.4 | ✅ |
| REG_TRIG_HP_SW_TRG_EN | TRG_004 | HP_SW_TRG_EN 使能门控 | EN=0 写 HP_SW_TRIG | 不触发 | P0 | §3.4 | ✅ |
| REG_TRIG_LP_MCTM_EN | TRG_005 | LP_MCTM_EN 使能门控 | EN=0 外部脉冲 | 不触发 | P0 | §3.4 | ✅ |
| REG_TRIG_HP_MCTM_EN | TRG_005 | HP_MCTM_EN 使能门控 | EN=0 外部脉冲 | 不触发 | P0 | §3.4 | ✅ |
| REG_TRIG_LP_TRG_SEL | TRG_002/010/011 | LP_TRG_SEL 源选择(含ecc/tue) | TRG_SEL=0~8 循环 | 对应 mctm 触发 | P0 | §3.4 | ✅ |
| REG_TRIG_HP_TRG_SEL | TRG_013 | HP_TRG_SEL 源选择(含ecc/tue) | TRG_SEL=0~8 循环 | 对应 mctm 触发 | P0 | §3.4 | ✅ |
| REG_TRIG_RSVD | REG_005 | TRIG 保留位读0 | 读 RSVD 位 | 返回0 | P1 | §3.4 | ✅ |
| REG_INT_EN_6BITS | REG_011/INT_007 | INT_EN 6 位独立使能 | 逐位写1/读回 | 各位独立读写 | P0 | §3.5 | ✅ |
| REG_INT_STAT_W1C | INT_008/REG_010 | INT_STAT W1C 写1清零 | 写1到各bit | 对应位清零 | P0 | §3.6 | ✅ |
| REG_INT_STAT_RDONLY | INT_007 | INT_STAT 读反映事件状态 | 事件后读 | 对应位置1 | P1 | §3.6 | ✅ |
| REG_CAL_CTRL_CAL_ST | CAL_001/REG_014 | CAL_ST RW 置1/清0 | 写CAL_CTRL[0] | cal_st 跟随 | P0 | §3.7 | ✅ |
| REG_CAL_CTRL_CAL_DONE | CAL_004/005 | CAL_DONE RO 电平跟随 | cal_done 高时读 | CAL_CTRL[1]=1跟随 | P0 | §3.7 | ✅ |
| REG_CAL_VAL | CAL_002/REG_014 | CAL_VAL RO 锁存 | 校准后读 | CAL_VAL=模拟返回值 | P0 | §3.8 | ✅ |
| REG_ANA_CFG | REG_001/002 | ANA_CFG RW | 写随机值读回 | 读回=写入 | P1 | §3.9 | ✅ |
| REG_ANA_REG | REG_001/002 | ANA_REG RW | 写随机值读回 | 读回=写入 | P1 | §3.10 | ✅ |
| REG_CH_DATA_VALID | REG_007 | CH_DATA VALID 读清除 | 采样后读CH_DATA+uvm_hdl_read跨域 | VALID 1→0,ADC_CLK域清零 | P0 | §3.11 | ✅ |
| REG_CH_DATA_DATA | SMP_013/DATA_002 | CH_DATA DATA 对齐 | 左/右对齐采样 | DATA 位域符合 | P0 | §3.11 | ✅ |
| REG_CH_DATA_RANGE | REG_009/REG_013 | CH_DATA[0:31] 地址范围 | 读CH_DATA[26:31] | 地址译码覆盖 | P1 | §3.11 | ✅ |
| REG_DMA_CTRL_6BITS | DMA_001~010/REG_011 | DMA_CTRL 6 位独立使能 | 逐位使能+触发 | 对应事件触发 dma_ndreq | P0 | §3.12 | ✅ |
| REG_DMA_STAT_BUSY | DMA_014 | DMA_STAT[0] DMA_BUSY | 请求活跃时读 | DMA_BUSY=1(sync lag容忍) | P1 | §3.13 | ✅ |
| REG_DMA_STAT_DONE | DMA_015 | DMA_STAT[1] DMA_DONE | ack后读 | DMA_DONE=1(async容忍) | P1 | §3.13 | ✅ |
| REG_LP_SEQ | REG_002 | LP_SEQ[0:7] RW | 各寄存器写读 | 读回=写入 | P0 | §3.14 | ✅ |
| REG_HP_SEQ | REG_002/SMP_005 | HP_SEQ RW | 写4通道读回 | 读回=写入 | P0 | §3.15 | ✅ |
| REG_LP_SEQ_LEN | REG_001/SMP_003 | LP_SEQ_LEN 默认26 可配1~32 | 写LEN=26/32读回 | 读回=写入 | P0 | §3.16 | ✅ |
| REG_HP_SEQ_LEN | REG_001 | HP_SEQ_LEN 默认4 可配1~4 | 写LEN=4读回 | 读回=写入 | P0 | §3.17 | ✅ |
| REG_SPT_ENCODING | SMP_008/024 | SPT 8档编码映射 | 逐档配置 | MUXON 宽度符合档位 | P1 | §3.2 | ✅ |

### 3.2 采样测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| SMP_FLOW | SMP_001 | 采样流程11步端到端 | SW_TRIG单通道 | SOC→EOC→CH_DATA VALID=1 | P0 | §4.1 | ✅ |
| SMP_SINGLE | SMP_001 | 单次转换模式 | 序列执行一轮 | 完成后回 IDLE | P0 | §4.2 | ✅ |
| SMP_CONT | SMP_014 | 连续转换模式 | CTRL[14]=1触发 | 序列完成自动重启 | P1 | §4.3 | ✅ |
| SMP_PRECISION_14BIT | — | 14-bit ADC 精度 | 全量程采样 | adc_data[13:0] 完整 | P1 | §1.1 | ✅ |
| SMP_CH_RANGE | SMP_002/003 | 26通道+32预留 | LP_SEQ={CH5,10,15}/26通道全序列 | 全部VALID=1 | P0 | §1.1,§3.14 | ✅ |
| SMP_OVERRUN_OVERWRITE | DATA_003/INT_006 | 溢出覆盖旧数据 | 同通道二次采样不读 | OVERRUN中断+旧数据丢失 | P0 | §3.11 | ✅ |
| SMP_LP_SEQ_DONE | INT_002 | LP序列完成 | LP_SEQ_LEN=N 采样完 | LP_SEQ_DONE中断 | P0 | §4.1 | ✅ |
| SMP_HP_SEQ_DONE | INT_004/SMP_005 | HP序列完成 | HP_SEQ 4通道 | HP_SEQ_DONE中断 | P0 | §4.1 | ✅ |
| SMP_LP_RECOVERY | SMP_006 | HP抢占后LP恢复 | LP采样中HP触发 | LP从被中断通道恢复 | P0 | §4.4 | ✅ |
| SMP_SMPL_INTERVAL | SMP_009 | 采样间隔 | interval=0/128 | 间隔符合 | P1 | §3.2 | ✅ |

### 3.3 触发源测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| TRG_LP_SW | TRG_004 | LP软件触发 | 写TRIG[0]+EN | LP采样完成 | P0 | §4.5 | ✅ |
| TRG_HP_SW | TRG_009 | HP软件触发(优先) | LP+HP同写 | HP优先，LP屏蔽 | P0 | §4.5 | ✅ |
| TRG_LP_MCTM | TRG_001 | LP MCTM触发 | mctm_trig[0]脉冲 | LP采样完成 | P0 | §4.5 | ✅ |
| TRG_HP_MCTM | TRG_013 | HP MCTM触发 | mctm_trig[1]脉冲 | HP采样完成 | P0 | §4.5 | ✅ |
| TRG_SEL_MCTM0_5 | TRG_002 | MCTM源选择0~5 | TRG_SEL=0~5循环 | 对应mctm触发 | P0 | §3.4 | ✅ |
| TRG_SEL_MCTM34 | TRG_003/015 | MCTM组合mctm3\|4 | TRG_SEL=6 | mctm3或4均可触发 | P1 | §3.4 | ✅ |
| TRG_SEL_ECC | TRG_010 | ecc触发源(TRG_SEL=7) | mctm_trig[0] | 映射mctm0触发 | P1 | §3.4 | ✅ |
| TRG_SEL_TUE | TRG_011 | tue触发源(TRG_SEL=8) | mctm_trig[1] | 映射mctm1触发 | P1 | §3.4 | ✅ |
| TRG_SEL_RESERVED | TRG_012 | 保留编码9~15不触发 | TRG_SEL=9~15 | CH_DATA VALID=0 | P2 | §3.4 | ✅ |
| TRG_EN_GATING | TRG_004/005 | 触发使能门控 | EN=0写触发 | 不触发 | P0 | §4.5 | ✅ |
| TRG_INDEP | TRG_006/014 | LP/HP独立配置 | 不同源各自触发 | 各自按源触发 | P1 | §4.5 | ✅ |
| TRG_MCTM_CDC | TRG_007 | MCTM CDC同步+边沿检测 | 稳定多周期脉冲 | sync+edge正确触发 | P0 | §4.5 | ✅ |

### 3.4 中断测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| INT_LP_EOC | INT_001 | LP_EOC中断 | LP单次完成 | INT_STAT[0]=1,adc_int=1 | P0 | §4.6 | ✅ |
| INT_LP_SEQ_DONE | INT_002 | LP_SEQ_DONE中断 | LP序列完成 | INT_STAT[1]=1 | P0 | §4.6 | ✅ |
| INT_HP_EOC | INT_003 | HP_EOC中断 | HP单次完成 | INT_STAT[2]=1 | P0 | §4.6 | ✅ |
| INT_HP_SEQ_DONE | INT_004 | HP_SEQ_DONE中断 | HP序列完成 | INT_STAT[3]=1 | P0 | §4.6 | ✅ |
| INT_HP_PREEMPT | INT_005 | HP_PREEMPT中断 | HP抢占事件 | INT_STAT[4]=1 | P1 | §4.6 | ✅ |
| INT_OVERRUN | INT_006 | OVERRUN中断 | VALID=1时新采样 | INT_STAT[5]=1 | P0 | §4.6 | ✅ |
| INT_EN_GATING | INT_007 | 使能门控 | INT_EN=0事件 | INT_STAT不更新 | P0 | §4.6 | ✅ |
| INT_W1C | INT_008 | W1C清零 | 写1到INT_STAT | 对应位清零 | P0 | §4.6 | ✅ |
| INT_ADC_INT_DOMAIN | — | adc_int PCLK域 | INT_STAT&INT_EN | adc_int正确聚合 | P0 | §4.6 | ✅ |
| — | INT_010 | 逐位反向门控 | 使能X时事件Y≠X | adc_int不拉 | P0 | §4.6 | ✅ |
| — | INT_011 | 多通道共享OVERRUN | 多通道overflow | 均触发INT_STAT[5] | P0 | §3.11 | ✅ |

### 3.5 DMA测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| DMA_LP_EOC | DMA_001/002 | LP_EOC触发DMA | 单次完成 | dma_ndreq拉低→ack后回高 | P0 | §4.7 | ✅ |
| DMA_LP_SEQ | DMA_007 | LP_SEQ触发DMA | 序列完成 | dma_ndreq拉低 | P1 | §4.7 | ✅ |
| DMA_HP_EOC | DMA_008 | HP_EOC触发DMA | HP单次完成 | dma_ndreq拉低 | P1 | §4.7 | ✅ |
| DMA_HP_SEQ | DMA_009 | HP_SEQ触发DMA | HP序列完成 | dma_ndreq拉低 | P1 | §4.7 | ✅ |
| DMA_OVERRUN | DMA_010 | OVERRUN触发DMA | overflow | dma_ndreq拉低 | P1 | §4.7 | ✅ |
| DMA_ACK_HANDSHAKE | DMA_002/003/006 | ack握手 | ack清除/保持/无req时ack | 正确握手 | P0 | §4.7 | ✅ |
| DMA_EN_GATING | DMA_005 | DMA_EN全局门控 | EN=0时事件 | dma_ndreq不拉 | P0 | §3.12 | ✅ |
| DMA_INDEP_INT | DMA_016 | DMA与中断独立 | LP_EOC+OVERRUN叠加 | 各自独立触发 | P1 | §4.7 | ✅ |

### 3.6 校准测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| CAL_FLOW | CAL_001 | 校准流程8步 | 写CAL_ST=1 | CAL_DONE返回 | P0 | §3.7 | ✅ |
| CAL_VAL_LATCH | CAL_002 | 校准值锁存 | 校准后读CAL_VAL | CAL_VAL=0x2A | P0 | §3.8 | ✅ |
| CAL_PARALLEL | CAL_003 | 校准与采样并行 | CAL_ST=1+触发采样 | 并行不冲突(不互斥) | P1 | §3.7 | ✅ |
| CAL_DONE_SET | CAL_004 | CAL_DONE电平跟随(高) | cal_done多周期高 | CAL_CTRL[1]持续=1 | P0 | §3.7 | ✅ |
| CAL_DONE_CLR | CAL_005 | CAL_DONE电平清零 | CAL_ST=0 | CAL_CTRL[1]跟随回0 | P0 | §3.7 | ✅ |
| CAL_20CYCLE | — | 校准20周期 | 计数20个ADC_CLK | CAL_DONE置1 | P1 | §3.7 | ✅ |
| CAL_ADC_EN_GATE | — | ADC_EN=0清校准 | ADC_EN=0时CAL_ST=1 | cal_done不产生 | P1 | §3.7 | ✅ |
| CAL_RECAL | — | 重新校准 | CAL_ST=0→1 | 重新计数20周期 | P1 | §3.7 | ✅ |
| CAL_ST_DIRECT | — | CAL_ST直送模拟 | PCLK RW位直出 | 无CDC同步器 | P1 | §3.7 | ✅ |
| CAL_DONE_SYNC | — | CAL_DONE 2级同步 | cal_done_s1/s2 | PCLK域2拍同步 | P1 | §3.7 | ✅ |
| CAL_NO_TIMEOUT | — | 无超时保护 | 模拟故障CAL_DONE不回 | CAL_BUSY保持,软件判定 | P2 | §3.7 | ✅ |

### 3.7 复位测试

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| RST_HW_PRSTN | RST_001 | PRSTn硬件复位 | 断言PRSTn | 全寄存器复位,FSM回IDLE | P0 | §6.1 | ✅ |
| RST_PRESETN | — | PRESETn APB域复位 | 断言PRESETn | APB域寄存器复位 | P0 | §6.1 | ✅ |
| RST_SW_RST | RST_002 | SW_RST软件复位 | 写CTRL[1]=1 | 复位+自清零 | P0 | §6.1 | ✅ |
| RST_REENABLE | RST_003/005 | 复位后重使能 | 复位后ADC_EN=1 | FSM正常工作 | P1 | §6.2 | ✅ |
| RST_DURING_ACQ | RST_004 | 采集中复位 | 采样中SW_RST | 立即终止+复位 | P0 | §6.1 | ✅ |
| RST_SHARED_SYNC | — | SW_RST与PRSTn共享同步器 | 对比两者时序 | 时序行为一致 | P2 | §6.1 | ✅ |
| RST_DEFAULT_VALUES | REG_001 | 复位默认值 | 复位后读全寄存器 | 各寄存器=spec默认值 | P0 | §6.1 | ✅ |

### 3.8 时序测试（新增——旧 testplan 几乎无）

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| TIM_SOC | — | SOC单周期adc_clkn↑ | 触发后观察SOC | posedge adc_clkn单周期 | P0 | §2.3 | ✅(SVA) |
| TIM_EOC | — | EOC单周期adc_clk↓ | 观察EOC | negedge adc_clk单周期 | P0 | §2.3 | ✅(SVA) |
| TIM_MUXON_RISE | — | MUXON与SOC同沿拉高 | 观察MUXON | posedge adc_clkn同SOC | P0 | §2.3 | ✅(SVA) |
| TIM_MUXON_FALL | — | MUXON SPT满拉低 | SPT后观察 | 计满同沿拉低 | P0 | §2.3 | ✅(SVA) |
| TIM_EOC_SAMPLE | — | 控制器ADC_CLK↑采样EOC | 观察采样沿 | posedge adc_clk采样 | P0 | §4.1 | ✅(SVA cover) |
| TIM_CH_SEL_LATCH | — | ch_sel MUXON↓锁存 | 观察ch_sel切换 | MUXON↓锁存下一通道 | P0 | §2.3 | ✅(scoreboard) |
| TIM_PREEMPT_RST_N | SMP_020/023 | preempt_rst_n先于HP SOC≥1周期 | LP采样中HP触发 | rst_n先于SOC | P0 | §4.4 | ✅(SVA) |
| TIM_PREEMPT_LP_SAMPLE | SMP_007 | 抢占时机1 SAMPLE | LP SAMPLE中HP | ST_LP_SAMPLE→PREEMPT | P0 | §4.4 | ✅ |
| TIM_PREEMPT_LP_WAIT_EOC | SMP_008 | 抢占时机2 WAIT_EOC | LP WAIT_EOC中HP | ST_LP_WAIT_EOC→PREEMPT | P0 | §4.4 | ✅ |
| TIM_PREEMPT_LP_INTERVAL | SMP_020 | 抢占时机3 INTERVAL | LP INTERVAL中HP | ST_LP_INTERVAL→PREEMPT | P0 | §4.4 | ✅ |
| TIM_PREEMPT_HOLD | SMP_023 | preempt_hold防回退 | 抢占后muxon_fall | ch_sel不回退lp | P0 | §4.4 | ✅ |
| TIM_PREEMPT_ABORT_MUXON | SMP_007 | preempt_abort MUXON强制拉低 | 抢占时MUXON | MUXON立即拉低 | P0 | §4.4 | ✅ |
| TIM_PREEMPT_SOC_PEND | — | preempt_soc_pend推迟SOC | 跟踪寄存器 | PREEMPT置位→HP_SAMPLE释放 | P0 | §4.4 | ✅(SVA) |
| TIM_PREEMPT_SAME_CYCLE | — | rst_n/abort同拍生效 | 观察ST_LP_PREEMPT | 组合同拍 | P0 | §4.4 | ✅(SVA) |
| TIM_DUAL_CLK | — | 双时钟同源反相 | ADC_CLK/ADC_CLKn | 180°相位,1级采样 | P1 | §1.1 | ✅(SVA+sequence) |
| TIM_3MSPS | — | 3Msps采样率上限 | ADC_CLK=60MHz | 时序闭合(验证范围外,STA确认) | P2 | §1.1 | |

### 3.9 边界挑战测试（新增）

| ID | 测试点 | 场景 | 预期结果 | 优先级 | 可行性 | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| EDGE_001 | DMA_BUSY同步链断裂 | 读DMA_STAT.BUSY | 验证同步链是否正常 | P1 | 可测 | INFO(DMA_014已覆盖) |
| EDGE_002 | CH_DATA PCLK直读ADC_CLK域 | 读CH_DATA.DATA | 验证跨域直读安全 | P1 | 可测 | |
| EDGE_003 | VALID读清与EOC写同周期竞争 | 同周期读+写 | 无竞争错误 | P1 | 可测 | INFO(难以精确对齐) |
| EDGE_004 | OVERRUN检测ch_valid | 连续overflow | 正确检测 | P1 | 可测 | INFO(INT_006/011已覆盖) |
| EDGE_005 | PCLK读CH_DATA逢ADC_CLK写 | 跨域读写同时 | 设计可接受(CH_DATA EOC后稳定),验证范围外(CDC稳定性由STA保证) | P1 | 验证范围外 | ✅ |
| EDGE_006 | SW_RST与PRSTn共享同步器 | 对比时序 | 时序一致 | P2 | 可测 | |
| EDGE_007 | SW_RST期间模拟转换未preempt_rst_n | SW_RST中观察 | 模拟转换中止 | P2 | 可测 | |
| EDGE_008 | 复位在ST_LP_PREEMPT拍到达 | preempt中复位 | 正确恢复IDLE | P1 | 可测 | ✅ |
| EDGE_009 | EOC粘着跨采样边界 | EOC高跨两次WAIT_EOC | 仅第一拍触发 | P1 | 可测 | INFO(SMP_019已覆盖) |
| EDGE_010 | CAL_DONE高时cal_val重锁存 | cal_done多周期 | cal_val稳定(无害) | P2 | 可测 | |
| EDGE_011 | CAL_ST保持高 | CAL_ST=1不清 | cal_busy持续 | P2 | 可测 | |
| EDGE_012 | LP_SEQ_LEN=0 | 写LEN=0触发 | FSM正确处理空序列 | P1 | 可测 | ✅ |
| EDGE_013 | LP_SEQ_LEN=33~63 | 写LEN>32 | ptr回绕行为 | P2 | 可测 | |
| EDGE_014 | HP_SEQ_LEN=0 | 写LEN=0触发 | FSM正确处理 | P1 | 可测 | ✅ |
| EDGE_015 | SMPL_INTERVAL位宽 | spec改[22:16]7-bit,RTL已扩展 | 已解决(spec+RTL对齐0~127) | P1 | 已解决 | ✅ |
| EDGE_016 | 通道26~31被采样静默写入 | LP_SEQ_LEN=32采CH26~31 | 正常写入(已验证REG_013) | P1 | 可测 | ✅ |
| EDGE_017 | CONT_MODE下ADC_EN=0不停止 | 连续中关ADC_EN | 当前序列完成后停 | P1 | 可测 | ✅ |
| EDGE_018 | LP抢占恢复哨兵冲突 | lp_save_ptr=1F边界 | 正确恢复 | P2 | 可测 | INFO(需精确时序控制) |
| EDGE_019 | TRIG WO位RTL不自清零 | 写WO位读回 | 读回0(mask) | P1 | 可测 | ✅ |
| EDGE_020 | 非法FSM状态STAT表现 | force非法状态 | STAT正确+恢复IDLE | P1 | 可测 | ✅ |
| EDGE_021 | p_cal_st_soc_exclusive SVA vs spec | SVA已删除(spec不强制互斥) | 已解决(SVA删除,spec§3.7为准) | P1 | 已解决 | ✅ |
| EDGE_022 | 校准并行RTL无互斥 | CAL_ST=1+采样 | 并行正确(spec§3.7软件责任) | P1 | 已解决 | ✅ |
| EDGE_023 | dma_ack与新EOC同拍请求丢失 | 同拍ack+新事件 | 请求不丢失 | P1 | 可测 | INFO(难以精确对齐) |
| EDGE_024 | mctm 1周期毛刺确定性捕获 | 1 ADC_CLK宽脉冲 | 被捕获(非亚稳态) | P2 | 可测 | INFO(TRG_007已覆盖) |
| EDGE_025 | adc_data全0/全1边界 | 全0/全1采样 | 数据正确 | P2 | 可测 | INFO(SMP_PRECISION已覆盖) |
| EDGE_026 | LP+HP同写SW_TRIG未实现 | 同写TRIG[0]+[8] | HP优先LP屏蔽 | P0 | 可测 | ✅ |
| EDGE_027 | SW+MCTM同周期验证不充分 | 同周期SW+MCTM | 无丢失 | P0 | 可测 | ✅ |

### 3.10 参数化测试（新增——参数化重构配套）

| ID | 旧ID映射 | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--|:--:|:--|:--:|
| PARAM_NUM_CH_8 | — | 8 通道配置 smoke | `ADC_NUM_CH=8` | ch_sel 3bit / LP_DATA 8 个 / LP_SEQ 2 组 / LP_SEQ_LEN 4bit 复位 8 正确 | P1 | §3.0 | ✅ `tb_adc_top_8ch` |
| PARAM_NUM_CH_32 | — | 32 通道配置 smoke | `ADC_NUM_CH=32` | ch_sel 5bit / LP_DATA 32 个 / LP_SEQ 8 组 / LP_SEQ_LEN 6bit 复位 32(0x20) 正确 / **LP_DATA[26:31] @0x8C~0xA0 读回 VALID+data**（b75842f 闭合） | P0 | §3.0 | ✅ `tb_adc_top_32ch` |
| PARAM_DATA_W_12 | — | 12bit ADC 配置 smoke | `ADC_DATA_W=12` | adc_data 12bit 右对齐/左对齐正确 | P1 | §3.0 | ✅ `tb_adc_top_8ch` |
| PARAM_SPT1_MASK | — | SPT1 位图可选 | `ADC_SPT1_CH_MASK=0` | 全 SPT0，SPT1 配置忽略 | P2 | §3.2 | ✅ `tb_adc_top_8ch`+`tb_adc_top_32ch` |
| PARAM_ADDR_RSV | — | 超出 NUM_LP_DATA 的 entry 地址读回 0 | 访问 0x24+NUM_LP_DATA×4（LP_DATA）/ 0xB8+NUM_LP_DATA×4 起 LP_SEQ entry 越界（entry idx≥NUM_LP_DATA，含 LP_SEQ 组内高位 entry） | 读回 0、写忽略；entry 粒度（非组粒度） | P1 | §3.0 | ✅(部分) N=8 由 `tb_adc_top_8ch` 默认复位读回覆盖（LP_DATA idx 8..31 读 0）；N=32 无预留项（全 32 实现） |
| PARAM_SEQ_RSV | — | entry 内 rsv 高位读回 0 | 写 LP_SEQ/HP_SEQ entry 占位高 rsv 位（如 26ch 写 0x1F→entry 低5bit 有效）读回 | rsv 高位读回 0、ch_sel 位读回=写入低 W_CH_SEL bit | P1 | §3.13/§3.14 | ✅ `tb_adc_top_32ch` Test3（N=32 W_CH_SEL=5bit，写 0xFFFFFFFF 读 0x1F1F1F1F） |
| PARAM_COMPAT_26 | — | 默认 26 向后兼容 | 默认参数全回归 | 行为与参数化前一致（除 LP_SEQ7 读回 0、LP_SEQ_LEN 位宽 6→5） | P0 | §3.0 | ✅ |

## 4. 覆盖率目标

| 覆盖率类型 | 目标值 | 验证方法 |
|:--|:--:|:--|
| 语句覆盖率 | ≥95% | VCS 代码覆盖率（shell 分支 waiver） |
| 分支覆盖率 | ≥90% | VCS 代码覆盖率（非法状态/保留编码 waiver） |
| 条件覆盖率 | ≥85% | VCS 代码覆盖率 |
| FSM 覆盖率 | ≥90% | VCS FSM 覆盖率 |
| 翻转覆盖率 | ≥80% | VCS 代码覆盖率（CH_DATA 预留位 waiver） |
| 功能覆盖率 | 100%（所有 P0 测试点通过） | UVM covergroup |

### 4.1 Waiver 清单

| Waiver 项 | 位置 | 原因 |
|:--|:--|:--|
| RTL shell 模式分支 | 各模块 P_SHELL_MODE=1 | 系统仿真用，模块验证走 active |
| 非法 FSM 状态 default | adc_seq_fsm.v 4'h9~F | 需 force 注入 |
| TRG_SEL 保留编码 | adc_trig_sync.v 4'h9~F | spec reserved 无输出 |
| CH_DATA[26:31] 未采样 toggle | adc_regfile.v | 32 通道预留，默认不采 |
| SVA unreachable | bind_adc_assert.sv | 断言模块自身 |

## 5. 待补测试点清单

以下测试点状态为空（待实现），按优先级排列。P0 项已全部补完（11/11），剩余为 P1/P2。

| # | ID | 优先级 | 缺口类型 | 补验方式 | 状态 |
|:--|:--|:--:|:--|:--|:--:|
| 7 | SMP_019 EOC电平粘着 | P1 | 旧标✅未实现 | EOC多周期高仅第一拍触发 | ✅ |
| 8 | REG_CH_DATA RO写保护 | P1 | 旧REG_008未实现 | 向CH_DATA写值后读回无变化 | |
| 9 | REG_STAT_CAL_BUSY | P1 | 新增 | 校准中读STAT[3] | ✅ |
| 10 | SMP_PRECISION_14BIT | P1 | 新增 | 14-bit全量程数据完整性 | ✅ |
| 15 | TIM_DUAL_CLK | P1 | 新增 | 双时钟同源反相验证 | ✅(SVA+sequence) |
| 16 | CAL_20CYCLE | P1 | 新增 | 校准20周期计数 | ✅ |
| 17 | CAL_ST_DIRECT | P1 | 新增 | CAL_ST直送无CDC | ✅ |
| 18 | CAL_DONE_SYNC | P1 | 新增 | CAL_DONE 2级同步 | ✅ |
| 19 | CAL_NO_TIMEOUT | P2 | 新增 | 无超时保护 | ✅ |
| 20 | RST_SHARED_SYNC | P2 | 新增 | SW_RST与PRSTn共享同步器 | ✅ |
| 21-27 | EDGE_001~005/008~014/018/023~025 | P1/P2 | 新增边界挑战 | 按挑战点描述验证 | INFO(DMA_014已覆盖) |

> P0 全部 11 项已补完并验证 PASS（2026-07-13）。

## 变更记录

| 版本 | 日期 | 变更类型 | 变更内容 | 原因 |
|:--|:--|:--|:--|:--|
| v1.0 | 2026-07-02 | 初始 | 82 测试点 | 首次生成 |
| v2.0 | 2026-07-13 | 重新生成 | 144 测试点(3 agent 并行分析) | 旧 testplan 标✅与sequence脱节 |
| v2.0 | 2026-07-13 | 合并 | 旧ID映射+状态回填+新增TIM/EDGE | 用户要求对比后合并 |
