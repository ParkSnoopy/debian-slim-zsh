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

# Bun
#export BUN_INSTALL="$HOME/.bun"
#export PATH="$BUN_INSTALL/bin:$PATH"

# NodeJS
#export NVM_DIR="$HOME/.nvm"
#[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Rust
#export PATH="$PATH:$HOME/.cargo/env"

# GoLang
#export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"

# ====================

# Environment
export TZ="${TZ:-Asia/Seoul}"
export LANG="${LANG:-en_US.UTF-8}"
typeset -U path PATH
path=("$HOME/.local/bin" $path)

export TAR_OPTIONS="--no-same-owner"
