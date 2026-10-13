# 一套面部，三种表情：审稿版

根据用户给出的Facial Animation式参考，收敛为同一个眼型与翠绿虹膜，展示平静、专注、受伤三个状态。所有绘图均为原创SVG，没有使用AI或模组贴图。

`preview.png`展示无头盔脸部放大、无盔/戴盔小人及尺寸对照。`face-animated.gif`展示面部动态，`pawn-animated.gif`展示同一动画在无盔和戴盔状态下的外观。动画循环7.2秒，仅用于审稿。

身体、头部圆形轮廓与头盔直接取自当前游戏的`assets/art/vector/friendly_atlas.svg`。每种状态只有一个面部图层，在无盔和戴盔图中复用；头盔绘制在面部之上。眉、眼白、虹膜、眼睑、鼻嘴由SVG图元组成；眨眼通过眼睑裁切眼球，虹膜本身不缩放。

尚未批准、未接入游戏。仅有正面；固定顺序的表情循环、眨眼时间和尺寸对照均不是最终游戏状态逻辑。此轮保留头部轮廓，没有擅自扩大头部或改变身体比例。

源文件：`svg/`，透明PNG：`png/`，源图哈希：`source.json`。重建：Python运行`make.py generate`，Godot运行`--headless --path . --script docs/art_review/facial_single_v1/render.gd`，Python运行`make.py compose`。
