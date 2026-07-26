# ADC 控制器 — 用户指南

## 1. 概述

ADC 控制器是一个 SAR ADC 数字控制 IP，负责管理模数转换的完整流程：触发采样、通道序列调度、数据锁存、中断/DMA 请求。

### 1.1 特性

| 特性 | 规格 |
|:--|:--|
| ADC 精度 | 可配 `ADC_DATA_W`（1~16-bit，默认 14） |
| 最高采样率 | 3 Msps |
| 模拟通道 | 可配 `ADC_NUM_CH`（4~32，默认 26；地址空间按 32 预留） |
| 采样时间可配 | 8 种档位：3/8/14/29/42/56/78/240 cycles |
| 采样间隔可配 | 0~127 cycles |
| 序列槽（普通优先级） | `ADC_NUM_CH`（默认 26） |
| 序列槽（高优先级） | 4（固定） |
| 支持抢占 | 高优先级可抢占低优先级 |
| 触发方式 | 软件触发 + MCTM 外部硬件触发 |
| 数据对齐 | 16-bit 右对齐 / 左对齐（DATA 域固定 16-bit） |
| 中断源 | 6 个，独立使能 |
| DMA 请求 | 5 个事件源，独立使能 |
| 自校准 | 支持 |

> **参数化：** 通道数 `ADC_NUM_CH`（默认 26，范围 4~32）/ ADC 数据位宽 `ADC_DATA_W`（默认 14，1~16）/ SPT1 通道位图 `ADC_SPT1_CH_MASK`（默认 CH21/CH22）可配，默认值与原固定设计一致、向后兼容。改参数只动 `rtl/adc_params.vh` 或实例化 override。详见 `spec/adc_spec.md` §3.0。

### 1.2 时钟架构

```
PCLK ───── APB 接口，最高 200 MHz
ADC_CLK ── ADC 工作时钟，最高 60 MHz（与 PCLK 异步）
ADC_CLKn ─ ADC 反向时钟（与 ADC_CLK 同频反相，同步关系）
```

---

## 2. 接口定义

### 2.1 APB 总线接口

| 信号 | 方向 | 位宽 | 说明 |
|:--|:--:|:--:|:--|
| PCLK | I | 1 | APB 时钟 |
| PRESETn | I | 1 | APB 复位（低有效） |
| PADDR | I | 16 | APB 地址 |
| PWRITE | I | 1 | 1=写，0=读 |
| PSEL | I | 1 | APB 选择 |
| PENABLE | I | 1 | APB 使能 |
| PWDATA | I | 32 | APB 写数据 |
| PRDATA | O | 32 | APB 读数据 |
| PREADY | O | 1 | 就绪（固定高，零等待） |
| PSLVERR | O | 1 | 错误（固定 0） |

### 2.2 ADC 模拟接口

| 信号 | 方向 | 位宽 | 说明 |
|:--|:--:|:--:|:--|
| SOC | O | 1 | 采样开始脉冲（ADC_CLKn 上升沿，单周期） |
| MUXON | O | 1 | 采样使能电平（与 SOC 同时拉高，SPT 满后拉低） |
| ch_sel | O | W_CH_SEL | 通道选择（0~ADC_NUM_CH-1，位宽 = $clog2(ADC_NUM_CH)，默认 5） |
| EOC | I | 1 | 转换完成脉冲（ADC_CLK 下降沿产生，单周期） |
| adc_data | I | ADC_DATA_W | 转换结果（与 EOC 同时有效，默认 14-bit） |
| CAL_ST | O | 1 | 校准启动 |
| CAL_DONE | I | 1 | 校准完成（电平信号） |
| cal_val | I | 6 | 校准值（与 CAL_DONE 同时有效） |

### 2.3 触发、中断与 DMA

| 信号 | 方向 | 位宽 | 说明 |
|:--|:--:|:--:|:--|
| mctm_trig | I | 6 | MCTM 外部触发源（与 ADC_CLK 异步） |
| adc_int | O | 1 | 中断请求（电平） |
| dma_req | O | 1 | DMA 请求（电平） |
| dma_ack | I | 1 | DMA 响应 |

---

## 3. 寄存器映射

APB 32-bit 总线，地址按 4 字节对齐。

| 地址偏移 | 名称 | 属性 | 说明 |
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
| 0x24 ~ 0xA0 | LP_DATA[0:NUM_LP_DATA-1] | RO | LP 序列数据寄存器（NUM_LP_DATA × 32-bit，默认 26；地址按 32 预留，超出读回 0） |
| 0xA4 ~ 0xB0 | HP_DATA[0:3] | RO | HP 序列数据寄存器（4 × 32-bit，固定） |
| 0xB4 | DMA_CTRL | RW | DMA 控制寄存器 |
| 0xB8 ~ 0xD4 | LP_SEQ[0:NUM_LP_SEQ_REG-1] | RW | 低优序列配置（NUM_LP_SEQ_REG × 32-bit，默认 7 组；地址按 8 组预留，超出读回 0 写忽略） |
| 0xD8 | HP_SEQ | RW | 高优序列配置（1 × 32-bit） |
| 0xDC | LP_SEQ_LEN | RW | 低优序列长度寄存器 |
| 0xE0 | HP_SEQ_LEN | RW | 高优序列长度寄存器 |

> DMA_STAT 寄存器已删除（不再提供 DMA_BUSY/DMA_DONE 软件可读状态）。

### 3.1 CTRL — 控制寄存器（0x00）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | ADC_EN | RW | 0 | ADC 全局使能，1=使能 |
| 1 | SW_RST | RW_SS | 0 | 软件复位，写 1 复位，硬件自清零 |
| 3:2 | DATA_ALIGN | RW | 0 | 数据对齐：0=右对齐，1=左对齐 |
| 7:4 | RSVD | RO | 0 | 保留 |
| 10:8 | SPT0 | RW | 0 | 采样时间档位 0（默认非 SPT1 通道） |
| 13:11 | SPT1 | RW | 0 | 采样时间档位 1（由 ADC_SPT1_CH_MASK 位图决定，默认 CH21/CH22） |
| 14 | CONT_MODE | RW | 0 | 连续转换模式 |
| 15 | RSVD | RO | 0 | 保留 |
| 22:16 | SMPL_INTERVAL | RW | 0 | 采样间隔（ADC_CLK cycle，0~127） |
| 31:23 | RSVD | RO | 0 | 保留 |

SPT 档位编码：

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

### 3.2 STAT — 状态寄存器（0x04）

| 位 | 名称 | 属性 | 说明 |
|:--:|:--|:--:|:--|
| 0 | ADC_BUSY | RO | ADC 采样或转换中 |
| 1 | LP_BUSY | RO | 低优序列执行中 |
| 2 | HP_BUSY | RO | 高优序列执行中 |
| 3 | CAL_BUSY | RO | 校准进行中 |
| 15:4 | RSVD | RO | 保留 |

### 3.3 TRIG — 触发控制寄存器（0x08）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | LP_SW_TRIG | WO | 0 | 低优先软件触发，写 1 启动（读回 0） |
| 1 | LP_SW_TRG_EN | RW | 0 | 低优先软件触发使能 |
| 2 | LP_MCTM_EN | RW | 0 | 低优先 MCTM 触发使能 |
| 6:3 | LP_TRG_SEL | RW | 0 | 低优先触发源选择 |
| 7 | RSVD | RO | 0 | 保留 |
| 8 | HP_SW_TRIG | WO | 0 | 高优先软件触发，写 1 启动（读回 0） |
| 9 | HP_SW_TRG_EN | RW | 0 | 高优先软件触发使能 |
| 10 | HP_MCTM_EN | RW | 0 | 高优先 MCTM 触发使能 |
| 14:11 | HP_TRG_SEL | RW | 0 | 高优先触发源选择 |
| 15 | RSVD | RO | 0 | 保留 |

触发源编码：

| TRG_SEL | 触发源 |
|:--:|:--|
| 0000 | mctm0 |
| 0001 | mctm1 |
| 0010 | mctm2 |
| 0011 | mctm3 |
| 0100 | mctm4 |
| 0101 | mctm5 |
| 0110 | mctm3 \| mctm4（或组合） |
| 0111 | ecc |
| 1000 | tue |
| 1001~1111 | reserved |

### 3.4 INT_EN — 中断使能寄存器（0x0C）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | LP_EOC_EN | RW | 0 | 低优先 EOC 中断使能 |
| 1 | LP_SEQ_DONE_EN | RW | 0 | 低优先序列完成中断使能 |
| 2 | HP_EOC_EN | RW | 0 | 高优先 EOC 中断使能 |
| 3 | HP_SEQ_DONE_EN | RW | 0 | 高优先序列完成中断使能 |
| 4 | HP_PREEMPT_EN | RW | 0 | 高优先打断中断使能 |
| 5 | OVERRUN_EN | RW | 0 | 溢出中断使能 |
| 15:6 | RSVD | RO | 0 | 保留 |

### 3.5 INT_STAT — 中断状态寄存器（0x10）

| 位 | 名称 | 属性 | 说明 |
|:--:|:--|:--:|:--|
| 0 | LP_EOC | RW1C | 低优先 EOC |
| 1 | LP_SEQ_DONE | RW1C | 低优先序列完成 |
| 2 | HP_EOC | RW1C | 高优先 EOC |
| 3 | HP_SEQ_DONE | RW1C | 高优先序列完成 |
| 4 | HP_PREEMPT | RW1C | 高优先打断 |
| 5 | OVERRUN | RW1C | 溢出 |
| 15:6 | RSVD | RO | 0 |

写 1 清零对应位。

### 3.6 CAL_CTRL — 校准控制寄存器（0x14）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | CAL_ST | RW_SS | 0 | 校准启动，写 1 触发，完成后硬件自清 |
| 1 | CAL_DONE | RO | 0 | 校准完成（sticky，校准完成后为 1） |
| 15:2 | RSVD | RO | 0 | 保留 |

### 3.7 CAL_VAL — 校准值寄存器（0x18）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 5:0 | CAL_VAL | RO | 0 | 6-bit 校准值 |
| 15:6 | RSVD | RO | 0 | 保留 |

### 3.8 ANA_CFG / ANA_REG

| 地址 | 名称 | 属性 | 位宽 | 说明 |
|:--|:--|:--:|:--:|:--|
| 0x1C | ANA_CFG | RW | 16 | 模拟配置 |
| 0x20 | ANA_REG | RW | 32 | 通用模拟寄存器 |

### 3.9 LP_DATAn / HP_DATAn — 序列数据寄存器（序列绑定）

数据寄存器按序列位置绑定（非通道绑定）：LP_DATA 索引为 LP 序列指针，HP_DATA 索引为 HP 序列指针。

#### LP_DATA[0:NUM_LP_DATA-1]（0x24 + n × 4，默认 26 个）

| 位 | 名称 | 属性 | 说明 |
|:--:|:--|:--:|:--|
| 31 | VALID | RO | 数据有效，读本寄存器时自清零 |
| 30:16 | RSVD | RO | 保留 |
| 15:0 | DATA | RO | ADC 转换结果（DATA 域固定 16-bit，ADC_DATA_W 位对齐进去） |

地址 0x24 ~ 0x24+(NUM_LP_DATA-1)×4（默认 0x88），超出 NUM_LP_DATA 的地址（按 32 预留）读回 0。

#### HP_DATA[0:3]（0xA4 + n × 4，固定 4 个）

位格式同 LP_DATA，地址 0xA4 ~ 0xB0。

数据对齐：右对齐 `[ADC_DATA_W-1:0]=ADC`、高位 0；左对齐 `[15:16-ADC_DATA_W]=ADC`、低位 0。

### 3.10 DMA_CTRL — DMA 控制寄存器（0xB4）

| 位 | 名称 | 属性 | 复位值 | 说明 |
|:--:|:--|:--:|:--:|:--|
| 0 | DMA_EN | RW | 0 | DMA 全局使能 |
| 1 | DMA_LP_EOC | RW | 0 | LP 单次完成触发 DMA |
| 2 | DMA_LP_SEQ | RW | 0 | LP 序列完成触发 DMA |
| 3 | DMA_HP_EOC | RW | 0 | HP 单次完成触发 DMA |
| 4 | DMA_HP_SEQ | RW | 0 | HP 序列完成触发 DMA |
| 5 | DMA_OVERRUN | RW | 0 | 溢出触发 DMA |
| 15:6 | RSVD | RO | 0 | 保留 |

> DMA_STAT 寄存器已删除（不再提供 DMA_BUSY/DMA_DONE 软件可读状态）。

### 3.11 LP_SEQ[0:NUM_LP_SEQ_REG-1] — 低优序列配置（0xB8 + n × 4）

每个 32-bit 寄存器含 4 个 8-bit 序列条目（APB 占位）：

```
[31:24]=ENT#3, [23:16]=ENT#2, [15:8]=ENT#1, [7:0]=ENT#0
```

**条目格式（8-bit 占位，ch_sel 位宽自适应）：**

| 位 | 名称 | 说明 |
|:--:|:--|:--|
| [W_CH_SEL-1:0] | CH_SEL | 通道号 0~ADC_NUM_CH-1（位宽 = $clog2(ADC_NUM_CH)，默认 5） |
| [7:W_CH_SEL] | RSVD | 保留，不存、读回 0（写 rsv 无效） |

`NUM_LP_SEQ_REG = ceil(ADC_NUM_CH/4)`：8 通道→2 组，26 通道→7 组，32 通道→8 组。地址空间固定按 8 组（0xB8~0xD4）预留，超出 `NUM_LP_DATA` 的 entry 读回 0、写忽略。

| 地址 | 条目 |
|:--|:--|
| 0xB8 | ENT0~3 |
| 0xBC | ENT4~7 |
| 0xC0 | ENT8~11 |
| 0xC4 | ENT12~15 |
| 0xC8 | ENT16~19 |
| 0xCC | ENT20~23 |
| 0xD0 | ENT24~27（26ch 实现 ENT24/25，ENT26/27 越界读 0） |
| 0xD4 | ENT28~31（仅 NUM_LP_SEQ_REG==8 即 ADC_NUM_CH≥29 时实现；默认读回 0 写忽略） |

### 3.12 HP_SEQ — 高优先序列配置（0xD8）

1 个 32-bit 寄存器，4 个 entry（固定数量，位宽 W_CH_SEL 自适应），格式同 LP_SEQ。

| 地址 | 条目 |
|:--|:--|
| 0xD8 | ENT0~3（4 个条目） |

### 3.13 LP_SEQ_LEN / HP_SEQ_LEN

| 地址 | 名称 | 位宽 | 复位值 | 说明 |
|:--|:--|:--:|:--:|:--|
| 0xDC | LP_SEQ_LEN | W_LP_SEQ_LEN = $clog2(ADC_NUM_CH+1) | ADC_NUM_CH | LP 序列有效条目数，1~ADC_NUM_CH |
| 0xE0 | HP_SEQ_LEN | 3（固定） | 4 | HP 序列有效条目数，1~4 |

---

## 4. 初始化流程

```text
1. 释放 PRESETn / PRSTn（硬件复位）
2. 配置 CTRL（ADC_EN=0 时配置以下参数）：
   - DATA_ALIGN[3]      — 对齐方式
   - SMPL_INTERVAL[22:16] — 采样间隔（0~127）
   - SPT0[10:8], SPT1[13:11] — 采样时间档位
3. 配置 LP_SEQ[0:NUM_LP_SEQ_REG-1] / HP_SEQ — 序列通道映射（entry 低 W_CH_SEL bit=ch_sel）
4. 配置 LP_SEQ_LEN / HP_SEQ_LEN — 序列长度
5. 配置 TRIG — 触发源选择、使能
6. 配置 INT_EN / DMA_CTRL — 中断/DMA 使能
7. 可选：写 CAL_CTRL[0]=1 启动自校准，等待 CAL_DONE，读 CAL_VAL
8. 写 CTRL[0]=1（ADC_EN=1）
9. 触发采样
```

### 4.1 软件触发单次采样示例

```c
// Step 1: 配置序列长度（单次采样 = 1 条）
*(volatile uint32_t*)(BASE + 0xDC) = 0x00000001;  // LP_SEQ_LEN = 1

// Step 2: 配置序列（单通道 CH5，放 LP_SEQ0 的 ENT0）
*(volatile uint32_t*)(BASE + 0xB8) = 0x00000005;  // LP_SEQ0: ENT0=CH5
// 其余 LP_SEQ 组写 0（地址按 8 组预留，超出 NUM_LP_SEQ_REG 的组写忽略）

// Step 3: 使能 ADC
*(volatile uint32_t*)(BASE + 0x00) = 0x00000001;  // CTRL: ADC_EN=1

// Step 4: 触发采样
*(volatile uint32_t*)(BASE + 0x08) = 0x00000002;  // TRIG: LP_SW_TRG_EN
*(volatile uint32_t*)(BASE + 0x08) = 0x00000003;  // TRIG: LP_SW_TRIG + LP_SW_TRG_EN

// Step 5: 等待采样完成
while (!(*(volatile uint32_t*)(BASE + 0x24) & 0x80000000));  // LP_DATA0[31]=VALID

// Step 6: 读取数据（读同时清除 VALID）
uint32_t lp_data = *(volatile uint32_t*)(BASE + 0x24);  // LP_DATA0
uint16_t sample  = lp_data & 0xFFFF;  // DATA[15:0]
```

> 注：entry 占位 8-bit，只有低 `W_CH_SEL` bit 是 ch_sel（默认 26 通道 = 低 5 bit），高位 rsv 写无效、读回 0。

---

## 5. 快速命令

```bash
# RTL 语法检查
make lint

# 仿真（手写 TB）
make sim

# UVM 验证
make sim-uvm TESTNAME=adc_reg_test

# SVA 断言检查
make sim-assert

# Verdi 波形
make verdi

# 清理
make clean

# 全部检查（lint + 测试）
make check
```

---

## 6. 模块层次

```text
adc_top
├── adc_rst_sync     — 异步复位同步释放（2-stage）
├── adc_apb_if       — APB 32-bit 零等待从接口
├── adc_regfile      — 寄存器文件（双时钟域，52 寄存器）
├── adc_trig_sync    — MCTM 触发同步 + 边缘检测 + 源选择
├── adc_seq_fsm      — 核心 FSM（9 状态，序列扫描，HP 抢占）
├── adc_int_ctrl     — 中断控制器（6 事件源）
├── adc_dma_req      — DMA 请求控制器
├── adc_calib        — 已废弃 stub（校准逻辑移入 regfile PCLK 域，已从 filelist 移除）
└── adc_sync_cell    — 2-stage CDC 同步器（通用）
```

## 7. 文件结构

```text
adc_new/
├── rtl/           — 10 个 RTL 模块
├── tb/
│   ├── unit/      — 手写自检查 TB
│   ├── uvm/       — UVM 验证环境（47 文件）
│   └── formal/    — 形式化验证属性
├── bind/          — SVA 断言 bind 文件
├── spec/          — 规格文档 + 验证计划
├── doc/           — 设计文档
├── scripts/       — 脚本
└── sim/           — 仿真产物
```

## 8. 修订历史

| 版本 | 日期 | 内容 |
|:--|:--|:--|
| v1.0 | 2026-07-02 | 初版 |
