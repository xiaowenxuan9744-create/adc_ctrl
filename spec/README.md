# ADC 控制器规格文档

本目录存放 ADC 控制器项目的需求规格和设计规格文档。

## 文档清单

| 文件 | 说明 | 最后更新 |
|:--|:--|:--:|
| `adc_spec.md` | 完整规格文档：接口定义、寄存器映射、时序、参数化说明 | ✅ Jul 21 |
| `testplan_adc.md` | 144 测试点验证计划 | ✅ Jul 21 |
| `testplan_adc_new.md` | 新版验证计划（合并后） | ✅ Jul 13 |
| `adc_spec_ori.md` | 原始固定版本规格（参数化前基线） | — |

## 阅读顺序

1. **项目概览** → [`doc/project_config.md`](../doc/project_config.md)（模块层次、时钟域、验证环境）
2. **接口定义与寄存器** → `adc_spec.md` §2（接口） + §3（寄存器）
3. **功能时序** → `adc_spec.md` §4~§6
4. **验证计划** → `testplan_adc.md`

## 规格文档规范

- 使用 Markdown 格式
- 包含：接口定义、功能描述、时序约束、寄存器映射
- 规格 ↔ RTL ↔ SDC ↔ regmap ↔ TB 五端一致性通过定期 `make consistency-check` 维护
