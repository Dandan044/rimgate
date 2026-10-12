# Demo v0.2 构建记录

本版使用 Godot `4.7.2.stable.official.ed1daf0bf`、Compatibility / OpenGL 3.3，Windows x64导出。最终产品导出提交为 `a4b9cd6433d68550c61841b51c523f5e13bd187c`，导出时间 `2026-10-12T07:36:55.3610531Z`。

- EXE SHA256：`D34D36F3BE1A6C49C56525AE86469B92E4F417DDF0B43CF00DD80C385C4B0562`
- PCK SHA256：`DBE837A0C0C1E0627C1928BF4D09788CCA969541D5F93AC295843EC5168365A9`
- 产品源文件指纹：`C2B64534064D52E025A93126FD9F54A893F6C8A9E990E1100A3212618DD0358F`

EXE由Godot模板生成，资源和游戏脚本位于相邻PCK中，两者必须一起分发。不能仅凭EXE哈希区分版本。

`tools/build.ps1 -ExportOnly -ExportDirectory build/release_v0.2_windows` 将导出提交、产品指纹及二进制哈希写入 `EXPORT.json`。指纹覆盖Git跟踪的 `project.godot`、`main.tscn`、`export_presets.cfg`、`scripts/`、`assets/` 的路径和文件SHA256。文档、测试与工具不参与产品指纹，因此最终整理这些文件后可用 `-PackageOnly` 原样打包已测试的导出；该命令会重新核对指纹与二进制哈希，拒绝混用修改后的产品源码。

最终交付的 `VERSION.json` 和 `Rimgate-demo-v0.2.0-manifest.json` 分别记录 `export_source_commit` 与包含最终文档/测试/工具的 `source_commit`。源码ZIP通过 `git -c core.autocrlf=false archive HEAD` 生成，保留提交中的原始字节而不套用本机CRLF转换，ZIP注释中的提交须与清单一致。打包校验结果随独立证据包提供。

最终导出用于实时压力、48项输入、完整480秒防守、离线运动录像和30分钟长运行。额外5项工事鼠标检查使用同一个PCK，通过 `--main-pack` 加载；不由源码目录替代游戏代码。[验收报告](V2_TEST_REPORT.md)说明各夹具及限制。

性能优化前的旧PCK `1C7ACA…` 压力平均50.68FPS，仅作为失败与优化过程记录。它不在最终Windows包内，最终验收不混用其性能数据。第一版文件和报告保留在原位置。

Windows包附带运行程序、说明、音频与字体许可、原始许可通知、精选截图/录像及原始测试记录。源码ZIP附带源音频、混音生成器和测试，不含本地引擎、导出模板、`.tools`、`.godot` 或生成的 `build/`。本轮只向公开仓库推送已获授权的源码及设计文档，不创建公开二进制Release。

引擎MIT许可和第三方组件通知分别位于 `docs/GODOT_LICENSE.txt`、`docs/GODOT_THIRD_PARTY_NOTICES.txt`，由 `tools/license_dump.gd` 从同版本Godot引擎的许可API提取，保存102项组件信息与19份许可文本。保存组件版权、许可标识与完整许可文本的做法依据 [Godot官方分发说明](https://docs.godotengine.org/en/stable/about/complying_with_licenses.html)。

## 复核命令

以下在仓库根目录的PowerShell执行，路径可替换为本地Godot或导出位置。运行报告使用绝对路径，避免被Godot解释为用户目录。实时模式会打开测试窗口；普通双击程序不会启用QA。

```powershell
$game = (Resolve-Path build/release_v0.2_windows/Rimgate.exe).Path
$reportRoot = (Resolve-Path build/reports).Path
# 四套源码规则回归；-Godot 可指定自己的4.7.2 console程序。
./tools/test.ps1
# 最终导出的实际鼠标输入、压力采样和完整实时防守，分别执行。
& $game --resolution 1920x1080 -- --qa-mode=interaction "--qa-report=$reportRoot/input-recheck.json"
& $game --resolution 1920x1080 -- --qa-mode=benchmark "--qa-report=$reportRoot/performance-recheck.json"
& $game --resolution 1920x1080 -- --qa-mode=victory "--qa-report=$reportRoot/victory-recheck.json"
# 长运行保留原始结果，使用新的输出前缀。
./tools/soak.ps1 -Executable $game -ReportPrefix "$reportRoot/soak-recheck"
./tools/check_soak_memory.ps1 -ReportPrefix "$reportRoot/soak-recheck"
# 包完成后核对CRC、二进制、源码提交、许可、报告和暂停截图。
python tools/verify_release_v2.py
```

重跑得到的时间与性能会随设备、负载和显示缩放变化；报告中的原始验收数据不因此被覆盖或改写。
