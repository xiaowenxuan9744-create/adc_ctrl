---
name: adc-design
description: ADC 控制器设计知识与验证指南（SOC/EOC 时序、序列扫描、高优抢占、DMA 触发、校准）
triggers:
  - ADC设计
  - ADC控制器
  - 模数转换
  - 序列采样
  - SAR ADC
  - 高优先级抢占
---

# ADC Design — SAR ADC 控制器设计知识（领域 skill）

> **本 skill 是 ADC 控制器领域知识库，非通用方法论 skill。** 内容绑定 SAR ADC
> 控制器（SOC/EOC 握手、序列扫描、高优抢占、DMA、校准、ADC_CLK/ADC_CLKn 时钟
> 架构）。通用 RTL 设计方法论见 rtl_generator/rtl_reviewer/consistency_check
> 等 skill。本 skill 仅在 ADC 类项目中提供领域知识检索。
>
> **skill 性质：记录类（模板豁免，且不进通用模板）。** 项目专属领域知识，绑定 ADC
> 项目语境。**不参与 skill 模板化/去语境化处理**，且**不进通用模板 ic_rtl_template**——
> 新项目若非 ADC 类，按需自建对应的领域 skill（如 `dac_design`/`pwm_design`）。
> 本仓库 adc_new 内原样保留 ADC 内容作为该项目的领域知识沉淀。

## 累计更新规则

每次遇到新的设计问题（CDC 遗漏、时序 Bug、状态机缺陷等）→ 在此文件中追加记录。
**累计 ≥5 条** 时 → 触发整理更新（合并同类、补充根因、更新预防措施）。
此规则适用于本 ADC 领域知识库的维护。

本项目专用的 ADC 控制器设计知识，涵盖 SOC/EOC 握手、序列扫描、优先级抢占、DMA 触发和自校准。

## 设计参数速查

> **参数化（2026-07-20 重构）：** 通道数 / ADC 精度 / SPT1 通道位图已参数化，
> 下表"默认"列与原固定设计一致（向后兼容）。改参数只动 `rtl/adc_params.vh`。

| 参数 | 默认 | 参数化范围 | 派生 |
|:--|:--|:--|:--|
| 精度 `ADC_DATA_W` | 14-bit | 1~16 | DATA 寄存器域固定 16bit |
| 最高采样率 | 3 Msps | — | — |
| PCLK 频率 | 最高 200 MHz | — | — |
| ADC_CLK 频率 | 最高 60 MHz | — | — |
| PCLK ↔ ADC_CLK | 异步关系 | — | — |
| 模拟通道 `ADC_NUM_CH` | 26 | 2~32 | ch_sel 位宽 = $clog2(N) |
| 采样时间配置 | 3-bit: 3/8/14/29/42/56/78/240 cycles，默认 3 | — | — |
| SPT1 通道 `ADC_SPT1_CH_MASK` | CH21/CH22 | 32bit 位图 | bit i=1 → 通道 i 用 SPT1 |
| 采样间隔 | 可配，最大 128 cycles | — | — |
| 序列槽（普通） | 26 | = `ADC_NUM_CH` | LP_SEQ_LEN 位宽 = $clog2(N+1) |
| 序列槽（高优） | 4 | 固定（不参数化） | — |
| 对齐模式 | 16-bit 左对齐 / 右对齐 | — | DATA 域固定 16bit |
| 触发方式 | 软件触发 / MCTM 硬件脉冲触发 | — | — |
| DMA 触发 | 单次完成 / 组完成 / 全序列完成 | — | — |
| 复位 | 异步低有效 `negedge rst_n` | — | — |

## 时钟架构

```
CKCU ──→ ADC_CLK  ──→ 控制器工作时钟、模拟电路时钟
       ──→ ADC_CLKn ──→ SOC 生成（相位反转，同频）
       ──→ PCLK     ──→ APB 接口时钟（异步于 ADC_CLK）
```

- ADC_CLK 与 ADC_CLKn 同频反相（180° 相移），由 CKCU 产生，属于同步域
- PCLK 与 ADC_CLK 为异步关系（PCLK 最高 200MHz，ADC_CLK 最高 60MHz），跨域需 2 级同步器
- CDC 路径：PCLK ↔ ADC_CLK 使用 2 级同步器（异步关系，PCLK 最高 200MHz / ADC_CLK 最高 60MHz）

## SOC/EOC 时序规范

### 基本握手

```
ADC_CLK  __|¯¯|__|¯¯|__|¯¯|__|¯¯|__|¯¯|__|¯
ADC_CLKn ¯¯|__|¯¯|__|¯¯|__|¯¯|__|¯¯|__|¯¯|_

SOC (ADC_CLKn域)  ¯¯|________|¯¯|________|¯__
                        ^-- 单周期脉冲

EOC (ADC_CLK域)   _____|¯¯¯|______________|__
                         ^-- 单周期脉冲
```

- **SOC 生成**：在 ADC_CLKn 时钟域产生，单周期脉冲
  - 目的：模拟电路在 ADC_CLK 上升沿采样 SOC
  - 使用 ADC_CLKn 使信号提前半个周期到达模拟端
- **EOC 接收**：模拟在 ADC_CLK 下降沿输出 EOC，控制器在 ADC_CLK 上升沿捕获
- **EOC 超时**：SOC 发出后最多 16 个 ADC_CLK 周期内必须收到 EOC
- **SOC 和 EOC 均为单周期脉冲**

### testbench 模拟模型行为

`tb/adc_analog_model.v` 中的参数：

```verilog
parameter EOC_DELAY = 12;  // SOC→EOC 延迟周期数（典型值）
```

根据采样时间配置不同延迟：
- 采样时间=3 cycles → 总延迟 = 3 + 12 = 15 cycles
- 采样时间=240 cycles → 总延迟 = 240 + 12 = 252 cycles

## 序列扫描控制器规范

### 普通优先级（参数化 LP 槽，默认 26）

> **参数化（2026-07-20 重构）：** LP 序列槽数随 `ADC_NUM_CH` 参数化（默认 26，
> 范围 2~32）。HP 槽固定 4（不参数化）。详见 `spec/adc_spec.md` §3.0 与
> `doc/design/2026-07-20-parameterization-design.md`。

```
序列长度寄存器 LP_SEQ_LEN[W_LP_SEQ_LEN-1:0] → N = LP_SEQ_LEN（存 count，1~ADC_NUM_CH）
  W_LP_SEQ_LEN = $clog2(ADC_NUM_CH+1)：8通道→4bit, 26通道→5bit, 32通道→6bit
  复位默认值 = ADC_NUM_CH

序列配置寄存器 LP_SEQ[0:NUM_LP_SEQ_REG-1]：
  APB 占位：每寄存器 32-bit 放 4 个 8-bit entry（[7:0]/[15:8]/[23:16]/[31:24]）
  内部存储：按 entry 粒度存 NUM_LP_DATA 个 W_CH_SEL-bit ch_sel（每通道一个）
    → 8bit 占位只有效低 W_CH_SEL bit，rsv 高位不存、读回 0（写 rsv 无效）
  NUM_LP_SEQ_REG = ceil(ADC_NUM_CH/4)：8通道→2组, 26通道→7组, 32通道→8组
  地址空间固定按 8 组（0xB8~0xD4）预留，超出 NUM_LP_DATA 的 entry 读回 0、写忽略
  entry 格式：[W_CH_SEL-1:0]=ch_sel, [7:W_CH_SEL]=rsv（rsv 读 0，位宽自适应）
  W_CH_SEL = $clog2(ADC_NUM_CH)：8通道→3bit, 16通道→4bit, 26通道→5bit

HP_SEQ（0xD8）：1 个 32-bit 寄存器，4 个 W_CH_SEL-bit entry（固定数量，位宽随 N）
  内部 4×W_CH_SEL bit 存储，APB 32bit 整读写（rsv 读 0）
```

### 高优先级抢占

```
低优先级采样进行中
    ↓
高优先级触发到来
    ↓
当前采样被丢弃，模拟电路复位
    ↓
高优先级序列开始（占用高优 4 槽）
    ↓
高优先级序列完成
    ↓
低优先级从断点恢复（被打断的通道重新采样）
```

**关键验证点**：
1. 高优打断时低优当前采样立即终止
2. 模拟电路复位后重新初始化
3. 低优恢复时从被打断的通道开始，而不是从头开始
4. 高优序列期间低优触发被屏蔽
5. 连续模式下高优结束后低优继续

### 连续模式

- 序列完成后自动从头开始下一轮
- 高优抢占不影响连续模式的循环
- 连续模式下序列长度必须≥1

## DMA 触发规范

| 触发类型 | 条件 | 用途 |
|:--|:--|:--|
| 单次完成 | 每次转换完成 | 实时读取 |
| 组完成 | 指定数量的转换完成 | 批量传输 |
| 全序列完成 | 整个序列完成 | 一次搬完 |

总线接口：`DMA_REQ` / `DMA_ACK` / `DMA_DATA[15:0]` / `DMA_LAST`

## 校准控制

- 模拟自校准，独立时序控制
- 校准触发后控制器进入等待状态
- 校准完成信号返回后恢复正常操作
- 校准期间所有触发被忽略

## 数据对齐

| 对齐 | 数据 | 说明 |
|:--|:--|:--|
| 右对齐 | `{2'b0, ADC_DATA[13:0]}` | 低 14 位有效 |
| 左对齐 | `{ADC_DATA[13:0], 2'b0}` | 高 14 位有效 |

## 测试点清单

### 功能测试（P0）

| # | 测试点 | 描述 |
|:-:|:--|:--|
| 1 | 软件触发单次转换 | 写 SW_TRIG=1 → SOC 发出 → EOC 返回 → 数据读取正确 |
| 2 | 序列采样 | 配置序列 → 触发 → 所有通道依次完成 |
| 3 | 连续模式 | 使能 CONT → 序列自动循环 |
| 4 | 高优打断高优 | 低优采样中，高优触发 → 低优打断 → 高优执行 → 低优恢复 |
| 5 | DMA 单次请求 | 每次 EOC 后 DREQ 拉高 |
| 6 | MCTM 外部触发 | 外部脉冲触发采样 |
| 7 | 校准流程 | 启动校准 → 等待完成 |

### 边界测试（P1）

| # | 测试点 | 描述 |
|:-:|:--|:--|
| 8 | 采样时间边 | 最小 3/最大 240 cycles |
| 9 | 采样间隔界 | 0/128 cycles |
| 10 | 序列长度边界 | 1 槽 / 26 槽（低优）/ 4 槽（高优） |
| 11 | 转换中重触发 | 转换进行中再次触发 |
| 12 | 数据对齐切换 | 运行时切换 ALIGN 位 |
| 13 | 非法地址访问 | APB 访问未定义地址 |
| 14 | EOC 超时 | SOC 发出后模拟不返回 EOC |

### 异常测试（P2）

| # | 测试点 | 描述 |
|:-:|:--|:--|
| 15 | 连续高优打断 | 每轮序列中多次插入高优 |
| 16 | DMA 未应答 | DREQ 发出后外部不返回 ACK |
| 17 | 校准中触发 | 校准过程中触发采样 |
| 18 | 无序列配置 | 序列槽全 0 时触发采样 |

## 与验证相关的 assertion 属性

### SOC/EOC 握手断言

```systemverilog
// SOC 期间必须收到 EOC
assert property (@(posedge adc_clk) disable iff (!rst_n)
    $rose(soc) |=> ##[1:16] $rose(eoc));

// SOC 和 EOC 不能同时为高
assert property (@(posedge adc_clk) disable iff (!rst_n)
    !(soc && eoc));

// 连续模式下序列结束后的下一拍自动开始新序列
assert property (@(posedge adc_clk) disable iff (!rst_n)
    cont_mode && seq_done |=> ##[1:10] soc);
```

### 优先级抢占断言

```systemverilog
// 高优触发后低优当前采样必须终止
assert property (@(posedge adc_clk) disable iff (!rst_n)
    hi_prio_trig && lprio_busy |=> !lprio_active);

// 高优完成后低优必须恢复
assert property (@(posedge adc_clk) disable iff (!rst_n)
    hi_prio_done && had_preempt |=> ##[1:10] lprio_active);
```


## 设计问题记录

每次发现设计问题（CDC 遗漏、时序 Bug、状态机缺陷、寄存器定义错误等）追加到此列表。
**每次追加后，检查上次整理以来新增 ≥5 条** → 触发整理更新（合并同类、补充根因、更新预防措施）。

> 当前累计：**32 条**（最近一次整理更新：2026-07-20，补充 #29-32 参数化重构问题）
> 原始记录全部保留，下同。

### 模式总结与合并说明

从 28 条问题中提炼出 6 类重复模式（F 类为新增，目前仅 #28 一例，待积累更多
案例后升格为成熟模式）：

| 模式 | 问题举例 | 根因 | 预防措施 |
|:--|:--:|:--|:--|
| **A. CDC 判断** | #1, #4, #5, #6, #18, #19 | 默认"跨域必须 2 级同步"，未判断信号稳定性 | 先判断变化频率：长期稳定→同步"更新通知"；频繁变化→FIFO/Gray 码 |
| **B. preempt 时序链** | #14, #15, #16, #17, #23 | 同一路径链多个控制信号未逐拍对齐 | 涉及时序沿的信号先画图推演再选组合/寄存 |
| **C. 控制条件共享** | #11, #17 | 正常路径条件在异常路径不成立 | 写 `if (A && B)` 时列出所有前置 FSM 状态逐项验证 |
| **D. 存储位宽** | #13, #20 | 按总线宽度定义内部存储 | 按数据实际位宽定义，APB 读取时组合 |
| **E. 验证配置遗漏** | #24, #25, #26, #31 | sequence 随机化/约束/硬件对齐不全、参数化后期望值未跟随 | 创建后检查 randomize()、约束完备性、配置寄存器；参数化重构后逐项核对 TB 期望值与默认配置变化 |
| **F. 批量改写语义核对**（待积累） | #28, #32 | 批量正则/sed 替换或复制 TB 后只看编译通过，未核对语义 | 批量替换/复制后 `git diff` 逐文件核对语义 + grep 旧标识符；带引号字面量优先用 Python；编译通过≠语义正确 |
| **G. 参数化派生 localparam 作用域**（待积累） | #29, #30 | Verilog-2005 限制 localparam 位置 + iverilog `define 全局致守卫误伤 | 集中 `.vh` + iverilog `-g2012` + 不加 ifndef 守卫；详见 env-bug #10/#11 |

### 已发现的设计问题（完整记录）

| # | 模块 | 问题 | 根因 | 修复 |
|:-:|:--|:--|:--|:--|
| 1 | adc_regfile | `cal_val[5:0]` 缺少 CDC 同步器 | 多比特信号直接从 A→B 域未同步 | 补 2 级同步器 |
| 2 | adc_int_ctrl | `int_events` 跨时钟域无 PCLK 侧同步 | 脉冲信号直接跨域 | 补 PCLK 域 sync chain |
| 3 | adc_seq_fsm | `dma_ack` 未同步到 adc_clk 域 | 异步信号直接使用 | 补 2 级同步器 |
| 4 | adc_seq_fsm | SOC 脉冲从未产生 | `soc_req` 未在 FSM 中置位 | 补充 FSM next-state 赋值 |
| 5 | adc_int_ctrl | `int_pending` 无清除路径 | 寄存器设计缺少清零机制 | 简化移除该寄存器 |
| 6 | adc_regfile | VALID CDC 脉冲过短 | 单周期脉冲在慢域丢失 | 展宽为 8 PCLK 周期（后改为本地 VALID 方案） |
| 7 | adc_sync_cell | nested generate VCS 不兼容 | VCS scope 展开歧义 | 拍平为单层 generate |
| 8 | adc_seq_fsm | generate 内 reg 跨 always 引用 | VCS 嵌套 scope 限制 | 声明提到模块级 |
| 9 | adc_regfile | STAT 寄存器位序与 spec 相反 | 读 mux 拼接位序笔误 | 修正 `adc_regfile.v:478` |
| 10 | tb_adc_top | Test 7 状态残留导致数据丢失 | 前序 test 遗留的 TRIG 状态未清除 | 每个 test 前 SW_RST + 清 TRIG |
| 11 | adc_seq_fsm | soc_req_set 跨域未对齐导致 FSM 死锁 | 单周期 combo 信号与 ADC_CLKn 沿竞争 | soc_pending 寄存器保持请求 |
| 12 | adc_seq_fsm | CONT_MODE 连续模式未实现 | localparam 硬编码 1'b0 | 新增 cfg_cont_mode 端口 + FSM 循环 |
| 13 | adc_regfile | TRIG WO 位读回非0 | 读 mux 无掩码 | 掩掉 bit0/bit8 |
| 14 | adc_seq_fsm | `preempt_rst_n` 寄存输出晚于 SOC | 默认"复位信号寄存" | 组合逻辑 `(fsm_curr_st == ST_LP_PREEMPT)` |
| 15 | adc_seq_fsm | HP SOC 和 preempt_rst_n 同拍，被复位吃掉 | ST_LP_PREEMPT 中 soc_req_set 和 rst 同时生效 | `preempt_soc_pend` 延迟到 ST_HP_SAMPLE |
| 16 | adc_seq_fsm | `muxon_fall` 覆盖 preempt_abort 已切换的 HP ch_sel | 2 拍后 muxon_fall 覆盖回 lp_ch_sel | `preempt_hold` 屏蔽 |
| 17 | adc_seq_fsm | `!spt_active` 阻止 HP preempt 时 SPT 重启 | 正常路径条件在 preempt 路径不成立 | 删 `!spt_active` |
| 18 | adc_regfile | CH_DATA 多比特用 2 级同步器跨域，概念错误 | 默认"跨域=2 级"，未判断稳定性，多比特 skew 不解决 | 数据直读，VALID 单独同步 |
| 19 | adc_regfile | VALID 读清除需 CDC 往返，开销大 | VALID 在 ADC_CLK 域，读清除靠脉冲展宽+同步器 | VALID 同步到 PCLK 域 `ch_valid_pclk`，读清除本地完成 |
| 20 | adc_regfile | `ch_data_adc[30:16]` 15-bit RSVD 浪费 480 flops | 按总线宽度 32-bit 定义内部存储 | 改为 16-bit，APB 读取时组合拼接 |
| 21 | tb_uvm | ch_sel 切换正确性无独立验证 | 数据正确不意味控制路径正确 | scoreboard 新增 ch_sel 序列检查 |
| 22 | tb_uvm | scoreboard 管道延迟匹配过度复杂 | EOC→CH_DATA 队列+时间戳 | 改为本地 VALID 后直接检查 |
| 23 | adc_analog_model | preempt_rst_n 时发 EOC 与 HP SOC 重叠 | 复位产生 eoc_int | 删复位 EOC |
| 24 | tb_uvm | adc_sequence_seq randomize 缺失 | `rand` 声明了未调 `randomize()` | 加 `void'(randomize())` |
| 25 | tb_uvm | adc_sequence_seq LP_SEQ_LEN 未配 | 默认 26 条等待不足 | 写 `LP_SEQ_LEN = 3` |
| 26 | tb_uvm | adc_sequence_seq 通道未对齐 8-bit 条目 | 位宽不匹配 | `{8'(ch[2]), 8'(ch[1]), 8'(ch[0])}` |
| 27 | 全流程 | 仿真通过后 spec 未同步更新 | 修完 RTL 直接下一步 | Step 9e+ 强制 |
| 28 | 全流程 | 批量正则替换 `16'h00XX`→`` `ADC_XXX `` 宏时丢 backtick，宏变裸标识符 | bash+perl 在带 `'` 字面量上引号转义吃掉 backtick；SV 未声明标识符恰好编译过 | 批量替换后 `git diff` 逐文件核对语义，不只看编译；带引号字面量优先用 Python |
| 29 | adc_regfile / adc_seq_fsm / adc_top | 参数化重构：派生 localparam 放 ANSI 参数列表 `#(...)` 内，iverilog -g2005 报 `requires SystemVerilog` | Verilog-2005 不支持 ANSI 端口列表内 localparam | 改 iverilog `-g2012`；详见 env-bug #10 |
| 30 | adc_params.vh | 参数化重构：多 module 共享 `.vh` 加 `ifndef 守卫，第二个起 module `Unable to bind` localparam | iverilog `define 全局，守卫使后续 include 被跳过 | `.vh` 不加 `ifndef 守卫；详见 env-bug #11 |
| 31 | adc_regfile | 参数化重构：LP_SEQ_LEN 默认 26 + LP_SEQ7 读回 0，UVM adc_reg_test 未同步导致 fail | 参数化后默认 26 配置 LP_SEQ_LEN 位宽 6→5、LP_SEQ 物理寄存器 8→7，sequence 期望值未跟随 | adc_reg_seq: LP_SEQ_LEN default check 改 0x1A、LP_SEQ7 write/read+sweep 按 `ADC_NUM_CH>=29` 条件、sweep mask 按位宽派生 |
| 32 | tb_adc_top | 参数化重构：8 通道 smoke TB 复制自 26 通道 TB，`$fsdbDumpvars(0, tb_adc_top)` / `$dumpvars` 模块名未改、`ovrd_adc_data(14'h0000)` 位宽未自适应 | 复制 TB 改参数时漏改 module 内部硬编码引用 | 复制 TB 后 grep 旧 module 名 + 硬编码位宽字面量逐一改；详见验证报告 §9 |

### 合并说明

**#1 CDC 遗漏/错误**（合并原 #1 cal_val、#4 int_events、#5 dma_ack、#6 VALID 脉冲、#18 ch_data、#19 ch_valid）

| 子问题 | 根因 | 修复 |
|:--|:--|:--|
| `cal_val[5:0]` 无同步器 | 多比特直连 | 补 2 级同步器（多比特，变化不频繁） |
| `int_events` 无 PCLK 侧同步 | 脉冲直连 | 补 PCLK 域 2 级同步 + 边沿检测 |
| `dma_ack` 无同步器 | 异步信号直连 | 补 2 级同步器 |
| VALID 读清除脉冲过短 | 单周期脉冲在慢域丢失 | 展宽 8 PCLK（后改为本地 VALID 方案） |
| ch_data 32-bit 2 级同步 | 默认"跨域=2 级"，未判断稳定性 | 数据直读，VALID 单独同步 |
| ch_valid CDC 往返 | 读清除靠脉冲展宽+同步器 | VALID 同步到 PCLK 域，读清除本地完成 |

#3 Preempt 时序链（合并原 #14 preempt_rst_n 寄存、#15 HP SOC 同拍、#16 ch_sel 覆盖、#17 SPT 重启、#23 EOC 冲突部分）

| 子问题 | 根因 | 修复 |
|:--|:--|:--|
| `preempt_rst_n` 寄存输出晚于 SOC | 默认"复位信号寄存" | 组合逻辑 `(fsm_curr_st == ST_LP_PREEMPT)` |
| HP SOC 和 preempt_rst_n 同拍，被复位吃掉 | ST_LP_PREEMPT 中 soc_req_set 和 rst 同时生效 | `preempt_soc_pend` 延迟到 ST_HP_SAMPLE |
| `muxon_fall` 覆盖 preempt_abort 切好的 HP ch_sel | 2 拍后 muxon_fall 覆盖回 lp_ch_sel | `preempt_hold` 屏蔽 |
| `!spt_active` 阻止 HP SPT 重启 | 正常路径条件在 preempt 路径不成立 | 删 `!spt_active` |

**预防措施更新（基于 6 类模式）：**
- **时序沿决策**（preempt_rst_n/SOC/ch_sel）：涉及多个信号的相对时序，先画图推演再选组合/寄存
- **控制共享条件**（`!spt_active`）：写 `if (A && B)` 时列出所有前置 FSM 状态逐一验证每个子项
- **数据跨域**（ch_data/cal_val）：先判断数据变化频率，长期稳定→同步"更新通知"
- **存储位宽**（ch_data_adc）：按数据实际位宽定义，不复制总线宽度
- **UVM sequence 配置**：创建后检查 randomize 调用、约束完备性、硬件配置对齐
- **批量改写语义核对**：批量正则/sed 替换后 `git diff` 逐文件核对语义，不只看编译通过；带引号字面量优先用 Python
