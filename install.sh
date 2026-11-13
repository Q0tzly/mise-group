#!/bin/bash
# Install the mise-group binary into ~/.local/bin and prepare the default
# groups directory.
#
#   ./install.sh              # download the latest release binary
#   MISE_GROUP_VERSION=v0.2.0 ./install.sh
#
# If the download is unavailable and a Go toolchain is present, the binary
# is built from this checkout instead. The recommended installation is via
# mise itself:  mise use -g "github:Q0tzly/mise-group@latest"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO="Q0tzly/mise-group"

triple() {
  local os arch
  case "$(uname -s)" in
    Darwin) os="apple-darwin" ;;
    Linux) os="unknown-linux-gnu" ;;
    *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
  esac
  case "$(uname -m)" in
    arm64|aarch64) arch="aarch64" ;;
    x86_64) arch="x86_64" ;;
    *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;;
  esac
  echo "$arch-$os"
}

install_bin() { # install_bin <path-to-binary>
  mkdir -p "$HOME/.local/bin"
  cp "$1" "$HOME/.local/bin/mise-group"
  chmod +x "$HOME/.local/bin/mise-group"
  echo "==> Installed $HOME/.local/bin/mise-group"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

version="${MISE_GROUP_VERSION:-}"
if [[ -z "$version" ]]; then
  version="$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | sed -nE 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' | head -n 1 || true)"
fi

done=0
if [[ -n "$version" ]]; then
  asset="mise-group-$version-$(triple).tar.gz"
  url="https://github.com/$REPO/releases/download/$version/$asset"
  echo "==> Downloading $asset"
  if curl -fsSL "$url" -o "$TMP/asset.tar.gz"; then
    tar xzf "$TMP/asset.tar.gz" -C "$TMP"
    bin="$(find "$TMP" -type f -name mise-group | head -n 1)"
    [[ -n "$bin" ]] && { install_bin "$bin"; done=1; }
  else
    echo "==> Download failed, falling back to a source build" >&2
  fi
fi

if [[ $done -eq 0 ]]; then
  command -v go >/dev/null || { echo "no release binary and no Go toolchain found" >&2; exit 1; }
  echo "==> Building from source"
  (cd "$ROOT" && go build -o "$TMP/mise-group" ./cmd/mise-group)
  install_bin "$TMP/mise-group"
fi

mkdir -p "$HOME/.config/mise/groups" "$HOME/.config/mise/conf.d"
echo "==> Groups directory: $HOME/.config/mise/groups"
echo "Done. Try: mise-group list"
