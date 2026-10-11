# Rimgate · 防线

Godot 4.7.2 / Windows x64。原创俯视战术防御 Demo，6 名守军在一张固定地图上守护核心 8 分钟，迎击 3 波敌人。经营、建设和长期存档留待后续版本。

当前为开发版本；实际验证结果以 [测试报告](docs/TEST_REPORT.md) 为准。详细范围见 [开发规划](DEMO_PLAN.md)，完整游戏设计见 [设计记录](GAME_DESIGN.md)。

## 游玩

解压 Windows 包，运行 `Rimgate.exe`。不需要安装 Godot，也不需要联网。

- 左键选人，拖框多选，Shift 增选；右键地面移动，右键敌人指定攻击。
- 右键机枪或迫击炮选择操控或补给。机枪限 1 人，迫击炮限 2 人；工事需要人员在岗才能工作。
- 选中迫击炮或炮手，点击“轰击”，再左键选择落点；右键取消瞄点。每次命令仅发射一枚，爆炸和弹片会误伤友军。
- 右键伤员选择现场急救；对昏迷者可以救援至救护区。急救只止血，生命缓慢恢复。
- HUD 调整征召、停止、姿态和作战风格。移动中可以低精度射击；强制伏低或溃逃会中断作战。
- Space 暂停/继续，WASD 或中键平移镜头，滚轮缩放，Esc 打开菜单。
- 开局处于准备暂停；布置命令后点击“开始防守”。暂停时可以下命令，恢复后执行。
- 守到 8:00 获胜；核心被摧毁或全员死亡则失败。结果页可以重开。

可以先让两人操作机枪、一人操作迫击炮，其余三人警戒侧翼并补给、救援。机枪只能攻击朝北的 120°射界，北面沙袋无法保护侧面来袭的火力。已验证的八分钟战术与操作时点见 [战术记录](docs/TACTICAL_COMPARISON.md)；这证明场景可胜利，不代表上述简单分工即可自动获胜。

## 源工程

用 Godot **4.7.2 标准版**导入 `project.godot`，按 F6/F5 运行。使用 Compatibility 渲染器和纯 GDScript，不需要 .NET。当前人物与工事使用原创 SVG 图集，旧 PNG 仅保留作回退；素材来源见 [ASSETS](docs/ASSETS.md)。

固定 60 Hz 的仿真位于 `scripts/sim`，界面与表现位于 `scripts/ui`。显示帧在前后仿真位置之间插值，地图格子不限制单位屏幕位置。画面和音效不决定伤害；固定种子为 104729。美术与实时连续感的参考依据及修订见 [调研记录](docs/REFERENCE_REVIEW.md)。

```powershell
# -Godot 可指定自己的 Godot 4.7.2 console 路径。
powershell -ExecutionPolicy Bypass -File tools/test.ps1

# 将官方同版本 export_templates.tpz 放到 .tools 后，只提取 Windows 模板。
python tools/extract_templates.py
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

本地引擎、导出模板、`.godot` 缓存与 `build` 不纳入 Git。导出程序与源码 ZIP 输出至 `build`。

发布打包要求先提交工程变更，源码ZIP取自该Git提交。`tools/build.ps1 -ExportOnly -ExportDirectory build/release_windows` 先导出并记录产品文件指纹；测试该导出后，可用 `-PackageOnly -ExportDirectory build/release_windows` 原样打包。打包会核对指纹及EXE/PCK哈希，版本清单分别记录导出与文档所在提交；只打包不代替测试。
