#!/usr/bin/env bash
set -euo pipefail

# Watchman uninstaller

INSTALL_DIR="${WATCHMAN_INSTALL_DIR:-$HOME/.local/share/watchman}"
BIN_DIR="${WATCHMAN_BIN_DIR:-$HOME/.local/bin}"
CONFIG_DIR="$HOME/.config/watchman"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $1"; }
warn()  { echo -e "${YELLOW}==>${NC} $1"; }

echo ""
echo -e "${RED}  Watchman Uninstaller${NC}"
echo ""

read -rp "  Remove watchman? This deletes code, config, and database. [y/N] " answer

if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "  Cancelled."
  exit 0
fi

# Remove symlink
if [ -L "$BIN_DIR/wm" ]; then
  rm -f "$BIN_DIR/wm"
  info "Removed $BIN_DIR/wm"
fi

# Remove installation
if [ -d "$INSTALL_DIR" ]; then
  rm -rf "$INSTALL_DIR"
  info "Removed $INSTALL_DIR"
fi

# Ask about config and data
read -rp "  Also remove config (~/.config/watchman)? [y/N] " answer
if [[ "$answer" =~ ^[Yy]$ ]]; then
  rm -rf "$CONFIG_DIR"
  info "Removed $CONFIG_DIR"
fi

DB_PATH="$HOME/.local/share/watchman/watchman.db"
if [ -f "$DB_PATH" ]; then
  read -rp "  Also remove database ($DB_PATH)? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -f "$DB_PATH"*
    info "Removed database"
  fi
fi

echo ""
info "Watchman uninstalled."
