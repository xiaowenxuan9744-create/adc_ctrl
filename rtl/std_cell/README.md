# rtl/std_cell — 标准单元封装

功能 RTL 中禁止直接使用 `*`（乘法）、`/`（除法）运算符，必须用本目录下的封装
模块实例，以便流片时通过条件编译宏切换为晶圆厂 IP。

## 封装模块清单

| 模块（模板名 `std_cell_`） | 用途 | 晶圆厂替换宏 |
|:--|:--|:--|
| `std_cell_div_pipe` | 流水线除法器 | `STD_CELL_USE_FOUNDRY_DIV` |
| `std_cell_mul_pipe` | 无符号乘法器 | `STD_CELL_USE_FOUNDRY_DSP` |
| `std_cell_mul_pipe_s` | 有符号乘法器 | `STD_CELL_USE_FOUNDRY_DSP` |
| `std_cell_clk_gate` | 时钟门控（ICG） | `STD_CELL_USE_FOUNDRY_ICG` |

> **命名约定**：本目录文件用 `std_cell_` 模板前缀（合法标识符，可直接 lint）。
> 实际项目使用时复制本目录，把 `std_cell_` 批量改为项目前缀（如项目前缀
> `xxx` → `xxx_div_pipe`，宏 `XXX_USE_FOUNDRY_DIV`）。模板前缀仅为可编译，不
> 含项目特定语义。

## 使用方式

1. 复制本目录 4 个 `.v` 文件到项目 `rtl/std_cell/`
2. 批量替换 `std_cell_` → 项目前缀、`STD_CELL_` → 项目大写前缀
3. 功能 RTL 中用 `<proj>_mul_pipe`/`<proj>_div_pipe`/`<proj>_clk_gate` 实例
   代替内联 `*`/`/`/手写门控
4. 流片时在综合脚本定义 `<PROJ>_USE_FOUNDRY_*` 宏，替换占位的 foundry IP 实例

## 行为模型 vs 晶圆厂 IP

- **不定义宏**（默认）：走行为模型，功能仿真用，P_LATENCY=0 组合输出
- **定义宏**：走 foundry IP 实例（占位文件里是 `$error` 提示，流片时补真实实例）

详见 `/rtl-generator` skill 的"标准单元封装"章节。
