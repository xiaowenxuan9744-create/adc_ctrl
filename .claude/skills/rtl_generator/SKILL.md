---
name: rtl-generator
description: 根据结构化规格生成可综合的 Verilog/SystemVerilog RTL 代码
triggers:
  - 生成RTL
  - 生成Verilog
  - 生成模块代码
  - RTL生成
---
# RTL Generator - RTL 代码生成器

根据 spec-parser 输出的 JSON 规格生成可综合的 RTL 代码。

## 输入

- spec-parser 输出的 JSON 规格
- 或用户描述的模块接口和功能

## 输出

- 单个或多个 `.v` / `.sv` 文件
- 模块骨架或完整实现

## 流程

### Step 1: 确定生成顺序

按 `connections` 中的依赖关系确定模块生成顺序：

1. 先生成无依赖的叶子模块
2. 再生成依赖已生成模块的父模块
3. 最后生成顶层模块

### Step 2: 生成模块声明

```verilog
module module_name #(
  parameter DATA_WIDTH = 32
) (
  input  wire        clk,
  input  wire        rst_n,
  input  wire [DATA_WIDTH-1:0] data_in,
  output reg  [DATA_WIDTH-1:0] data_out
);
```

### Step 3: 声明内部信号

根据端口连接需求推断内部信号：

```verilog
  // 内部信号
  wire [DATA_WIDTH-1:0] mul_result;
  reg  [DATA_WIDTH-1:0] acc_reg;
```

### Step 4: 生成逻辑

#### 叶子模块

根据端口名称和功能描述生成：

- 时序逻辑：`always @(posedge clk)`
- 组合逻辑：`assign` 或 `always @(*)`，优先使用`assign`
- 状态机：三段式 FSM

#### 父模块

实例化子模块并完成端口连接：

```verilog
  // 子模块实例
  multiplier #(
    .DATA_WIDTH(DATA_WIDTH)
  ) u_mul (
    .clk     (clk),
    .a       (data_in),
    .b       (32'd2),
    .result  (mul_result)
  );
```

### Step 5: 代码风格规范

所有生成的 RTL 代码必须遵循以下编码约定。

#### 设计简化原则（M2 强制）

代码必须保持简洁直白，**坚决杜绝将简单逻辑复杂化**。核心约束：

- **简单逻辑直接写**：能用一行 `assign` 表达的逻辑，不对其进行模块封装、参数化或状态机包装
- **禁止无意义抽象**：单一用途的信号或逻辑块不应引入参数化/宏定义/设计模式
- **TB 同样简洁**：Testbench 的激励生成、检查逻辑、结果比对同样遵循简化原则，禁止引入多余的层次结构
- **三行直白代码优于一个过度封装的模块**
- **判断标准**：如果一个逻辑可以被团队新人一眼看懂，就不要做任何"优化封装"

反例（禁止）：
```verilog
// ❌ 过度设计：简单二选一包装成参数化模块
module mux2 #(parameter W = 8) (input [W-1:0] a, b, input sel, output [W-1:0] o);
    assign o = sel ? b : a;
endmodule
```
正例：
```verilog
// ✅ 直接表达
assign pixel_y = (y_is_even) ? y0 : y1;
```

#### 精确修改原则（M2 强制）

修改已有 RTL 时，严格遵守最小修改范围：

- **只改必须改的模块**：不顺手"优化"或"重构"与本次任务无关的代码路径
- **保留原有设计意图**：不删除或改写原有注释中的设计意图说明（如 `// Buffer to avoid CDC glitch`）
- **保持风格一致**：新增代码的命名约定、缩进、端口对齐方式与所在文件的原有风格完全一致，不引入新风格
- **不擅自合并/拆分模块**：除非规格明确要求，否则不改变模块边界

#### 先理解后编码原则（M2 强制）

修改已有模块前，必须先理解其微架构：

- **阅读相关文档**：先看对应模块的 spec 文档（`spec/<module>.md`）和架构文档
- **理解数据流**：清楚信号的上下游关系后再动笔
- **列出方案再选择**：如有多种实现方式，列出并分析优劣后再编码
- **不确定则提问**：遇到不确定的时序行为、接口协议、边界条件时，主动提问而非猜测

#### 文件组织与头部

- 每个文件只包含一个模块（M2 强制）
- 文件名与模块名一致，小写（如 `tx_fifo.v` 对应 `TX_FIFO`）
- 每个文件必须包含文件头，含：文件名、作者、版本号、日期、功能描述、参数说明
- 文件头用标准边界标记起止（`//********************`）
- 额外构造（task/function）需独立头部，含：名称、类型、用途、参数
- 文件头建议包含：复位策略、时钟策略、关键时序、测试特性、异步接口说明

#### 命名规范

- **模块/实例名**：小写字母，下划线分隔单词（如 `tx_controller_top`, `u_tx_ctrl`）
- **端口/信号/变量名**：小写字母，用下划线分隔单词（`ram_addr`, `wr_data`）
- **常量（parameter / `define）**：大写字母（`BUS_WIDTH `, `AHB_TRANS_SEQ`）
- **时钟信号**：统一含 `clk`（`clk`, `hclk`, `clk_77m`, `<domain>_clk` 等）
- **复位信号**：统一含 `rst`（`rst_n`, `hrst_n`）
- **低有效信号**：后缀 `_n`（`rst_n`, `we_n`）
- **FSM 变量**：`<fsm_name>_curr_st`, `<fsm_name>_next_st`
- **锁存器信号**：后缀 `_lat`
- **三态信号**：后缀 `_z`
- **异步信号**：后缀 `_a`
- **延迟寄存器**：后缀 `_ff1`, `_ff2`, `_ff3`...
- **仅字母、数字、下划线**，首字符必须是字母（M1 强制）
- 信号名长度不超过 20 字符
- 信号名在整个层次结构中保持一致
- 禁止使用 Verilog/VHDL 关键字作为标识符（M1 强制）
- 禁止使用_reg为后缀

#### 寄存器排布规范

适用于 AHB/APB 从机寄存器接口模块的位域定义与 RTL 编码。

##### 1. 配对合并

逻辑上成对的参数合并到同一个 32-bit 寄存器，减少地址空间占用，避免配置中间态：

| 成对关系 | 合并寄存器 | 位域布局 |
|----------|-----------|---------|
| 宽+高 | `XXX_SIZE` | [27:16]=h, [15:12] rsvd, [11:0]=w |
| X+Y 坐标 | `XXX_ORIGIN` | [27:16]=y, [15:12] rsvd, [11:0]=x |
| 行+列 | `XXX_GRID` | [14:8]=rows, [7] rsvd, [6:0]=cols |
| 基地址 L/R | `XXX_BASE_L` / `XXX_BASE_R` | 保持独立地址（地址类不适合合并） |

同一类布局风格在项目内保持统一（尺寸类高半字放 H、低半字放 W；坐标类高半字放 Y、低半字放 X）。

##### 2. 地址连续性

删除某个寄存器后，后续所有寄存器地址依次前移，保持紧凑排列，**不留空洞**。禁止将释放的地址标记为"保留（reserved）"后再在其后追加新寄存器——应直接占用空出的地址位。

修改前后对比：

| 操作 | 错误做法 | 正确做法 |
|------|---------|---------|
| 删除 0x04 的寄存器 | 0x00, ~~0x04~~, 0x08, 0x0C（留空洞） | 0x00, 0x04, 0x08（前移紧凑） |
| 新增寄存器 | 追加到末尾 0x10 | 优先填入空闲位置，或追加后重排 |

##### 3. 位域对齐

多 bit 配置项按 4/8/16 bit 边界排布，禁止跨边界字段：

- 1-bit 标志位：可放任意位置
- 2~4 bit 字段：起始位为 4 的倍数（bit0/4/8/12/16/20/24/28）
- 5~8 bit 字段：起始位为 8 的倍数（bit0/8/16/24）
- 9~16 bit 字段：起始位为 16 的倍数（bit0/16）

**反例**（禁止）：5-bit 字段占据 [6:2]，8-bit 字段占据 [19:12]。
**正例**：5-bit 字段占据 [12:8]（8 边界），8-bit 字段占据 [23:16]（16 边界）。

对齐后产生的间隙填 rsvd，读回 0。好处：软件可用 byte/halfword 掩码独立访问字段，仿真波形中字段边界对齐十六进制显示。

##### 4. 寄存器位域独立定义规范（强制）

> **设计动机**：传统做法用一个 `ctrl_reg [31:0]` 存储整个 32-bit 寄存器，
> RSVD 位也占用 flop 资源，且 `ctrl_reg[0]` 这种切片命名看不出含义。
> 新规范：每个功能位域独立定义，按 spec 位域名命名，RSVD 位不定义 reg，
> 读回时按 spec 位置拼接 32-bit bus。零 RSVD flop 浪费 + 命名即文档。

**规则：**

1. **每个功能位域独立定义 reg**，不用一个大的 `xxx_reg [31:0]` 存整个寄存器
2. **按 spec 位域名命名**，不加 `_reg` 后缀，保持名称全局一致
   - spec `TX_EN` → `reg tx_en;`（不是 `ctrl_reg[0]`）
   - spec `MODE[2:0]` → `reg [2:0] mode;`（不是 `ctrl_reg[10:8]`）
   - spec `INTERVAL[6:0]` → `reg [6:0] interval;`
3. **RSVD 位不定义 reg**，读回时硬编码 0
4. **读回时按 spec 位置拼接**，用 spec 定义的寄存器总名称
5. **CDC 同步链直接引用位域名**，不靠切片
6. **WO 位不定义存储 reg**，读回硬编码 0（写后不存）

**示例：CTRL 寄存器（0x00）**

spec 定义：
```
[0]     ADC_EN        RW
[1]     SW_RST        RW_SS（自清零）
[2]     RSVD          RO
[3]     DATA_ALIGN    RW
[7:4]   RSVD          RO
[10:8]  SPT0[2:0]     RW
[13:11] SPT1[2:0]     RW
[14]    CONT_MODE     RW
[15]    RSVD          RO
[22:16] SMPL_INTERVAL[6:0] RW
[31:23] RSVD          RO
```

RTL 实现：
```verilog
// 位域独立定义（RSVD 不定义 reg）
reg        adc_en;           // [0]
reg        sw_rst;           // [1] 自清零
// [2] RSVD — 不定义
reg        data_align;       // [3]
// [7:4] RSVD — 不定义
reg [2:0]  spt0;             // [10:8]
reg [2:0]  spt1;             // [13:11]
reg        cont_mode;        // [14]
// [15] RSVD — 不定义
reg [6:0]  smpl_interval;    // [22:16]
// [31:23] RSVD — 不定义

// 写入（逐位域赋值）
if (wr_en && addr == CTRL) begin
    adc_en         <= wr_data[0];
    sw_rst         <= wr_data[1];
    data_align     <= wr_data[3];
    spt0           <= wr_data[10:8];
    spt1           <= wr_data[13:11];
    cont_mode      <= wr_data[14];
    smpl_interval  <= wr_data[22:16];
end

// 读回（按 spec 位置拼接，RSVD 补 0）
rd_data = {9'h0, smpl_interval, 1'b0, cont_mode, spt1, spt0, 5'h0, data_align, 1'b0, sw_rst, adc_en};

// CDC 同步链（直接引用位域名，不切片）
ctrl_adc_en_s1 <= adc_en;        // 不是 ctrl_reg[0]
ctrl_spt0_s1   <= spt0;          // 不是 ctrl_reg[10:8]
```

**优势：**
- **零 RSVD flop**——RSVD 位不定义 reg，不浪费资源
- **命名即文档**——`adc_en` 而非 `ctrl_reg[0]`，看代码即知 spec 位域
- **无打包问题**——每个位域独立，不存在"中间有 RSVD 要不要重新打包"的纠结
- **toggle 覆盖率准确**——没有 RSVD 位拉低 toggle（实测省 80 flops，toggle +15%）
- **WO 位不存**——写后不存 reg，读回硬编码 0，不浪费 flop

**适用范围：** 所有含 APB/AHB 从机寄存器接口的模块。

##### 5. CDC 同步设计规范（强制）

> **设计动机**（ADC 项目历史教训）：regfile 曾对所有 PCLK→ADC_CLK 配置信号都加 2 级同步（272 flop），
> 但大多数配置在使能位=1 之前写好，使能位同步完成时已稳定，不需要同步。
> 本规范按信号特性分类，只对真正需要同步的信号加同步器。

### 5.1 CDC 基本原则（所有跨域路径必须遵守）

1. **跨域信号必须先过寄存器**——源域输出的跨域信号必须是寄存器输出（posedge/negedge 打过一拍），禁止组合逻辑直接跨域。组合路径的毛刺会传播到目标域导致误触发。

2. **同步器放在接收域**——2 级同步器的两个 flip-flop 必须在目标时钟域，靠近目标域的时钟树。不在发送域做同步。

3. **2 级同步只适用于单比特**——多比特信号不能逐位 2 级同步，因为各位之间有 skew，目标域可能采到中间态。多比特必须用握手/Gray码/FIFO/快照等方式。

4. **同步器级数选择**——默认 2 级（MTBF 足够）。高频域（>500MHz）或高可靠性场景（汽车/航空）用 3 级。2 级 vs 3 级是 MTBF 权衡，不是功能差异。

### 5.2 信号分类与同步策略

| 类型 | 同步方式 | 适用条件 | 例子 |
|:--|:--|:--|:--|
| **实时电平（单比特）** | 2级同步 | 目标域每拍检查，信号可能随时变化 | 使能位（FSM每拍查） |
| **配置类** | **不同步（设计契约）** | 源域写好后到目标域使用有足够稳定时间 | 模式/分频/中断使能 |
| **脉冲事件（单比特）** | 2级同步+边沿检测 | 单拍脉冲跨域 | 完成脉冲/溢出脉冲 |
| **多比特数据+握手** | **源域寄存+不同步直读** | 配合单比特握手信号，握手到达时数据已稳定 | 索引/指针多比特 |
| **多比特数据（频繁变化）** | 异步FIFO或Gray码 | 数据频繁变化，不能用握手 | FIFO指针/数据流 |
| **多比特状态读回** | 源域寄存快照+目标域同步后读 | 多比特状态偶尔读回 | 状态寄存器读回 |
| **状态回传（单比特）** | 2级同步 | 源域状态，目标域读 | busy/done 标志 |
| **SW脉冲触发** | **不在regfile同步** | 传raw给专门模块做同步+边沿检测 | 软件触发→trig_sync |

### 5.3 各类型详细说明

**配置类不同步（设计契约模式）：**

```
软件流程（spec初始化流程）：
  1. 使能位=0 时配置所有寄存器
  2. 写使能位=1 → 使能信号经 2级同步到目标域（2个目标域周期）
  3. 同步后的使能有效后 FSM 开始工作——此时配置信号早已稳定

关键：使能位同步的 2 个目标域周期远大于源域→目标域传播延迟，
配置信号在 FSM 开始工作时一定稳定。不需要额外同步。
```

> **重要警告**：这是设计契约，不是 CDC 保证。
> - RTL 不提供硬件保护——工作期间改配置会产生亚稳态，行为未定义
> - 软件必须保证：使能位=1 期间不修改配置寄存器
> - SDC false_path 的含义是"工具不检查时序"，不是"路径安全"
> - 如果无法保证软件契约，必须改用 2 级同步（多比特则用握手模式）

**SDC 约束：** 配置类路径设 `set_false_path -from <src_clk> -to <dst_clk>`，
因为这些路径不满足"异步域每拍读"的前提——只在使能位同步完成后才读。

**多比特数据+握手（源域寄存 + 数据直读）：**

```
源域:
  事件发生 → data[N:0] <= src_ptr (源域寄存器锁存)
           → pulse <= 1 (单比特脉冲,跨域同步)
  之后 data 保持不变,直到下次事件

目标域:
  pulse 2级同步 → pulse_s2 (单比特,防亚稳态)
  pulse_s2 上升沿到达时:
    data 已稳定了 N 个源域周期 (N = 事件间隔 ≥ 几十拍)
    N >> 任何 bit-to-bit skew
    → 直接读 data, 不需要同步

保护不来自那1级寄存器,而来自时序关系:
  数据在握手信号到达前已稳定 N 个周期 → 直读安全
```

**多比特数据频繁变化（异步FIFO / Gray码）：**

当多比特数据频繁变化（如数据流、FIFO 指针），不能用握手模式（握手太慢）：
- **异步 FIFO**：跨域数据传输的标准方案，读写指针用 Gray 码跨域
- **Gray 码**：连续计数值跨域，每次只有 1 bit 变化，2 级同步安全
- 适用场景：DMA 数据传输、跨域计数器、FIFO 满空判断

**多比特状态读回（寄存快照）：**

偶尔需要读回的多比特状态（如读源域的完整状态寄存器）：
- 源域用一个 enable 信号触发快照寄存器锁存当前值
- 快照值跨域 2 级同步后读
- 或者：源域寄存器本身在 EOC 后到下次 EOC 之间稳定 → 直读（同握手模式）

### 5.4 脉冲跨域同步注意事项

1. **脉冲信号不能直传跨域**——源域 1 拍脉冲（如源域 20ns）可能落在目标域
   时钟周期（如目标域 40ns）的两个沿之间而被漏掉。必须在目标域做 2 级同步
   +边沿检测，不能源域直传目标域做边沿检测。
2. **不需要源域预同步**——脉冲从源域到目标域，只需在目标域做 2 级同步+边沿
   检测。在源域额外做 2 级预同步不仅浪费 flop（4 级 vs 2 级），还增加延迟。
3. **SW_TRIG 等 WO 脉冲**——在 regfile 里存 1 拍脉冲 reg，直接输出给专门模块
   （如 trig_sync）做 CDC 同步+边沿检测。不在 regfile 里同步。
4. **快时钟→慢时钟的脉冲展宽**——源域（快时钟）脉冲可能被目标域（慢时钟）
   漏掉。如果 2 级同步+边沿检测仍可能漏（脉冲窄于目标域周期），需要先在源域
   展宽脉冲（至少 1 个目标域周期宽度），再做同步。或者改用电平+握手模式。

### 5.5 复位跨域（异步断言，同步释放）

> **最易出问题的 CDC 路径**——复位释放如果不同步，某些寄存器看到复位释放、
> 某些没看到，导致状态不一致。

**规则：复位断言异步传播，复位释放必须同步到对应时钟域。**

```verilog
// 标准做法：异步复位同步释放
// 复位断言（低有效）：立即传播到所有寄存器（异步）
// 复位释放：经过目标域 2 级同步后才释放
always @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) begin
        rst_sync_s1 <= 1'b0;
        rst_sync_s2 <= 1'b0;
    end else begin
        rst_sync_s1 <= 1'b1;  // 复位释放后,同步到目标域
        rst_sync_s2 <= rst_sync_s1;
    end
end
// rst_sync_s2 是目标域的同步复位释放信号
// 所有目标域寄存器用 rst_sync_s2 做复位
```

**多域复位：** 每个时钟域需要自己的"异步复位同步释放"电路。不能用一个域的
同步释放信号直接做另一个域的复位——必须各自同步。

### 5.6 寄存器 spec 需标注 sync 属性

每个位域在 spec 里标注是否需要 CDC 同步：
- `sync=yes` → 实时电平（单比特），2级同步
- `sync=no` → 配置类，不同步（设计契约，使能位前配好，工作期间不改）
- `sync=pulse` → 脉冲事件（单比特），2级同步+边沿检测
- `sync=handshake` → 多比特数据+握手，源域寄存+目标域同步握手后直读
- `sync=fifo` → 多比特频繁变化，异步FIFO
- `sync=gray` → 多比特连续计数，Gray码+2级同步

### 5.7 不生成 RSVD 地址的寄存器

预留地址空间不生成寄存器（读回0），只为未来扩展保留地址位置。
例：LP_DATA[0:25] 生成26个寄存器，LP_DATA[26:31] 预留地址不生成。
扩展时只需新增寄存器，不影响后续地址布局。

##### 6. 命名风格

寄存器与位域命名遵循简洁、统一原则：

- 寄存器总名称（spec 地址定义）：`大写模块前缀_功能`，如 `<PROJ>_FRAME_SIZE`、`<PROJ>_MESH_GRID`
- 位域信号（RTL 内部 reg）：按 spec 位域名小写命名，**不加 `_reg` 后缀**
  - 如 `tx_en`、`sw_rst`、`mode`、`interval`、`cont_mode`
- 配置输出（到其他模块）：`cfg_` 前缀 + 位域名，如 `cfg_tx_en`、`cfg_mode`
- 尺寸类统一后缀：`_w`/`_h`（宽高）、`_size`（合并寄存器名）
- 坐标类统一后缀：`_x`/`_y`、`_origin`（合并寄存器名）
- 网格类统一后缀：`_cols`/`_rows`、`_grid`（合并寄存器名）
- 避免同义异名：统一用 `cfg_` 前缀表示配置输出，`status_` 表示状态输入

#### 信号命名缩写约定

| 全称        | 缩写    |  | 全称          | 缩写     |
| :---------- | :------ | :- | :------------ | :------- |
| acknowledge | ack     |  | address       | addr(ad) |
| arbiter     | arb     |  | check         | chk      |
| clock       | clk     |  | config        | cfg      |
| control     | ctrl    |  | count         | cnt      |
| data in     | din(di) |  | data out      | dout(do) |
| decode      | deco    |  | delay         | dly      |
| disable     | dis     |  | error         | err      |
| enable      | en(e)   |  | frame         | frm      |
| generate    | gen     |  | grant         | gnt      |
| increase    | inc     |  | input         | in(i)    |
| length      | len     |  | output        | out(o)   |
| packet      | pkt     |  | priority      | pri      |
| pointer     | ptr     |  | rd enable     | ren      |
| read        | rd      |  | ready         | rdy      |
| receive     | rx      |  | request       | req      |
| reset       | rst     |  | segment       | seg      |
| source      | scr     |  | statistics    | stat     |
| timer       | tmr     |  | switch fabric | sf       |
| temporary   | tmp     |  | transmit      | tx       |
| valid       | vld(v)  |  | wr enable     | wen      |
| write       | wr      |  | decrease      | dec      |

#### 编码风格

- **4 空格缩进**，不使用 Tab（M2 强制）
- 每条 HDL 语句占独立一行（M1 强制）
- 每个端口声明占独立一行（M1 强制）
- 行宽不超过 72 字符
- 端口声明顺序：先 input 后 output，先 clock 后 reset
- 所有内部 wire 集中在一个区域声明
- `parameter` 优于 `define` 用于可配置常量
- 保持常量间的数学关系（`WORD = 2 * HALFWORD`）
- **实例化必须使用命名端口连接**
- 端口连接中避免内联表达式（避免不必要的 glue logic）
- **实例化端口对齐规范**（M2 强制）：
  - 模块声明：每个端口独占一行，逗号 `,` 推至右侧对齐列，最后一个端口无逗号，`);` 独占一行
  - 无参数例化：`MOD_NAME u_inst` 同行，`(` 换行独占一行
  - 有参数例化：`MOD_NAME #(` 换行 → 参数块 → `)` 换行 → `u_inst` 独占一行 → `(` 换行
  - 实例名：小写字母
  - 同一实例块内对齐：`.port_name` 按该块最长端口名用空格补齐，`(signal` 紧随其后，`),` 推至同一右侧列
  - `#()` 与 `()` 对齐：有参数时 `#(` 和 `(` 同缩进列，内部 `)` 同右侧列
  - 示例（无参数，`<proj>_sync` 为项目同步器封装）：
    ```verilog
    <proj>_sync u_sync_sw_reset
    (
        .clk        (core_clk              ),
        .rst_n      (rst_n                 ),
        .din        (cfg_sw_reset_hclk     ),
        .dout       (                      ),
        .dout_pulse (cfg_sw_reset_pulse    )
    );
    ```
  - 示例（有参数）：
    ```verilog
    <proj>_sync #
    (
        .EDGE_DETECT (1                     )
    )
    u_sync_sw_reset
    (
        .clk        (core_clk              ),
        .rst_n      (rst_n                 ),
        .din        (cfg_sw_reset_hclk     ),
        .dout       (                      ),
        .dout_pulse (cfg_sw_reset_pulse    )
    );
    ```
- FSM 状态编码必须使用 parameter
- 复杂表达式加括号明确优先级
- wire 必须显式声明
- 操作数位宽必须匹配
- 条件表达式应为 1-bit 值
- `assign` 仅用于信号重命名或简单组合逻辑（如 `assign valid = !empty`），禁止用 assign 实现复杂选择/状态逻辑
- always块内尽量只操作一个寄存器信号名称
- 避免使用 for 循环
- **注释必须使用英文**，简洁易懂（M2 强制）
  - 文件头、端口注释、内部信号注释、逻辑块注释一律使用英文
  - 避免复杂从句，使用简单的主谓宾结构
  - 示例：`// Internal signals` 而非 `// 内部信号`
- **组合/时序标注**：组合逻辑块标注 `// combo logic`，时序逻辑块标注 `// seq logic`
- **模块化**：单一职责原则，一个模块只做一件事，代码尽量简洁，无冗余逻辑

#### FSM 编码风格（三进程法）

```verilog
// State register
always @(posedge clock or negedge reset_n) begin
    if (reset_n == 1'b0)
        curr_st <= ST_IDLE;
    else
        curr_st <= next_st;
end

// Next state logic
always @(*) begin
    case (curr_st)
        ST_IDLE : next_st = ST_READ;
        ST_READ : next_st = ST_WRITE;
        // ...
        default : next_st = ST_IDLE;
    endcase
end

// Output logic
always @(posedge clock or negedge reset_n) begin
    if (reset_n == 1'b0)
        out <= 2'b0;
    else begin
        if (curr_st == ST_WRITE)
            out <= data;
        else
            out <= 2'b0;
    end
end
```

#### 可综合设计（Synthesis）

- 只使用可综合语句（M1 强制）
- 禁止波形语句（如 `$finish`, `$shm_open`）（M1 强制）
- 禁止仿真系统任务（`$display`, `$monitor`, `$printf` 等）（M1 强制）
- 禁止 `wait` 语句和 `#delay` 延迟语句（M1 强制）
- 禁止 `real` 和 `event` 数据类型（M1 强制）
- 每个 always 块只能有一个时钟（M1 强制）
- 循环必须是静态范围（M1 强制）
- 禁止内嵌综合脚本
- 禁止 `full_case` / `parallel_case` 指令
- 组合逻辑必须完整赋值，避免 latch
- 禁止 Verilog 原语（UDP）（M1 强制）
- 未用的 module 输入必须驱动（M1 强制）
- 未用的 module 输出留空连接（`.port()`），禁止声明 `_nc`/`_unused` 信号
- 避免顶层 glue logic
- case 语句必须有 default 分支
- 状态机必须有默认状态

#### 标准单元封装（rtl/std_cell/）

功能 RTL 中禁止直接使用 `*`（乘法）、`/`（除法）运算符或手工实现迭代除法器/乘法器。必须使用 `rtl/std_cell/` 下的封装模块，以便后续流片时替换为晶圆厂 IP。

> **模板与项目前缀**：`rtl/std_cell/` 提供模板文件（前缀 `std_cell_`，可编译）。
> 项目使用时复制模板并批量替换为项目前缀（如 `xxx_div_pipe`），宏用
> `XXX_USE_FOUNDRY_*`。示例中 `<proj>_` 为项目前缀占位。

##### 封装模块清单

| 模块（示例前缀 `<proj>_`） | 用途 | 参数要点 | 晶圆厂替换宏 |
|------|------|----------|-------------|
| `<proj>_div_pipe` | 流水线除法器 | `P_WIDTH_N/P_WIDTH_D/P_WIDTH_Q/P_LATENCY/P_CEIL` | `<PROJ>_USE_FOUNDRY_DIV` |
| `<proj>_mul_pipe` | 无符号乘法器 | `P_WIDTH_A/P_WIDTH_B/P_LATENCY` | `<PROJ>_USE_FOUNDRY_DSP` |
| `<proj>_mul_pipe_s` | 有符号乘法器 | `P_WIDTH_A/P_WIDTH_B/P_LATENCY` | `<PROJ>_USE_FOUNDRY_DSP` |
| `<proj>_clk_gate` | 时钟门控 | 无参数，端口：`clk_in/en/te/clk_out` | `<PROJ>_USE_FOUNDRY_ICG` |

> 模板文件见 `rtl/std_cell/`（div_pipe.v/mul_pipe.v/mul_pipe_s.v/clk_gate.v +
> README）。示例沿用 `<proj>_` 前缀作说明，使用时替换为本项目前缀。

##### 使用规则

1. **禁止内联 `*` 运算符**：所有乘法必须通过 `<proj>_mul_pipe`（无符号）或 `<proj>_mul_pipe_s`（有符号）实例完成
2. **禁止内联 `/` 运算符**：所有除法必须通过 `<proj>_div_pipe` 实例完成
3. **禁止手写迭代除法器**：如恢复余数除法器，改用 `<proj>_div_pipe` 封装 + 简化序列器 FSM
4. **P_LATENCY 默认为 0**：组合逻辑输出，与原有行为一致；需要时设为 1 或更高
5. **P_CEIL=1 用于向上取整除法**：`ceil(a/b)` 等价于 `(a + b - 1) / b`，也可直接用 `P_CEIL=1` 避免手动偏移
6. **时钟门控**：使用 `<proj>_clk_gate` 封装，`te` 端口接 `scan_mode`，功能模式下 `te=0`
7. **未用输出留空连接**：封装模块的未用输出端口留空连接 `.port()`，禁止声明 `_nc`/`_unused` 信号

##### 除法器/乘法器/门控实例模板 + 条件编译策略

实例模板（div_pipe / mul_pipe / mul_pipe_s / clk_gate 的完整例化代码）与条件编译
宏表（`<PROJ>_USE_FOUNDRY_*`）已外迁到 **`TEMPLATES.md` §1**——生成时不必注入，
**只在用到除法/乘法/门控 IP 时按需 grep `TEMPLATES.md` 相应节查阅**。

#### SHELL_MODE 空壳模式（M2 强制）

每个模块顶层必须包含 `P_SHELL_MODE` 参数，用于系统级仿真时将不需要的模块变为空壳，避免其输出影响总线行为。

##### 设计意图

- 系统仿真时，某些模块可能尚未准备好或不需要参与仿真
- 若简单地将模块输入悬空，内部逻辑可能产生 X 态传播，或输出非法值导致总线 hang 住
- SHELL_MODE 将整个模块变为空壳，所有输出接固定安全值，彻底隔离该模块

##### 实现规范

1. **参数声明**：每个模块顶层必须声明 `parameter P_SHELL_MODE = 0`
2. **generate 隔离**：使用 `generate if (P_SHELL_MODE) ... else ... endgenerate` 将空壳逻辑与正常逻辑完全隔离
3. **输出信号 tie-off 规则**：
   - **握手 ready 信号**（含 `ready`/`rdy` 的输出）：接 `1'b1`，表示本模块始终准备好接收，不会阻塞上游
   - **握手 valid 信号**（含 `valid`/`vld` 的输出）：接 `1'b0`，表示本模块无有效数据产出
   - **数据信号**（`data`/`addr`/`len` 等）：接 `'0`（全零）
   - **中断/错误信号**：接 `1'b0`（不触发）
   - **状态信号**：接空闲状态值
4. **输入处理**：空壳模式下所有输入未使用，综合工具会自动优化
5. **子模块例化**：空壳分支内不例化任何子模块，纯 wire 赋值

> **SHELL_MODE 完整代码模板 + tie-off 速查表 + 顶层集成建议**已外迁到
> **`TEMPLATES.md` §2**——生成时不必注入，**只在写 SHELL_MODE 模块时按需 grep
> `TEMPLATES.md` §2 查阅**。规范（设计意图 + 实现规范 5 条）留在此处常驻。

#### Generate 块规范

##### 规则 1：分支条件必须合并到同一 generate 块（M2 强制）

所有由同一组参数决定的条件分支必须整合为单一 `generate-if-else if-else` 结构，每个分支自包含其所有信号声明和逻辑。禁止将同一个参数的条件逻辑分散在 generate 块内外。

```verilog
// ❌ 禁止：generate 内外各判断同一参数
reg sync_ff1, sync_ff2;
always @(posedge clk)
    if (!P_SHELL_MODE) sync_ff2 <= sync_ff1;
assign sync_out = P_SHELL_MODE ? 1'b0 : sync_ff2;
generate
    if (EDGE_DETECT && !P_SHELL_MODE) begin
        ...
    end
endgenerate

// ✅ 正确：所有分支在同一个 generate 内
generate
    if (P_SHELL_MODE) begin : gen_shell
        // 自包含，无寄存器
    end else if (EDGE_DETECT) begin : gen_edge
        reg sync_ff1, sync_ff2, sync_dly;   // 分支内声明
    end else begin : gen_plain
        reg sync_ff1, sync_ff2;              // 分支内声明
    end
endgenerate
```

##### 规则 2：generate 嵌套不超过 1 层（RECOMMENDED）

generate 嵌套层级推荐不超过 1 层。generate 块内声明且被多个 `always` 块引用的信号，必须提升到公共父级 scope 声明，或重组逻辑消除多层嵌套。

##### 规则 3：generate 分支必须有命名标签（M2 强制）

每个 `generate-if` 分支必须使用 `begin : <标签名>` 语法命名，标签名统一使用 `gen_` 前缀 + 分支功能描述，便于调试和层次化引用。

```verilog
generate
    if (P_SHELL_MODE)   begin : gen_shell ... end
    else if (EDGE_DETECT) begin : gen_edge ... end
    else                 begin : gen_plain ... end
endgenerate
```

#### 时序与 STA

- 避免组合逻辑反馈环
- 采用同步设计方法
- 简化寄存器时钟来源
- 避免 multicycle path 和 false path
- 避免时钟作为数据
- 禁止使用 latch（M2 强制）
- 异步逻辑独立成单独模块
- IP 接口输出必须寄存（M2 强制）
- IP 接口寄存器同一时钟单沿触发
- IP 必须是同步设计（M2 强制）
- 时钟方案必须文档化（M1 强制）
- 避免手工时钟门控，使用综合工具插入
- IP 必须可复位，复位策略必须文档化（M1 强制）
- 避免工艺相关单元

#### DFT（可测性设计）

- 禁止三态器件（M1 强制）
- 禁止双向 net
- 禁止在设计中用 latch
- 禁止使用时钟双沿
- 禁止门控时钟
- 禁止内部生成的时钟
- 禁止内部生成的 set/reset 信号
- 禁止用时钟和 set/reset 信号作为数据
- 避免组合环
- 避免常量输入或浮空输出
- 避免时钟或 set/reset 信号直接输出
- 避免时钟作为 set/reset 信号
- 避免异步路径环路

#### 仿真

- **时序 always 块用非阻塞赋值 `<=`**（M1 强制）
- **组合 always 块用阻塞赋值 `=`**（M1 强制）
- 组合 always 块敏感列表必须完整（M1 强制）
- 避免冗余敏感列表
- 初始化控制存储单元
- 禁止赋 X 值（`don't care`）（M1 强制）
- 避免使用 delay 赋值

## 示例

**accumulator 输入 JSON + 输出 Verilog 完整示例**已外迁到 **`TEMPLATES.md` §3**——
生成时不必注入，**只在第一次理解生成流程时按需 grep `TEMPLATES.md` §3 查阅**。

## 生成后操作

### lint 集成（MUST）

RTL 生成后立即调用 `/lint-manager` 跑 `make lint`（iverilog 组编译）+ `make vcs`
（VCS 编译），两者都 PASS 才算生成完成：
- 有 error → 报告并定位，修复后重跑
- 有 warning → 区分误报/真问题，误报给 waiver 建议，真问题修复
- 详见 lint-manager skill

> **spec JSON 新鲜度检查**：生成前若消费 spec_parser JSON，先检查 JSON mtime vs
> spec 文件 mtime——spec 更新则提示先 `/spec-parser` 刷新 JSON，避免用过期 JSON
> 生成（见 spec_parser 刷新模式约定）。

### 寄存器接口

如果模块包含寄存器接口，调用 `/regmap-gen`：
- 自动生成寄存器地址宏定义文件（`<module>_regmap.svh`），供 testbench 使用
- 自动生成寄存器文档（Markdown 表格）+ 脚本寄存器枚举
- 确保 RTL、testbench、文档三端的寄存器定义一致
- 生成后执行 regmap-gen 的接入验证 Step N（防孤儿）

### 多时钟域

如果模块含多个时钟域，生成后调用 `/cdc-review` 检查 CDC 路径同步器正确性；
写 RTL 前应已用 `/clock-domain-table` 生成域归属表作为生成依据。

## 可选配置

用户可指定：

- 代码风格：Verilog / SystemVerilog
- 复位策略：异步低有效 / 同步高有效 / 无复位
- 是否生成 testbench 骨架
- 是否生成接口封装（AXI/AHB/APB）
