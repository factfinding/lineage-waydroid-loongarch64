# Unity Terrain 最小复现

这个独立程序用于调查 LoongArch64 Waydroid 上 ARM64 Unity 游戏的地形缺失。
使用 Unity **2022.3.62f3**、Built-In Render Pipeline，Android 构建为 **IL2CPP / ARM64**。
GLES3 与 Vulkan 分别构建、分别安装，避免 Unity 自动切换图形接口干扰结果。

另有针对透明、深度采样、折射、反射、浮点渲染目标及实例化的
[水面相关路径测试](WATER.md)，使用独立的 `org.la64.waterprobe.gles3` 包。

原神是否使用原生 Terrain 或自定义地形渲染尚未证实。这个测试复现标准 API 路径，
不是原神场景的提取或完整替代。最近五轮优化之前的版本也被用户报告地形缺失；
全解释模式因速度和游戏联网失败未能完成有效的场景对照，不能据此排除所有 JIT 错误。

## 用例

相机、方向光、背景色和高度图固定。普通 Mesh 与 Terrain 使用同一份高度数据，
不依赖联网、AssetBundle、外部纹理、压缩纹理、烘焙光照、植被或地形孔洞。

| 编号 | 路径 | 高度 | 材质 | 实例化 | pixel error |
| --- | --- | --- | --- | --- | --- |
| 00 | Mesh | 平面 | 无光照棋盘格 | 无 | 不适用 |
| 01 | Mesh | 两个不对称山丘 | 无光照棋盘格 | 无 | 不适用 |
| 02 | Mesh | 同上 | Standard / 有光照 | 无 | 不适用 |
| 03 | Terrain | 平面 | 单层 | 关 | 1 |
| 04 | Terrain | 山丘 | 单层 | 关 | 1 |
| 05 | Terrain | 山丘 | 单层 | 开 | 1 |
| 06 | Terrain | 山丘 | 双层混合 | 关 | 1 |
| 07 | Terrain | 山丘 | 双层混合 | 开 | 1 |
| 08 | Terrain | 山丘 | 双层混合 | 关 | 20 |
| 09 | Terrain | 山丘 | 双层混合 | 开 | 20 |

`Terrain.drawInstanced`、`heightmapPixelError` 和材质由标准
[Terrain API](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/Terrain.html) 控制。
高度通过 [SetHeights](https://docs.unity3d.com/2022.3/Documentation/ScriptReference/TerrainData.SetHeights.html)
提交，数组按 `[z,x]` 索引。Mesh 的 UV 和 Terrain 的贴图重复次数一致；
法线、三角形划分和地形 LOD 可能不同，因此不要求两个路径截图逐像素相同。

## 构建

安装 Unity Editor 2022.3.62f3 及 Android Build Support、SDK/NDK 和 OpenJDK。
**不要用 2022.3.72f1 替代**：本次实测它要求 Extended LTS 的 Industry/Enterprise 授权，
已有 Personal 许可证无法运行（Editor 退出码 198）。62f3 已在当前许可证下实际构建成功。

在 WSL 执行以下命令，脚本会把源文件复制到专用 Windows 构建目录：

```bash
python3 tools/build-wsl.py \
    --editor '/mnt/c/Program Files/Unity/Hub/Editor/2022.3.62f3/Editor/Unity.exe' \
    --work '/mnt/c/la64-build/TerrainProbe' \
    --api gles3
```

再以 `--api vulkan` 构建 Vulkan APK。`--api windows` 可生成 Windows/D3D11/Mono
参考程序。三次构建按顺序执行，不要同时打开同一个构建目录。
APK 和完整构建日志回收到本项目的 `Builds/`，不作为源文件提交。

也可以用 Editor 打开项目，选择 **Terrain Probe → Prepare scene** 后直接 Play。
构建入口为 `La64.TerrainProbe.ProbeBuild.Build`，参数为 `-terrainApi gles3|vulkan`
和 `-terrainOutput <APK绝对路径>`。自动构建会保留 Terrain shader 及实例化变体，
避免把测试程序自身的 shader stripping 错认成设备错误。

独立输入数据检查（.NET 10，不需要 Editor）：

```bash
dotnet run --project checks/FixtureChecks.csproj
```

此检查覆盖 Python 独立生成的高度哈希、峰值坐标、三角形朝向/索引、顶点覆盖、
alpha 权重和。不等于 Unity 编译通过或 GPU 绘制正确。

## 在设备上运行

操作前遵守工作区 DEVICE.md。安装测试 APK 不需要修改游戏或转译库。
现有 SSH 别名 `la64-root` 必须可用，Waydroid 用户会话应已启动且显示窗口。

```bash
python3 tools/run-la64.py --api gles3 --apk Builds/terrain-gles3.apk \
    --out /home/noctis/aosp-la64/logs/terrain-probe-gles3-RUN_ID
```

Vulkan 同理替换 `--api` 和 APK。脚本只强制停止自身测试包，保持其他应用数据不变。
它以 `probe_auto=true` 启动，等待每个用例至少 30 帧和 2 秒，再采集图像。
默认最多等待 600 秒；可用 `--timeout` 调整，不要通过时间耗尽判断渲染正确。

采集完成后运行 `python3 tools/summarize.py <采集目录>`，解包结果并生成
`summary.json`。其中 `visual_pass` 保持空值，视觉是否正常必须查看 PNG。

手工运行时，屏幕按钮提供 Previous / Next / Capture / Run all。
Windows 参考程序支持 `--probe-auto --probe-quit`，完成后退出。

## 结果与判读

每次启动创建独立目录，避免混入旧截图：

- `environment.json`：Unity 版本、CPU、GPU、实际图形接口、IL2CPP/Mono、JIT 属性。
- 每用例 `*-data.json`：输入哈希、Unity 数据回读误差、shader 是否受支持。
- `*-camera.png`：960×540 固定相机 RenderTexture 回读，不含 UI。
- `*-screen.png`：实际屏幕截图，不含 UI。与相机输出对照可检查显示/合成差异。
- `player.log`：Unity 日志和异常。
- `COMPLETE.txt`：仅表示全矩阵采集结束，**不是视觉通过标记**。

高度回读允许量化误差，`cpuReadbackPass` 仅检查数据，不能证明 GPU 输出正确。
建议先用 Windows 或原生 ARM64 Android 得到正常参考，再在 la64 比较：

| 结果 | 下一步优先检查（不是直接定因） |
| --- | --- |
| 输入哈希或回读不一致 | CPU/解释器/JIT、数据提交与回读 |
| Mesh 正常，Terrain 异常 | Terrain shader、LOD、实例化、地形绘制参数 |
| 仅实例化异常 | 实例化属性、buffer/纹理读取及翻译路径 |
| 仅双层异常 | alpha、纹理采样和 shader 变体 |
| GLES3 与 Vulkan 不同 | 相应代理/驱动路径；不单凭此排除 CPU 翻译 |
| 相机回读正常、屏幕异常 | 屏幕渲染/合成路径和时序 |
| 全部正常 | 标准 Terrain 未复现；继续调查游戏自定义路径和资源 |

改变 Berberis JIT/寄存器缓存时需重启测试进程，并保存库哈希。此程序很小，适合后续
进行纯解释对照，避免原神在全解释模式下加载过慢、联网超时而无法到达场景。

本设备上试过 `wrap.<package>` 加 `BERBERIS_MODE=interpret-only` 的单应用对照，
但包装启动没有正确初始化 Native Bridge，`libmain.so` 报架构不匹配，未进入 Unity。
这不是有效的纯解释渲染结果。wrap 属性已恢复为空，脚本不提供这个不可用的选项。
全局 Berberis 和 ART JIT 保持开启；纯解释对照仍待实现。

## 2026-09-11 实测

三个目标均构建成功。Windows/D3D11 与 la64/GLES3 各完成十个用例，CPU 数据检查
全部通过；逐张检查相机回读和屏幕截图，均未出现原神那种地形缺失。
la64 Vulkan-only 版停在图形初始化，日志报告 Vulkan 驱动库无法加载，未进入场景。
单应用纯解释尝试因上述 Native Bridge 启动限制无效。

完整环境、APK 哈希、证据路径和结论边界见
[实测报告](../../docs/UNITY_TERRAIN_PROBE.md)。这些结果证明此测试路径可运行，
不能证明原神使用相同地形实现，也不能排除其他 JIT、shader 或资源路径的问题。
