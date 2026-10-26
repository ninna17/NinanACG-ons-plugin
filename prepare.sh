#!/bin/bash
# 准备 ONS 插件的构建工作区（在 Linux/WSL/虚拟机里运行；需要 git、curl、tar）。
# 用法: ./prepare.sh <工作区目录>      例如 ./prepare.sh /mnt/ninanacg/_emu_ons
# 工作区路径要尽量短：Windows 上编译 SDL 等第三方库时容易超过 260 字符路径限制。
set -euo pipefail

# 固定到已验证的上游提交，升级上游时手动改这里并重新验证
UPSTREAM_URL=https://github.com/YuriSizuku/OnscripterYuri.git
UPSTREAM_COMMIT=08f744b31cc1907b66a15f0402e62321a131ed81

WORK=${1:?用法: prepare.sh <工作区目录>}
mkdir -p "$WORK"
if [ ! -d "$WORK/up/.git" ]; then git clone "$UPSTREAM_URL" "$WORK/up"; fi
git -C "$WORK/up" fetch --quiet origin "$UPSTREAM_COMMIT" || true
git -C "$WORK/up" checkout -q "$UPSTREAM_COMMIT"

# 第三方库源码（SDL2 / image / ttf / mixer / lua / bzip2）
cd "$WORK/up/script"
export CMAKELISTS_PATH="$(cd .. && pwd)" PLATFORM=android
source ./_fetch.sh
prepare_port() {
    if [ -f "$1/external/download.sh" ]; then chmod +x "$1/external/download.sh"; "$1/external/download.sh"; fi
}
fetch_bz2;        prepare_port "$BZ2_SRC"
fetch_lua;        prepare_port "$LUA_SRC"
fetch_sdl2;       prepare_port "$SDL2_SRC"
fetch_sdl2_image; prepare_port "$SDL2_IMAGE_SRC"
fetch_sdl2_ttf;   prepare_port "$SDL2_TTF_SRC"
fetch_sdl2_mixer; prepare_port "$SDL2_MIXER_SRC"

# NDK r26+ 移除了 ALooper_pollAll，SDL 2.26.3 的传感器代码还在用；SDL 官方后续版本同样改成了 ALooper_pollOnce
sed -i 's/ALooper_pollAll(/ALooper_pollOnce(/' "$CMAKELISTS_PATH/thirdparty/port/SDL2-2.26.3/src/sensor/android/SDL_androidsensor.c"

# 让上游 Android 工程能用本机已装的 SDK/NDK 编译，只改构建参数，不改源码
python3 "$(dirname "$(readlink -f "$0")")/patch_upstream_gradle.py" "$WORK/up/src/onsyuri_android/app/build.gradle"
# Windows 宿主编译时需要 SDK 路径，通过 ANDROID_SDK_WIN 传入，例如 C:\\Users\\me\\AppData\\Local\\Android\\Sdk
if [ -n "${ANDROID_SDK_WIN:-}" ]; then
    printf 'sdk.dir=%s\n' "${ANDROID_SDK_WIN//\\/\\\\}" | sed 's/:/\\:/' > "$WORK/up/src/onsyuri_android/local.properties"
fi
echo "工作区已就绪: $WORK/up"
