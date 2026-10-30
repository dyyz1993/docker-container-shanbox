#!/usr/bin/env bash
# 重工具链外挂引导：Android SDK + Flutter 装在外挂卷 /opt/tools，首次启动自动安装（国内源），之后跳过
# 幂等：以 ok 标记文件判断；后台执行，不阻塞 runner 上线
set -uo pipefail
LOG=/tmp/bootstrap-tools.log
TOOLS=/opt/tools
ANDROID_HOME="${ANDROID_HOME:-$TOOLS/android-sdk}"
FLUTTER_DIR="$TOOLS/flutter"
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.8}"
ANDROID_BUILD_TOOLS="${ANDROID_BUILD_TOOLS:-36.0.0}"
ANDROID_PLATFORM="${ANDROID_PLATFORM:-android-36}"
STORAGE_BASE="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

log() { echo "[$(date '+%F %T')] $*" >> "$LOG"; }

mkdir -p "$TOOLS"

# ---------- Android SDK ----------
if [[ ! -f "$ANDROID_HOME/ok" ]]; then
  log "bootstrapping Android SDK -> $ANDROID_HOME"
  mkdir -p "$ANDROID_HOME/cmdline-tools"
  T=$(mktemp -d)
  if curl -fsSL "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip" -o "$T/ct.zip" \
     || curl -fsSL "https://mirrors.cloud.tencent.com/AndroidSDK/commandlinetools-linux-11076708_latest.zip" -o "$T/ct.zip"; then
    unzip -q "$T/ct.zip" -d "$T/x" && mv "$T/x/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest" && rm -rf "$T"
    (yes | "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" --licenses >/dev/null 2>&1) || true
    "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$ANDROID_HOME" \
      "platform-tools" "platforms;${ANDROID_PLATFORM}" "build-tools;${ANDROID_BUILD_TOOLS}" >> "$LOG" 2>&1 \
      && chown -R 1001:1001 "$ANDROID_HOME" \
      && touch "$ANDROID_HOME/ok" && log "Android SDK ready" \
      || log "Android SDK install FAILED (will retry next boot)"
  else
    log "cmdline-tools download FAILED (dl.google.com + tencent mirror)"
  fi
fi

# ---------- Flutter ----------
if [[ ! -f "$FLUTTER_DIR/ok" ]]; then
  log "bootstrapping Flutter $FLUTTER_VERSION -> $FLUTTER_DIR"
  T=$(mktemp -d)
  if curl -fsSL "${STORAGE_BASE}/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o "$T/f.tar.xz" \
     && tar -xJf "$T/f.tar.xz" -C "$TOOLS" && rm -rf "$T"; then
    echo "$FLUTTER_VERSION" > "$FLUTTER_DIR/ok"
    chown -R 1001:1001 "$FLUTTER_DIR"
    git config --system --add safe.directory "$FLUTTER_DIR"
    log "Flutter extracted; precache android artifacts"
    HOME="$TOOLS" git config --global --add safe.directory "$FLUTTER_DIR" 2>/dev/null || true
    sudo -u \#1001 env HOME=/home/runner PUB_CACHE=/home/runner/.pub-cache \
      "$FLUTTER_DIR/bin/flutter" precache --android >> "$LOG" 2>&1 \
      && log "Flutter ready" || log "precache failed (flutter usable, artifacts lazy-download)"
  else
    log "Flutter download FAILED ($STORAGE_BASE)"
    rm -rf "$T"
  fi
fi

log "bootstrap pass done"
