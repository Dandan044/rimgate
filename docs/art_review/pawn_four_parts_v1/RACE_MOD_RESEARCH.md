# 种族模组美术研究与当前路线修正

研究日期：2026-10-13。

## 最新要求

- 人物身份由五官、脸型、发型、体型四项组合。
- 不画独立手臂；当前结构稿也不保留垂在身体两侧的手掌。
- 双腿靠拢，不留明显透明间隔，用低对比度的中缝和靴子分界提示两条腿。
- 参考用户提供的Q版二次元种族模组画面，保持短身比例；不是写实人体比例。
- 不使用AI生图。正面母稿需用户审定后再拓展方向、姿态与装备。

## 已核实的一手资料

1. [NewRatkinPlus作者页面](https://steamcommunity.com/sharedfiles/filedetails/?id=1578693166)明确署名：美术Gloomylynx，程序与内容NukaFrog。页面链接至作者GitHub仓库。
2. [Ratkin纹理目录](https://github.com/solaris0115/NewRatkin/tree/release/Project/Contents/Textures)将Hair、Apparel、Things等分开管理。[服装目录](https://github.com/solaris0115/NewRatkin/tree/release/Project/Contents/Textures/Apparel)实际包含RK_Cardigan_Thin_south.png、north.png、east.png等方向PNG，也有不同体型/年龄版本。不是每个人都以一张穿好全套装备的图片存储。
3. [Rabbie作者页面](https://steamcommunity.com/sharedfiles/filedetails/?id=1837246563)说明可以组合服装与颜色，以及不同脸、耳形与发型。
4. [Kurin HAR作者页面](https://steamcommunity.com/sharedfiles/filedetails/?id=2326430787)分别列出原美术、后续美术与代码贡献者。
5. [HAR Graphic Paths](https://github.com/erdelf/AlienRaces/wiki/Graphic-Paths)定义独立身体、头部、遮罩及服装图像路径。[Apparel Graphics](https://github.com/erdelf/AlienRaces/wiki/Apparel-Graphics)支持针对特殊头型、体型提供替代服装素材和回退规则。

本轮核对了作者说明、公开纹理目录与框架文档；未下载或导入模组贴图。没有核实各作者使用的具体绘画软件，也没有测量每个模组贴图的原始分辨率，不能将这些信息写成事实。

## 从用户截图得到的美术判断

参考图的完成度来自轮廓、发束、衣褶、材质明暗与配色的协调，而不仅是画布尺寸。头像、身体和服装层之间的色调与阴影方向一致；细节服务于小尺寸下的识别。

当前稿仍是少量SVG路径组成的结构研究：头发主要为大色块加少量高光，衣服的褶皱与遮挡关系过于简单，轮廓过于均匀、对称。它已经验证部件组合，但没有达到参考图的精修程度。将512×832导出成更大的PNG只增加采样像素，不会增加绘画内容。

这不是SVG格式本身不能做精细美术；问题在当前用简单路径快速拼装的制作方式。也不能把导出PNG称为已经完成手绘精修。

## 后续制作方法

先集中完成一名无手臂、并拢腿部的正面母稿，再扩展四项组合。母稿应增加真实的发束分组、基于结构的硬边阴影与少量柔和过渡、领口/腰线/衣褶及材质区别；同时检查放大稿和游戏显示尺寸。

源文件继续保留五官、脸型、前后头发、体型与服装分层，并统一脚底基准和颈部锚点。可以使用矢量轮廓配合分层绘制的位图细节；最终透明PNG仅是游戏运行格式，不代表必须将每套配装整个人重新绘制。不同体型的服装仍需要对应适配，不能只将整张图片横向拉宽。

当前structure-review.png与body-types.png仅供确认最新轮廓约束，均不作为完成精修的成果，也未接入游戏运行资源。
