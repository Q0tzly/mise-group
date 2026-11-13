#!/bin/bash
# Link mise-group into PATH and prepare the default groups directory.
#   ./install.sh
# The groups directory itself is yours: put <group>.toml files in
# ~/.config/mise/groups (or point MISE_GROUPS_DIR elsewhere, e.g. at the
# mise/groups directory of a dotfiles repo).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

link() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [[ -L "$dst" && "$(readlink "$dst")" == "$src" ]]; then
    return
  fi
  if [[ -e "$dst" || -L "$dst" ]]; then
    mv "$dst" "$dst.bak.$(date +%Y%m%d%H%M%S)"
    echo "==> Backed up existing $dst"
  fi
  ln -s "$src" "$dst"
  echo "==> Linked $dst"
}

link "$ROOT/bin/mise-group" "$HOME/.local/bin/mise-group"
mkdir -p "$HOME/.config/mise/groups" "$HOME/.config/mise/conf.d"
echo "==> Groups directory: $HOME/.config/mise/groups"
echo "Done. Try: mise-group list"
