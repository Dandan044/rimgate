# Demo v0.3 构建与证据说明

本文件说明构建和复核方式，不预填尚未取得的验收结果。实际版本、提交、导出时间及哈希以 Windows 包内 `VERSION.json`、外部 `build/Rimgate-demo-v0.3.0-manifest.json` 和导出目录 `EXPORT.json` 为准；具体通过情况与限制见 `V3_TEST_REPORT.md` 及对应原始报告。

本版使用 Godot `4.7.2.stable.official.ed1daf0bf`、Compatibility / OpenGL 3.3、Windows x64。EXE由导出模板生成，游戏脚本与资源在相邻PCK中；同一模板生成的EXE可能相同，必须同时核对PCK。

## 导出、验收和打包

1. 提交产品源码并保持工作区干净，运行 `tools/build.ps1 -Version 0.3.0 -ExportOnly -ExportDirectory build/release_v0.3_windows`。脚本执行规则测试、导出独立目录并写入 `EXPORT.json`；不会替换v0.1/v0.2导出。
2. 对该目录的同一EXE/PCK执行最终输入、实时性能、完整防守、动作录像与30分钟稳定性检查。运行前后核对PCK哈希，报告必须明确绑定实际运行的PCK。UI专用夹具仅说明操作/显示，不能代替通关或平衡证据。
3. 整理最终报告、说明和工具后再次提交。产品指纹必须保持与导出一致，再运行 `-PackageOnly`，使用 `-TestReport docs/V3_TEST_REPORT.md -EvidenceDirectory build/v3_delivery_evidence/build`。此步骤重新核对当前产品指纹及EXE/PCK哈希，原样打包已测试导出。
4. 运行 `tools/verify_release.py --version 0.3.0`。缺少证据、失败的报告、版本/PCK不一致或不合法的源码包都会使校验失败；校验器不会自动修补报告。

产品源文件指纹覆盖 Git 跟踪的 `project.godot`、`main.tscn`、`export_presets.cfg`、`scripts/`、`assets/` 的路径和文件SHA256。文档、测试和工具不参与该指纹。清单分别保存 `export_source_commit` 和含最终文档/工具的 `source_commit`，两者之间不得有产品文件差异。

源码ZIP通过 `git -c core.autocrlf=false archive --format=zip HEAD` 生成，保留提交中的原始字节，不套用本机CRLF转换；ZIP注释必须等于清单中的完整提交号。通用校验器会重新生成该提交的git archive，对比整个ZIP、全部跟踪文件集合及每个文件内容，再单独核对关键源码和最终报告。源码包不含本地引擎、模板、`.git`、`.godot`、`.tools`或生成的`build/`。

## 原始证据的口径

最终运行报告使用 `build/reports/v3_final_*.json`，包括 `input`、`benchmark`、`victory`、`motion`、`soak`、`soak-process`、`soak-memory-recheck`。每份报告必须明确记录最终PCK哈希；若原始外部输入脚本没有该字段，由运行包装流程在核对实际命令、前后PCK哈希后记录绑定，不可据文件名猜测版本。

- 输入证据采用实际Viewport鼠标按下/松开/拖动、键盘、菜单与Alt事件，覆盖暂停落点、队形、连续右键和HUD不穿透。专用敌人/伤势/岗位夹具只用于暴露UI状态。
- 性能证据必须是最终Windows程序的至少65秒实时采样，记录CPU/GPU、逻辑/窗口/渲染分辨率及负载；门槛为平均至少60FPS、P95不高于33.3ms。离线录像的帧率不算实时性能。
- 胜利证据必须运行当前v0.3公开命令录像，完成28,800步、480秒，实际结果与同种子重放指纹一致。不得套用v0.2战术指纹，也不通过额外加血、加弹或减伤制造结果。
- 动作录像默认交付 `build/Rimgate-demo-v0.3.0-motion.mp4`，暂停段截图为 `build/v3_evidence/motion_14.5.png` 和 `motion_15.5.png`。校验器检查合法的音视频轨、时长与原始录像报告一致，并要求两张暂停帧完全相同；`motion_audio_report.json`记录实际混音的非静音双声道和削波检查。
- 稳定性证据包括30分钟程序内部报告、外部进程/私有内存采样及独立离线重新聚合。内存为零或缺失不代表通过；重新聚合必须引用原始进程报告哈希，且使用相同的样本与增长容差。

Windows包附带音频、字体许可与原始通知，以及 `GODOT_LICENSE.txt`、`GODOT_THIRD_PARTY_NOTICES.txt`。校验器将这些文件与清单指向的源码提交逐字节比较。美术审稿原稿留在源码包，精选运行截图/录像与报告按相对目录进入证据包。

## 复核命令

在仓库根目录的PowerShell执行，替换为自己的引擎路径；以下命令会实际运行测试程序，报告使用新的输出位置，避免覆盖原始验收证据。

```powershell
$godot = (Resolve-Path .tools/godot/Godot_v4.7.2-stable_win64_console.exe).Path
$release = (Resolve-Path build/release_v0.3_windows).Path
$game = Join-Path $release 'Rimgate.exe'
$pck = Join-Path $release 'Rimgate.pck'
$reports = Join-Path (Get-Location) 'build/recheck-v3'
New-Item -ItemType Directory -Force -Path $reports | Out-Null
./tools/test.ps1 -Godot $godot
# 外部UI检查脚本，产品脚本/资源仍从这个PCK加载。
$inputScript = (Resolve-Path tests/input_v3.gd).Path
& $godot --main-pack $pck --script $inputScript -- "--report=$reports/input.json" "--capture=$reports/ui"
& $game --resolution 1920x1080 -- --qa-mode=benchmark "--qa-report=$reports/benchmark.json"
& $game --resolution 1920x1080 -- --qa-mode=victory "--qa-report=$reports/victory.json"
./tools/soak.ps1 -Executable $game -ReportPrefix "$reports/soak"
./tools/check_soak_memory.ps1 -ReportPrefix "$reports/soak"
# 完成正式打包后，只读核对导出/ZIP/证据，另写独立校验结果。
python tools/verify_release.py --version 0.3.0
```

外部UI脚本的报告绑定应保存实际PCK路径、运行命令和前后哈希；未完成这一绑定的重跑报告不能作为通用包校验器的正式输入。正式清单中的哈希可直接读取，不在本说明里维护第二份手填值：

```powershell
Get-Content build/Rimgate-demo-v0.3.0-manifest.json -Raw | ConvertFrom-Json |
    Select-Object version, source_commit, export_source_commit, executable_sha256, pck_sha256, product_source_sha256
```

包校验器也可通过 `--export-dir`、`--manifest`、`--windows-zip`、`--source-zip`、`--report-prefix`、`--media`、`--pause-frames`、`--audio-report` 指定其他路径。路径选项改变查找位置，不放宽验收条件。
