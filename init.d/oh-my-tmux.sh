#!/bin/env bash
set -euo pipefail

sudo apt install -y git gnu-which tmux zsh

# Setup oh-my-tmux
sudo chsh -s "$(which zsh)" "$(id -un)"
cd "$HOME"
git clone --single-branch https://github.com/gpakosz/.tmux.git
ln -s -f .tmux/.tmux.conf
cp .tmux/.tmux.conf.local .
