# 完整小人审稿：减细描边与戴盔发型

按用户反馈修改06号：用连续曲线柔化颧骨、下颌与下巴，取消原来的尖角菱形脸。身体、头盔、头发与脸的外轮廓描边约减半；眼睛继续沿用上轮缩小后的比例。原版完整身体轮廓与配色保留，本轮没有增加写实四肢或改变身体结构。

戴盔发型有六套单独绘制的前发、后发部件：侧分刘海、寸头鬓角、短发两侧发尾、后梳鬓角、压低卷发、低马尾。头顶部头发由头盔覆盖，盔沿下的发束保留个人特征。马尾连接点位于头盔下沿附近；未使用上一轮的横向矩形裁切方式。

- `full-body-review.png`：六组完整小人，无盔/戴盔成对展示。
- `helmet-hair-detail.png`：六组戴盔头发特写。
- `06-revision.png`：06号修改前后对照。
- `full-body-animated.gif`：完整小人的眨眼动画，循环3.6秒。
- `svg/`：独立身体、头盔、脸型、五官、无盔头发、戴盔头发及组合源图。
- `png/`：对应透明PNG。

只做正面审稿，尚未接入游戏。SVG源图及生成器为原创，没有使用AI或模组素材。源图几何来自项目已有资源，此轮仅在审稿图中调整描边；`manifest.json`记录当前运行资源的哈希。

重建顺序：Python运行`make_revision.py generate`；Godot运行`--headless --path . --script docs/art_review/facial_combinations_v2/render.gd`；Python运行`make_revision.py compose`。生成器复用相邻`facial_combinations_v1`与`facial_single_v1`中的原始图元。
