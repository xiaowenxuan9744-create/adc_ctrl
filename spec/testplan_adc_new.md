# 验证计划 — ADC 控制器（重新生成版）

> 由 /testplan-gen 重新生成（2026-07-13）。3 agent 并行分析：
> 功能覆盖 115 点 + RTL 路径 149 条 + 边界挑战 27 点 = 合并 142 个测试点。
> 测试点状态初始全空（待验证），不预设 ✅。

## 1. 概述
- **模块名**: ADC 控制器（adc_top）
- **验证阶段**: 顶层集成验证
- **验证方法**: UVM 随机验证 + 定向测试 + SVA 断言

## 2. 功能特性

| 特性 | 描述 | 优先级 |
|:--|:--|:--:|
| 接口 | APB 32-bit 总线接口零等待读写所有寄存器 | P0 |
| 寄存器 | 寄存器地址映射正确性（0x00~0xD4） | P0 |
| 寄存器 | CTRL[0] ADC_EN 全局使能 RW | P0 |
| 寄存器 | CTRL[1] SW_RST 软件复位写1触发、硬件自清零（RW_SS） | P0 |
| 寄存器 | CTRL[3] DATA_ALIGN 数据对齐 0=右对齐 1=左对齐 | P1 |
| 寄存器 | CTRL[7:4] SMPL_INTERVAL 采样间隔配置（spec 标注最大 128） | P1 |
| 寄存器 | CTRL[10:8] SPT0 采样时间档位0（CH0~CH20,CH23~CH25） | P0 |
| 寄存器 | CTRL[13:11] SPT1 采样时间档位1（CH21,CH22） | P0 |
| 寄存器 | CTRL[14] CONT_MODE 连续转换模式 | P0 |
| 寄存器 | CTRL 保留位读0、写忽略 | P2 |
| 参数 | SPT 8 档编码到采样周期数的映射 | P0 |
| 寄存器 | STAT[0] ADC_BUSY 只读状态 | P1 |
| 寄存器 | STAT[1] LP_BUSY 只读状态 | P1 |
| 寄存器 | STAT[2] HP_BUSY 只读状态 | P1 |
| 寄存器 | STAT[3] CAL_BUSY = cal_busy=cfg_cal_st&~cal_done 经 | P1 |
| 寄存器 | TRIG[0] LP_SW_TRIG WO 写1启动 LP 软件触发 | P0 |
| 寄存器 | TRIG[1] LP_SW_TRG_EN 软件触发使能门控 | P1 |
| 寄存器 | TRIG[2] LP_MCTM_EN MCTM 外部触发使能门控 | P1 |
| 寄存器 | TRIG[6:3] LP_TRG_SEL 低优触发源选择（含6+2组合/ecc/tue/保留） | P0 |
| 寄存器 | TRIG[8] HP_SW_TRIG WO 写1启动 HP 软件触发 | P0 |
| 寄存器 | TRIG[9] HP_SW_TRG_EN 高优软件触发使能门控 | P1 |
| 寄存器 | TRIG[10] HP_MCTM_EN 高优 MCTM 触发使能门控 | P1 |
| 寄存器 | TRIG[14:11] HP_TRG_SEL 高优触发源选择 | P0 |
| 寄存器 | TRIG 保留位读0写忽略 | P2 |
| 寄存器 | INT_EN[5:0] 6 个中断源独立使能 RW | P0 |
| 寄存器 | INT_STAT[5:0] RW1C 写1清零 | P0 |
| 寄存器 | INT_STAT 读反映实时事件状态 | P1 |
| 寄存器 | CAL_CTRL[0] CAL_ST RW 软件置1/清0，ADC_EN=0或复位清 | P0 |
| 寄存器 | CAL_CTRL[1] CAL_DONE RO 读2级同步后电平 | P0 |
| 寄存器 | CAL_VAL[5:0] RO 在 cal_done_s2=1 时锁存 | P1 |
| 寄存器 | ANA_CFG[15:0] RW 模拟配置 | P2 |
| 寄存器 | ANA_REG[31:0] RW 通用模拟寄存器 | P2 |
| 寄存器 | CH_DATA[31] VALID 0→1采样完成、读寄存器自清零 | P0 |
| 寄存器 | CH_DATA[15:0] DATA 转换结果按对齐方式存放 | P0 |
| 寄存器 | CH_DATA[0:31] 32个通道数据寄存器地址范围 0x24~0xA0 | P1 |
| 寄存器 | DMA_CTRL[5:0] 6个独立DMA使能位 + DMA_EN全局使能 | P0 |
| 寄存器 | DMA_STAT[0] DMA_BUSY RO 请求处理中 | P1 |
| 寄存器 | DMA_STAT[1] DMA_DONE RO 传输完成 | P1 |
| 寄存器 | LP_SEQ[0:7] 8个寄存器各含4个8-bit条目(CH_SEL[4:0]) | P0 |
| 寄存器 | HP_SEQ 4个条目(由HP_SEQ_LEN控制有效数) | P0 |
| 寄存器 | LP_SEQ_LEN[5:0] 默认26，范围1~32 | P0 |
| 寄存器 | HP_SEQ_LEN[2:0] 默认4，范围1~4 | P0 |
| 功能模式 | 采样流程11步端到端（IDLE→触发→SOC→SPT→MUXON↓→EOC→锁存→VALID→中断→ | P0 |
| 功能模式 | 单次转换模式：序列执行一轮后停止回 IDLE | P0 |
| 功能模式 | 连续转换模式：序列完成自动从头重启 | P0 |
| 功能模式 | LP 序列达到 LP_SEQ_LEN 触发 LP_SEQ_DONE 事件 | P0 |
| 功能模式 | HP 序列达到 HP_SEQ_LEN 触发 HP_SEQ_DONE 事件 | P0 |
| 参数 | 14-bit ADC 精度（adc_data[13:0] 全量程） | P1 |
| 参数 | 26 模拟通道（地址空间按32通道预留） | P1 |
| 功能模式 | 溢出时新采样覆盖旧数据、旧数据丢失 | P0 |
| 功能模式 | HP 抢占后 LP 从被中断通道重新开始采样 | P0 |
| 功能模式 | SMPL_INTERVAL 计数器在序列模式下控制相邻采样间隔 | P1 |
| 参数 | 最高 3 Msps 采样率 | P1 |
| 时序 | 双时钟架构 ADC_CLK/ADC_CLKn 同源反相同步时钟 | P1 |
| 时序 | SOC 单周期脉冲在 ADC_CLKn↑ 产生 | P0 |
| 时序 | MUXON 与 SOC 同沿(adc_clkn↑)拉高 | P0 |
| 时序 | MUXON 在 SPT 计数满后拉低 | P0 |
| 时序 | ch_sel 在 MUXON↓ 时锁存下一通道并保持稳定；复位默认 CH0 | P0 |
| 时序 | EOC 单周期脉冲在 ADC_CLK↓ 产生 | P0 |
| 时序 | 控制器在 ADC_CLK↑ 采样 EOC 并锁存 ADC_DATA | P0 |
| 时序 | preempt_rst_n 低有效单周期脉冲，先于 HP SOC 至少1个 adc_clk 周期 | P0 |
| 时序 | preempt_rst_n/preempt_abort 组合同拍生效，preempt_soc_pen | P0 |
| 时序 | preempt_abort 时 MUXON 强制拉低 | P0 |
| 时序 | preempt_soc_pend 在 ST_LP_PREEMPT 置位，推迟到 ST_HP_SAMP | P0 |
| 时序 | preempt_hold 寄存器保护 ch_sel_reg 防止 muxon_fall 覆盖回 lp | P0 |
| 时序 | HP 抢占时机1：ST_LP_SAMPLE→ST_LP_PREEMPT→ST_HP_SAMPLE | P0 |
| 时序 | HP 抢占时机2：ST_LP_WAIT_EOC→ST_LP_PREEMPT→ST_HP_SAMPLE | P0 |
| 时序 | HP 抢占时机3：ST_LP_INTERVAL→ST_LP_PREEMPT→ST_HP_SAMPLE | P0 |
| 功能模式 | LP 软件触发：写 TRIG[0] 启动 LP 采样 | P0 |
| 功能模式 | LP MCTM 外部硬件触发 | P0 |
| 功能模式 | HP 软件触发：写 TRIG[8] 启动 HP 采样（可抢占 LP） | P0 |
| 功能模式 | HP MCTM 外部硬件触发 | P0 |
| 功能模式 | 触发源编码 0000~0101 选中 mctm0~mctm5 单源 | P1 |
| 功能模式 | 触发源编码 0110 = mctm3|mctm4 组合 | P1 |
| 功能模式 | 触发源编码 0111 = ecc | P1 |
| 功能模式 | 触发源编码 1000 = tue | P1 |
| 功能模式 | 触发源编码 1001~1111 保留不触发 | P2 |
| 功能模式 | 触发使能门控：软件触发需 SW_TRG_EN、MCTM 需 MCTM_EN | P0 |
| 时序 | mctm_trig 与 ADC_CLK 异步，经2级同步器+上升沿检测 | P0 |
| 功能模式 | HP/LP 各自独立配置触发源和使能 | P1 |
| 功能模式 | LP_EOC 低优先单次采样完成中断源 | P0 |
| 功能模式 | LP_SEQ_DONE 低优先序列完成中断源 | P0 |
| 功能模式 | HP_EOC 高优先单次采样完成中断源 | P0 |
| 功能模式 | HP_SEQ_DONE 高优先序列完成中断源 | P0 |
| 功能模式 | HP_PREEMPT 高优先打断中断源 | P0 |
| 功能模式 | OVERRUN 任意通道数据溢出中断源 | P0 |
| 功能模式 | 6 中断源通过 INT_EN 独立使能门控 | P0 |
| 功能模式 | INT_STAT 写1清零机制 | P0 |
| 接口 | adc_int 在 PCLK 域由 INT_STAT & INT_EN 驱动 | P1 |
| 功能模式 | DMA_LP_EOC 低优单次完成触发 DMA 请求 | P1 |
| 功能模式 | DMA_LP_SEQ 低优序列完成触发 DMA 请求 | P1 |
| 功能模式 | DMA_HP_EOC 高优单次完成触发 DMA 请求 | P1 |
| 功能模式 | DMA_HP_SEQ 高优序列完成触发 DMA 请求 | P1 |
| 功能模式 | DMA_OVERRUN 溢出触发 DMA 请求 | P1 |
| 功能模式 | DMA_EN 全局使能门控所有 DMA 请求 | P0 |
| 接口 | dma_ndreq 低有效请求 + dma_ack 握手清除 | P0 |
| 功能模式 | DMA 请求与中断共享事件源但走独立使能路径互不干扰 | P1 |
| 功能模式 | 校准流程8步（ADC_EN→CAL_ST=1→模拟计数20→CAL_DONE=1→同步→锁存cal_ | P0 |
| 时序 | 校准固定 20 个 ADC_CLK 周期后置 CAL_DONE | P0 |
| 功能模式 | CAL_DONE 置1条件：CAL_ST=1 且校准满20个ADC_CLK周期 | P0 |
| 功能模式 | CAL_DONE 清0条件：CAL_ST=0 或 ADC_EN=0 或复位 | P0 |
| 时序 | cal_val 在 cal_done_s2=1 时锁存到 CAL_VAL | P1 |
| 接口 | CAL_ST 为 PCLK 域 RW 寄存器位直送模拟，无 CDC 同步器 | P1 |
| 时序 | CAL_DONE 经 PCLK 2级同步（cal_done_s1/s2）后读 | P0 |
| 功能模式 | 重新校准：写 CAL_ST=0 清模拟 CAL_DONE 后再写1重新计数20周期 | P1 |
| 功能模式 | 校准与采样不互斥：控制器不强制屏蔽，由软件保证不发起采样 | P2 |
| 功能模式 | 控制器不实现超时保护，软件通过 CAL_BUSY 卡死判定异常 | P2 |
| 功能模式 | 校准前提：仅 ADC_EN=1 时可校准，ADC_EN=0 清 CAL_ST/CAL_DONE | P1 |
| 功能模式 | PRSTn 硬件复位：异步断言立即复位 ADC_CLK 域，同步释放2级 | P0 |
| 功能模式 | PRESETn APB 域复位（与 PCLK 同步）直接使用 | P0 |
| 功能模式 | SW_RST 软件复位写1触发、硬件自清零，复位所有寄存器和 FSM | P0 |
| 时序 | SW_RST 与 PRSTn 共享同一2级同步释放电路 | P1 |
| 功能模式 | 复位释放后重新使能并正常工作 | P1 |
| 功能模式 | 采集中复位：FSM/计数器/数据寄存器正确清理 | P0 |
| 寄存器 | 复位后所有寄存器恢复默认值 | P0 |

**功能域**: ADC 控制器

## 3. 测试点清单

共 142 个测试点（功能 115 + 边界 27）。

### 3.1 寄存器测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| REG_ADDR_MAP | 寄存器地址映射正确性（0x00~0xD4） | 逐个寄存器按 spec 地址访问；访问保留地址区间 | 每个寄存器在唯一地址响应；保留地址读返回 0 且不产生副作用；CH_DATA[0 | P0 | §3.1, §7 |  |
| REG_ANA_CFG | ANA_CFG[15:0] RW 模拟配置 | 写 ANA_CFG[15:0] 各值回读，写[31:16] | [15:0] 可读写；[31:16] 保留读0写忽略 | P2 | §3.9 |  |
| REG_ANA_REG | ANA_REG[31:0] RW 通用模拟寄存器 | 写 ANA_REG 全32位回读 | 全32位可读写，复位值0 | P2 | §3.10 |  |
| REG_APB32 | APB 32-bit 总线接口零等待读写所有寄存器 | APB 主对 0x00~0xD4 全部寄存器做 32-bit 读写，PSEL/PENABLE/PWR | PREADY 始终在 PENABLE 拍拉高，PSLVERR 固定 0；写入值可 | P0 | §1.1, §2.1, §3.1 |  |
| REG_CAL_CTRL_CAL_DONE | CAL_CTRL[1] CAL_DONE RO 读2级同步后电平 | 校准完成后读 CAL_CTRL[1] | 模拟 CAL_DONE 经 PCLK 2级同步后读出；CAL_ST=0/ADC_ | P0 | §3.7, §5.3 |  |
| REG_CAL_CTRL_CAL_ST | CAL_CTRL[0] CAL_ST RW 软件置1/清0，ADC_EN=0或复 | 写 CAL_ST=1/0，ADC_EN=0 时写1，复位后读 | 软件写1置1直送模拟；写0清0；ADC_EN=0 或复位时硬件清0；CAL_ST | P0 | §3.7, §4.x 校准 |  |
| REG_CAL_VAL | CAL_VAL[5:0] RO 在 cal_done_s2=1 时锁存 | 校准完成读 CAL_VAL，复位后读，校准未完成时读 | 仅在 CAL_DONE 同步有效时锁存 cal_val；复位值0；CAL_DON | P1 | §3.8, §5.3 |  |
| REG_CH_DATA_DATA | CH_DATA[15:0] DATA 转换结果按对齐方式存放 | 对多通道采样，按右/左对齐读 DATA 域 | 右对齐 DATA[13:0]=ADC,[15:14]=0；左对齐 DATA[15 | P0 | §3.11 |  |
| REG_CH_DATA_RANGE | CH_DATA[0:31] 32个通道数据寄存器地址范围 0x24~0xA0 | 访问 CH_DATA0~CH_DATA31 全部32个寄存器 | 32个寄存器各自独立读写 VALID/DATA；间隔4字节；26通道有效，26~ | P1 | §3.11, §1.1 |  |
| REG_CH_DATA_VALID | CH_DATA[31] VALID 0→1采样完成、读寄存器自清零 | 采样完成读 VALID，再读该寄存器 | 采样完成 VALID=1；读该 CH_DATA 后 VALID 自清零为0；未读 | P0 | §3.11 |  |
| REG_CTRL_ADC_EN | CTRL[0] ADC_EN 全局使能 RW | 写 ADC_EN=0→1→0，观察 FSM/触发/校准是否被门控 | ADC_EN=0 时禁止采样与校准；ADC_EN=1 时正常工作；复位值为 0； | P0 | §3.2 |  |
| REG_CTRL_CONT_MODE | CTRL[14] CONT_MODE 连续转换模式 | 置 CONT_MODE=1 触发一次，观察序列结束后是否自动循环 | CONT_MODE=1 时序列完成后自动从头重启；=0 时序列完成回到 IDLE | P0 | §3.2, §4.3 |  |
| REG_CTRL_DATA_ALIGN | CTRL[3] DATA_ALIGN 数据对齐 0=右对齐 1=左对齐 | 分别写 DATA_ALIGN=0/1 后采样，读 CH_DATA | 右对齐时 DATA[13:0]=ADC,[15:14]=0；左对齐时 DATA[ | P1 | §3.2, §3.11 |  |
| REG_CTRL_RSVD | CTRL 保留位读0、写忽略 | 向 CTRL[2]、CTRL[15] 写1后回读 | 保留位读返回 0，写入不影响功能 | P2 | §3.2 |  |
| REG_CTRL_SMPL_INTERVAL | CTRL[7:4] SMPL_INTERVAL 采样间隔配置（spec 标注最大 | 写不同 SMPL_INTERVAL 值，连续采样测量相邻 SOC 间隔 | 相邻通道 SOC 间隔 = SPT+转换+SMPL_INTERVAL 个 ADC | P1 | §3.2, §4.1 |  |
| REG_CTRL_SPT0 | CTRL[10:8] SPT0 采样时间档位0（CH0~CH20,CH23~CH | 对 CH0~CH20、CH23~CH25 配置 SPT0 各档位采样，测量 MUXON 高电平宽度 | MUXON 高电平持续对应 SPT 编码周期数（3/8/14/29/42/56/ | P0 | §3.2 |  |
| REG_CTRL_SPT1 | CTRL[13:11] SPT1 采样时间档位1（CH21,CH22） | 对 CH21、CH22 配置 SPT1 各档位采样，测量 MUXON 宽度 | CH21/CH22 的 MUXON 宽度由 SPT1 决定，与 SPT0 独立 | P0 | §3.2 |  |
| REG_CTRL_SW_RST | CTRL[1] SW_RST 软件复位写1触发、硬件自清零（RW_SS） | 配置若干寄存器后写 CTRL[1]=1，随后读 CTRL[1] | 写1后下一拍 SW_RST 自动回 0；所有寄存器与 ADC 状态机复位到默认值 | P0 | §3.2, §6.1 |  |
| REG_DMA_CTRL_6BITS | DMA_CTRL[5:0] 6个独立DMA使能位 + DMA_EN全局使能 | 独立置位/清零 6 个 DMA 使能位，触发对应事件 | DMA_EN=0 时全部 DMA 请求被屏蔽；各事件使能位独立门控对应 DMA  | P0 | §3.12, §4.7 |  |
| REG_DMA_STAT_BUSY | DMA_STAT[0] DMA_BUSY RO 请求处理中 | DMA 请求发出未 ack 时读 DMA_STAT[0] | dma_ndreq 有效（拉低）且未收到 ack 期间 DMA_BUSY=1 | P1 | §3.13 |  |
| REG_DMA_STAT_DONE | DMA_STAT[1] DMA_DONE RO 传输完成 | DMA 传输完成后读 DMA_STAT[1] | 收到 dma_ack 完成握手后 DMA_DONE=1；[15:2]保留读0 | P1 | §3.13 |  |
| REG_HP_SEQ | HP_SEQ 4个条目(由HP_SEQ_LEN控制有效数) | 写 HP_SEQ 配置 4 个条目，触发 HP 采样 | 4个条目 CH_SEL[4:0] 指定通道；按序执行至 HP_SEQ_LEN 条 | P0 | §3.15 |  |
| REG_HP_SEQ_LEN | HP_SEQ_LEN[2:0] 默认4，范围1~4 | 写 HP_SEQ_LEN=1/4 及越界值，触发 HP 采样 | HP 序列执行到 HP_SEQ_LEN 条触发 HP_SEQ_DONE；默认4； | P0 | §3.17 |  |
| REG_INT_EN_6BITS | INT_EN[5:0] 6 个中断源独立使能 RW | 独立置位/清零 6 个使能位，分别触发对应事件 | 每个使能位独立门控对应中断；多使能位组合时各自独立生效；复位值0 | P0 | §3.5, §4.6 |  |
| REG_INT_STAT_RDONLY | INT_STAT 读反映实时事件状态 | 事件发生前后读 INT_STAT | 读返回当前各事件状态位；与 INT_EN 无关（使能与否都置位） | P1 | §3.6 |  |
| REG_INT_STAT_W1C | INT_STAT[5:0] RW1C 写1清零 | 事件置位后分别写1清零各 INT_STAT 位 | 事件发生时对应位置1；写1清零、写0不变；不支持读清零（仅 CH_DATA VA | P0 | §3.6, §4.6 |  |
| REG_LP_SEQ | LP_SEQ[0:7] 8个寄存器各含4个8-bit条目(CH_SEL[4:0] | 写各 LP_SEQ 寄存器配置 4 个条目的 CH_SEL，触发 LP 采样验证通道顺序 | LP_SEQ0~7 对应 ENT0~ENT31；每个条目 CH_SEL[4:0] | P0 | §3.14 |  |
| REG_LP_SEQ_LEN | LP_SEQ_LEN[5:0] 默认26，范围1~32 | 写 LP_SEQ_LEN=1/26/32 及越界值，触发采样观察序列完成时机 | 序列执行到 LP_SEQ_LEN 条触发 LP_SEQ_DONE；默认26；范围 | P0 | §3.16 |  |
| REG_SPT_ENCODING | SPT 8 档编码到采样周期数的映射 | 遍历 SPT[2:0]=000~111，采样并测量 MUXON 周期数 | 000→3,001→8,010→14,011→29,100→42,101→56, | P0 | §3.2 |  |
| REG_STAT_ADC_BUSY | STAT[0] ADC_BUSY 只读状态 | 采样进行中与空闲时分别读 STAT[0] | 采样/转换期间 ADC_BUSY=1，空闲时=0；写无效 | P1 | §3.3 |  |
| REG_STAT_CAL_BUSY | STAT[3] CAL_BUSY = cal_busy=cfg_cal_st&~ | 启动校准后轮询 STAT[3]，校准完成后再次读 | 校准进行中 CAL_BUSY=1；CAL_DONE 同步有效后 CAL_BUSY | P1 | §3.3, §3.7 |  |
| REG_STAT_HP_BUSY | STAT[2] HP_BUSY 只读状态 | HP 序列执行中读 STAT[2] | HP 序列执行期间 HP_BUSY=1，完成后=0 | P1 | §3.3 |  |
| REG_STAT_LP_BUSY | STAT[1] LP_BUSY 只读状态 | LP 序列执行中读 STAT[1] | LP 序列执行期间 LP_BUSY=1，完成或被抢占后正确变化 | P1 | §3.3 |  |
| REG_TRIG_HP_MCTM_EN | TRIG[10] HP_MCTM_EN 高优 MCTM 触发使能门控 | 使能/禁用 HP_MCTM_EN 后施加 mctm_trig | EN=1 且 TRG_SEL 匹配时 HP 外部触发有效 | P1 | §3.4 |  |
| REG_TRIG_HP_SW_TRG_EN | TRIG[9] HP_SW_TRG_EN 高优软件触发使能门控 | 使能/禁用 HP_SW_TRG_EN 后写 HP_SW_TRIG | EN=1 时 HP 软件触发有效，EN=0 时忽略 | P1 | §3.4 |  |
| REG_TRIG_HP_SW_TRIG | TRIG[8] HP_SW_TRIG WO 写1启动 HP 软件触发 | HP_SW_TRG_EN=1 时写 TRIG[8]=1 | 写1产生一次 HP 触发；回读为0；可抢占 LP | P0 | §3.4, §4.5 |  |
| REG_TRIG_HP_TRG_SEL | TRIG[14:11] HP_TRG_SEL 高优触发源选择 | 遍历 HP_TRG_SEL=0000~1111，施加 mctm_trig | 与 LP_TRG_SEL 编码一致；保留编码不触发 | P0 | §3.4, §4.5 |  |
| REG_TRIG_LP_MCTM_EN | TRIG[2] LP_MCTM_EN MCTM 外部触发使能门控 | 使能/禁用 LP_MCTM_EN 后施加 mctm_trig 脉冲 | EN=1 且 TRG_SEL 匹配时外部触发有效，EN=0 时被忽略 | P1 | §3.4, §4.5 |  |
| REG_TRIG_LP_SW_TRG_EN | TRIG[1] LP_SW_TRG_EN 软件触发使能门控 | 使能/禁用 LP_SW_TRG_EN 后写 LP_SW_TRIG | EN=1 时软件触发有效，EN=0 时软件触发被忽略 | P1 | §3.4 |  |
| REG_TRIG_LP_SW_TRIG | TRIG[0] LP_SW_TRIG WO 写1启动 LP 软件触发 | LP_SW_TRG_EN=1 时写 TRIG[0]=1 | 写1产生一次 LP 触发脉冲；回读为0（WO）；未使能时不触发 | P0 | §3.4, §4.5 |  |
| REG_TRIG_LP_TRG_SEL | TRIG[6:3] LP_TRG_SEL 低优触发源选择（含6+2组合/ecc/ | 遍历 LP_TRG_SEL=0000~1111，分别施加对应 mctm_trig 线 | 0000~0101 选 mctm0~5；0110 选 mctm3|4 组合；01 | P0 | §3.4, §4.5 |  |
| REG_TRIG_RSVD | TRIG 保留位读0写忽略 | 写 TRIG[7]、TRIG[15] 后回读 | 保留位读0，写无效 | P2 | §3.4 |  |

### 3.2 采样测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| SMP_CH_RANGE | 26 模拟通道（地址空间按32通道预留） | 对 CH0~CH25 采样；配置 CH26~CH31 序列条目 | CH0~CH25 正常采样并写入对应 CH_DATA；CH26~CH31 预留地 | P1 | §1.1, §3.14 |  |
| SMP_CONT | 连续转换模式：序列完成自动从头重启 | CONT_MODE=1 触发一次，观察多轮；中途清 ADC_EN | 序列完成后自动回序列头继续；直到 ADC_EN=0 或触发停止；循环期间不断产生 | P0 | §4.3 |  |
| SMP_FLOW | 采样流程11步端到端（IDLE→触发→SOC→SPT→MUXON↓→EOC→锁存 | 单通道单次采样完整流程跟踪 SOC/MUXON/EOC/VALID/中断 | 依次完成11步；SOC 单周期 adc_clkn↑；MUXON 与 SOC 同沿 | P0 | §4.1 |  |
| SMP_HP_SEQ_DONE | HP 序列达到 HP_SEQ_LEN 触发 HP_SEQ_DONE 事件 | HP 触发后执行 HP_SEQ_LEN 条 | 执行满 HP_SEQ_LEN 条时产生 HP_SEQ_DONE 事件/中断 | P0 | §3.17, §4.6 |  |
| SMP_LP_RECOVERY | HP 抢占后 LP 从被中断通道重新开始采样 | LP 采 CH_n 中被 HP 抢占，HP 完成后观察 LP 恢复 | HP 序列全部完成后，LP 从被中断的通道重新采样，再继续序列剩余通道 | P0 | §4.4 |  |
| SMP_LP_SEQ_DONE | LP 序列达到 LP_SEQ_LEN 触发 LP_SEQ_DONE 事件 | LP_SEQ_LEN=26 连续采样，计满26条 | 执行满 LP_SEQ_LEN 条时产生 LP_SEQ_DONE 事件/中断；连续 | P0 | §3.16, §4.6 |  |
| SMP_OVERRUN_OVERWRITE | 溢出时新采样覆盖旧数据、旧数据丢失 | 某通道 VALID=1 未读时再次采样完成 | VALID 已为1时新采样完成触发 OVERRUN 事件；DATA 被新值覆盖； | P0 | §3.11 |  |
| SMP_PRECISION_14BIT | 14-bit ADC 精度（adc_data[13:0] 全量程） | 输入已知模拟值采样，验证 DATA 14-bit 精度 | adc_data 14-bit 完整传入 DATA 域；0 和满量程边界值正确 | P1 | §1.1, §3.11 |  |
| SMP_SINGLE | 单次转换模式：序列执行一轮后停止回 IDLE | CONT_MODE=0 触发一次 LP 序列 | 序列执行一轮所有有效条目后停止；STAT 忙位清零；等待下一次触发 | P0 | §4.2 |  |
| SMP_SMPL_INTERVAL | SMPL_INTERVAL 计数器在序列模式下控制相邻采样间隔 | 连续模式相邻通道采样，测量 EOC 到下一 SOC 间隔 | 序列模式下 EOC 后启动 SMPL_INTERVAL 计数，计满发下一 SOC | P1 | §3.2, §5.2 |  |

### 3.4 触发源测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| TRG_EN_GATING | 触发使能门控：软件触发需 SW_TRG_EN、MCTM 需 MCTM_EN | SW_TRG_EN/MCTM_EN 各种 0/1 组合下施加触发 | 对应使能位=0 时触发被忽略；=1 时触发有效；软件触发与 MCTM 触发可同时 | P0 | §4.5, §3.4 |  |
| TRG_HP_MCTM | HP MCTM 外部硬件触发 | HP_MCTM_EN=1、HP_TRG_SEL 选定源，施加 mctm_trig 脉冲 | 经同步+边沿检测后路由到 HP 触发逻辑，可抢占 LP | P0 | §4.5, §2.4 |  |
| TRG_HP_SW | HP 软件触发：写 TRIG[8] 启动 HP 采样（可抢占 LP） | HP_SW_TRG_EN=1 写 HP_SW_TRIG=1 | 产生 HP 触发，可抢占正在执行的 LP | P0 | §4.5 |  |
| TRG_INDEP | HP/LP 各自独立配置触发源和使能 | LP/HP 配置不同触发源与使能，独立触发 | LP 与 HP 触发配置完全独立；一方配置变化不影响另一方 | P1 | §1.1, §4.5 |  |
| TRG_LP_MCTM | LP MCTM 外部硬件触发 | LP_MCTM_EN=1、LP_TRG_SEL 选定源，施加对应 mctm_trig 脉冲 | 经 2级同步+上升沿检测后路由到 LP 触发逻辑，启动 LP 采样 | P0 | §4.5, §2.4 |  |
| TRG_LP_SW | LP 软件触发：写 TRIG[0] 启动 LP 采样 | LP_SW_TRG_EN=1 写 LP_SW_TRIG=1 | 产生 LP 触发，启动 LP 序列采样 | P0 | §4.5 |  |
| TRG_MCTM_CDC | mctm_trig 与 ADC_CLK 异步，经2级同步器+上升沿检测 | mctm_trig 相对 ADC_CLK 异步施加，快脉冲连续施加 | 异步输入经2级同步器（ADC_CLK域）+上升沿检测后产生单拍触发脉冲；无亚稳态 | P0 | §2.4, §4.5 |  |
| TRG_SEL_ECC | 触发源编码 0111 = ecc | TRG_SEL=0111，施加 ecc 触发 | ecc 源触发有效 | P1 | §3.4, §4.5 |  |
| TRG_SEL_MCTM0_5 | 触发源编码 0000~0101 选中 mctm0~mctm5 单源 | TRG_SEL=0000~0101，分别只施加 mctm_trig[0]~[5] | 仅所选 mctm_trig 线的上升沿触发；其他线脉冲不触发 | P1 | §3.4, §4.5 |  |
| TRG_SEL_MCTM34 | 触发源编码 0110 = mctm3|mctm4 组合 | TRG_SEL=0110，分别施加 mctm3、mctm4 脉冲 | mctm3 或 mctm4 任一上升沿均可触发 | P1 | §3.4, §4.5 |  |
| TRG_SEL_RESERVED | 触发源编码 1001~1111 保留不触发 | TRG_SEL=1001~1111，施加任何 mctm_trig | 保留编码下任何触发源都不产生触发 | P2 | §3.4, §4.5 |  |
| TRG_SEL_TUE | 触发源编码 1000 = tue | TRG_SEL=1000，施加 tue 触发 | tue 源触发有效 | P1 | §3.4, §4.5 |  |

### 3.5 中断测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| INT_ADC_INT_DOMAIN | adc_int 在 PCLK 域由 INT_STAT & INT_EN 驱动 | 产生中断观察 adc_int 与 PCLK 时序 | adc_int 在 PCLK 域组合/寄存输出；INT_STAT 置位且 EN= | P1 | §2.5, §4.6, memory |  |
| INT_EN_GATING | 6 中断源通过 INT_EN 独立使能门控 | 各 INT_EN 位 0/1 组合下产生事件，观察 adc_int | EN=0 时事件仍置 INT_STAT 但不产生 adc_int；EN=1 时产 | P0 | §3.5, §4.6 |  |
| INT_HP_EOC | HP_EOC 高优先单次采样完成中断源 | HP 单次采样完成、HP_EOC_EN=1 | HP 每次单采样完成置 INT_STAT[2]；EN=1 时中断；W1C 清零 | P0 | §3.6, §4.6 |  |
| INT_HP_PREEMPT | HP_PREEMPT 高优先打断中断源 | HP 抢占 LP 发生、HP_PREEMPT_EN=1 | 每次 HP 抢占事件置 INT_STAT[4]；EN=1 时中断；W1C 清零 | P0 | §3.6, §4.6, §4.4 |  |
| INT_HP_SEQ_DONE | HP_SEQ_DONE 高优先序列完成中断源 | HP 序列执行满 HP_SEQ_LEN、HP_SEQ_DONE_EN=1 | HP 序列完成置 INT_STAT[3]；EN=1 时中断；W1C 清零 | P0 | §3.6, §4.6 |  |
| INT_LP_EOC | LP_EOC 低优先单次采样完成中断源 | LP 单次采样完成、LP_EOC_EN=1 | LP 每次单采样完成置 INT_STAT[0]；EN=1 时 adc_int 拉 | P0 | §3.6, §4.6 |  |
| INT_LP_SEQ_DONE | LP_SEQ_DONE 低优先序列完成中断源 | LP 序列执行满 LP_SEQ_LEN、LP_SEQ_DONE_EN=1 | 序列完成置 INT_STAT[1]；EN=1 时触发中断；W1C 清零 | P0 | §3.6, §4.6 |  |
| INT_OVERRUN | OVERRUN 任意通道数据溢出中断源 | 任意通道 VALID=1 时新采样完成、OVERRUN_EN=1 | 32 通道任一 overflow 事件均置同一个 INT_STAT[5]；EN= | P0 | §3.6, §3.11, §4.6 |  |
| INT_W1C | INT_STAT 写1清零机制 | 多中断位同时置位后分别 W1C 清零 | 对某位写1清零该位、写0不变；可选择性清零；清零后若事件仍活跃不重新置位（电平已 | P0 | §3.6, §4.6 |  |

### 3.6 DMA测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| DMA_ACK_HANDSHAKE | dma_ndreq 低有效请求 + dma_ack 握手清除 | DMA 请求发出后施加 dma_ack，观察 dma_ndreq 与 DMA_STAT | 请求时 dma_ndreq 拉低；dma_ack 响应后 dma_ndreq 回 | P0 | §2.5, §4.7 |  |
| DMA_EN_GATING | DMA_EN 全局使能门控所有 DMA 请求 | DMA_EN=0/1 与各事件使能位组合下产生事件 | DMA_EN=0 时任何事件都不产生 DMA 请求；=1 时按各事件使能位独立产 | P0 | §3.12, §4.7 |  |
| DMA_HP_EOC | DMA_HP_EOC 高优单次完成触发 DMA 请求 | DMA_EN=1、DMA_HP_EOC=1，HP 单采样完成 | HP 单采样完成产生 DMA 请求 | P1 | §3.12, §4.7 |  |
| DMA_HP_SEQ | DMA_HP_SEQ 高优序列完成触发 DMA 请求 | DMA_EN=1、DMA_HP_SEQ=1，HP 序列完成 | HP 序列完成产生 DMA 请求 | P1 | §3.12, §4.7 |  |
| DMA_INDEP_INT | DMA 请求与中断共享事件源但走独立使能路径互不干扰 | 同一事件使能 INT 与 DMA 各种组合 | 同一事件可只触发中断、只触发 DMA、两者都触发或都不触发，由 INT_EN 和 | P1 | §3.12, §4.7 |  |
| DMA_LP_EOC | DMA_LP_EOC 低优单次完成触发 DMA 请求 | DMA_EN=1、DMA_LP_EOC=1，LP 单采样完成 | LP 单采样完成产生 DMA 请求脉冲；dma_ack 后清除 | P1 | §3.12, §4.7 |  |
| DMA_LP_SEQ | DMA_LP_SEQ 低优序列完成触发 DMA 请求 | DMA_EN=1、DMA_LP_SEQ=1，LP 序列完成 | LP 序列完成产生 DMA 请求；dma_ack 后清除 | P1 | §3.12, §4.7 |  |
| DMA_OVERRUN | DMA_OVERRUN 溢出触发 DMA 请求 | DMA_EN=1、DMA_OVERRUN=1，发生溢出 | 溢出事件产生 DMA 请求 | P1 | §3.12, §4.7 |  |

### 3.7 校准测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| CAL_20CYCLE | 校准固定 20 个 ADC_CLK 周期后置 CAL_DONE | CAL_ST=1 后计数 ADC_CLK 周期数至 CAL_DONE 置1 | 模拟在 CAL_ST=1 期间计数 0~19，第20周期满置 CAL_DONE= | P0 | §3.7, §5.3 |  |
| CAL_ADC_EN_GATE | 校准前提：仅 ADC_EN=1 时可校准，ADC_EN=0 清 CAL_ST/C | ADC_EN=0 时写 CAL_ST=1；校准中清 ADC_EN | ADC_EN=0 时 CAL_ST 被硬件清0、CAL_DONE 清0；校准中清 | P1 | §3.7, §5.3 |  |
| CAL_DONE_CLR | CAL_DONE 清0条件：CAL_ST=0 或 ADC_EN=0 或复位 | CAL_DONE=1 后分别清 CAL_ST、清 ADC_EN、施加复位 | 任一条件触发 CAL_DONE=0；cal_done_s2 经2级同步后跟随清0 | P0 | §3.7, §5.3 |  |
| CAL_DONE_SET | CAL_DONE 置1条件：CAL_ST=1 且校准满20个ADC_CLK周期 | CAL_ST=1 维持满20周期 | 条件满足时 CAL_DONE 置1并保持；cal_val 在此前已稳定送出 | P0 | §3.7, §5.3 |  |
| CAL_DONE_SYNC | CAL_DONE 经 PCLK 2级同步（cal_done_s1/s2）后读 | 模拟 CAL_DONE 翻转，观察 PCLK 域 cal_done_s1/s2 | 模拟 CAL_DONE 是 ADC_CLK 域稳定电平，经2级同步后供 CAL_ | P0 | §2.3, §3.7, §5.3 |  |
| CAL_FLOW | 校准流程8步（ADC_EN→CAL_ST=1→模拟计数20→CAL_DONE=1 | 按8步校准流程完整执行 | 完成全流程；CAL_VAL 锁存正确；CAL_CTRL[1] 可轮询到1；写 C | P0 | §3.7, §5.3 |  |
| CAL_NO_TIMEOUT | 控制器不实现超时保护，软件通过 CAL_BUSY 卡死判定异常 | 模拟 IP 故障使 CAL_DONE 永不返回 | CAL_CTRL[1] 始终读0；STAT[3] CAL_BUSY 保持1；软件 | P2 | §3.7 |  |
| CAL_PARALLEL | 校准与采样不互斥：控制器不强制屏蔽，由软件保证不发起采样 | 校准期间软件发起采样（违反软件约定） | 控制器不屏蔽校准期间的采样请求；行为由软件保证；此为软件责任，控制器不报错 | P2 | §3.7 |  |
| CAL_RECAL | 重新校准：写 CAL_ST=0 清模拟 CAL_DONE 后再写1重新计数20周 | 完成一次校准后再写 CAL_ST=1 重新校准 | 写 CAL_ST=0 后模拟 CAL_DONE=0；再写1可重新计数20周期完成 | P1 | §3.7, §5.3 |  |
| CAL_ST_DIRECT | CAL_ST 为 PCLK 域 RW 寄存器位直送模拟，无 CDC 同步器 | 软件写 CAL_ST，观察 CAL_ST 端口直送模拟 | CAL_ST 端口电平直接跟随 cal_ctrl_reg[0]；PCLK→模拟跨 | P1 | §2.3, §3.7, §5.3 |  |
| CAL_VAL_LATCH | cal_val 在 cal_done_s2=1 时锁存到 CAL_VAL | 观察 cal_val 锁存时刻与 CAL_DONE 同步关系 | cal_val 在 CAL_DONE 之前稳定；控制器在 PCLK 域 cal_ | P1 | §3.8, §5.3 |  |

### 3.8 复位测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| RST_DEFAULT_VALUES | 复位后所有寄存器恢复默认值 | 复位后逐个读所有寄存器 | CTRL=0(ADC_EN=0等)、LP_SEQ_LEN=26、HP_SEQ_L | P0 | §3.2~§3.17, §6.1 |  |
| RST_DURING_ACQ | 采集中复位：FSM/计数器/数据寄存器正确清理 | 采样/转换/HP 抢占/校准进行中施加复位 | 复位立即中止当前采样/转换；FSM 回 IDLE；SOC/MUXON/preem | P0 | §6.1, §4.x |  |
| RST_HW_PRSTN | PRSTn 硬件复位：异步断言立即复位 ADC_CLK 域，同步释放2级 | PRSTn 拉低再释放，观察 rst_adc_n 与寄存器 | PRSTn 下降沿立即复位所有 ADC_CLK 域寄存器；上升沿后经2级同步器约 | P0 | §2.2, §6.1 |  |
| RST_PRESETN | PRESETn APB 域复位（与 PCLK 同步）直接使用 | PRESETn 拉低再释放，观察 APB 寄存器 | PRESETn 低期间所有 APB 域寄存器复位到默认值；释放后寄存器可重新配置 | P0 | §2.2, §6.1 |  |
| RST_REENABLE | 复位释放后重新使能并正常工作 | 复位释放后按初始化流程重新配置并启动采样 | 复位释放后按初始化8步流程配置，ADC 可正常采样/校准；无复位残留状态 | P1 | §6.2 |  |
| RST_SHARED_SYNC | SW_RST 与 PRSTn 共享同一2级同步释放电路 | 分别触发 PRSTn 和 SW_RST，观察 rst_adc_n 时序 | 两者相与后送入同一同步器；时序行为一致（异步断言、同步释放约2个 ADC_CLK | P1 | §6.1 |  |
| RST_SW_RST | SW_RST 软件复位写1触发、硬件自清零，复位所有寄存器和 FSM | 配置寄存器与运行采样中写 CTRL[1]=1 | 写1后 SW_RST 自清零；所有寄存器回默认值；ADC FSM 回 IDLE； | P0 | §3.2, §6.1 |  |

### 3.3 时序测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| TIM_3MSPS | 最高 3 Msps 采样率 | ADC_CLK=60MHz、最小 SPT+间隔配置下连续采样测量吞吐 | 在最高配置下采样率可达 3 Msps；ADC_CLK 最高 60MHz；时序闭合 | P1 | §1.1, §2.2 |  |
| TIM_CH_SEL_LATCH | ch_sel 在 MUXON↓ 时锁存下一通道并保持稳定；复位默认 CH0 | 观察 MUXON↓ 时 ch_sel 切换；复位后观察 ch_sel 默认值 | 正常推进时 MUXON↓ 锁存 cur_ch_sel 并保持到下次 MUXON↓ | P0 | §2.3, §4.4 |  |
| TIM_DUAL_CLK | 双时钟架构 ADC_CLK/ADC_CLKn 同源反相同步时钟 | ADC_CLK/ADC_CLKn 同源反相运行，跨域路径采样 | 两时钟同频固定相位差180°；跨域只需1级采样寄存器无需2级同步器；STA 按半 | P1 | §1.1, §2.2, project_config |  |
| TIM_EOC | EOC 单周期脉冲在 ADC_CLK↓ 产生 | 观察 EOC 脉冲宽度与产生沿 | EOC 在 negedge adc_clk 产生单周期；adc_data 与 E | P0 | §2.3, §5.1 |  |
| TIM_EOC_SAMPLE | 控制器在 ADC_CLK↑ 采样 EOC 并锁存 ADC_DATA | 观察控制器对 EOC 的采样沿 | 控制器 posedge adc_clk 采样到 EOC 后锁存 adc_data | P0 | §4.1, §5.1 |  |
| TIM_MUXON_FALL | MUXON 在 SPT 计数满后拉低 | 配置 SPT 后观察 MUXON 高电平持续周期 | SPT 计数器在 MUXON=1 期间计数，计满同沿拉低 MUXON；拉低触发锁 | P0 | §2.3, §4.1 |  |
| TIM_MUXON_RISE | MUXON 与 SOC 同沿(adc_clkn↑)拉高 | 观察 SOC 与 MUXON 拉高时刻 | MUXON 在与 SOC 相同的 posedge adc_clkn 拉高；高电平 | P0 | §2.3, §5.1 |  |
| TIM_PREEMPT_ABORT_MUXON | preempt_abort 时 MUXON 强制拉低 | LP MUXON 高电平期间触发 HP 抢占 | 抢占发生 MUXON 立即被强制拉低，模拟清除 conv_active 不产生  | P0 | §4.4 |  |
| TIM_PREEMPT_HOLD | preempt_hold 寄存器保护 ch_sel_reg 防止 muxon_f | LP CH1 采样中被 HP CH8 抢占，观察 ch_sel 序列 0→8→8 | preempt_abort 立即切到 hp_ch_sel；preempt_hol | P0 | §4.4 |  |
| TIM_PREEMPT_LP_INTERVAL | HP 抢占时机3：ST_LP_INTERVAL→ST_LP_PREEMPT→ST | LP 处于 ST_LP_INTERVAL 时触发 HP | ST_LP_INTERVAL 检测 hp_trig_pulse 转入 ST_LP | P0 | §4.4 |  |
| TIM_PREEMPT_LP_SAMPLE | HP 抢占时机1：ST_LP_SAMPLE→ST_LP_PREEMPT→ST_H | LP 处于 ST_LP_SAMPLE 时触发 HP | ST_LP_SAMPLE 检测 hp_trig_pulse 转入 ST_LP_P | P0 | §4.4 |  |
| TIM_PREEMPT_LP_WAIT_EOC | HP 抢占时机2：ST_LP_WAIT_EOC→ST_LP_PREEMPT→ST | LP 处于 ST_LP_WAIT_EOC 时触发 HP | ST_LP_WAIT_EOC 检测 hp_trig_pulse 转入 ST_LP | P0 | §4.4 |  |
| TIM_PREEMPT_RST_N | preempt_rst_n 低有效单周期脉冲，先于 HP SOC 至少1个 ad | LP 采样中触发 HP，观察 preempt_rst_n 与 HP SOC 时序 | preempt_rst_n 在 ST_LP_PREEMPT 同拍拉低（组合驱动） | P0 | §2.3, §4.4 |  |
| TIM_PREEMPT_SAME_CYCLE | preempt_rst_n/preempt_abort 组合同拍生效，preem | 观察 ST_LP_PREEMPT 状态与 preempt_rst_n、preempt_abort、p | Cycle N posedge adc_clk 进入 ST_LP_PREEMPT | P0 | §4.4 |  |
| TIM_PREEMPT_SOC_PEND | preempt_soc_pend 在 ST_LP_PREEMPT 置位，推迟到  | 跟踪 preempt_soc_pend 寄存器在 PREEMPT 置位、HP_SAMPLE 释放 | PREEMPT 态 soc_req_set=0 不发 SOC；进 HP_SAMP | P0 | §4.4 |  |
| TIM_SOC | SOC 单周期脉冲在 ADC_CLKn↑ 产生 | 触发后观察 SOC 脉冲宽度与产生沿 | SOC 在 posedge adc_clkn 产生，持续单周期；模拟在下一个 A | P0 | §2.3, §5.1 |  |

### 3.9 边界挑战测试

| ID | 测试点 | 场景 | 预期结果 | 优先级 | Spec | 状态 |
|:--|:--|:--|:--|:--:|:--|:--:|
| EDGE_001 | DMA_BUSY 同步链断裂：adc_regfile.v:802 `dma_bu | DMA_BUSY 同步链断裂：adc_regfile.v:802 `dma_busy_s2 <= d | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_002 | CH_DATA 的 DATA[15:0] 域由 PCLK 组合逻辑直读 ADC_ | CH_DATA 的 DATA[15:0] 域由 PCLK 组合逻辑直读 ADC_CLK 域寄存器：a | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_003 | CH_DATA VALID 读清与 EOC 新写同周期竞争：adc_regfil | CH_DATA VALID 读清与 EOC 新写同周期竞争：adc_regfile.v:732-73 | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_004 | OVERRUN 检测使用 seq_fsm 内部 ch_valid[31:0](a | OVERRUN 检测使用 seq_fsm 内部 ch_valid[31:0](adc_seq_fsm | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_005 | PCLK 读 CH_DATA 恰逢 ADC_CLK 域 eoc_captured | PCLK 读 CH_DATA 恰逢 ADC_CLK 域 eoc_captured 写拍：FSM 在  | 需决策 | P1 | 边界挑战 |  |
| EDGE_006 | SW_RST 与 PRSTn 共享同一 2 级同步器(adc_top.v:128 | SW_RST 与 PRSTn 共享同一 2 级同步器(adc_top.v:128 sw_rst_n= | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_007 | SW_RST 期间进行中的模拟转换未通过 preempt_rst_n 复位(SW | SW_RST 期间进行中的模拟转换未通过 preempt_rst_n 复位(SW_RST 不驱动 p | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_008 | 复位在 ST_LP_PREEMPT 拍到达：rst_adc_n=0 异步复位 f | 复位在 ST_LP_PREEMPT 拍到达：rst_adc_n=0 异步复位 fsm_curr_st | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_009 | EOC 保持高多周期跨采样边界：SMP_019 仅验证单次 WAIT_EOC 内 | EOC 保持高多周期跨采样边界：SMP_019 仅验证单次 WAIT_EOC 内不重复捕获，但未覆盖 | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_010 | CAL_DONE 保持高时 cal_val_reg 每拍重锁存：adc_regf | CAL_DONE 保持高时 cal_val_reg 每拍重锁存：adc_regfile.v:461  | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_011 | CAL_ST 保持高(CAL_CTRL[0]=1 未清)：adc_top.v:3 | CAL_ST 保持高(CAL_CTRL[0]=1 未清)：adc_top.v:335 cal_bus | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_012 | LP_SEQ_LEN=0：adc_seq_fsm.v:591,748 `lp_s | LP_SEQ_LEN=0：adc_seq_fsm.v:591,748 `lp_seq_ptr >=  | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_013 | LP_SEQ_LEN=33~63：lp_seq_ptr 为 5-bit(0~31 | LP_SEQ_LEN=33~63：lp_seq_ptr 为 5-bit(0~31)，条件 `ptr  | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_014 | HP_SEQ_LEN=0：adc_seq_fsm.v:628,781,806 ` | HP_SEQ_LEN=0：adc_seq_fsm.v:628,781,806 `hp_seq_ptr | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_015 | SMPL_INTERVAL 位宽与 spec 矛盾：spec §3.2 CTRL | SMPL_INTERVAL 位宽与 spec 矛盾：spec §3.2 CTRL[7:4] SMPL | 需决策 | P1 | 边界挑战 |  |
| EDGE_016 | 通道 26~31(预留空间)被采样时静默写入：spec §1.1 称 26 模拟 | 通道 26~31(预留空间)被采样时静默写入：spec §1.1 称 26 模拟通道、地址空间按 3 | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_017 | CONT_MODE 下 ADC_EN=0 不停止：adc_seq_fsm.v:5 | CONT_MODE 下 ADC_EN=0 不停止：adc_seq_fsm.v:593-595，ST_ | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_018 | LP 抢占恢复哨兵冲突：lp_save_ptr 复位为 5'h1F(adc_se | LP 抢占恢复哨兵冲突：lp_save_ptr 复位为 5'h1F(adc_seq_fsm.v:67 | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_019 | TRIG WO 位(bit0/bit8)RTL 不自清零：spec §3.4 与 | TRIG WO 位(bit0/bit8)RTL 不自清零：spec §3.4 与 testplan  | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_020 | 非法 FSM 状态 4'h9~F 的 STAT 表现：adc_seq_fsm.v | 非法 FSM 状态 4'h9~F 的 STAT 表现：adc_seq_fsm.v:820 `stat | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_021 | bind_adc_assert.sv:63-68 断言 p_cal_st_soc | bind_adc_assert.sv:63-68 断言 p_cal_st_soc_exclusive | 按挑战点描述验证 | P1 | 边界挑战 |  |
| EDGE_022 | spec §3.7 校准与采样互斥为"软件责任"，RTL 完全并行(FSM 不检 | spec §3.7 校准与采样互斥为"软件责任"，RTL 完全并行(FSM 不检查 cal_st)。 | 需决策 | P1 | 边界挑战 |  |
| EDGE_023 | dma_ack 与新 EOC 同拍请求丢失：adc_dma_req.v:71-8 | dma_ack 与新 EOC 同拍请求丢失：adc_dma_req.v:71-83，同拍内若 ena | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_024 | mctm_trig 1-ADC_CLK 周期宽毛刺被确定性捕获：testplan | mctm_trig 1-ADC_CLK 周期宽毛刺被确定性捕获：testplan TRG_007 以 | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_025 | adc_data 全 0/全 1 边界 + 对齐切换未单独验证：adc_data | adc_data 全 0/全 1 边界 + 对齐切换未单独验证：adc_data 为 14-bit， | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_026 | LP+HP 同写周期 SW_TRIG(TRG_009)未实现：verify_co | LP+HP 同写周期 SW_TRIG(TRG_009)未实现：verify_completeness | 按挑战点描述验证 | P2 | 边界挑战 |  |
| EDGE_027 | SW+MCTM 同周期到达(TRG_008)验证不充分：adc_trig_syn | SW+MCTM 同周期到达(TRG_008)验证不充分：adc_trig_sync.v:175 lp | 按挑战点描述验证 | P2 | 边界挑战 |  |

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

## 5. RTL 逻辑路径覆盖映射

共 149 条逻辑路径。

| 类型 | 描述 | 文件:行号 | 覆盖需求 |
|:--|:--|:--|:--|
| FSM状态 | FSM 状态 ST_IDLE (4'h0)：复位/空闲态，清零 lp_seq_p | /path/to/adc_new/rtl/adc_seq_fsm.v:112 | 复位后与 SW_RST 后确认 fsm_curr_st==ST_IDLE；覆盖  |
| FSM状态 | FSM 状态 ST_WAIT_TRIG (4'h1)：等待 LP/HP 触发，L | /path/to/adc_new/rtl/adc_seq_fsm.v:113 | 覆盖 lp_trig_pulse 单独、hp_trig_pulse 单独、两者同 |
| FSM状态 | FSM 状态 ST_LP_SAMPLE (4'h2)：LP 采样期，SPT 计数 | /path/to/adc_new/rtl/adc_seq_fsm.v:114 | 覆盖 SPT 各档位下的 LP_SAMPLE 停留周期数；覆盖此态被 HP 抢占 |
| FSM状态 | FSM 状态 ST_LP_WAIT_EOC (4'h3)：等待 LP 转换完成  | /path/to/adc_new/rtl/adc_seq_fsm.v:115 | 覆盖 eoc_captured 到达与超时未到达；覆盖此态被 HP 抢占；覆盖  |
| FSM状态 | FSM 状态 ST_LP_INTERVAL (4'h4)：LP 通道间隔计数，完 | /path/to/adc_new/rtl/adc_seq_fsm.v:116 | 覆盖 interval_done 后 非末通道/末通道-cont/末通道-sin |
| FSM状态 | FSM 状态 ST_HP_SAMPLE (4'h5)：HP 采样期，首拍 SOC | /path/to/adc_new/rtl/adc_seq_fsm.v:117 | 覆盖抢占进入(首拍 SOC)与 WAIT_TRIG 直接触发(无 preempt |
| FSM状态 | FSM 状态 ST_HP_WAIT_EOC (4'h6)：等待 HP EOC，捕 | /path/to/adc_new/rtl/adc_seq_fsm.v:118 | 覆盖 eoc_captured 到达；overflow (hp_ch_valid |
| FSM状态 | FSM 状态 ST_HP_INTERVAL (4'h7)：HP 通道间隔，完成后 | /path/to/adc_new/rtl/adc_seq_fsm.v:119 | 覆盖 HP 末通道+有 LP 恢复、HP 末通道+无 LP+cont、HP 末通 |
| FSM状态 | FSM 状态 ST_LP_PREEMPT (4'h8)：LP 被抢占过渡态，拉低 | /path/to/adc_new/rtl/adc_seq_fsm.v:120 | 确认单周期停留；preempt_rst_n 低脉冲宽度=1 ADC_CLK；pr |
| FSM转移 | IDLE→WAIT_TRIG：cfg_adc_en=1 | /path/to/adc_new/rtl/adc_seq_fsm.v:542 | 覆盖 cfg_adc_en 0→1 上升沿后状态转移；2 级 CDC 同步延迟观 |
| FSM转移 | WAIT_TRIG→IDLE：cfg_adc_en=0 (运行中禁用 ADC) | /path/to/adc_new/rtl/adc_seq_fsm.v:548 | 覆盖运行中清 adc_en 各状态回归 IDLE；确认中途禁用不丢数据 |
| FSM转移 | WAIT_TRIG→HP_SAMPLE：hp_trig_pulse=1, soc | /path/to/adc_new/rtl/adc_seq_fsm.v:550 | 覆盖 HP 单独触发首通道 SOC 脉冲；确认 soc 在 posedge ad |
| FSM转移 | WAIT_TRIG→LP_SAMPLE：lp_trig_pulse=1, soc | /path/to/adc_new/rtl/adc_seq_fsm.v:554 | 覆盖 LP 单独触发首通道 SOC 脉冲 |
| FSM转移 | WAIT_TRIG 同周期 LP+HP 触发：HP 分支优先，LP 被忽略 (e | /path/to/adc_new/rtl/adc_seq_fsm.v:550 | 同周期注入 lp_trig_pulse+hp_trig_pulse，确认进 HP |
| FSM转移 | LP_SAMPLE→LP_PREEMPT：hp_trig_pulse=1, pr | /path/to/adc_new/rtl/adc_seq_fsm.v:561 | 在 LP_SAMPLE 任意 SPT 计数中点注入 HP 触发；确认 spt_c |
| FSM转移 | LP_SAMPLE→LP_WAIT_EOC：spt_done=1 (采样完成) | /path/to/adc_new/rtl/adc_seq_fsm.v:565 | 覆盖 SPT 8 档位全到达 spt_done 转移 |
| FSM转移 | LP_WAIT_EOC→LP_PREEMPT：hp_trig_pulse=1,  | /path/to/adc_new/rtl/adc_seq_fsm.v:572 | 在 LP_WAIT_EOC 期间注入 HP 触发；确认未完成的 LP 转换被 a |
| FSM转移 | LP_WAIT_EOC→LP_INTERVAL：eoc_captured=1,  | /path/to/adc_new/rtl/adc_seq_fsm.v:576 | 覆盖 EOC 到达后进间隔；确认 lp_eoc_pulse 单周期脉冲与 CH_ |
| FSM转移 | LP_INTERVAL→LP_PREEMPT：hp_trig_pulse=1,  | /path/to/adc_new/rtl/adc_seq_fsm.v:585 | 在 LP_INTERVAL 各计数值注入 HP 触发；确认间隔计数被抢占打断 |
| FSM转移 | LP_INTERVAL→LP_SAMPLE：interval_done + 末通 | /path/to/adc_new/rtl/adc_seq_fsm.v:593 | cont_mode=1, lp_seq_len=N, 走完 N 通道后确认 lp |
| FSM转移 | LP_INTERVAL→WAIT_TRIG：interval_done + 末通 | /path/to/adc_new/rtl/adc_seq_fsm.v:596 | cont_mode=0, 走完序列确认回 WAIT_TRIG 且 lp_seq_ |
| FSM转移 | LP_INTERVAL→LP_SAMPLE：interval_done + 非末 | /path/to/adc_new/rtl/adc_seq_fsm.v:600 | 覆盖 lp_seq_len=2..32 各长度下逐通道推进；边界 len=1(无 |
| FSM转移 | HP_SAMPLE→HP_WAIT_EOC：spt_done=1 | /path/to/adc_new/rtl/adc_seq_fsm.v:613 | 覆盖 HP 路径 SPT 8 档位 spt_done 转移 |
| FSM转移 | HP_WAIT_EOC→HP_INTERVAL：eoc_captured=1,  | /path/to/adc_new/rtl/adc_seq_fsm.v:619 | 确认 hp_eoc_pulse 单周期；HP CH_DATA 写入 hp_ch_ |
| FSM转移 | HP_INTERVAL→LP_SAMPLE：interval_done + HP | /path/to/adc_new/rtl/adc_seq_fsm.v:628 | 抢占后 HP 走完，确认 lp_seq_ptr 恢复为 lp_save_ptr  |
| FSM转移 | HP_INTERVAL→HP_SAMPLE：interval_done + HP | /path/to/adc_new/rtl/adc_seq_fsm.v:636 | 无 LP 恢复 + cont 模式下 HP 自动重启；确认 lp_save_pt |
| FSM转移 | HP_INTERVAL→WAIT_TRIG：interval_done + HP | /path/to/adc_new/rtl/adc_seq_fsm.v:639 | 无 LP 恢复 + 单次模式 HP 结束回 WAIT_TRIG；hp_seq_d |
| FSM转移 | HP_INTERVAL→HP_SAMPLE：interval_done + HP | /path/to/adc_new/rtl/adc_seq_fsm.v:643 | 覆盖 hp_seq_len=1..4 各长度逐通道推进；边界 len=1 与 l |
| FSM转移 | LP_PREEMPT→HP_SAMPLE：无条件转移 (单周期过渡) | /path/to/adc_new/rtl/adc_seq_fsm.v:651 | 确认 LP_PREEMPT 恰停留 1 周期；preempt_rst_n 在此态 |
| default分支 | FSM next-state default：任意非法状态(4'h9~4'hF) | /path/to/adc_new/rtl/adc_seq_fsm.v:657 | 用 force 注入非法状态 4'h9..4'hF，确认次周期回 IDLE；形式 |
| ... | 共 149 条 | | |

## 6. 边界挑战三分类

| ID | 类别 | 描述 | 严重度 | 可行性 |
|:--|:--|:--|:--:|:--|
| CH-001 | 跨域交互 | DMA_BUSY 同步链断裂：adc_regfile.v:802 `dma_busy_s2 <= d | 高 | 可测 |
| CH-002 | 跨域交互 | CH_DATA 的 DATA[15:0] 域由 PCLK 组合逻辑直读 ADC_CLK 域寄存器：a | 高 | 可测 |
| CH-003 | 跨域交互 | CH_DATA VALID 读清与 EOC 新写同周期竞争：adc_regfile.v:732-73 | 中 | 可测 |
| CH-004 | 跨域交互 | OVERRUN 检测使用 seq_fsm 内部 ch_valid[31:0](adc_seq_fsm | 高 | 可测 |
| CH-005 | 跨域交互 | PCLK 读 CH_DATA 恰逢 ADC_CLK 域 eoc_captured 写拍：FSM 在  | 中 | 需决策 |
| CH-006 | 复位行为 | SW_RST 与 PRSTn 共享同一 2 级同步器(adc_top.v:128 sw_rst_n= | 中 | 可测 |
| CH-007 | 复位行为 | SW_RST 期间进行中的模拟转换未通过 preempt_rst_n 复位(SW_RST 不驱动 p | 中 | 可测 |
| CH-008 | 复位行为 | 复位在 ST_LP_PREEMPT 拍到达：rst_adc_n=0 异步复位 fsm_curr_st | 中 | 可测 |
| CH-009 | 信号粘着 | EOC 保持高多周期跨采样边界：SMP_019 仅验证单次 WAIT_EOC 内不重复捕获，但未覆盖 | 中 | 可测 |
| CH-010 | 信号粘着 | CAL_DONE 保持高时 cal_val_reg 每拍重锁存：adc_regfile.v:461  | 中 | 可测 |
| CH-011 | 信号粘着 | CAL_ST 保持高(CAL_CTRL[0]=1 未清)：adc_top.v:335 cal_bus | 低 | 可测 |
| CH-012 | 边界值 | LP_SEQ_LEN=0：adc_seq_fsm.v:591,748 `lp_seq_ptr >=  | 高 | 可测 |
| CH-013 | 边界值 | LP_SEQ_LEN=33~63：lp_seq_ptr 为 5-bit(0~31)，条件 `ptr  | 高 | 可测 |
| CH-014 | 边界值 | HP_SEQ_LEN=0：adc_seq_fsm.v:628,781,806 `hp_seq_ptr | 高 | 可测 |
| CH-015 | spec与RTL不一致 | SMPL_INTERVAL 位宽与 spec 矛盾：spec §3.2 CTRL[7:4] SMPL | 高 | 需决策 |
| CH-016 | 边界值 | 通道 26~31(预留空间)被采样时静默写入：spec §1.1 称 26 模拟通道、地址空间按 3 | 中 | 可测 |
| CH-017 | 设计未定义行为 | CONT_MODE 下 ADC_EN=0 不停止：adc_seq_fsm.v:593-595，ST_ | 高 | 可测 |
| CH-018 | 设计未定义行为 | LP 抢占恢复哨兵冲突：lp_save_ptr 复位为 5'h1F(adc_seq_fsm.v:67 | 中 | 可测 |
| CH-019 | 设计未定义行为 | TRIG WO 位(bit0/bit8)RTL 不自清零：spec §3.4 与 testplan  | 中 | 可测 |
| CH-020 | 设计未定义行为 | 非法 FSM 状态 4'h9~F 的 STAT 表现：adc_seq_fsm.v:820 `stat | 低 | 可测 |
| CH-021 | spec与RTL不一致 | bind_adc_assert.sv:63-68 断言 p_cal_st_soc_exclusive | 高 | 可测 |
| CH-022 | spec与RTL不一致 | spec §3.7 校准与采样互斥为"软件责任"，RTL 完全并行(FSM 不检查 cal_st)。 | 中 | 需决策 |
| CH-023 | 外部接口异常 | dma_ack 与新 EOC 同拍请求丢失：adc_dma_req.v:71-83，同拍内若 ena | 中 | 可测 |
| CH-024 | 外部接口异常 | mctm_trig 1-ADC_CLK 周期宽毛刺被确定性捕获：testplan TRG_007 以 | 中 | 可测 |
| CH-025 | 外部接口异常 | adc_data 全 0/全 1 边界 + 对齐切换未单独验证：adc_data 为 14-bit， | 低 | 可测 |
| CH-026 | 异常场景 | LP+HP 同写周期 SW_TRIG(TRG_009)未实现：verify_completeness | 中 | 可测 |
| CH-027 | 异常场景 | SW+MCTM 同周期到达(TRG_008)验证不充分：adc_trig_sync.v:175 lp | 低 | 可测 |

## 变更记录

| 版本 | 日期 | 变更类型 | 变更内容 | 原因 |
|:--|:--|:--|:--|:--|
| v2.0 | 2026-07-13 | 重新生成 | /testplan-gen 3 agent 并行分析，142 测试点 | 旧 testplan 标 ✅ 与 sequence 实现脱节，重新生成干净版本 |