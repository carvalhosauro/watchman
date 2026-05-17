#!/usr/bin/env bash
set -euo pipefail

# Watchman installer
# Usage: curl -fsSL https://raw.githubusercontent.com/OWNER/watchman/main/install.sh | bash

REPO="https://github.com/OWNER/watchman.git"
INSTALL_DIR="${WATCHMAN_INSTALL_DIR:-$HOME/.local/share/watchman}"
BIN_DIR="${WATCHMAN_BIN_DIR:-$HOME/.local/bin}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}==>${NC} $1"; }
ok()    { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}==>${NC} $1"; }
fail()  { echo -e "${RED}==>${NC} $1"; exit 1; }

header() {
  echo ""
  echo -e "${GREEN}"
  echo "  ┌─────────────────────────────┐"
  echo "  │   Watchman Installer        │"
  echo "  └─────────────────────────────┘"
  echo -e "${NC}"
}

# --- Checks ---

check_command() {
  command -v "$1" &>/dev/null
}

check_elixir() {
  if check_command elixir; then
    local version
    version=$(elixir --version 2>&1 | grep "Elixir" | awk '{print $2}')
    ok "Elixir $version found"
    return 0
  fi
  return 1
}

check_erlang() {
  if check_command erl; then
    ok "Erlang/OTP found"
    return 0
  fi
  return 1
}

check_git() {
  if check_command git; then
    return 0
  fi
  fail "git is required. Install it first."
}

install_elixir_prompt() {
  warn "Elixir not found."
  echo ""
  echo "  Install options:"
  echo "    1) mise  — curl https://mise.run | sh && mise use -g elixir"
  echo "    2) asdf  — asdf plugin add elixir && asdf install elixir latest"
  echo "    3) apt   — sudo apt install elixir erlang-dev (Debian/Ubuntu)"
  echo "    4) brew  — brew install elixir (macOS)"
  echo ""
  echo "  After installing Elixir, re-run this script."
  exit 1
}

# --- Install ---

clone_or_update() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing installation..."
    git -C "$INSTALL_DIR" pull --ff-only
  else
    if [ -d "$INSTALL_DIR" ]; then
      warn "$INSTALL_DIR exists but is not a git repo. Backing up..."
      mv "$INSTALL_DIR" "${INSTALL_DIR}.bak.$(date +%s)"
    fi
    info "Cloning watchman..."
    git clone --depth 1 "$REPO" "$INSTALL_DIR"
  fi
}

install_deps() {
  info "Installing dependencies..."
  cd "$INSTALL_DIR"
  mix local.hex --force --if-missing >/dev/null 2>&1
  mix local.rebar --force --if-missing >/dev/null 2>&1
  mix deps.get --only prod >/dev/null 2>&1
  MIX_ENV=prod mix compile >/dev/null 2>&1
  ok "Dependencies installed"
}

create_symlink() {
  mkdir -p "$BIN_DIR"

  local target="$INSTALL_DIR/bin/wm"
  local link="$BIN_DIR/wm"

  if [ -L "$link" ] || [ -e "$link" ]; then
    rm -f "$link"
  fi

  ln -s "$target" "$link"
  ok "Symlink created: $link -> $target"

  # Check if BIN_DIR is in PATH
  if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    warn "$BIN_DIR is not in your PATH"
    echo ""
    echo "  Add to your shell config:"
    echo ""
    if [ -f "$HOME/.zshrc" ]; then
      echo "    echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.zshrc"
      echo "    source ~/.zshrc"
    else
      echo "    echo 'export PATH=\"$BIN_DIR:\$PATH\"' >> ~/.bashrc"
      echo "    source ~/.bashrc"
    fi
    echo ""
  fi
}

run_setup() {
  echo ""
  read -rp "  Run initial setup now? [Y/n] " answer
  answer=${answer:-Y}

  if [[ "$answer" =~ ^[Yy]$ ]]; then
    cd "$INSTALL_DIR"
    mix run -e "Watchman.Setup.run()"
  else
    info "Skip setup. Run later: wm setup"
  fi
}

# --- Main ---

main() {
  header
  check_git
  check_erlang  || install_elixir_prompt
  check_elixir  || install_elixir_prompt
  clone_or_update
  install_deps
  create_symlink

  ok "Watchman installed!"
  echo ""
  echo "  Commands:"
  echo "    wm setup              Configure API keys and providers"
  echo "    wm assets TICKER...   Register assets to track"
  echo "    wm run                Run daily analysis"
  echo "    wm show               View results"
  echo ""

  run_setup
}

main "$@"
