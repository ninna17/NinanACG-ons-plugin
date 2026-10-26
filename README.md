# ONS

这只是给 NinanACG 适配的 ONS 模拟器插件，一切以适配我们自己的APP为准，我们只能保证所有代码可以成功构建插件，可能无法直接使用

## 许可

插件整体（native 库、`classes.dex`、本仓库源码）以 **GNU GPL v2 或更新版本** 分发，协议全文见 [LICENSE](LICENSE)

- 引擎：OnscripterYuri，上游固定提交 `08f744b31cc1907b66a15f0402e62321a131ed81`
  — <https://github.com/YuriSizuku/OnscripterYuri>（内含 ONScripter by Ogapee，GPL）
- 对于 C++ 部分未做任何改动，源码由 `prepare.sh` 拉取，`patch_upstream_gradle.py`
  只调整 `app/build.gradle` 的 SDK/NDK/ABI 构建参数
- Java 部分位于 `src/acg/ninan/uk/emu/plugin/ons/`（`OnsEngine.java`、`SafFile.java`），
  由 `package.ps1` 编译成 `classes.dex` 打包，`OnsEngine.java` 由 `ONScripter.java` 修改而来
- 第三方库（SDL2 系列 zlib、lua MIT、bzip2、libjpeg-turbo、libwebp、libvorbis/ogg BSD 类）
  分别遵循各自协议

插件壳（SDL Activity）不含 ONScripter 代码，不属于本插件 **APP和本插件是两个独立的程序**

## 目录

```
src/                      插件 Java 部分（编译至 classes.dex）
prepare.sh                准备源码到工作区
patch_upstream_gradle.py  调整 Gradle 构建参数
package.ps1               把 native 库 + classes.dex 打包成 ons-<版本>.zip
LICENSE                   GPL v2 协议
```

## 构建

1. 准备源码工作区：

   ```bash
   ./prepare.sh /short/path/_emu_ons
   ```

   它会切到固定提交、用 `script/_fetch.sh` 下载好 SDL2 等第三方库、
   改掉 SDL 里的 `ALooper_pollAll` （NDK r26 以后貌似必须修改）、再做一遍 Gradle 参数修改
   在 Windows 上编的话，用 `ANDROID_SDK_WIN` 传 SDK 路径，脚本会处理 `local.properties`

2. 用 Android SDK / NDK 编译工程：

   ```bash
   cd /short/path/_emu_ons/up/src/onsyuri_android
   ./gradlew :app:assembleDebug
   ```

   产物为 `libonsyuri.so` 及 SDL2 系列依赖库，ABI 为 `arm64-v8a`、`x86_64`(`x86_64`只是为了方便Agent自动化测试)

3. 打包插件（Windows上，需先 `flutter build apk` 出 APK，用于编译 Java 层）：

   ```powershell
   powershell -File package.ps1 -Apk <apk路径> -Version 1.0.0 -Out <输出目录>
   ```

   默认 `-MinHostApi 3`(这个参数在我们这里只是用于给我们的APP判断是否能够兼容某个版本)