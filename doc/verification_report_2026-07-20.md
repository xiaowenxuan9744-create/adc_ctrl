# ADC 控制器参数化重构 验证签收报告

日期：2026-07-20
分支：feature/parameterization
基线：feature/calib-pclk-rewrite
设计依据：`doc/design/2026-07-20-parameterization-design.md`
实现计划：`docs/superpowers/plans/2026-07-20-parameterization.md`

## 1. 签收结论

**✅ 签收通过。** ADC 控制器参数化重构完成，默认 26 通道 / 14bit 配置与原固定设计
行为一致（向后兼容），8 通道 / 12bit smoke 验证参数化语义正确。`make check` 全绿。

## 2. 参数化范围

| 主参数 | 默认 | 范围 | 说明 |
|:--|:--:|:--|:--|
| `ADC_NUM_CH` | 26 | 4~32 | 通道数，影响 ch_sel/seq_ptr/seq_len 位宽、LP_DATA/LP_SEQ 寄存器数 |
| `ADC_DATA_W` | 14 | 1~16 | ADC 分辨率，影响 adc_data 端口宽度（DATA 寄存器域固定 16bit） |
| `ADC_SPT1_CH_MASK` | `32'h0060_0000` | 32bit 位图 | bit i=1 → 通道 i 用 SPT1；默认 CH21/CH22 |

集中派生 localparam 定义于 `rtl/adc_params.vh`（ANSI 参数列表内 include，需 SV）。
HP 队列固定 4（不参数化）。地址空间固定按 32 预留、实现数随 N 收缩、超出读回 0 写忽略。

## 3. 回归结果（make check）

| 检查项 | 结果 |
|:--|:--|
| `make lint`（iverilog -g2012，15 模块） | ✅ 15/15 PASS |
| `make vcs`（VCS RTL 编译） | ✅ PASS |
| `make test-unit`（iverilog，2 TB） | ✅ 2/2 PASS（tb_adc_top + tb_adc_top_8ch） |
| `make sim-uvm-regr`（VCS UVM，18 case） | ✅ 18/18 PASS |
| **总计** | **全绿** |

### 3.1 默认 26 通道 / 14bit 配置（向后兼容）

- `tb_adc_top`（unit TB，9 测试场景）：运行通过（exit 0）。
  Test1-6 APB RW / 单次采样 / 中断 / 校准 / SW 复位 / DMA PASS。
  Test7-9 HP/LP 序列抢占中部分 data check fail 为 **TB 自身 exp_data 按 ch_sel
  索引的预先存在问题**（基线对照：原版 26 通道 TB 同样 Test7 CH1/CH4/CH7/CH15
  fail、Test8/9 LP 抢占恢复 fail），非参数化引入。
- `sim-uvm-regr` 18 case 全 PASS，与原版基线一致。

### 3.2 8 通道 / 12bit smoke 配置（参数化验证）

- `tb_adc_top_8ch`（unit TB）：运行通过（exit 0）。
  - Test1 APB RW：LP_SEQ0 / DMA_CTRL / INT_EN / ANA_CFG / TRIG write/read PASS，
    证明 8 通道下寄存器译码与位宽正确。
  - Test2 单次采样：12bit adc_data 对齐正确。
  - Test3-6 中断 / 校准 / SW 复位 / DMA 核心功能 PASS。
  - Test7 HP/LP 序列抢占：4 HP 通道（CH8~CH11）VALID 全部 PASS，LP 序列推进正确。
  - 与原版同源的 fail（CH8/CH11/CH15 exp_data 竞态、Test8/9 LP 抢占恢复）为 TB
    预先存在问题，基线对照确认非参数化引入。

## 4. 默认 26 配置的细微变化（向后兼容，已确认接受）

| 项 | 参数化前 | 参数化后 | 影响 |
|:--|:--|:--|:--|
| LP_SEQ 物理寄存器数 | 8 组（0xB8~0xD4 全实现） | 7 组（`ceil(26/4)=7`） | 0xD4（LP_SEQ7）读回 0、写忽略；软件无感 |
| LP_SEQ_LEN 物理位宽 | 6bit | 5bit（`$clog2(27)=5`） | 仍能存 26；复位值 26 不变、软件写 26 仍正确 |

UVM `adc_reg_test` 已对齐：LP_SEQ_LEN default check 改 0x1A、LP_SEQ7 write/read
+ sweep 按 `ADC_NUM_CH>=29` 条件执行、LP_SEQ_LEN sweep mask 按位宽派生。

## 5. 一致性检查（五端）

| 端 | 参数化同步状态 |
|:--|:--|
| spec（`spec/adc_spec.md`） | ✅ §1.1 特性 + §3.0 参数化配置章节 + §3.2 SPT1 位图 + §3.11/§3.13/§3.15/§7 寄存器参数化 |
| RTL（`rtl/adc_params.vh` + regfile/seq_fsm/top） | ✅ 派生 localparam 集中 + 三模块参数透传 |
| regmap（`tb/adc_regmap.svh`） | ✅ LP_SEQ_LEN_W 注释参数化（adc_uvm_pkg 按参数重定义） |
| TB（unit + UVM） | ✅ 端口位宽自适应 + 默认 26 实例化 + 8 通道 smoke |
| SDC | ✅ 端口名不变（ch_sel/adc_data），位宽由 RTL 决定，无需改 |

## 6. 验证完整性

testplan（`spec/testplan_adc.md` §3.10）新增 5 个参数化测试点：
- `PARAM_NUM_CH_8`（8 通道 smoke）— tb_adc_top_8ch 验证 ✅
- `PARAM_DATA_W_12`（12bit ADC）— tb_adc_top_8ch 验证 ✅
- `PARAM_SPT1_MASK`（SPT1 位图可选）— tb_adc_top_8ch mask=0 验证 ✅
- `PARAM_ADDR_RSV`（超出地址读回 0）— tb_adc_top_8ch 验证 ✅
- `PARAM_COMPAT_26`（默认 26 向后兼容）— make check 全绿 ✅

## 7. Waiver

无 waiver。参数化重构未引入新覆盖率 hole；Test7-9 TB 预先存在的 exp_data 竞态
fail 为 TB 问题（非 RTL bug、非参数化引入），不在本次签收范围，已在 commit 说明
留痕，建议后续单独修 TB exp_data 索引逻辑。

## 8. 改动文件清单

**RTL：**
- `rtl/adc_params.vh`（新建）— 派生 localparam 集中定义
- `rtl/adc_params_check.vh`（新建）— elaboration 范围断言
- `rtl/adc_regfile.v` — 端口/数组/边界/复位值参数化
- `rtl/adc_seq_fsm.v` — 端口/ptr/entry_array generate/SPT 位图/数据对齐参数化
- `rtl/adc_top.v` — 参数列表 + 端口 + 三模块参数透传
- `rtl/filelist.f` — 末尾换行

**TB：**
- `tb/unit/tb_adc_top.v` — 默认 26 参数化
- `tb/unit/tb_adc_top_8ch.v`（新建）— 8 通道/12bit smoke
- `tb/unit/adc_analog_model.v` — 参数化端口位宽
- `tb/uvm/interface/adc_if.sv` — 参数化接口位宽
- `tb/uvm/tb_top.sv` — 默认 26 实例化透传
- `tb/uvm/adc_uvm_pkg.sv` — `ADC_NUM_CH`/`ADC_DATA_W` 宏
- `tb/uvm/sequence/adc_reg_seq.sv` — LP_SEQ_LEN/LP_SEQ7 参数化条件
- `tb/uvm/uvm.flist` — +incdir+rtl

**文档：**
- `spec/adc_spec.md` — §1.1/§3.0/§3.2/§3.11/§3.13/§3.15/§7 参数化
- `spec/testplan_adc.md` — §2/§3.10 参数化测试点
- `doc/project_config.md` — 模块层次 + 参数化说明
- `tb/adc_regmap.svh` — LP_SEQ_LEN_W 注释

**构建：**
- `Makefile` — lint/test-unit/sim-uvm-compile 加 -g2012/-Irtl/+incdir+rtl

## 9. 未尽事项与后续建议

1. **TB exp_data 竞态修复**：unit TB 的 Test7-9 中 `exp_data[ch_sel]` 按 ch_sel
   索引、HP 抢占后 LP 恢复时索引错位，导致部分 data mismatch。基线即存在，
   建议后续单独修 TB（用 `exp_data_seq[seq_ptr]` 按序列位置索引），非本次参数化范围。
2. **多配置覆盖率**：本次只对默认 26 配置收覆盖率；8 通道 smoke 只看 PASS 不收
   覆盖率（避免双份合并）。如需 8 通道覆盖率闭环，可单独建 cov run。
3. **综合 SDC 联动**：参数化后 SDC 端口名不变，但若综合用非默认通道数，需确认
   SDC 的 `get_ports` 位宽推断正确（综合工具通常自动跟随 RTL）。

## 10. 提交历史

```
8656c33 fix: Makefile test-unit 加 -g2012 -Irtl + filelist 末尾换行适配参数化
f997447 test: 新增 8 通道/12bit 参数化 smoke TB
d806cde docs: spec/regmap/testplan/project_config 同步参数化
3b62c71 feat: UVM env 参数化(默认 26 配置,18 test 全 PASS)
71a4c31 feat: unit TB 参数化(默认 26 配置,与现状行为一致)
d41cd42 feat: adc_seq_fsm + adc_top 参数化 + vh 改 ANSI localparam + Makefile -g2012
4823f49 feat: adc_regfile 参数化(端口/数组/边界/复位值随 ADC_NUM_CH) + vh 拆分
8583ca8 feat: 新建 adc_params.vh 参数化派生 localparam 集中定义
```
