# 原版小人：动态二次元面部审稿

沿用 `assets/art/vector/friendly_atlas.svg` 中游戏正在使用的正面小人，身体、头盔、轮廓、配色保持原样，只增加独立眉眼、嘴部及表情符号。未修改游戏资源或行为。

- `reference-animated.gif`：根据用户参考图调整后的动态对比，含68px游戏绘制尺寸与96px放大对照，尚未定稿。
- `reference-expressions.png`：原版与参考图方向的静态审稿板。
- `reference-A.gif`、`reference-B.gif`、`reference-C.gif`：单独动态示例。
- `svg/`：当前原版、12张带表情的小人、12张独立透明表情图层。
- `png/`：对应透明PNG。
- `source.json`：原版源文件哈希及方案名称。

A为柔和蔷薇瞳，B为平静翠绿瞳，C为锐利紫罗兰瞳。每版展示待命眨眼、专注时瞳孔跟随、惊慌汗滴、受伤闭眼忍痛。动画是外观候选，尚未绑定游戏状态；专注示例中的瞳孔左右运动用于演示，正式接入时应跟随目标方向。上一轮`expressions*`及`A/B/C-animated.gif`为被否定的旧稿，不再作为推荐方向。

用户随后要求研究RimWorld的Facial Animation及其衍生模组。研究链接和后续收敛方案记录于`REFERENCE_STUDY.md`，所有现有示例均保持未批准状态。

三种画法均使用同一张身体和同一头盔，没有重画小人。先审定正面表情，再适配侧面、姿态及敌方单位。

重建顺序：Python运行 `make_examples.py`，Godot以 `--headless --path . --script docs/art_review/facial_expressions/render.gd` 渲染，然后Python运行 `compose.py`。
