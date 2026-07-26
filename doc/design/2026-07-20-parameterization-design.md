# ADC 控制器参数化设计

日期：2026-07-20
状态：设计草案（待 review）
分支：feature/calib-pclk-rewrite

## 1. 背景与目标

当前 ADC 控制器按固定 26 通道 / 14-bit 分辨率实现。本设计将其参数化，使通道数与 ADC 数据位宽可配，分辨率/通道数变化后只需改参数即可，无需改 RTL 逻辑。

### 1.1 参数化范围

| 项目 | 是否参数化 | 说明 |
|:--|:--:|:--|
| 通道数 | 是 | 主参数，影响 ch_sel/seq_ptr/seq_len 位宽、LP_DATA/LP_SEQ 寄存器数、vld 数 |
| ADC 数据位宽 | 是 | 主参数，影响 adc_data 端口宽度（DATA 寄存器域固定 16bit） |
| SPT1 作用通道 | 是（可选） | 位图参数，默认保持现状（CH21/CH22 用 SPT1） |
| 高优先级队列长度 | 否 | 固定 4 条序列、1 个 HP_SEQ 寄存器、HP_DATA 4 个 |
| 中断/DMA/触发源个数 | 否 | 固定 6 中断源、6 MCTM 触发源 |

### 1.2 设计原则

- **向后兼容**：默认参数（26 通道 / 14bit / SPT1=CH21,CH22）下，行为与参数化前一致，现有 12 UVM case + 9 unit TB 期望值不动。
- **集中派生**：所有派生 localparam 集中在 `rtl/adc_params.vh`，改配置只动一处。
- **地址空间固定预留**：LP_DATA/LP_SEQ 地址区间按 32 预留，物理实现数随 N 收缩，超出范围读回 0、写忽略。软件驱动地址不变。
- **YAGNI**：HP 队列不参数化（固定 4）；只参数化真正需要随通道/分辨率变化的量。

## 2. 参数定义与派生

### 2.1 用户主参数（顶层可配）

| 参数 | 类型 | 默认 | 合法范围 | 说明 |
|:--|:--|:--:|:--|:--|
| `ADC_NUM_CH` | int | 26 | 4~32 | 通道数（下界 4：HP seq_ptr 需 2bit，N≥4 保证 W_CH_SEL≥W_HP_SEQ_PTR） |
| `ADC_DATA_W` | int | 14 | 1~16 | ADC 分辨率（DATA 寄存器域固定 16bit，故上限 16） |
| `ADC_SPT1_CH_MASK` | int(32bit) | `32'h0060_0000` | 任意 32bit | bit i 置 1 = 通道 i 用 SPT1 采样档位；默认 bit21/bit22（现状） |

> 命名说明：现有 `P_SHELL_MODE` 为历史参数保留；新增参数统一用 `ADC_` 前缀简写。

### 2.2 派生 localparam（`rtl/adc_params.vh` 集中定义，不可配）

```verilog
`ifndef ADC_PARAMS_VH
`define ADC_PARAMS_VH

// ---- 用户主参数（默认值，顶层可 override）----
`ifndef ADC_NUM_CH
  parameter int ADC_NUM_CH        = 26;
`else
  parameter int ADC_NUM_CH        = `ADC_NUM_CH;
`endif
`ifndef ADC_DATA_W
  parameter int ADC_DATA_W        = 14;
`else
  parameter int ADC_DATA_W        = `ADC_DATA_W;
`endif
`ifndef ADC_SPT1_CH_MASK
  parameter int ADC_SPT1_CH_MASK  = 32'h0060_0000;  // bit21,22 = CH21,CH22
`else
  parameter int ADC_SPT1_CH_MASK  = `ADC_SPT1_CH_MASK;
`endif

// ---- 派生 localparam ----
localparam int W_CH_SEL       = $clog2(ADC_NUM_CH);          // N>=4 → >=2（HP seq_ptr 需 2bit）
localparam int W_LP_SEQ_PTR   = W_CH_SEL;                 // LP seq_ptr 0~N-1
localparam int W_HP_SEQ_PTR   = 2;                        // HP seq_ptr 固定 0~3
localparam int W_LP_SEQ_LEN   = $clog2(ADC_NUM_CH + 1);   // 存 count 1~N：8→4, 26→5, 32→6
localparam int W_HP_SEQ_LEN   = 3;                        // HP_SEQ_LEN 固定 1~4
localparam int NUM_LP_DATA    = ADC_NUM_CH;               // LP_DATA 寄存器数
localparam int NUM_HP_DATA    = 4;                        // HP_DATA 固定 4
localparam int NUM_LP_SEQ_REG = (ADC_NUM_CH + 3) / 4;     // LP_SEQ 寄存器组数（每组 4 条 seq）
localparam int NUM_HP_SEQ_REG = 1;                        // HP_SEQ 固定 1 组
localparam int W_LP_DATA_WEN  = ADC_NUM_CH;               // lp_data_wr_en one-hot 宽
localparam int W_HP_DATA_WEN  = 4;                        // hp_data_wr_en 固定
localparam int W_EOC_IDX      = W_CH_SEL;                 // eoc_idx 宽（N>=4 时 W_CH_SEL>=W_HP_SEQ_PTR，够索引 LP+HP）

// HP 固定常量
localparam int HP_NUM_SEQ     = 4;

// ---- elaboration 合法范围断言 ----
`ifndef SYNTHESIS
initial begin
  if (ADC_NUM_CH < 4 || ADC_NUM_CH > 32)
    $error("ADC_NUM_CH=%0d out of range [4,32] (HP seq_ptr 需 2bit, N>=4 保证 W_CH_SEL>=W_HP_SEQ_PTR)", ADC_NUM_CH);
  if (ADC_DATA_W < 1 || ADC_DATA_W > 16)
    $error("ADC_DATA_W=%0d out of range [1,16] (DATA register field fixed 16-bit)", ADC_DATA_W);
end
`endif

`endif // ADC_PARAMS_VH
```

> `$clog2(1)=0` 会导致 1 通道 ch_sel 位宽 0（非法），故下限取 2。

### 2.3 典型配置派生值

| 配置 | ADC_NUM_CH | W_CH_SEL | W_LP_SEQ_LEN | NUM_LP_DATA | NUM_LP_SEQ_REG | LP_DATA_WEN |
|:--|:--:|:--:|:--:|:--:|:--:|:--:|
| 默认 26 通道 | 26 | 5 | 5 | 26 | 7 | 26 |
| 8 通道 | 8 | 3 | 4 | 8 | 2 | 8 |
| 16 通道 | 16 | 4 | 5 | 16 | 4 | 16 |
| 32 通道 | 32 | 5 | 6 | 32 | 8 | 32 |

## 3. 寄存器布局与地址译码

### 3.1 地址空间（固定按 32 预留）

| 区域 | 地址范围（固定预留） | 物理实现数 | 超出范围行为 |
|:--|:--|:--|:--|
| LP_DATA | 0x24 ~ 0xA0（32 槽） | `NUM_LP_DATA = N` | idx ≥ N 读回 0、写忽略 |
| HP_DATA | 0xA4 ~ 0xB0（4 槽） | 4（固定） | — |
| LP_SEQ | 0xB8 ~ 0xD4（8 组=32 seq） | `NUM_LP_SEQ_REG = ceil(N/4)` | 组 idx ≥ ceil(N/4) 读回 0、写忽略 |
| HP_SEQ | 0xD8（1 组=4 seq） | 1（固定） | — |
| LP_SEQ_LEN | 0xDC | 1，位宽 `W_LP_SEQ_LEN` | — |
| HP_SEQ_LEN | 0xE0 | 1，位宽 3（固定） | — |

地址区间判断（`is_lp_data`/`is_hp_data`/`is_lp_seq`/`is_hp_seq`）保持固定边界不变，仅写/读时加 `< NUM_*` 边界判断。

### 3.2 8bit seq entry 格式（参数化）

```
[W_CH_SEL-1:0] = ch_sel    // 8通道→[2:0], 26通道→[4:0], 32通道→[4:0]
[7:W_CH_SEL]   = rsv       // 8通道→[7:3] rsv, 26通道→[7:5] rsv
```

每组 32bit 寄存器仍放 4 个 entry（[7:0]/[15:8]/[23:16]/[31:24]），entry 内 ch_sel 位宽自适应、高位补 rsv。HP_SEQ 同理（W_CH_SEL 自适应）。

### 3.3 默认 26 配置的兼容性影响

参数化后默认配置与现状的差异（仅以下两条，均已确认接受）：
- **LP_SEQ 物理寄存器数 8 → 7**：`ceil(26/4)=7`，0xD4 从"实现 rsv entry"变"读回 0"。软件写 0xD4 无效、读回 0。
- **LP_SEQ_LEN 物理位宽 6 → 5**：`$clog2(27)=5`，仍能存 26；复位值 26 不变、软件写 26 仍正确，仅寄存器物理位宽收窄。

其余（地址区间、LP_DATA 26 个、HP_DATA 4 个、HP_SEQ 1 个、ch_sel 5bit、复位值）全不变。

## 4. 模块改动点

### 4.1 adc_regfile.v

| 改动项 | 现状 | 参数化后 |
|:--|:--|:--|
| 端口 `lp_data_wr_en` | `[25:0]` | `[NUM_LP_DATA-1:0]` |
| 端口 `hp_data_wr_en` | `[3:0]` | `[3:0]`（固定） |
| 端口 `eoc_idx` | `[4:0]` | `[W_EOC_IDX-1:0]` |
| `lp_data` 数组 | `reg [15:0] lp_data [0:25]` | `reg [15:0] lp_data [0:NUM_LP_DATA-1]` |
| `hp_data` 数组 | `reg [15:0] hp_data [0:3]` | 不变 |
| `lp_valid_pclk` | `reg [25:0]` | `reg [NUM_LP_DATA-1:0]` |
| `hp_valid_pclk` | `reg [3:0]` | 不变 |
| `lp_data_idx` | `reg [4:0]` | `reg [W_EOC_IDX-1:0]` |
| `cfg_lp_seq` 端口 | 8 条独立 32bit 线 `cfg_lp_seq0..7` | packed bus `cfg_lp_seq_flat[W_CH_SEL*NUM_LP_DATA-1:0]`，entry i 在 `[i*W_CH_SEL +: W_CH_SEL]` |
| `cfg_hp_seq` 端口 | 1 条 32bit `cfg_hp_seq` | packed bus `cfg_hp_seq_flat[W_CH_SEL*NUM_HP_DATA-1:0]`，entry i 在 `[i*W_CH_SEL +: W_CH_SEL]` |
| `lp_seq` 内部存储 | `reg [31:0] lp_seq [0:7]`（32bit/组） | `reg [W_CH_SEL-1:0] lp_seq_ent [0:NUM_LP_DATA-1]`（N×W_CH_SEL bit ch_sel，每通道一个，rsv 不存） |
| `hp_seq` 内部存储 | `reg [31:0] hp_seq` | `reg [W_CH_SEL-1:0] hp_seq_ent [0:NUM_HP_DATA-1]`（4×W_CH_SEL bit） |
| `lp_seq_len` | `reg [5:0]` 复位 26 | `reg [W_LP_SEQ_LEN-1:0]` 复位 `ADC_NUM_CH` |
| `hp_seq_len` | `reg [2:0]` 复位 4 | 不变 |
| 地址译码边界 | `eoc_idx <= 5'd25` / `<= 5'd3` | `eoc_idx < NUM_LP_DATA` / `< 4` |
| LP_SEQ 写/读 | 8 组都实现（32bit 整存整读） | APB 边界拆/拼 32bit↔4 ch_sel：写取每 8bit 占位低 `W_CH_SEL` bit、读零扩展 rsv 补 0；全局 entry idx = `lp_seq_idx*4+k`，`< NUM_LP_DATA` 保护，超出读 0 写忽略 |
| 读回拼接 | `{valid, 15'h0, data}` | DATA 域固定 16bit 不变；valid 在 bit31 不变 |

**`cfg_lp_seq`/`cfg_hp_seq` 传递方式**：采用 packed bus——regfile 内部按 ch_sel 粒度存储（N×`W_CH_SEL` bit / 4×`W_CH_SEL` bit，rsv 高位不存），输出时用 generate part-select 左值 assign 拼成 `[W_CH_SEL*N-1:0]` packed bus，entry i 在 `[i*W_CH_SEL +: W_CH_SEL]`；seq_fsm 直切 `cfg_lp_seq_flat[gi*W_CH_SEL +: W_CH_SEL]` 取 ch_sel，无需 `lp_seq_grp` 中转拆组。APB 边界仍按 32bit/组（4 entry × 8bit 占位）读写，拆/拼只在 regfile 一处。与项目现有 packed vector 端口形式一致，无 unpacked 数组端口的综合兼容顾虑。

### 4.2 adc_seq_fsm.v

| 改动项 | 现状 | 参数化后 |
|:--|:--|:--|
| 端口 `adc_data` | `[13:0]` | `[ADC_DATA_W-1:0]` |
| 端口 `ch_sel` | `[4:0]` | `[W_CH_SEL-1:0]` |
| 端口 `cfg_lp_seq` | 8 条 32bit `cfg_lp_seq0..7` | packed bus `cfg_lp_seq_flat[W_CH_SEL*ADC_NUM_CH-1:0]`，entry i 在 `[i*W_CH_SEL +: W_CH_SEL]` |
| 端口 `cfg_hp_seq` | 1 条 32bit | packed bus `cfg_hp_seq_flat[W_CH_SEL*4-1:0]` |
| `lp_seq_ptr` | `reg [4:0]` | `reg [W_LP_SEQ_PTR-1:0]` |
| `hp_seq_ptr` | `reg [1:0]` | 不变 |
| `lp_entry_array` | `[0:31]`，32 条手写 assign | `[0:ADC_NUM_CH-1]`，元素 `W_CH_SEL` bit，generate 直切 `cfg_lp_seq_flat[gi*W_CH_SEL +: W_CH_SEL]` |
| `hp_entry_array` | `[0:3]` | `[0:3]`，元素 `W_CH_SEL` bit，从 `cfg_hp_seq_flat[i*W_CH_SEL +: W_CH_SEL]` 直切 |
| `cur_ch_sel`/`lp_ch_sel`/`hp_ch_sel` | `[4:0]` | `[W_CH_SEL-1:0]` |
| `adc_data_d1`/`adc_data_capt` | `reg [13:0]` | `reg [ADC_DATA_W-1:0]` |
| SPT 分档判断 | `cur_ch_sel == 5'd21 \|\| 5'd22` | `spt1_ch_mask[cur_ch_sel]`（位图查表） |
| seq_ptr 回卷 | `5'h00` / `+1` | 用 `W_LP_SEQ_PTR` 位宽，回卷逻辑不变 |
| ch_sel 默认值 | `5'h00` | `{W_CH_SEL{1'b0}}` |

**`lp_entry_array` generate 实现**（直切 packed bus，元素即 ch_sel，无需 `lp_seq_grp` 中转）：

```verilog
wire [W_CH_SEL-1:0] lp_entry_array [0:ADC_NUM_CH-1];
genvar gi;
generate
  for (gi = 0; gi < ADC_NUM_CH; gi = gi + 1) begin : gen_lp_entry
    assign lp_entry_array[gi] = cfg_lp_seq_flat[gi*W_CH_SEL +: W_CH_SEL];
  end
endgenerate

assign lp_ch_sel = lp_entry_array[lp_seq_ptr];   // 元素已是 W_CH_SEL bit，无需再切片
```

**SPT1 位图查表**：

```verilog
// ADC_SPT1_CH_MASK: bit i = 1 → 通道 i 用 SPT1
wire use_spt1 = ADC_SPT1_CH_MASK[cur_ch_sel];  // cur_ch_sel 宽 W_CH_SEL ≤ 5
// SPT 计数器选择：use_spt1 ? cfg_spt1 : cfg_spt0
```

> `ADC_SPT1_CH_MASK` 为 32bit，`cur_ch_sel` 位宽 ≤ 5，索引安全。通道数 < 32 时高位 mask 位不引用，综合优化掉。

### 4.3 adc_top.v

- 端口 `ch_sel` `[4:0]` → `[W_CH_SEL-1:0]`
- 端口 `adc_data` `[13:0]` → `[ADC_DATA_W-1:0]`
- 顶层参数列表：`#(parameter P_SHELL_MODE=0, parameter ADC_NUM_CH=26, parameter ADC_DATA_W=14, parameter ADC_SPT1_CH_MASK=32'h0060_0000)`
- `include adc_params.vh` 后 internal wire 位宽自动派生
- `cfg_lp_seq_flat`/`cfg_hp_seq_flat` packed bus 连线（宽度 `W_CH_SEL*N`），regfile↔seq_fsm 两实例对接

### 4.4 不涉及参数化的模块

`adc_apb_if` / `adc_trig_sync` / `adc_int_ctrl` / `adc_dma_req` / `adc_rst_sync` / `adc_sync_cell`：不涉及通道数/数据位宽，无需改。中断源（6）、MCTM 触发源（6）、DMA 事件源个数固定。

## 5. 数据对齐与溢出

### 5.1 DATA 寄存器域（固定 16bit）

DATA 寄存器域位宽固定 16bit（bit31=VALID，bit30:16=rsv，bit15:0=DATA）。ADC_DATA_W 参数化只影响输入端口 `adc_data[ADC_DATA_W-1:0]` 与 FSM 内 `adc_data_d1/adc_data_capt` 位宽，DATA 寄存器域不变。

| 对齐方式 | DATA 域 | 说明 |
|:--|:--|:--|
| 右对齐 | `[ADC_DATA_W-1:0] = ADC[]`, `[15:ADC_DATA_W] = 0` | 默认 |
| 左对齐 | `[15:16-ADC_DATA_W] = ADC[]`, `[15-ADC_DATA_W:0] = 0` | 左移至 MSB 对齐 |

> 对齐逻辑用参数化拼接实现，`ADC_DATA_W=14` 时与现状完全一致。

### 5.2 溢出检测

不变。`lp_valid_pclk` / `hp_valid_pclk` 位宽随 `NUM_LP_DATA` / 4 变，溢出检测逻辑（EOC 握手到达时查 valid[idx]）不变，idx 边界用 `< NUM_LP_DATA`。

## 6. 下游文件同步

| 文件 | 同步内容 |
|:--|:--|
| `spec/adc_spec.md` | §1.1 特性改为参数化描述；新增「参数化配置」章节（主参数/派生表/entry 格式/地址预留说明）；§3 LP_DATA「26 个」→「N 个，默认 26」；LP_SEQ_LEN 位宽「6-bit」→「$clog2(N+1) bit，默认 5bit 存 26」；entry ch_sel 位宽标注「= W_CH_SEL」；SPT1 通道改为「由 ADC_SPT1_CH_MASK 位图决定，默认 CH21/CH22」 |
| regmap 产物 | 跑 `/regmap-gen` 重新生成，地址/位宽标注参数化 |
| `tb/` testbench | 顶层 `include adc_params.vh`，端口位宽用派生 localparam；UVM agent/sequence 通道号随机范围 `[0:ADC_NUM_CH-1]` |
| UVM testplan/testcase | 默认 26 跑全回归不动；新增 8 通道/12bit smoke 配置条目 |
| `scripts/adc_constraints.sdc` | 端口名不变，无需改；`/sdc-manager` 自检端口名存在性应仍通过 |
| `filelist.f` | 若需列头文件则加 `rtl/adc_params.vh`（`include 即可不加） |
| `doc/project_config.md` | 模块层次加 `adc_params.vh`；特性段标注「参数化：通道数/ADC 位宽/SPT1 通道可配」 |
| Makefile | 可选加 `PARAM_NUM_CH` / `PARAM_DATA_W` 透传给仿真（smoke 用） |

## 7. 验证策略

### 7.1 默认 26/14 全回归（向后兼容）

现有 12 UVM case + 9 unit TB 期望值不动，`make check` 全绿证明向后兼容。预期：除 LP_SEQ 0xD4 读回 0、LP_SEQ_LEN 物理位宽 6→5 外，行为与参数化前一致。

### 7.2 8 通道 / 12bit smoke

- 顶层参数设 `ADC_NUM_CH=8, ADC_DATA_W=12, ADC_SPT1_CH_MASK=0`（全 SPT0）
- 跑 `make test-unit` + 2~3 个关键 UVM case（APB RW、单次采样、HP 抢占）
- 验证点：
  - ch_sel 3bit、LP_DATA 8 个、LP_SEQ 2 组（8 条 seq）
  - LP_SEQ_LEN 4bit、复位值 8
  - adc_data 12bit 右对齐/左对齐正确
  - 0x24+8*4=0x44 起 LP_DATA 读回 0；0xB8+2*4=0xC0 起 LP_SEQ 读回 0
  - SPT1 mask=0 时全部走 SPT0

### 7.3 覆盖率

默认 26 配置走完整 `/coverage-analyze` 闭环。8 通道 smoke 只看 PASS，不收覆盖率（避免双份覆盖率合并）。

## 8. 一致性检查新增项

参数化后 `/consistency-check` 五端一致性新增：
- spec 参数章节 ↔ RTL `adc_params.vh` 派生表 ↔ regmap 地址/位宽 ↔ TB 端口位宽 ↔ SDC 端口名
- 默认 26 配置下，除 LP_SEQ 寄存器数 8→7、LP_SEQ_LEN 位宽 6→5 两条已确认变化外，所有端必须与参数化前一致

## 9. 风险与注意事项

1. **`$clog2` 综合/lint 兼容**：iverilog 与 VCS 均支持 `$clog2`。`adc_params.vh` 内 initial `$error` 用 `` `ifndef SYNTHESIS `` 保护，避免综合阶段报错；若 lint 报 `$error` 不可综合，加 `// lint_waive: <原因>`。
2. **SPT1 mask 通道越界**：`ADC_SPT1_CH_MASK` 为 32bit，`cur_ch_sel` 位宽 ≤ 5，索引安全；通道数 < 32 时高位 mask 不引用。
3. **packed bus part-select 左值**：`assign cfg_lp_seq_flat[ei*8 +: 8] = lp_seq_ent[ei]` 在 generate 内对 packed vector 做 part-select 左值，iverilog -g2012 + VCS 均支持（已验证 lint/vcs/test-unit 通过）；若综合工具报错，退路 always @(*) 用 integer 循环拼装。
4. **ch_sel 位宽变化对抢占时序的影响**：HP 抢占时 ch_sel 切换逻辑（preempt_abort/preempt_hold）依赖 cur_ch_sel 比较，位宽自适应后比较逻辑不变（等位宽比较），需在 8 通道 smoke 中验证抢占时序。
5. **LP_SEQ_LEN 复位值**：参数化后复位值为 `ADC_NUM_CH`（不是固定 26），需确认 regfile 复位块用 `ADC_NUM_CH` 而非硬编码。

## 10. 不在本次范围

- HP 队列长度参数化（固定 4）
- 中断源/DMA 事件源/MCTM 触发源个数参数化（固定）
- 地址空间随 N 浮动收缩（采用固定预留方案）
- DATA 寄存器域位宽参数化（固定 16bit）
- 多组配置的完整 UVM 回归（仅默认 26 全回归 + 8 通道 smoke）
