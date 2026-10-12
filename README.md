# Rimgate · 防线

Godot 4.7.2 / Windows x64。原创俯视战术防御 Demo，6 名守军在一张固定地图上守护核心 8 分钟，迎击 3 波敌人。经营、建设和长期存档留待后续版本。

当前为第二版 Demo v0.2；范围见 [第二版规划](DEMO_V2_PLAN.md)，验证结果见 [第二版验收](docs/V2_TEST_REPORT.md)，完整游戏方向见 [设计记录](GAME_DESIGN.md)。[第一版规划](DEMO_PLAN.md)与历史测试报告保留作对照。

## 游玩

解压 Windows 包，运行 `Rimgate.exe`，并保留相邻的 `Rimgate.pck`。不需要安装 Godot，也不需要联网。详细操作见 [游玩说明](docs/PLAY_V2.md)。

- 左键选人，拖框多选，Shift 增选；右键地面移动，右键敌人指定攻击。
- 右键机枪或迫击炮选择操控或补给。机枪限 1 人，迫击炮限 2 人；工事需要人员在岗才能工作。
- 选中工事后右键敌人指定该工事目标。迫击炮也可点击“轰击”，再左键选择落点；每次命令仅发射一枚，爆炸和弹片会误伤友军。
- 新一次右键替换旧菜单或选点状态，并立即处理本次点击，无需先左键空白处。
- 右键伤员选择现场急救；对昏迷者可以救援至救护区。急救只止血，生命缓慢恢复。
- HUD 调整征召、停止、姿态和作战风格。移动中可以低精度射击；强制伏低或溃逃会中断作战。
- Space 暂停/继续，WASD 或中键平移镜头，滚轮缩放，Esc 打开菜单。
- 开局处于准备暂停；布置命令后点击“开始防守”。暂停时可以下命令，恢复后执行。
- 守到 8:00 获胜；核心被摧毁或全员死亡则失败。结果页可以重开。

可以先让两人操作机枪、一人操作迫击炮，其余三人警戒侧翼并补给、救援。迫击炮增加副手可缩短作业周期。左机枪覆盖西北、右机枪覆盖北面，各自保持120°射界；开放的L/U形阵地保留通路与侧后暴露。前沿守军尽量与己方机枪弹道错开，炮击前也要注意友军位置。

本版重做了沿途掩体和格子占位；常规步枪约3秒一轮，压制与谨慎有不同射速、精度和耗弹节奏。瞄准锥、枪口出弹、枪焰后座、透红受击、医疗动作及分层空间音效同步实际战斗事件。自动姿态在压制解除后恢复站姿，仍可手动锁定姿态。

## 源工程

用 Godot **4.7.2 标准版**导入 `project.godot`，按 F6/F5 运行。使用 Compatibility 渲染器和纯 GDScript，不需要 .NET。当前人物与工事使用原创 SVG 图集，旧 PNG 仅保留作回退；素材来源见 [ASSETS](docs/ASSETS.md)。

固定60Hz仿真位于`scripts/sim`，界面与表现位于`scripts/ui`。活动单位独占格子，格心之间连续移动，显示帧继续插值；画面和音效不决定伤害，固定种子104729。美术与实时连续感的参考依据见 [调研记录](docs/REFERENCE_REVIEW.md)，新增声音来源见 [音频记录](docs/AUDIO_V2.md)。

```powershell
# -Godot 可指定自己的 Godot 4.7.2 console 路径。
powershell -ExecutionPolicy Bypass -File tools/test.ps1

# 将官方同版本 export_templates.tpz 放到 .tools 后，只提取 Windows 模板。
python tools/extract_templates.py
powershell -ExecutionPolicy Bypass -File tools/build.ps1
```

本地引擎、导出模板、`.godot` 缓存与 `build` 不纳入 Git。导出程序与源码 ZIP 输出至 `build`。

发布打包要求先提交工程变更，源码ZIP取自该Git提交。`tools/build.ps1 -ExportOnly -ExportDirectory build/release_v0.2_windows` 先导出并记录产品文件指纹；测试该导出后，可用 `-PackageOnly -ExportDirectory build/release_v0.2_windows` 原样打包。打包会核对指纹及EXE/PCK哈希，版本清单分别记录导出与文档所在提交；只打包不代替测试。
