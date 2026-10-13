# 四项部件结构研究

当前为未定稿的正面结构研究，尚未达到用户参考图的精修完成度。

- `structure-review.png`：六组无手臂、腿部靠拢的无盔/戴盔外观。
- `body-types.png`：同一个人的五官、脸型、发型保持一致，仅更换六种体型。
- `svg/`、`png/`：独立部件与组合预览。部件包含五官、脸型、前后头发、身体以及头盔。
- `manifest.json`：组合编号、体型参数、脚底基准、颈部锚点及最新约束。
- `RACE_MOD_RESEARCH.md`：种族模组的一手来源与美术路线修正。

最新约束：不绘制独立手臂；不在双腿之间留明显透明间隔；保留Q版比例，不使用AI生图。源文件与运行资源分离，当前没有改变游戏内美术。

重建源图：Python运行`make_pawns.py`，Godot以`--headless --path . --script docs/art_review/pawn_four_parts_v1/render.gd`渲染。生成器引用之前审稿目录的源图元。审稿板由对应PNG排版生成。
