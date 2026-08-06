#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the license found in the
# LICENSE file in the root directory of this source tree.

# Install DAT SDK AI development config into your project.
# Usage:
#   ./install-skills.sh              # Interactive menu (when run with a tty)
#   ./install-skills.sh claude       # Claude Code plugin
#   ./install-skills.sh codex        # Codex plugin
#   ./install-skills.sh copilot      # GitHub Copilot only
#   ./install-skills.sh cursor       # Cursor only
#   ./install-skills.sh agents       # AGENTS.md only
#   ./install-skills.sh all          # All tools
#   curl -sL ...install-skills.sh | bash   # Defaults to "all" (no tty)

set -euo pipefail

REPO="facebook/meta-wearables-dat-ios"
BRANCH="main"
ARCHIVE_URL="https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz"
EXTRACT_DIR="meta-wearables-dat-ios-${BRANCH}"
PLUGIN_DIR="${EXTRACT_DIR}/plugins/mwdat-ios"

safe_cleanup() {
  if [ -z "${EXTRACT_DIR:-}" ]; then
    echo "Warning: EXTRACT_DIR is empty, skipping cleanup." >&2
    return 0
  fi
  if [[ ! "$EXTRACT_DIR" =~ ^meta-wearables-dat-ios- ]]; then
    echo "Warning: EXTRACT_DIR does not match expected pattern, skipping cleanup." >&2
    return 0
  fi
  if [ -d "$EXTRACT_DIR" ]; then
    rm -rf "$EXTRACT_DIR"
  fi
}
trap safe_cleanup EXIT

download_archive() {
  if [ ! -d "${EXTRACT_DIR}" ]; then
    curl -sL "$ARCHIVE_URL" | tar xz 2>/dev/null
  fi
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: '$1' is not installed or not on PATH." >&2
    return 1
  fi
}

install_claude() {
  echo "Installing Claude Code plugin for iOS..."
  require_command claude
  download_archive
  if [ -d "${PLUGIN_DIR}" ]; then
    claude plugin install "${PLUGIN_DIR}" || return 1
    echo "Installed Claude plugin from ${PLUGIN_DIR}."
  else
    echo "Error: Failed to download Claude plugin payload." >&2
    return 1
  fi
}

install_codex() {
  echo "Adding Codex marketplace for iOS..."
  require_command codex
  download_archive
  if [ -d "${EXTRACT_DIR}" ]; then
    codex plugin marketplace add "./${EXTRACT_DIR}" || return 1
    echo "Added Codex marketplace from ./${EXTRACT_DIR}."
  else
    echo "Error: Failed to download Codex marketplace payload." >&2
    return 1
  fi
}

install_copilot() {
  echo "Installing GitHub Copilot config for iOS..."
  download_archive
  if [ -d "${EXTRACT_DIR}/.github" ]; then
    mkdir -p .github
    cp -R "${EXTRACT_DIR}/.github/." .github/
    echo "Installed .github/copilot-instructions.md."
  else
    echo "Error: Failed to download .github/ config." >&2
    return 1
  fi
}

install_cursor() {
  echo "Installing Cursor config for iOS..."
  download_archive
  if [ -d "${EXTRACT_DIR}/.cursor" ]; then
    mkdir -p .cursor
    cp -R "${EXTRACT_DIR}/.cursor/." .cursor/
    echo "Installed .cursor/rules/ with $(find .cursor -name '*.mdc' | wc -l | tr -d ' ') files."
  else
    echo "Error: Failed to download .cursor/ config." >&2
    return 1
  fi
}

install_agents() {
  echo "Installing AGENTS.md..."
  download_archive
  if [ -f "${EXTRACT_DIR}/AGENTS.md" ]; then
    cp "${EXTRACT_DIR}/AGENTS.md" AGENTS.md
    echo "Installed AGENTS.md"
  else
    echo "Error: Failed to download AGENTS.md." >&2
    return 1
  fi
}

install_all() {
  local failed=0
  if command -v claude >/dev/null 2>&1; then
    install_claude || failed=1
  else
    echo "Skipping Claude Code plugin install because 'claude' is not on PATH."
  fi
  if command -v codex >/dev/null 2>&1; then
    install_codex || failed=1
  else
    echo "Skipping Codex marketplace install because 'codex' is not on PATH."
  fi
  install_copilot || failed=1
  install_cursor || failed=1
  install_agents || failed=1
  if [ "$failed" -eq 1 ]; then
    return 1
  fi
}

show_menu() {
  echo ""
  echo "DAT SDK AI Config Installer (iOS)"
  echo "================================="
  echo ""
  echo "Which tool do you want to install config for?"
  echo ""
  echo "  1) Claude Code plugin"
  echo "  2) Codex plugin"
  echo "  3) GitHub Copilot (.github/)"
  echo "  4) Cursor         (.cursor/)"
  echo "  5) AGENTS.md      (universal fallback)"
  echo "  6) All supported tools"
  echo "  7) Cancel"
  echo ""
  read -rp "Enter choice [1-7]: " choice
  case "$choice" in
    1) install_claude ;;
    2) install_codex ;;
    3) install_copilot ;;
    4) install_cursor ;;
    5) install_agents ;;
    6) install_all ;;
    7) echo "Cancelled." ; exit 0 ;;
    *) echo "Invalid choice." >&2 ; exit 1 ;;
  esac
}

# Main
TOOL="${1:-}"

if [ -n "$TOOL" ]; then
  case "$TOOL" in
    claude)  install_claude ;;
    codex)   install_codex ;;
    copilot) install_copilot ;;
    cursor)  install_cursor ;;
    agents)  install_agents ;;
    all)     install_all ;;
    *)       echo "Unknown tool: $TOOL. Use: claude, codex, copilot, cursor, agents, or all." >&2 ; exit 1 ;;
  esac
elif [ -t 0 ]; then
  show_menu
else
  # Piped via curl — default to all for backward compatibility
  install_all
fi

echo ""
echo "Install complete."
