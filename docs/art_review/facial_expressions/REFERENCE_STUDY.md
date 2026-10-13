# Facial Animation 参考研究

研究日期：2026-10-13。依据原作者及衍生模组的Steam创意工坊说明；用户提供的三张脸作为当前视觉参考。部分在线动图和浏览器页面读取失败，因此以下不声称已逐帧检查原模组动画，也未检查其运行源码。

## 原模组提供的线索

- [[NL] Facial Animation - WIP](https://steamcommunity.com/sharedfiles/filedetails/?id=1635901197)：列出眨眼、战斗待命、移动、倒地等动作。启发：表情应随单位状态变化，并保留平静待命的基础脸。
- [[NL] Facial Animation - Experimentals](https://steamcommunity.com/sharedfiles/filedetails/?id=2581693737)：扩展眼球、眼白和随情绪变化的脸色。更新说明提及眼睑、半遮眼球、战斗待命与眨眼定义，以及疼痛导致的泪眼。启发：眼睛需要考虑眼睑与眼球的遮挡关系，眉眼嘴协同形成表情。

## 衍生模组的方向

- [Vee face for Facial Animation](https://steamcommunity.com/sharedfiles/filedetails/?id=2682310477)：替换默认画面并增加嘴型。适合研究同一动画框架下如何整体重画面部，而非只改虹膜颜色。
- [Pupil addon](https://steamcommunity.com/sharedfiles/filedetails/?id=2647944558)：增加黑色瞳孔。启发：将眼白、虹膜、瞳孔与高光分开控制，维持清楚的视线。
- [Threat addon](https://steamcommunity.com/sharedfiles/filedetails/?id=2648460932)：以细微贴图调整使人物更有威胁感，不添加新动作。适合研究战斗时的眉形和眼睑，不必将整张脸夸张变形。
- [Girly addon](https://steamcommunity.com/sharedfiles/filedetails/?id=2650270222)：增加眼睑选择与轻量妆容。启发：人物气质可以来自眼型与眉形，且不必改变身体比例。
- [Nice Facial Animation](https://steamcommunity.com/sharedfiles/filedetails/?id=3302079637)：作者希望在点状眼睛与二次元眼睛之间保留原版感觉，作为面部复杂度的对照。
- [Vanilla Textures Expanded - [NL] Facial Animation](https://steamcommunity.com/sharedfiles/filedetails/?id=2816938779)：用黑色形状替代彩色二次元眼睛，简化嘴眉并去掉鼻子。用于判断我们希望保留多少二次元细节；用户当前参考更接近彩色眼睛的方向。

## 对Rimgate的设计建议（我们的判断，不是原模组的实现说明）

1. 保留当前小人身体与装备；脸型与五官位置共同审稿。必要时微调脸部留白和五官间距，但不能未经审稿就扩大或重画整个角色。
2. 使用用户参考中的粗上眼线、半垂眼睑、大块彩色虹膜；眼部强调清楚的明暗分块，鼻嘴维持小而简洁。避免堆叠多个高光、金属质感和过密渐变。
3. 单独制作眉毛、眼白、虹膜/瞳孔、眼睑、嘴以及汗泪等覆盖层。头盔/面罩按实际遮挡裁切面部，不能让眉眼穿过装备。
4. 将固有眼型、虹膜颜色与临时情绪区分。平静、专注、惊慌、疼痛来自眉眼嘴的组合；换瞳色本身不算一种新表情。
5. 眨眼应让眼睑覆盖眼球，虹膜保持大小；视线小幅跟随目标，避免持续左右摆动。动作时间以独立随机间隔和事件触发为主，审稿GIF的循环不是游戏最终逻辑。
6. 战斗状态只改变必要的部件：瞄准时收眼睑、眉压低；受击短暂闭眼；持续压制逐渐惊慌；昏迷闭眼并停止主动视线变化。动作优先级和具体数值后续讨论。
7. 下一次只提交一套完整的脸，展示平静、专注和受伤三种状态；同时展示脸部放大与游戏68px绘制尺寸。由用户先定稿，再扩展侧面、姿态与更多动画。

本研究只借鉴设计方法。未将任何模组贴图、代码或下载包加入项目；现有表情示例也尚未获用户批准，不接入游戏运行资源。
