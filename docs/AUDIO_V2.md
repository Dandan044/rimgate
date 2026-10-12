# 第二版音效制作与来源

第一版的战斗噪声合成替换为录制枪声与实物拟音的分层混音。保留界面确认/警报/胜负的原创提示音。枪械、装填、材质受击、脚步、包扎、接管和迫击炮装填有独立文件；世界声音采用位置与距离处理，重要提示优先，由表现层按显示事件时刻播放。

## 已核对来源

- Tabasco / Vincent Sevedge：[Gunshot Sounds](https://opengameart.org/content/gunshot-sounds)。页面标CC0，但下载包内明确Copyright 2009 Vincent Sevedge、CC BY 3.0。采用包内较严格要求，保存原文、署名、链接与改动说明；不把这包写为无条件CC0。
- Kenney：[Impact Sounds](https://kenney.nl/assets/impact-sounds)，CC0，包内许可已保存。使用grass/concrete、metal、mining、soft、wood、plate/tin子集。
- SpringySpringo：[Gun reload sounds](https://opengameart.org/content/gun-reload-sounds)，CC0，使用作者发布的气枪机械录音。
- NenadSimic：[Muffled Distant Explosion](https://opengameart.org/content/muffled-distant-explosion)，CC0，作者说明为低音木鼓加反射尾音；用于爆炸低频层，不宣称是实录炮击。

完整署名和改动信息在 `assets/audio/LICENSES.txt`，发布ZIP另附同一文本。源音频是选取后转换的48kHz/16bit单声道PCM，随源码保存；`source/MANIFEST.json`记录上游原始文件与转换PCM的SHA256。未运行或试听的验收不能写成已通过。

## 可复现

`assets/generate_audio_v2.py`使用Python与NumPy，从仓库内源PCM离线生成音效。枪声取不同实录单发，保留瞬态/主体/早期反射，滤去低频杂声并收束录音背景尾部；机枪增加机械层，迫击炮和爆炸另混低频及碎屑层。所有输出做电平控制和端点淡入淡出。

`tools/prepare_audio_sources.py`仅用于从已下载原始包选取和统一格式，依赖FFmpeg，不执行包内代码、不按包内路径解压。原始下载位于`.tools/audio_v2`，不进入分发；处理后的源子集与许可进入源码。运行时不需要Python、NumPy或FFmpeg。

`assets/audio/MIX_REPORT.json`记录输出时长、电平峰值和RMS，辅助排查静音/削波；这不是主观听感或实际空间音效验收的替代。
