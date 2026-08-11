# 面向 LoongArch64 的 LineageOS Waydroid

[English](README.md)

本仓库是 LineageOS 23.2 / Android 16 移植到 LoongArch64 Waydroid 的源码入口。

> [!WARNING]
> 当前公开的是开发中源码，尚未创建可复现的正式版本标签。在公开源码结构整理完成前，开发分支仍可能变化。

当前系统已经能在 AOSC OS LoongArch64 主机上启动至 `sys.boot_completed=1`。原生 LoongArch64 ART、bionic、WebView、音频、网络和 Mesa 图形栈均经过运行验证。ARM64 应用原生库通过 LoongArch64 Berberis Native Bridge 运行，兼容性和转译性能仍在持续开发。

## 源码组织

- GitHub 上具有准确上游的 Android 和 Waydroid 项目使用 fork，开发分支统一为 `loongarch64/lineage-23.2`。
- 没有准确 GitHub 镜像的 AOSP 项目，以保留作者信息的补丁序列放在 `patches/`。
- Chromium WebView 源码发布在 [`factfinding/chromium`](https://github.com/factfinding/chromium) 的 `loongarch64/webview-151.0.7922.71` 分支。
- Clang、Rust、VNDK 和 WebView 等大型构建产物不进入普通 Git 历史。
- LLVM 21 与 Rust 1.88 的源码修改和已有构建输入记录在 [`toolchains/`](toolchains/README.md)。
- `projects.tsv` 记录每个项目的源码路径、发布方式、来源和当前精确提交。

源码关系如下：

```text
LineageOS 23.2 / Android 16
  + Waydroid 官方 base-patches-36
  + LoongArch64 平台适配
  + LoongArch64 Berberis Native Bridge
  + Chromium 151 LoongArch64 WebView
```

## 相关仓库

- [可部署的 system/vendor 镜像](https://github.com/factfinding/waydroid-loongarch64-builds)
- [Waydroid 宿主端修改和软件包](https://github.com/factfinding/waydroid)
- [AOSC OS LXC seccomp 构建](https://github.com/factfinding/aosc-os-abbs)
- [Chromium LoongArch64 WebView 源码](https://github.com/factfinding/chromium/tree/loongarch64/webview-151.0.7922.71)
- [Berberis LoongArch64 Native Bridge](https://github.com/factfinding/platform_frameworks_libs_binary_translation/tree/loongarch64/lineage-23.2)

## 构建

公开 manifest 和预编译工具链引导脚本仍在整理。最终构建目标为：

源码同步和补丁应用方法见[开发版构建说明](docs/BUILDING.md)。

```bash
source build/envsetup.sh
lunch lineage_waydroid_loongarch64-bp4a-userdebug
m -j8 systemimage vendorimage
```

为了兼容 ARM64 应用，应使用 4 KiB 页面大小的 LoongArch64 内核。在文档采用的 WSL2 构建环境中不要超过 `-j8`。

## 许可证

本仓库原创脚本和文档采用 Apache-2.0。Android、LineageOS、Waydroid、Chromium 及第三方组件继续使用各自的上游许可证和版权声明，详见 [docs/LICENSES.md](docs/LICENSES.md)。
