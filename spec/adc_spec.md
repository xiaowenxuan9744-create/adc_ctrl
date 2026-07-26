# ADC 控制器规格文档

## 1. 概述

本文档定义了 ADC（模数转换器）控制器的功能规格、接口定义、寄存器映射和时序要求。

### 1.1 特性

- 参数化 ADC 精度（`ADC_DATA_W`，默认 14-bit，范围 1~16；DATA 寄存器域固定 16bit）
- 最高 3 Msps 采样率
- 参数化通道数（`ADC_NUM_CH`，默认 26，范围 4~32；地址空间按 32 预留）
- 参数化 SPT1 作用通道（`ADC_SPT1_CH_MASK` 位图，默认 CH21/CH22）
- 双时钟架构（ADC_CLK / ADC_CLKn，相位相反，同步时钟）
- 支持 APB 32-bit 总线接口
- 支持两种转换模式：单次转换 / 连续转换
- 支持两种采样优先级：普通优先级（`ADC_NUM_CH` 序列条目） / 高优先级（固定 4 序列条目）
- 高优先级可抢占低优先级采样
- 支持多种触发方式：软件触发 / MCTM 外部硬件触发
- 高优/低优各自独立配置触发源和使能
- 支持 DMA 请求（单次完成 / 序列完成）
- 支持中断（6 个中断事件源，独立使能）
- 数据有效标志（VALID bit） + 溢出检测
- 支持模拟自校准

> **参数化说明：** 三个主参数（`ADC_NUM_CH` / `ADC_DATA_W` / `ADC_SPT1_CH_MASK`）
> 默认值与原固定设计一致（26 通道 / 14bit / SPT1=CH21,CH22），向后兼容。
> 派生位宽与寄存器数详见 §3.0。改参数只需改 `rtl/adc_params.vh` 或实例化时
> `#(.ADC_NUM_CH(N))` override，无需改 RTL 逻辑。

---

## 2. 接口定义

### 2.1 APB 总线接口

| 信号 | 方向 | 说明 |
|:--|:--:|:--|
| PCLK | I | APB 时钟 |
| PRESETn | I | APB 复位（与 PCLK 同步，低有效） |
| PADDR[15:0] | I | APB 地址 |
| PWRITE | I | 读写选择：1=写，0=读 |
| PSEL | I | APB 选择 |
| PENABLE | I | APB 使能 |
| PWDATA[31:0] | I | APB 写数据 |
| PRDATA[31:0] | O | APB 读数据 |
| PREADY | O | APB 就绪 |
| PSLVERR | O | APB 错误（固定 0） |

### 2.2 ADC 时钟与复位

| 信号 | 方向 | 说明 |
|:--|:--:|:--|
| PCLK | I | APB 时钟，最高 200 MHz |
| ADC_CLK | I | ADC 工作时钟，最高 60 MHz（与 PCLK 异步） |
| ADC_CLKn | I | ADC 反向时钟（与 ADC_CLK 同步，相位相反） |
| PRESETn | I | APB 域复位（与 PCLK 同步，低有效），即顶层 `presetn` 端口 |
| PRSTn | I | ADC 域复位输入（与 ADC_CLK 异步，低有效），即顶层 `prstn` 端口 |

> **复位端口说明：** PRESETn 和 PRSTn 为同一外部复位信号的两个域入口。
> - `presetn` — APB 域直接使用的同步复位
> - `prstn` — 送入 ADC 域的异步复位同步释放器
>
> 两者在芯片外部连接同一复位源。

复位架构：
- APB 域：`PRESETn` 直接使用（已与 PCLK 同步）
- ADC 域：`PRSTn` + `sw_rst_n`（软件复位）相与 → 异步复位同步释放（2 级同步器）→ `rst_adc_n`
- 软件复位：写 CTRL[1]=1 触发，硬件自清零

### 2.3 模拟接口

| 信号 | 方向 | 位宽 | 说明 |
|:--|:--:|:--:|:--|
| SOC | O | 1 | 采样开始脉冲，ADC_CLKn↑ 产生，单周期。模拟在下一个 ADC_CLK↑ 检测上升沿 |
| MUXON | O | 1 | 采样使能电平，与 SOC 同沿拉高（posedge adc_clkn），SPT 计数满后拉低 |
| ch_sel | O | W_CH_SEL | 通道选择（位宽 = $clog2(ADC_NUM_CH)，默认 5），MUXON↓ 时锁存下一通道号并保持稳定；复位默认 CH0。HP 抢占时由 preempt_abort 立即切换 |
| EOC | I | 1 | 转换完成脉冲，ADC_CLK 下降沿产生，单周期 |
| adc_data | I | ADC_DATA_W | 转换结果（默认 14-bit），与 EOC 同时有效，并行 |
| CAL_ST | O | 1 | 校准启动电平，PCLK 域寄存器位 CAL_CTRL[0] 直接输出。软件写1置1、读到 CAL_DONE=1 后软件写0清；ADC_EN=0 或复位也清。直送模拟，模拟内部自行采样 |
| CAL_DONE | I | 1 | 校准完成电平，模拟产生：仅当 CAL_ST=1 且校准满 20 个 ADC_CLK 周期后置1并保持；CAL_ST=0 或 ADC_EN=0 或复位清0。控制器 PCLK 域打 2 拍同步后读 |
| cal_val | I | 6 | 校准值，模拟在 CAL_DONE 之前送出并保持；控制器 PCLK 域采样到 CAL_DONE=1（同步后）时锁存 |
| preempt_rst_n | O | 1 | HP 抢占时复位模拟电路，低有效脉冲，单周期。与 ST_LP_PREEMPT 状态同拍生效，先于 HP SOC 至少 1 个 adc_clk 周期 |

### 2.4 外部触发接口

| 信号 | 方向 | 说明 |
|:--|:--:|:--|
| mctm_trig[5:0] | I | MCTM 外部触发源（与 ADC_CLK 异步） |

外部触发信号需经过 CDC 同步（2 级同步器 + 上升沿检测）后使用。

### 2.5 中断与 DMA 接口

| 信号 | 方向 | 说明 |
|:--|:--:|:--|
| adc_int | O | 中断请求 |
| dma_ndreq | O | DMA 请求，低有效（active-low）。DMA 控制器拉低表示有请求，ack 后回高 |
| dma_ack | I | DMA 响应 |

---

## 3. 寄存器映射

APB 32-bit 总线，地址按 4 字节对齐。

### 3.0 参数化配置

本控制器支持三个参数化配置（默认值与原固定设计一致，向后兼容）：

| 参数 | 默认 | 范围 | 说明 |
|:--|:--:|:--|:--|
| `ADC_NUM_CH` | 26 | 4~32 | 通道数，影响 ch_sel/seq_ptr/seq_len 位宽、LP_DATA/LP_SEQ 寄存器数 |
| `ADC_DATA_W` | 14 | 1~16 | ADC 分辨率，影响 adc_data 端口宽度（DATA 寄存器域固定 16bit） |
| `ADC_SPT1_CH_MASK` | `32'h0060_0000` | 32bit 位图 | bit i=1 → 通道 i 用 SPT1；默认 CH21/CH22 |

派生位宽（由 `ADC_NUM_CH` 算出，集中定义于 `rtl/adc_params.vh`）：

| 派生 localparam | 公式 | 默认 26 | 8 通道 | 32 通道 |
|:--|:--|:--:|:--:|:--:|
| `W_CH_SEL` | `$clog2(N)` | 5 | 3 | 5 |
| `W_LP_SEQ_LEN` | `$clog2(N+1)` | 5 | 4 | 6 |
| `NUM_LP_DATA` | `N` | 26 | 8 | 32 |
| `NUM_LP_SEQ_REG` | `ceil(N/4)` | 7 | 2 | 8 |

地址空间固定按 32 预留：LP_DATA 0x24~0xA0、LP_SEQ 0xB8~0xD4 区间不变，
物理实现数随 `ADC_NUM_CH` 收缩，超出范围读回 0、写忽略。HP_DATA（4）、
HP_SEQ（1）、HP_SEQ_LEN（3bit）固定不参数化。

8bit seq entry 格式：`[W_CH_SEL-1:0]`=ch_sel，`[7:W_CH_SEL]`=rsv（位宽自适应）。
每组 32bit 寄存器放 4 个 entry（[7:0]/[15:8]/[23:16]/[31:24]）。
entry 内部只存 `W_CH_SEL` bit ch_sel，rsv 高位不存、读回 0（写 rsv 位无效）。

**默认 26 配置的细微变化（向后兼容，已确认接受）：**
- LP_SEQ 物理寄存器数 8→7：`ceil(26/4)=7`，0xD4（LP_SEQ7）从"实现 rsv entry"
  变"读回 0、写忽略"。
- LP_SEQ_LEN 物理位宽 6→5：`$clog2(27)=5`，仍能存 26；复位值 26 不变、软件
  写 26 仍正确，仅寄存器物理位宽收窄。

### 3.1 寄存器列表

| 地址 | 名称 | 属性 | 说明 |
|:--|:--|:--:|:--|
| 0x00 | CTRL | RW | 控制寄存器 |
| 0x04 | STAT | RO | 状态寄存器 |
| 0x08 | TRIG | RW | 触发控制寄存器 |
| 0x0C | INT_EN | RW | 中断使能寄存器 |
| 0x10 | INT_STAT | RW1C | 中断状态寄存器 |
| 0x14 | CAL_CTRL | RW | 校准控制寄存器 |
| 0x18 | CAL_VAL | RO | 校准值寄存器 |
| 0x1C | ANA_CFG | RW | 模拟配置寄存器 |
| 0x20 | ANA_REG | RW | 通用模拟寄存器 |
| 0x24 ~ 0xA0 | LP_DATA[0:NUM_LP_DATA-1] | RO | LP 序列数据寄存器（NUM_LP_DATA × 32-bit，默认 26，序列绑定；地址按 32 预留，超出读回 0） |
| 0xA4 ~ 0xB0 | HP_DATA[0:3] | RO | HP 序列数据寄存器（4 × 32-bit，序列绑定，固定） |
| 0xB4 | DMA_CTRL | RW | DMA 控制寄存器 |
| 0xB8 ~ 0xD4 | LP_SEQ[0:NUM_LP_SEQ_REG-1] | RW | 低优序列配置（NUM_LP_SEQ_REG × 32-bit，默认 7 组；地址按 8 组预留，超出读回 0 写忽略） |
| 0xD8 | HP_SEQ | RW | 高优序列配置（1 × 32-bit） |
| 0xDC | LP_SEQ_LEN | RW | 低优序列长度寄存器 |
| 0xE0 | HP_SEQ_LEN | RW | 高优序列长度寄存器 |

### 3.2 CTRL — 控制寄存器（0x00）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | ADC_EN | RW | 0 | ADC 全局使能，1=使能 |
| 1 | SW_RST | RW_SS | 0 | 软件复位，写1复位，硬件自清零 |
| 2 | RSVD | RO | 0 | 保留 |
| 3 | DATA_ALIGN | RW | 0 | 数据对齐：0=右对齐，1=左对齐 |
| 7:4 | RSVD | RO | 0 | 保留 |
| 10:8 | SPT0[2:0] | RW | 0 | 采样时间档位 0（默认非 SPT1 通道） |
| 13:11 | SPT1[2:0] | RW | 0 | 采样时间档位 1（由 `ADC_SPT1_CH_MASK` 位图决定，默认 CH21/CH22） |
| 14 | CONT_MODE | RW | 0 | 连续转换模式，1=使能 |
| 15 | RSVD | RO | 0 | 保留，读0 |
| 22:16 | SMPL_INTERVAL[6:0] | RW | 0 | 采样间隔，单位：ADC_CLK cycle，范围 0~127 |
| 31:23 | RSVD | RO | 0 | 保留 |

采样时间档位编码：

| SPT[2:0] | 采样时间 (cycle) |
|:--:|:--:|
| 000 | 3 |
| 001 | 8 |
| 010 | 14 |
| 011 | 29 |
| 100 | 42 |
| 101 | 56 |
| 110 | 78 |
| 111 | 240 |

### 3.3 STAT — 状态寄存器（0x04）

| 位 | 名称 | 属性 | 说明 |
|:--:|:--|:--:|:--|
| 0 | ADC_BUSY | RO | ADC 正在采样/转换 |
| 1 | LP_BUSY | RO | 低优序列正在执行 |
| 2 | HP_BUSY | RO | 高优序列正在执行 |
| 3 | CAL_BUSY | RO | 校准正在进行。由 `cal_busy = cfg_cal_st & ~cal_done` 派生（PCLK 域），经 2 级同步（`cal_busy_s1/s2`）后读 |
| 15:4 | RSVD | RO | 保留 |

### 3.4 TRIG — 触发控制寄存器（0x08）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | LP_SW_TRIG | WO | 0 | 低优先软件触发，写1启动 |
| 1 | LP_SW_TRG_EN | RW | 0 | 低优先软件触发使能 |
| 2 | LP_MCTM_EN | RW | 0 | 低优先 MCTM 外部触发使能 |
| 6:3 | LP_TRG_SEL[3:0] | RW | 0 | 低优先触发源选择 |
| 7 | RSVD | RO | 0 | 保留 |
| 8 | HP_SW_TRIG | WO | 0 | 高优先软件触发，写1启动 |
| 9 | HP_SW_TRG_EN | RW | 0 | 高优先软件触发使能 |
| 10 | HP_MCTM_EN | RW | 0 | 高优先 MCTM 外部触发使能 |
| 14:11 | HP_TRG_SEL[3:0] | RW | 0 | 高优先触发源选择 |
| 15 | RSVD | RO | 0 | 保留 |

触发源编码（TRG_SEL[3:0]）：

| 编码 | 触发源 |
|:--:|:--|
| 0000 | mctm0 |
| 0001 | mctm1 |
| 0010 | mctm2 |
| 0011 | mctm3 |
| 0100 | mctm4 |
| 0101 | mctm5 |
| 0110 | mctm3\|4 |
| 0111 | ecc |
| 1000 | tue |
| 1001~1111 | reserved |

### 3.5 INT_EN — 中断使能寄存器（0x0C）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | LP_EOC_EN | RW | 0 | 低优先单次采样完成中断使能 |
| 1 | LP_SEQ_DONE_EN | RW | 0 | 低优先序列完成中断使能 |
| 2 | HP_EOC_EN | RW | 0 | 高优先单次采样完成中断使能 |
| 3 | HP_SEQ_DONE_EN | RW | 0 | 高优先序列完成中断使能 |
| 4 | HP_PREEMPT_EN | RW | 0 | 高优先打断中断使能 |
| 5 | OVERRUN_EN | RW | 0 | 溢出错误中断使能 |
| 15:6 | RSVD | RO | 0 | 保留 |

### 3.6 INT_STAT — 中断状态寄存器（0x10）

| 位 | 名称 | 属性 | 说明 |
|:--:|:--|:--:|:--|
| 0 | LP_EOC | RW1C | 低优先单次采样完成 |
| 1 | LP_SEQ_DONE | RW1C | 低优先序列完成 |
| 2 | HP_EOC | RW1C | 高优先单次采样完成 |
| 3 | HP_SEQ_DONE | RW1C | 高优先序列完成 |
| 4 | HP_PREEMPT | RW1C | 高优先打断 |
| 5 | OVERRUN | RW1C | 溢出错误 |
| 15:6 | RSVD | RO | 保留 |

写 1 清零对应中断状态位。

### 3.7 CAL_CTRL — 校准控制寄存器（0x14）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | CAL_ST | RW | 0 | 校准启动电平，软件写1置1启动校准、读到 CAL_DONE=1 后软件写0清；ADC_EN=0 或复位也清。直送模拟（PCLK→模拟跨域，模拟内部自行采样） |
| 1 | CAL_DONE | RO | 0 | 校准完成状态，读回模拟 CAL_DONE 经 PCLK 2 级同步后的电平。模拟在 CAL_ST=1 且校准满 20 周期后置1，CAL_ST=0/ADC_EN=0/复位清0 |

> **CAL_ST 寄存器归属：** `cal_st` 是 PCLK 域普通 RW 寄存器位（CAL_CTRL[0]），
> **不跨域到 ADC_CLKn**——软件写1/写0直接控制，输出端口直送模拟，由模拟内部采样该电平。
> 这是最简单的设计：PCLK 域存状态、直出，无 CDC 同步器、无回程。
>
> **CAL_DONE 读路径：** 模拟 CAL_DONE 是 ADC_CLK 域电平，PCLK 域读取经 2 级同步
> （`cal_done_s1/s2`）后供 CAL_CTRL[1] 读，并作为 cal_val 锁存的依据。CAL_DONE 是持续稳定
> 电平（校准完成后保持到 CAL_ST=0），2 级同步安全。
>
> **校准与采样互斥：** 仅在 ADC_EN=1 时可校准；校准期间其他 ADC 采样由软件保证不发起
> （控制器不强制屏蔽，软件责任）。

校准流程：
1. 写 CTRL[0] ADC_EN=1（使能 ADC，校准前提）
2. 写 CAL_CTRL[0] CAL_ST=1 → `cal_st`（PCLK 寄存器）置1，CAL_ST 直送模拟
3. 模拟见 CAL_ST=1 启动校准，计数 20 个 ADC_CLK 周期（期间 CAL_DONE=0）
4. 20 周期满 → 模拟置 CAL_DONE=1，cal_val 在 CAL_DONE 之前已稳定送出
5. 控制器 PCLK 域 2 级同步采到 CAL_DONE=1 → 锁存 cal_val 到 CAL_VAL、CAL_CTRL[1] 读=1
6. 软件轮询读 CAL_CTRL[1]=1 → 读 CAL_VAL 获取校准值 → 写 CAL_CTRL[0]=0
7. 模拟见 CAL_ST=0 → CAL_DONE=0；`cal_st` 寄存器=0。校准完成
8. 重新校准：直接写 CAL_CTRL[0]=1（模拟 CAL_DONE 已因 CAL_ST=0 清0，可重新计数 20 周期）

> **设计说明：** 校准控制逻辑在 PCLK 域（`cal_st` 寄存器、CAL_DONE 同步读、cal_val 锁存），
> 无 ADC_CLKn 域状态。CAL_ST 跨域（PCLK→模拟）由模拟内部采样保证；CAL_DONE 跨域（模拟→PCLK）
> 经 2 级同步。控制器不实现超时保护：若模拟 IP 故障使 CAL_DONE 永不返回，软件读
> CAL_CTRL[1] 始终为0、`CAL_BUSY`（STAT[3]）保持为1，软件可判定异常并复位模块。

### 3.8 CAL_VAL — 校准值寄存器（0x18）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 5:0 | CAL_VAL[5:0] | RO | 0 | 6-bit 校准值，控制器 PCLK 域采样到 CAL_DONE=1（同步后）时锁存 |
| 15:6 | RSVD | RO | 0 | 保留 |

### 3.9 ANA_CFG — 模拟配置寄存器（0x1C）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 15:0 | ANA_CFG[15:0] | RW | 0 | 模拟配置 |
| 31:16 | RSVD | RO | 0 | 保留 |

### 3.10 ANA_REG — 通用模拟寄存器（0x20）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 31:0 | ANA_REG[31:0] | RW | 0 | 通用模拟配置，预留未定义 |

### 3.11 LP_DATAn / HP_DATAn — 序列数据寄存器（序列绑定）

数据寄存器从"通道绑定"改为"序列绑定"：每个序列位置对应一个独立的数据寄存器，
LP_DATA 索引为 LP 序列指针 `lp_seq_ptr`，HP_DATA 索引为 HP 序列指针 `hp_seq_ptr`。
EOC 那一拍 `seq_ptr` 的值就是被写入的数据寄存器索引。

#### LP_DATA[0:NUM_LP_DATA-1] — LP 序列数据寄存器（0x24 + n × 4，n=0..NUM_LP_DATA-1，默认 26 个）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 31 | VALID | RO | 0 | 数据有效标志。0→1：LP 序列位置 n 采样完成；1→0：读本寄存器时自清零 |
| 30:16 | RSVD | RO | 0 | 保留 |
| 15:0 | DATA[15:0] | RO | 0 | ADC 转换结果 |

地址范围：0x24（LP_DATA0）~ 0x24+(NUM_LP_DATA-1)×4（默认 0x88，LP_DATA25），间隔 4 字节，共 NUM_LP_DATA 个（默认 26）。

#### LP_DATA[NUM_LP_DATA:31] — 预留地址（0x24+NUM_LP_DATA×4 ~ 0xA0）

idx ≥ NUM_LP_DATA 不生成寄存器，读回 0、写忽略（地址空间按 32 预留）。

#### HP_DATA[0:3] — HP 序列数据寄存器（0xA4 + n × 4，n=0..3）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 31 | VALID | RO | 0 | 数据有效标志。0→1：HP 序列位置 n 采样完成；1→0：读本寄存器时自清零 |
| 30:16 | RSVD | RO | 0 | 保留 |
| 15:0 | DATA[15:0] | RO | 0 | ADC 转换结果 |

地址范围：0xA4（HP_DATA0）~ 0xB0（HP_DATA3），间隔 4 字节，共 4 个。

#### 数据对齐方式

| 对齐方式 | DATA 域位 | 说明 |
|:--|:--|:--|
| 右对齐 | [13:0] = ADC[13:0], [15:14] = 0 | 默认 |
| 左对齐 | [15:2] = ADC[13:0], [1:0] = 0 | |

#### 溢出检测

- 新采样完成时，若该序列位置 VALID=1（上次数据未读），产生 OVERRUN 中断
- 任意序列位置的 overflow 事件均触发同一个 OVERRUN 中断
- 数据被新采样覆盖，旧数据丢失
- overflow 事件在 PCLK 域由 `int_evt_pclk_rise[0]`（LP EOC）/ `int_evt_pclk_rise[2]`（HP EOC）
  握手到达时检测 `lp_valid_pclk[idx]` / `hp_valid_pclk[idx]` 产生

#### 数据流

```
ADC_CLK 域:
  LP EOC → eoc_idx_reg <= lp_seq_ptr
           lp_data[lp_seq_ptr] <= adc_data_aligned
           lp_eoc_pulse_r <= 1 (已有 int_events 链)
  HP EOC → eoc_idx_reg <= hp_seq_ptr
           hp_data[hp_seq_ptr] <= adc_data_aligned
           hp_eoc_pulse_r <= 1

PCLK 域 (复用 int_evt_pclk_rise):
  int_evt_pclk_rise[0] (LP EOC 握手到达):
    idx = eoc_idx_reg (直读,已稳定,不需同步)
    if (lp_valid_pclk[idx]) → overflow
    lp_valid_pclk[idx] <= 1'b1
  int_evt_pclk_rise[2] (HP EOC 握手到达):
    idx = eoc_idx_reg
    if (hp_valid_pclk[idx]) → overflow
    hp_valid_pclk[idx] <= 1'b1
  读 LP_DATA[idx]: lp_valid_pclk[idx] <= 0 (本地读清除,不需回传 ADC_CLK)
  读 HP_DATA[idx]: hp_valid_pclk[idx] <= 0
```

### 3.12 DMA_CTRL — DMA 控制寄存器（0xB4）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | DMA_EN | RW | 0 | DMA 全局使能 |
| 1 | DMA_LP_EOC | RW | 0 | 低优单次完成触发 DMA 请求 |
| 2 | DMA_LP_SEQ | RW | 0 | 低优序列完成触发 DMA 请求 |
| 3 | DMA_HP_EOC | RW | 0 | 高优单次完成触发 DMA 请求 |
| 4 | DMA_HP_SEQ | RW | 0 | 高优序列完成触发 DMA 请求 |
| 5 | DMA_OVERRUN | RW | 0 | 溢出触发 DMA 请求 |
| 15:6 | RSVD | RO | 0 | 保留 |

DMA 请求与中断共享同一事件源，但走独立使能路径，互不干扰。

DMA_STAT 寄存器已删除（不再提供 DMA_BUSY/DMA_DONE 软件可读状态）。

### 3.13 LP_SEQn — 低优序列配置寄存器（0xB8 + n × 4）

每个 32-bit 寄存器包含 4 个 8-bit 序列条目（占位）。**内部只存每个 entry 的 `W_CH_SEL` bit ch_sel**，rsv 高位不存、读回 0（写 rsv 位无效）。

**条目格式（8-bit 占位，ch_sel 位宽自适应）：**

| 位 | 名称 | 说明 |
|:--:|:--|:--|
| [W_CH_SEL-1:0] | CH_SEL | 通道号 0~ADC_NUM_CH-1（位宽 = $clog2(ADC_NUM_CH)，存储/传输位宽 = W_CH_SEL） |
| [7:W_CH_SEL] | RSVD | 保留，不存、读回 0 |

**寄存器布局：**

| [31:24] | [23:16] | [15:8] | [7:0] |
|:--|:--|:--|:--|
| ENTRY #3 | ENTRY #2 | ENTRY #1 | ENTRY #0 |

**寄存器列表（默认 26 通道，NUM_LP_SEQ_REG=7；地址按 8 组预留）：**

| 地址 | 名称 | 条目 |
|:--|:--|:--|
| 0xB8 | LP_SEQ0 | ENT0~ENT3（CH0~CH3配置） |
| 0xBC | LP_SEQ1 | ENT4~ENT7 |
| 0xC0 | LP_SEQ2 | ENT8~ENT11 |
| 0xC4 | LP_SEQ3 | ENT12~ENT15 |
| 0xC8 | LP_SEQ4 | ENT16~ENT19 |
| 0xCC | LP_SEQ5 | ENT20~ENT23 |
| 0xD0 | LP_SEQ6 | ENT24~ENT27（默认 26 通道实际用到 ENT24/25，ENT26/27 预留） |
| 0xD4 | LP_SEQ7 | ENT28~ENT31（仅 NUM_LP_SEQ_REG==8 即 ADC_NUM_CH≥29 时实现；默认读回 0 写忽略） |

低优先序列有效条目数由 LP_SEQ_LEN 寄存器配置（默认 `ADC_NUM_CH`=26 条）。

> **实现说明：** regfile 内部按 ch_sel 粒度存储（`NUM_LP_DATA` 个 `W_CH_SEL`-bit entry，每通道一个，rsv 高位不存）。APB 边界拆/拼 32bit（4 entry × 8bit 占位/组）：写时每 8bit 占位取低 `W_CH_SEL` bit 存，读时每 entry 零扩展到 8bit（rsv 高位补 0）再拼 32bit。超出 `NUM_LP_DATA` 的 entry 不实现，对应地址（组 idx ≥ `ceil(N/4)`）读回 0、写忽略。regfile→seq_fsm 按 packed bus（`[W_CH_SEL*NUM_LP_DATA-1:0]`，entry i 在 `[i*W_CH_SEL +: W_CH_SEL]`）传输，seq_fsm 直切取 ch_sel 无需拆组。

### 3.14 HP_SEQ — 高优先序列配置寄存器（0xD8）

| [31:24] | [23:16] | [15:8] | [7:0] |
|:--|:--|:--|:--|
| ENTRY #3 | ENTRY #2 | ENTRY #1 | ENTRY #0 |

高优先序列 4 个有效条目（由 HP_SEQ_LEN 控制）。

> **实现说明：** regfile 内部按 4 个 `W_CH_SEL`-bit entry 存储（rsv 高位不存），APB 32bit 整读写（写取每 8bit 占位低 `W_CH_SEL` bit、读零扩展 rsv 补 0）；regfile→seq_fsm 按 packed bus（`[W_CH_SEL*4-1:0]`，entry i 在 `[i*W_CH_SEL +: W_CH_SEL]`）传输。

### 3.15 LP_SEQ_LEN — 低优序列长度寄存器（0xDC）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| [W_LP_SEQ_LEN-1:0] | LP_SEQ_LEN | RW | `ADC_NUM_CH`（默认 26） | 低优序列有效条目数，范围 1~`ADC_NUM_CH` |
| [15:W_LP_SEQ_LEN] | RSVD | RO | 0 | 保留 |

位宽 `W_LP_SEQ_LEN = $clog2(ADC_NUM_CH+1)`：8 通道→4bit，26 通道→5bit，32 通道→6bit。
序列达到 LP_SEQ_LEN 条后触发 LP_SEQ_DONE 中断/事件。默认 `ADC_NUM_CH` 条（兼容原设计）。

### 3.16 HP_SEQ_LEN — 高优序列长度寄存器（0xE0）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 2:0 | HP_SEQ_LEN[2:0] | RW | 4 (3'd4) | 高优序列有效条目数，范围 1~4 |
| 15:3 | RSVD | RO | 0 | 保留 |

序列达到 HP_SEQ_LEN 条后触发 HP_SEQ_DONE 中断/事件。默认 4 条（兼容原设计）。

---

## 4. 功能描述

### 4.1 采样流程

一次完整的单通道采样流程：

```
1. IDLE 状态，等待触发
2. 触发到来（软件写 TRIG 或外部脉冲）
3. 在 ADC_CLKn 上升沿产生 SOC 脉冲（单周期），同时拉高 MUXON
4. SPT 计数器开始计数（MUXON=1 期间，模拟持续采样）
5. SPT 计数满 → 拉低 MUXON
6. MUXON↓ 触发两件事：① 锁存下一通道的 ch_sel；② 模拟开始数据转换
7. 模拟转换完成 → 在 ADC_CLK 下降沿产生 EOC 脉冲 + ADC_DATA 有效
8. 控制器在 ADC_CLK 上升沿采样到 EOC，锁存 ADC_DATA
9. 对应序列数据寄存器（LP_DATA[lp_seq_ptr] 或 HP_DATA[hp_seq_ptr]）VALID=1，更新 DATA 域
10. 产生中断事件（如已使能）
11. 启动 SMPL_INTERVAL 计数器（若为序列模式，准备下一通道）
```

### 4.2 单次转换模式

- 每次触发只将**采样序列**执行一轮
- 序列执行完成后停止（回到 IDLE）
- 等待下一次触发

### 4.3 连续转换模式

- 触发后持续进行采样
- 序列完成后自动从序列头重新开始
- 直到软件清除 ADC_EN 或触发停止条件

### 4.4 高优先级抢占

- 高优先级触发可在任何时刻打断正在执行的低优先级采样
- 低优**当前通道丢弃**（采样中止），控制器输出 `preempt_rst_n` 低有效脉冲复位模拟电路
- `preempt_rst_n` 由 FSM 状态 ST_LP_PREEMPT 组合驱动，与抢占信号**同拍生效**
- 模拟在 preempt_rst_n 期间清除正在进行的转换（conv_active），不产生 EOC（控制器无需被通知）
- MUXON 在 preempt_abort 时强制拉低
- `preempt_soc_pend` 寄存器在 ST_LP_PREEMPT 置位，推迟到 ST_HP_SAMPLE 才发出 HP SOC
- **关键时序约束**：preempt_rst_n 先于 HP SOC 至少 1 个 adc_clk 周期生效，确保模拟复位完成后才接收到新的 SOC
- HP SOC 发出后 SPT 计数器立即重启，开始 HP 采样
- 高优序列全部完成后，低优从**被中断的通道重新开始采样**，然后继续序列中剩余通道

**抢占路径的 FSM 转移：**

```
ST_LP_SAMPLE     → (hp_trig_pulse)  → ST_LP_PREEMPT  → ST_HP_SAMPLE
ST_LP_WAIT_EOC   → (hp_trig_pulse)  → ST_LP_PREEMPT  → ST_HP_SAMPLE
ST_LP_INTERVAL   → (hp_trig_pulse)  → ST_LP_PREEMPT  → ST_HP_SAMPLE
```

**信号时序（以 ST_LP_SAMPLE 中抢占为例）：**

```
Cycle N     (posedge adc_clk):   fsm_curr_st ← ST_LP_PREEMPT
                                 preempt_rst_n = 0 (组合，同拍生效)
                                 preempt_abort = 1 → MUXON 强制拉低
                                 preempt_soc_pend = 1 (寄存，下一拍生效)
Cycle N+0.5 (posedge adc_clkn):  无 SOC（soc_req_set=0）
Cycle N+1   (posedge adc_clk):   fsm_curr_st ← ST_HP_SAMPLE
                                 preempt_rst_n = 1（已释放）
                                 preempt_soc_pend → soc_req_set = 1
Cycle N+1.5 (posedge adc_clkn):  HP SOC 发出（模拟已复位完毕）
```

**ch_sel 切换：**

```
正常通道推进：MUXON↓ 时锁存 cur_ch_sel
HP 抢占切换：preempt_abort 时立即切换到 hp_ch_sel（覆盖即将到来的 muxon_fall）
              preempt_hold 寄存器保护 ch_sel_reg，防止 muxon_fall 覆盖回 lp_ch_sel
              
ch_sel 序列示例（LP CH1 采样中被 HP CH8 抢占）：
  0 → 8 → 8
  ├复位默认┤├ preempt_abort 切到HP_CH┤├ LP恢复SOC，ch_sel保持8┤
```

**HP 抢占时序图（LP 采样中被 HP 打断）：**

```
ADC_CLK   ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐
          ─┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──
ADC_CLKn  ┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐
          ┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──
          │         │         │         │         │
          N        N+0.5      N+1      N+1.5     N+2
FSM       ST_LP_SAMP  ST_LP_PREEMPT  ST_HP_SAMPLE
preempt_  ──────────────────────┐└───────────────────────
rst_n                          │ 组合驱动，与PREEMPT状态同拍
preempt_  ──────────────────────┬──────┐└────────────────
soc_pend                       │      │  自动清0
                               │  寄存在PREEMPT←┘
soc_req_set ────────────────────┼──────────┬────────────
                               │ PREEMPT中=0│ HP_SAMPLE中=1←
SOC       ─────────────────────┼──────────────┐└───────
                               │              │ (posedge adc_clkn)
MUXON     ──┐  ┌──────┐└──────┤  ┌───────────┤└──────
  (LP SAMP)│  │             ┌──┐  │           (HP SAMP)
            ↑               │preempt_abort
        与SOC同沿           MUXON强制↓
ch_sel    [CH(N)]       [CH8]←preempt_abort切到HP通道
```

### 4.5 触发源选择

高优和低优各自独立配置触发方式：

- **软件触发**：写 TRIG 中对应 SW_TRIG 位（WO），需对应 SW_TRG_EN 使能
- **MCTM 硬件触发**：外部 mctm_trig 脉冲，需对应 MCTM_EN 使能 + TRG_SEL 选择源

外部触发信号（mctm_trig）与 ADC_CLK 异步，需经过：
1. 2 级同步器（ADC_CLK 域）
2. 上升沿检测
3. 根据 TRG_SEL 选择的触发源路由到对应优先级触发逻辑

### 4.6 中断

6 个中断事件源，通过 INT_EN 独立使能，INT_STAT 记录状态（写 1 清零）。

中断事件源：
- LP_EOC：低优先单次采样完成
- LP_SEQ_DONE：低优先序列完成
- HP_EOC：高优先单次采样完成
- HP_SEQ_DONE：高优先序列完成
- HP_PREEMPT：高优先级打断事件
- OVERRUN：任意序列位置数据溢出

### 4.7 DMA

DMA 请求与中断共享同一事件源，通过 DMA_CTRL 独立使能。

每个使能的事件发生时，控制器产生 DMA 请求脉冲。DMA 控制器响应（dma_ack）后清除请求。

---

## 5. 时序

### 5.1 单通道采样时序

```
ADC_CLK   ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐
          ─┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘

ADC_CLKn  ┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐
          ┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘
          │                                  │
          posedge adc_clkn                   posedge adc_clk
          (equiv negedge adc_clk)            (analog working edge)
          SOC, MUXON fired here              analog captures SOC here
SOC       ──────────┐  └────────────────────────────────────────────────
                    │   单周期脉冲 (at posedge adc_clkn)
MUXON     ────────────┐  ┌──────────────────────────────┐└───────────
                      │  │                              │
                  与SOC同沿↑                    SPT结束同沿拉低
                                                     │ MUXON↓ 触发：
ch_sel    ─────────────────────[ CH(N) ]───────────[ CH(N+1) ]─────────
                      ↑                                    ↑
                复位默认 CH0                           MUXON↓ 锁存通道
EOC       ──────────────────────────────────────────┐  └───────────────
                                                    │  (at negedge adc_clk)
ADC_DATA  ──────────────────────────────────────────────[XXXXXXXX]─────
                                                        (14-bit)
```
### 5.2 连续通道采样时序

```
CH(n)                              CH(n+1)

SOC     ┐└──────                    ┐└──────
MUXON   ┐└───────────              ┐└───────────
        │   SPT   │               │   SPT   │
        └─────────┘               └─────────┘
                  │&lt;─ 转换 ─&gt;│              │
EOC     ────────────┐└───    ────────────┐└───
                    │      │             │
        控制器采到EOC│      │  SMPL_INTERVAL计数器
                    │      │  计满发送下一SOC
                   &lt;─── SMPL_INTERVAL ───&gt;
```

### 5.3 校准时序

校准控制在 PCLK 域。`cal_st` 是 PCLK 寄存器位（CAL_CTRL[0]），软件写1置1、写0清0，
直送模拟。模拟在 CAL_ST=1 期间自动校准，固定 20 个 ADC_CLK 周期后置 CAL_DONE=1
（cal_val 在此前已稳定）；CAL_DONE 经 PCLK 2 级同步后供软件读与 cal_val 锁存；
软件读到 CAL_DONE=1 后写 CAL_ST=0，模拟随之清 CAL_DONE。

```
PCLK      软件写 ADC_EN=1, 再写 CAL_CTRL[0]=1
            │ cal_st (PCLK reg) 置1，直送模拟
            ▼
cal_st    ─────────────┐                              ┌──────
                      │                                │ 软件读到 cal_done=1 后写0
                      │                                ▼
adc_clk   ┌┴┐┌┴┐┌┴┐┌┴┐┌┴┐┌┴┐ … ┌┴┐┌┴┐┌┴┐┌┴┐
          ┘ └┘ └┘ └┘ └┘ └┘ └┘   └┘ └┘ └┘ └┘ └
            ↑ 模拟见 cal_st=1 启动，计数 0…19
                                    ↑ 20 周期满，cal_done=1
cal_val   ─────────────────────[ 6'hXX ]────────────  cal_done 之前已稳定
cal_done  ─────────────────────────┐
                                  │ 保持，直到 cal_st=0 (或 ADC_EN=0/复位)
                                  │
                                  │ PCLK 2级同步
                                  ▼
cal_done_s2 ───────────────────────────┐
                                       │ 软件读 CAL_CTRL[1]=1 → 锁存 cal_val
                                       │ 软件读 CAL_VAL → 写 CAL_CTRL[0]=0
                                  cal_st=0 → 模拟 cal_done=0 → cal_done_s2=0
```

**时序约束：**
- `cal_st` 是 PCLK 域 RW 寄存器位，直送模拟（PCLK→模拟跨域由模拟内部采样保证）
- CAL_DONE 由模拟产生（ADC_CLK 域电平），PCLK 域读取经 2 级同步（`cal_done_s1/s2`）
- CAL_DONE 置1条件：CAL_ST=1 且校准满 20 个 ADC_CLK 周期
- CAL_DONE 清0条件：CAL_ST=0 或 ADC_EN=0 或复位
- cal_val 在 CAL_DONE 之前稳定送出，控制器在 cal_done_s2=1 时锁存
- 校准与采样互斥：仅 ADC_EN=1 时校准，校准期间其他采样由软件保证不发起
- 重新校准：写 CAL_ST=0（清模拟 CAL_DONE）→ 写 CAL_ST=1（重新计数 20 周期）

---

## 6. 复位与初始化

### 6.1 复位架构

```
PRESETn / PRSTn (同一外部复位)
             │
PRESETn ─────┤
(PCLK域)     │
             ├──→ APB 域寄存器复位 (直接使用)
SW_RST ──────┤
(CTRL[1])    │
             └──→ AND → 异步复位同步释放 (2级) → rst_adc_n (ADC_CLK域)
```

- `PRESETn`（顶层 `presetn`）与 PCLK 同步，APB 域直接使用
- `PRSTn`（顶层 `prstn`）为 ADC 域复位入口，与 ADC_CLK 异步，需同步释放
- `SW_RST` 与 `PRSTn` 相与后统一送入同步释放电路
- 软件复位（SW_RST=1）复位所有寄存器和 ADC 状态机

**复位释放时序（异步复位，同步释放）：**
```
PRSTn     ────────────┐└──────────────────────────
                      │  异步下降，立即复位
ADC_CLK   ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐  ┌┴┐
          ─┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──┘ └──

rst_adc_n ────────────┐└─────────────────┐  └────
          (立即为0)   │                 │
                      │  同步器第1级    │  同步器第2级
                      │  释放后第一个    │  释放后第二个
                      │  ADC_CLK↑ 传播  │  ADC_CLK↑ 传播
                      │  logic-1        │  logic-1
```

> **说明：** PRSTn 下降沿立即复位所有 ADC_CLK 域寄存器（异步断言）。
> PRSTn 上升沿释放后，经过 2 级同步器（约 2 个 ADC_CLK 周期）后 rst_adc_n 释放（同步释放）。
> 软件复位（SW_RST）与 PRSTn 共享同一同步器，时序行为一致。

### 6.2 初始化流程

1. 释放 PRSTn（或软件复位）
2. 配置 CTRL（使能 ADC、对齐方式、SPT0、SPT1、采样间隔）
3. 配置 LP_SEQ / HP_SEQ（序列通道映射）
4. 配置 TRIG（触发源选择、使能）
5. 配置 INT_EN / DMA_CTRL（中断/DMA 使能）
6. 可选：触发 CAL_CTRL 自校准，等待 CAL_DONE，读取 CAL_VAL
7. 使能 ADC_EN=1，进入工作状态
8. 触发采样（软件写 TRIG 或等待外部触发）

---

## 7. 寄存器地址汇总

| 地址偏移 | 寄存器 | 属性 | 说明 |
|:--|:--|:--:|:--|
| 0x00 | CTRL | RW | 控制寄存器 |
| 0x04 | STAT | RO | 状态寄存器 |
| 0x08 | TRIG | RW | 触发控制寄存器 |
| 0x0C | INT_EN | RW | 中断使能寄存器 |
| 0x10 | INT_STAT | RW1C | 中断状态寄存器 |
| 0x14 | CAL_CTRL | RW | 校准控制寄存器 |
| 0x18 | CAL_VAL | RO | 校准值寄存器 |
| 0x1C | ANA_CFG | RW | 模拟配置寄存器 |
| 0x20 | ANA_REG | RW | 通用模拟寄存器 |
| 0x24 ~ 0xA0 | LP_DATA[0:NUM_LP_DATA-1] | RO | LP 序列数据寄存器（序列绑定，默认 26，地址按 32 预留） |
| 0xA4 ~ 0xB0 | HP_DATA[0:3] | RO | HP 序列数据寄存器（序列绑定，固定 4） |
| 0xB4 | DMA_CTRL | RW | DMA 控制寄存器 |
| 0xB8 ~ 0xD4 | LP_SEQ[0:NUM_LP_SEQ_REG-1] | RW | 低优序列配置寄存器（默认 7 组，地址按 8 预留） |
| 0xD8 | HP_SEQ | RW | 高优序列配置寄存器 |
| 0xDC | LP_SEQ_LEN | RW | 低优序列长度寄存器 |
| 0xE0 | HP_SEQ_LEN | RW | 高优序列长度寄存器 |
