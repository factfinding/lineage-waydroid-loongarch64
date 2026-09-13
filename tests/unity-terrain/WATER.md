# 水面相关 GLES 路径对照

这是对“原神缺失的可能是水面”的独立测试，不使用原神资源或 shader。
Unity 2022.3.62f3 / Built-In；固定透视相机、阶梯棋盘河床、三根彩色柱子和水面网格。
Android 仅 ARM64 / IL2CPP / GLES3，包名 `org.la64.waterprobe.gles3`。

| 编号 | 操作 | 预期观察 |
| --- | --- | --- |
| 00 | 无水面 | 河床及柱子参考 |
| 01 | 不透明纯色网格 | 青色水面，遮挡水下部分 |
| 02 | alpha=0.5 混合 | 青色与河床各占一半，柱子正常遮挡 |
| 03 | 深度纹理采样 | 水面到河床的深度差呈颜色变化 |
| 04 | 深度决定透明度 | 不同水深不同透明度 |
| 05 | GrabPass 颜色拷贝 | 应接近 00；本例没有着色或偏移，水面不可辨认是预期 |
| 06 | GrabPass 折射 | 固定正弦偏移使水下格子扭曲 |
| 07 | ARGB32 离屏平面反射 | 水面可见镜像柱子，另外保存反射纹理 |
| 08 | ARGBHalf 离屏反射 | 同上，记录真实分配格式 |
| 09 | ARGBFloat 离屏反射 | 同上，记录真实分配格式 |
| 10 | 四块水面分别 DrawMesh | 与 02 相同的混合，供实例化对照 |
| 11 | 同四块 DrawMeshInstanced | 应与 10 一致 |

原生 ARM64 插件通过 `GL.IssuePluginEvent` 在 Unity GLES 渲染线程查询：
当前 context、15 个选定入口、扩展列表、读/写 FBO 完整性及 GL 错误。
主相机在 AfterEverything 采样，反射相机在渲染目标仍绑定时采样。
插件不更改 GL 绑定；`glGetError` 会消费错误标志，因此只在独立测试程序使用。
每个事件编号最多记录 256 次，避免测试窗口长时间停留时持续写日志。
入口存在不是驱动实现正确的证明；这也不是游戏全部 API 的覆盖检查。
采样只反映这些时点，不能捕获所有已被 Unity 消费的错误。

## 构建和采集

沿用 README 的 `build-wsl.py` 参数，加 `--suite water`：

```bash
python3 tools/build-wsl.py --suite water --api gles3 \
    --editor '/mnt/c/Program Files/Unity/Hub/Editor/2022.3.62f3/Editor/Unity.exe' \
    --work '/mnt/c/la64-build/TerrainProbe'
python3 tools/run-la64.py --suite water --api gles3 --apk Builds/water-gles3.apk \
    --out /home/noctis/aosp-la64/logs/water-probe-gles3-RUN_ID
python3 tools/summarize.py /home/noctis/aosp-la64/logs/water-probe-gles3-RUN_ID
```

用安装了 Pillow 的 Python 执行 `tools/compare-water.py --windows <Windows采集目录>
--gles3 <GLES3采集目录>`，可生成颜色拷贝、透明混合公式、实例化和跨平台像素差异报告。
跨平台差异为描述性指标，不自动判定正常或异常；先核对同一平台的配对用例。

Android 构建脚本用 Editor 所带 NDK 编译 `native/water_gl.c`，只在专用构建目录
生成插件。`--api windows --suite water` 生成 `Builds/windows-water/WaterProbe.exe`，
以 `--probe-auto --probe-quit` 运行得到 D3D11/Mono 参考。
Windows 不使用 GLES 插件。不要将此水面诊断插件用于 Vulkan 构建。

各用例保存网格计数、shader 支持、分配格式、跳过原因、固定相机和实际屏幕截图。
`cpuReadbackPass` 在本套件仅检查固定网格计数，不代表材质或 GPU 检查通过。
格式不支持、分配失败或替换格式会记录为跳过，不能当作通过。
像素对照及 GL 诊断需要另外查看；`COMPLETE.txt` 仅代表采集结束。

测试没有模拟原神的自定义 shader 变体选择、波浪资源、完整渲染图或 shader 缓存。
全部正常时仍不能排除仅在游戏中触发的桥接、JIT、驱动或资源错误。
