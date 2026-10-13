# 脸型、五官、发型组合审稿

用户要求将圆形头部改为不同脸型，通过脸型、五官和发型区分小人，并将上一版眼睛略微缩小。本轮提供六组同一画风的正面组合，眼睛以13%缩小为基础，按个人眼型作轻微横纵调整。颜色变化之外，脸部轮廓、眉鼻嘴和头发剪影均不同。

- `combinations.png`：六组人物、无盔/戴盔外观、68px/96px尺寸对照。
- `combinations-animated.gif`：六组面部的眨眼示例，各自错开时间。
- `hair-swaps.png`：01与06号只交换头发，脸部与五官保持原样，展示分层组合。
- `svg/`：完整预览及独立脸型、五官、前发、后发、身体、头盔图层。
- `png/`：对应透明PNG；`manifest.json`记录源图、配置与比例。

身体和头盔仍直接采用当前游戏的SVG。前后头发与脸、五官分离；戴盔时遮住头顶部头发，仅保留盔沿下的部分。所有眼睛继承上一轮的彩色虹膜、厚上眼线与半垂眼睑，眨眼由眼睑遮挡完成。此轮仅有正面，尚未获用户批准，未更改游戏运行资源。

重建顺序：Python运行`make_combinations.py generate`，Godot以`--headless --path . --script docs/art_review/facial_combinations_v1/render.gd`渲染，再由Python运行`make_combinations.py compose`。生成器复用相邻`facial_single_v1/make.py`中的身体、头盔和眼睛源图元。
