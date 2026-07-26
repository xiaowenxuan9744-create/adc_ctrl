---
name: uvm-debug
description: UVM 验证环境问题记录（testbench 架构、UVM 用法、仿真环境兼容性）
triggers:
  - UVM报错
  - UVM环境
  - testbench错误
  - UVM编译错误
  - UVM仿真错误
  - UVM运行时错误
  - UVM sequence错误
  - scoreboard错误
---

# UVM Debug — UVM 验证环境问题记录

> **skill 性质：记录类（模板豁免）。** 内容是项目积累的 UVM 环境问题案例，绑定具体项目
> 语境。**不参与 skill 模板化/去语境化处理**——通用 skill 做模板化时本 skill 保持原样。
> 同步进通用模板（ic_rtl_template）时**清空成空容器**（只留性质说明 + 职责边界 + 累积
> 规则，删项目专属案例），新项目从空容器开始积累。

记录在搭建 UVM 验证环境、编写 testbench、调试仿真过程中遇到的共性问题和修复方式。

> **职责边界**：本 skill 是 UVM 环境问题的**唯一存放点**（原 env-bug #10-14
> 的 UVM 条目已迁入此处统一管理）。VCS/iverilog/Makefile/文件系统类问题仍归
> `/env-bug`，两者不重叠。

## 计数规则

- 遇到新问题 → 追加到此文件
- **累计 ≥5 条** 时 → 触发整理更新（合并同类、补充根因、更新预防措施）
- 更新后重置计数器
- 此规则适用于所有使用 UVM 的项目

---

## 问题列表

### 1. `run_test()` 必须在 time 0 调用

- **场景**: UVM 仿真启动时报 FATAL
- **报错**: `The run phase must start at time 0, current time is 400000. No non-zero delays are allowed before run_test(), and pre-run user defined phases may not consume simulation time before the start of the run phase.`
- **根因**: UVM 1.2 要求 `run_test()` 在 time 0 调用。如果 tb_top 的 initial 块中用 `#delay` 延迟了 `run_test()` 的执行，UVM 报 FATAL
- **解决**: `run_test()` 放在 time 0 的 initial 块中，复位通过独立的 initial block 控制，不在 `run_test()` 前加延时

```systemverilog
// ✅ 正确：time 0 调用 run_test()
initial begin
    uvm_config_db#(virtual ...)::set(null, "*", "m_vif", vif);
    run_test();  // Must be at time 0
end

// 独立 initial block 做复位（不阻塞 run_test）
initial begin
    #200;
    vif.reset_n = 1'b1;
end
```

### 2. 多 `uvm_analysis_imp` 端口需要 `uvm_analysis_imp_decl` 宏

- **场景**: scoreboard 有多个 `uvm_analysis_imp` 端口时编译报错
- **报错**: `Could not find member 'write' in class 'xxx_scoreboard'`
- **根因**: UVM 1.2 的 `uvm_analysis_imp` 要求目标类有 `write()` 方法。多个 imp 端口不能共用同名 `write()` 方法
- **解决**: 使用 `uvm_analysis_imp_decl` 宏为每个 imp 生成独立的接口名

```systemverilog
`uvm_analysis_imp_decl(_apb)
`uvm_analysis_imp_decl(_adc)

class my_scoreboard extends uvm_scoreboard;
    uvm_analysis_imp_apb #(txn_t, my_scoreboard) apb_export;
    uvm_analysis_imp_adc #(txn_t, my_scoreboard) adc_export;

    // 实现 write_apb() 和 write_adc() 替代 write()
    function void write_apb(txn_t txn);
        // ...
    endfunction
endclass
```

### 3. `config_db` 路径使用通配符 `*`

- **场景**: driver/monitor 的 `uvm_config_db::get()` 找不到 virtual interface
- **报错**: `Virtual interface not found`（UVM_FATAL）
- **根因**: `set()` 用 `"uvm_test_top"` 路径时，组件的 `get()` 从自身 hierarchy 路径搜索，找不到 uvm_test_top 级别的配置。子组件（如 agent 内部的 driver）的路径是 `uvm_test_top.m_env.m_agent.m_driver`，与 `"uvm_test_top"` 不匹配
- **解决**: 使用通配符 `"*"` 作为 set 的路径前缀，让所有组件都能搜索到

```systemverilog
// ❌ 组件找不到
uvm_config_db#(virtual if_t)::set(null, "uvm_test_top", "m_vif", vif);

// ✅ 通配符路径
uvm_config_db#(virtual if_t)::set(null, "*", "m_vif", vif);
```

### 4. UVM driver 监控单周期脉冲信号因 delta cycle 竞争错过

- **场景**: ADC driver 在 `posedge adc_clk` 上监控 DUT 输出的单周期 `soc` 信号，始终检测不到
- **根因**: DUT 在 `posedge adc_clk` 上产生 SOC 脉冲，UVM driver 在同一个 `posedge adc_clk` 上采样。由于 Verilog 的 NBA（非阻塞赋值）调度，driver 采样时 DUT 的 SOC 还未更新，导致错过
- **解决**: 改为监控持续时间更长的电平信号边沿，或使用 `@(negedge clk)` 采样

```systemverilog
// ❌ 监控脉冲信号（易因 delta cycle 竞争错过）
if (m_vif.soc) begin ... end

// ✅ 监控电平信号的边沿（电平持续时间 > 1 周期）
if (m_vif.muxon && !muxon_dly) begin ... end
muxon_dly <= m_vif.muxon;
```

### 5. 同一 `logic` 信号被 tb_top 和 UVM driver 多驱动冲突

- **场景**: `presetn` 信号既被 tb_top 的 initial 块初始化，又被 APB driver 的 RESET transaction 驱动
- **根因**: SystemVerilog 的 `logic` 类型不允许多驱动。当两个过程块同时赋值同一信号时，仿真结果不可预测（通常取最后驱动的值）
- **解决**: 将复位管理完全交给 tb_top 的 initial 块（只驱动一次），APB driver 不驱动复位信号。需要中间复位时使用软件复位（写寄存器）替代

```systemverilog
// tb_top 负责上电复位（只此一处驱动）
initial begin
    vif.presetn = 1'b0;
    #200;
    vif.presetn = 1'b1;
end

// APB driver 不再驱动 presetn
// 需要中间复位时，sequence 中写 CTRL[1] 做软件复位
```

### 6. UVM segment 中无法直接访问 `m_vif`

- **场景**: sequence 中需要直接驱动/采样 DUT 的 I/O 信号（如 `dma_req`、`cal_done`），直接写 `m_vif.xxx` 编译报错
- **报错**: `Cross-module reference resolution error` — segment 不是 component，没有 `m_vif`
- **根因**: `uvm_sequence` 不是 `uvm_component`，不能自动获取 config_db 中的 virtual interface。需要在 base_seq 的 `pre_body()` 中手动获取
- **解决**: 在 base_seq 中声明 `virtual if_t m_vif`，在 `pre_body()` 中通过 `uvm_config_db::get()` 获取

```systemverilog
class base_seq extends uvm_sequence #(txn_t);
    virtual my_if m_vif;

    virtual task pre_body();
        if (m_vif == null) begin
            uvm_config_db#(virtual my_if)::get(m_sequencer, "", "m_vif", m_vif);
        end
    endtask
    // ...
endclass
```

### 7. UVM 宏（ `` `uvm_info `` / `` `uvm_error `` ）在单行 if-else 中语法错误

- **场景**: `if (cond) `uvm_info(...); else `uvm_error(...);` 编译报错
- **报错**: `token is 'else'` — else 找不到匹配的 if
- **根因**: UVM 宏（`` `uvm_info ``、`` `uvm_error ``）展开为多行代码块（包含 if-else 结构），导致外层 if 与 else 的语法匹配断裂
- **解决**: UVM 宏调用必须放在 `begin...end` 块中，禁止使用单行 if-else

```systemverilog
// ❌ 编译错误：else 找不到匹配的 if
if (rd[31]) `uvm_info("ID", "PASS", UVM_LOW);
else `uvm_error("ID", "FAIL")

// ✅ 加 begin...end
if (rd[31]) begin
    `uvm_info("ID", "PASS", UVM_LOW)
end else begin
    `uvm_error("ID", "FAIL")
end
```

### 8. Scoreboard 记录 W1C 写操作导致后续读比对失败

- **场景**: 测试 sequence 中先写 INT_STAT（W1C 清零），稍后读 INT_STAT。scoreboard 把 W1C 写操作记录为"期望值=写入值"，后续读回的实际值不同（因清零操作导致）
- **报错**: `FAIL: addr=0x0010 rd=0x00000003 exp=0x0000003f` — 读回 0x0003 但 scoreboard 期望 0x003F（W1C 写的内容）
- **根因**: scoreboard 的 write monitor 将每一次 APB 写操作都记录为期望值。W1C（写 1 清零）寄存器的写入不是"期望值"，而是"操作命令"
- **解决**: 在 sequence 中 W1C 写操作后立即加一次读操作，刷新 scoreboard 的期望值

```systemverilog
// W1C 写之后立即读回，刷新 scoreboard
apb_write(16'h0010, 32'h0000_003F);  // W1C clear
#200;
apb_read(16'h0010, rd);  // 刷新 scoreboard 期望值（非强制但推荐）
```

或者改进 scoreboard：对 RW1C/WO 类型的写操作不记录期望值（更彻底的修复）。

### 9. VCS 增量编译导致 `VCSGlobalData` 符号错误

- **场景**: 修改 UVM testbench 文件后重新运行 `make sim-uvm`，VCS 使用增量编译，链接时报错
- **报错**: `sim/simv_uvm.daidir/_csrc0.so: undefined symbol: VCSGlobalData`
- **根因**: VCS O-2018.09-SP2 的增量编译在某些文件变更后会产生不一致的 .so 文件。RTL 文件未变更但 UVM 文件变更时，VCS 的增量编译无法正确处理
- **解决**: 删除 `simv_uvm` 和 `simv_uvm.daidir` 后重新编译。在 Makefile 的 sim-uvm target 中自动清理

```makefile
sim-uvm:
	rm -rf sim/simv_uvm sim/simv_uvm.daidir
	vcs ... -o sim/simv_uvm
```

---


### 10. Scoreboard 对控制类写操作（SW_RST）误记录为期望值

- **场景**: sequence 中写 CTRL[1]=1 触发 SW_RST，之后读 CTRL 返回 0（复位默认值），scoreboard 报 FAIL
- **报错**: `FAIL: addr=0x0000 rd=0x00000000 exp=0x00000002` — SW_RST 写入值被记录为期望值
- **根因**: scoreboard 将所有 APB 写操作都记录为期望值，但 SW_RST 写入的是"控制命令"而非"数据值"，复位后寄存器值变回 0
- **解决**: 同 W1C——在控制类写操作后加一次读回刷新 scoreboard 期望值；或修改 scoreboard 忽略 RW_SS/WO 类型地址的写记录

### 11. 连续序列产生的 EOC 事件导致 DMA/状态测试误判

- **场景**: `write_lp_seq_single()` 写入单通道到 LP_SEQ0 的 ENT0，但 ENT1-31 默认为 CH0，FSM 仍会处理全部 26 个条目。连续 EOC 事件在 DMA 测试中干扰状态判断
- **根因**: `write_lp_seq_single()` 只写 LP_SEQ0 不写 LP_SEQ1-7，而后者的默认值 0 表示 CH0。FSM 处理全部 26 个条目时反复采样 CH0，持续产生 EOC/DMA 事件。测试在两个测试点之间切换配置时，上一个序列的事件仍在进行
- **解决**: 测试点切换之间加 SW_RST 清除所有状态，或加足够等待让序列完成；或在 LP_SEQ1-7 中填入无效通道号（0x1F）跳过

### 12. 模拟信号通过 `m_vif` 驱动时保持时间不足导致 CDC 同步失败

- **场景**: `m_vif.cal_done = 1'b1; #100; m_vif.cal_done = 1'b0;` 后读 CAL_VAL 返回 0
- **报错**: `[FAIL] CAL_002: CAL_VAL = 0x00, expected 0x2A`
- **根因**: cal_done 信号需要通过 DUT 内部的 2 级同步器 + 边沿检测。100ns = 2.5 ADC_CLK 周期，不足以完成 3 级 CDC 流水线（2 级同步 + 1 级边沿延迟）。cal_done 下降沿到来时同步还未完成
- **解决**: 保持模拟信号至少 500ns（12.5 ADC_CLK 周期）确保 CDC 同步完成
  ```systemverilog
  m_vif.cal_done = 1'b1;
  m_vif.cal_val  = 6'h2A;
  #500;  // Hold for CDC (3+ ADC_CLK cycles + margin)
  m_vif.cal_done = 1'b0;
  ```

### 13. sequence 间残留事件干扰——上一个测试的序列仍在运行

- **场景**: 前一个测试触发 LP 序列采样，后一个测试修改寄存器配置开始新测试，但前一个序列的 EOC/hp_trig 事件仍在产生
- **报错**: 表现为期望状态与实际状态不符，如 TRG_004 检查 LP_BUSY 时返回值 1（来自上一个 MCTM 序列）
- **根因**: `write_lp_seq_single()` 产生 26 个通道采样约需 21us（680ns × 26）。如果 test 之间的间隔小于此时间，上一个序列的事件会干扰下一个测试
- **解决**: 测试间加 SW_RST 清除状态，或在检查前加足够等待（≥30000ns）确保前一个序列完成

## 常见排查顺序

遇到 UVM 验证环境报错时按以下顺序排查：

1. **编译错误** → 检查 UVM 宏展开（if-else begin/end）、import/incdir 路径、package 依赖顺序
2. **config_db 错误**（vif not found） → 检查 set() 是否用通配符 `*`，get() 路径是否匹配
3. **delta cycle 竞争**（信号采样不到） → 检查监控的是电平还是脉冲，时钟边沿是否对齐
4. **多驱动冲突** → 检查 logic 信号是否被多个 initial/always 赋值
5. **运行时 FATAL** → 检查 `run_test()` 是否在 time 0 调用，复位方式是否合理
6. **符号链接错误**（VCSGlobalData） → 清理后重编

## 已知 Verilator/UVM 兼容性问题

（本项目使用 VCS O-2018.09-SP2，尚未验证 Verilator 下的 UVM 行为）

## 与 `env_bug` skill 的关系

| Skill | 范围 | 典型错误 |
|:--|:--|:--|
| `env-bug` | EDA 工具、Makefile、文件系统、VCS 安装 | VCS 链接 undefined reference、Makefile 循环依赖 |
| `uvm-debug` | UVM 验证环境、testbench 架构、UVM 用法 | analysis_imp 宏、config_db 通配符、scoreboard 误比 |
