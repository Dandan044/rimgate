# 构建与证据对应

2026-10-12。生成报告位于独立的证据包；不要把不同PCK的检查结果混写成同一次运行。

## 交付文件

Windows EXE SHA256：`D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562`。

PCK SHA256：`D73B4B7678AA39CB998D97FE34F1AC53F153DFB1C4945741F80E1D3A22C212F2`。

`build/release_windows/EXPORT.json` 标记导出源码提交 `7524a6340fcbc3e6911d3005e7bead8e35c4dad7` 及产品源文件指纹 `F8D4CB1A4F170C0CE7031A4C5617C449EC9C95B39EECD78D4F8CC6471F6E7C23`。它与实际执行最终八分钟胜利及26秒录像的 `build/final_windows` 两文件逐字节相同。

后续文档/打包工具提交不会改该产品指纹。最终ZIP内的 `VERSION.json` 分别记录源码包提交、导出提交和二进制哈希；`tools/build.ps1 -PackageOnly` 必须通过产品文件指纹与EXE/PCK哈希核对，不给任意旧包贴新版本。

源码ZIP来自最终Git提交，包含工程、脚本、原始资源、测试及文档，排除 `.godot`、引擎与生成物。证据ZIP包含报告、实际截图及日志；解压到源码包根目录可还原文档的相对截图路径。Windows包也带报告/截图，录像单独提供。

## 检查边界

- **实时压力性能：** PCK `31D0B8676E0F9115BFFF23580040818C7AA001516A98BA49DF127B5AE105F349`；`ai_contract_benchmark.json`。现行战斗/AI完整，早于库存文字移位和最终秒数显示修正。
- **45项窗口输入与30分钟稳定性候选：** PCK `ABA42697EA556D52017B230FE52E6CA6258C17DCE8F41B109C74B4D954E015F1`；`candidate_interaction.json`、`ai_contract_soak.json`、`ai_contract_soak-process.json`、`ai_contract_soak-memory-recheck.json`。已含库存标签修正和增强稳定性检查。1800秒、15次重开已终止；原监控均值汇总错误的处理与原始样本重算见测试报告。
- **交付文件：** 上述 `D73B4B…C212F2`；`final_realtime_victory.json`、`final_motion.json`。在候选之上仅增加主动启用的固定战术/胜利QA和HUD秒数显示容差；战斗/AI/弹药/医疗/波次没有变化。不宣称交付PCK本身另做过独立30分钟。

源码四套回归、UI17项、80,000发统计及282步分区对照属于其各自的自动检查；窗口输入属于Viewport事件自动化。没有把这些记录标为人工试玩。实际胜利没有改HP、弹药、伤害或敌人；性能夹具的数值控制在测试报告中另行说明。
