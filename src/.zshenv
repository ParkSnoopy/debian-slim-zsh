# Private API Keys

# uv
#export UV_LINK_MODE="copy"

# Flutter
#export PATH="$HOME/.flutter/bin:$PATH"
#export CHROME_EXECUTABLE="microsoft-edge"

# Android SDK
#export ANDROID_HOME="$HOME/.android-tools"
#export ANDROID_SDK_ROOT="$ANDROID_HOME"
#export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$PATH"

# Rust
#source "$HOME/.cargo/env"

# GoLang
#export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"

# ====================

# Open GUI App from Podman
#export GDK_BACKEND="wayland"
#export XDG_RUNTIME_DIR="/run/user/1000"
#export WAYLAND_DISPLAY="wayland-0"

# Environment
export TZ="${TZ:-Asia/Shanghai}"
export LANG="${LANG:-en_US.UTF-8}"
typeset -U path PATH
path=("$HOME/.local/bin" $path)

export TAR_OPTIONS="--no-same-owner"
