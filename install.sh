#!/usr/bin/env bash
# ================================================================
#  PerfGuard Installer
#  Run: curl -fsSL https://raw.githubusercontent.com/YOU/perfguard/main/install.sh | bash
# ================================================================

set -euo pipefail

INSTALL_DIR="/usr/local/bin"
SCRIPT_NAME="perfguard"
REPO_RAW="https://raw.githubusercontent.com/YOU/perfguard/main/perfguard.sh"
CONFIG_DIR="$HOME/.perfguard"

R="\033[0m"
B="\033[1m"
D="\033[2m"
C1="\033[38;5;39m"
C2="\033[38;5;82m"
C3="\033[38;5;220m"
C4="\033[38;5;196m"

header() {
  echo ""
  printf "  ${C1}${B}PerfGuard Installer${R}\n"
  printf "  ${D}────────────────────────────────────────${R}\n\n"
}

step() { printf "  ${C1}→${R}  %s\n" "$1"; }
ok()   { printf "  ${C2}✓${R}  %s\n" "$1"; }
warn() { printf "  ${C3}!${R}  %s\n" "$1"; }
fail() { printf "  ${C4}✗${R}  %s\n" "$1"; exit 1; }

header

# ── Check macOS ──────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  fail "PerfGuard requires macOS."
fi

ok "macOS detected: $(sw_vers -productVersion)"

# ── Check dependencies ───────────────────────────────────────────
for dep in bash bc awk ps sysctl vm_stat; do
  if ! command -v "$dep" &>/dev/null; then
    warn "Missing: $dep — some features may not work"
  fi
done

# ── Download ─────────────────────────────────────────────────────
step "Downloading perfguard..."

TMP_FILE=$(mktemp)
if command -v curl &>/dev/null; then
  curl -fsSL "$REPO_RAW" -o "$TMP_FILE" || fail "Download failed. Check your internet connection."
elif command -v wget &>/dev/null; then
  wget -qO "$TMP_FILE" "$REPO_RAW" || fail "Download failed."
else
  fail "curl or wget required."
fi

ok "Downloaded successfully"

# ── Install ──────────────────────────────────────────────────────
step "Installing to ${INSTALL_DIR}/${SCRIPT_NAME}..."

if [[ ! -w "$INSTALL_DIR" ]]; then
  warn "Needs sudo to write to ${INSTALL_DIR}"
  sudo mv "$TMP_FILE" "${INSTALL_DIR}/${SCRIPT_NAME}"
  sudo chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
else
  mv "$TMP_FILE" "${INSTALL_DIR}/${SCRIPT_NAME}"
  chmod +x "${INSTALL_DIR}/${SCRIPT_NAME}"
fi

ok "Installed to ${INSTALL_DIR}/${SCRIPT_NAME}"

# ── Config directory ─────────────────────────────────────────────
step "Setting up config directory..."
mkdir -p "$CONFIG_DIR"
touch "$CONFIG_DIR/whitelist" "$CONFIG_DIR/perfguard.log"
ok "Config at ~/.perfguard/"

# ── Shell integration ────────────────────────────────────────────
# Ensure /usr/local/bin is in PATH for common shells
for rc in "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.bashrc"; do
  if [[ -f "$rc" ]]; then
    if ! grep -q '/usr/local/bin' "$rc" 2>/dev/null; then
      echo 'export PATH="/usr/local/bin:$PATH"' >> "$rc"
      ok "Added /usr/local/bin to PATH in $(basename "$rc")"
    fi
  fi
done

# ── Verify ───────────────────────────────────────────────────────
if command -v perfguard &>/dev/null || [[ -x "${INSTALL_DIR}/${SCRIPT_NAME}" ]]; then
  ok "Verified: perfguard is executable"
else
  warn "Could not verify — try opening a new terminal"
fi

# ── Done ─────────────────────────────────────────────────────────
echo ""
printf "  ${C2}${B}Installation complete.${R}\n\n"
printf "  ${D}Usage:${R}\n"
printf "    ${B}perfguard${R}           ${D}Open interactive menu${R}\n"
printf "    ${B}perfguard status${R}    ${D}Quick system overview${R}\n"
printf "    ${B}perfguard turbo${R}     ${D}Full optimization sequence${R}\n"
printf "    ${B}perfguard help${R}      ${D}All commands${R}\n"
echo ""
printf "  ${D}Open a new terminal window or run:${R}\n"
printf "    ${B}source ~/.zshrc${R}  ${D}(or your shell's rc file)${R}\n"
echo ""
printf "  ${C1}${B}Run ${R}${B}perfguard${C1} to get started.${R}\n\n"
