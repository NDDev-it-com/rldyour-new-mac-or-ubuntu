#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/common.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../lib/common.sh"

RLDYOUR_DRY_RUN="${RLDYOUR_DRY_RUN:-1}"
PROFILE="${RLDYOUR_PROFILE:-server}"
STRICT="${RLDYOUR_STRICT:-0}"
SKIP_SYSTEM="${RLDYOUR_SKIP_SYSTEM:-0}"
SKIP_AI="${RLDYOUR_SKIP_AI:-0}"
SKIP_LSPS="${RLDYOUR_SKIP_LSPS:-0}"
SKIP_BROWSER="${RLDYOUR_SKIP_BROWSER:-0}"
SKIP_CHECKS="${RLDYOUR_SKIP_CHECKS:-0}"

CLAUDE_CODE_VERSION="2.1.204"
CODEX_VERSION="0.142.5"
OPENCODE_VERSION="1.17.15"
MIMOCODE_VERSION="0.1.4"
ANTIGRAVITY_INSTALL_SCRIPT="https://antigravity.google/cli/install.sh"
MARKSMAN_VERSION="${MARKSMAN_VERSION:-2026-02-08}"
MARKSMAN_REPOSITORY="${MARKSMAN_REPOSITORY:-artempyanykh/marksman}"

# The `pyright` package ships both `pyright` and `pyright-langserver` console
# scripts; there is no separate `pyright-langserver` distribution to install.
PYTHON_TOOLING_PACKAGES=(
  pyright
  ruff
  pytest
  # macOS-parity LSPs that ship as Python wheels (0.2.8):
  # `ty` (Astral type-checker) and the CMake language server.
  ty
  cmake-language-server
)

# taplo ships as the npm `@taplo/cli` package (bare `taplo` is unpublished);
# marksman is not on npm and is installed from its pinned GitHub release below.
# vtsls replaces typescript-language-server as the recommended TS/JS LSP.
BUN_LSP_PACKAGES=(
  typescript
  "@vtsls/language-server"
  yaml-language-server
  bash-language-server
  dockerfile-language-server-nodejs
  vscode-langservers-extracted
  "@taplo/cli"
  gh-actions-language-server
)

# Bun-global quality-gate and formatter CLIs that are not well packaged via apt.
# These extend the LSP/runtime baseline with multi-language linting and SAST.
BUN_QUALITY_PACKAGES=(
  biome
  oxlint
  markdownlint-cli2
  prettier
  "@ansible/language-server"
)

APT_SYSTEM_PACKAGES=(
  ca-certificates
  build-essential
  curl
  gpg
  git
  jq
  python3
  python3-pip
  shellcheck
  shfmt
  clang
  clangd
  cmake
  golang-go
  unzip
  wget
  zip
  gnupg
  lsb-release
  yamllint
  pandoc
  fd-find
  bat
  xmlstarlet
  libxml2-utils
  # terminal layer (0.2.3): apt-available subset
  fzf
  zoxide
  tmux
  btop
  duf
  hexyl
  gh
  # macOS-parity, apt-available (0.2.8): search, http, data, Qt headers
  ripgrep
  httpie
  miller
  qtbase5-dev
)

APT_GOPLS_PACKAGE="gopls"

usage() {
  cat <<'EOF'
Usage: scripts/ubuntu/install.sh

Entrypoint for Ubuntu/server profile. This script is usually executed via
scripts/bootstrap.sh. It defaults to dry-run mode and supports strict checks
and skip flags.
EOF
}

apt_with_retries() {
  local -a cmd=(sudo -E DEBIAN_FRONTEND=noninteractive apt-get "$@")
  rldyour::run "${cmd[@]}"
}

ensure_apt_repo_updates() {
  rldyour::run sudo apt-get update
}

ensure_apt_packages() {
  rldyour::section "Install baseline apt packages"
  apt_with_retries install -y "${APT_SYSTEM_PACKAGES[@]}"
}

# `eza` is in Debian 13 / Ubuntu 24.10+ archives but not in older LTS ones;
# treat it as best-effort so the baseline never fails on supported LTS hosts.
ensure_eza() {
  rldyour::section "Ensure eza (best-effort on older LTS)"
  if command -v eza >/dev/null 2>&1; then
    rldyour::log "ok" "eza already installed"
    return 0
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] apt-get install -y eza"
    return 0
  fi
  if sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y eza; then
    rldyour::log "ok" "eza installed via apt"
  else
    rldyour::log "warn" "eza not available in this apt archive; skipping (best-effort)"
  fi
}


# Terminal layer (0.2.3): official installers for tools without reliable
# apt packages on supported LTS; every step is dry-run aware and idempotent.
ensure_starship() {
  rldyour::section "Ensure starship prompt"
  if command -v starship >/dev/null 2>&1; then
    rldyour::log "ok" "starship already installed"
    return 0
  fi
  rldyour::run bash -c "curl -sS https://starship.rs/install.sh | sh -s -- -y"
}

ensure_atuin() {
  rldyour::section "Ensure atuin history"
  if command -v atuin >/dev/null 2>&1; then
    rldyour::log "ok" "atuin already installed"
    return 0
  fi
  rldyour::run bash -c "curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh"
}

ensure_xh() {
  rldyour::section "Ensure xh HTTP client"
  if command -v xh >/dev/null 2>&1; then
    rldyour::log "ok" "xh already installed"
    return 0
  fi
  rldyour::run bash -c "curl -sfL https://raw.githubusercontent.com/ducaale/xh/master/install.sh | sh"
}

ensure_antidote_clone() {
  rldyour::section "Ensure antidote plugin manager (git clone)"
  if [ -d "$HOME/.antidote" ]; then
    rldyour::log "ok" "antidote already cloned"
    return 0
  fi
  rldyour::run git clone --depth=1 https://github.com/mattmc3/antidote.git "$HOME/.antidote"
}

ensure_node() {
  rldyour::section "Ensure Node.js (>=22)"
  if command -v node >/dev/null 2>&1; then
    if rldyour::require_cmd_min_version node 22 "--version"; then
      rldyour::log "ok" "node already available: $(node --version)"
      return 0
    fi
  fi
  rldyour::run bash -c "curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -"
  rldyour::run sudo apt-get install -y nodejs
}

ensure_uv() {
  rldyour::section "Install uv toolchain"
  if command -v uv >/dev/null 2>&1; then
    rldyour::log "ok" "uv already installed: $(uv --version)"
    return 0
  fi
  rldyour::run bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
}

ensure_bun() {
  rldyour::section "Install bun runtime"
  if command -v bun >/dev/null 2>&1; then
    rldyour::log "ok" "bun already installed: $(bun --version)"
    return 0
  fi
  rldyour::run bash -c "curl -fsSL https://bun.sh/install | bash"
}

ensure_rust() {
  rldyour::section "Install Rust toolchain"
  if command -v rustup >/dev/null 2>&1; then
    rldyour::log "ok" "rustup already installed"
  else
    rldyour::run bash -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 0 ] && [ -f "$HOME/.cargo/env" ]; then
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 0 ]; then
    rldyour::run rustup component add rust-src rust-analyzer
  fi
}

ensure_dart() {
  rldyour::section "Install Dart (SDK)"
  if command -v dart >/dev/null 2>&1; then
    rldyour::log "ok" "dart already installed"
    return 0
  fi

  rldyour::run bash -c "sudo mkdir -p /usr/share/keyrings"
  rldyour::run bash -c "curl -fsSL https://dl-ssl.google.com/linux/linux_signing_key.pub | gpg --dearmor | sudo tee /usr/share/keyrings/dart-archive-keyring.gpg > /dev/null"
  rldyour::run bash -c "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/dart-archive-keyring.gpg] https://storage.googleapis.com/download.dartlang.org/linux/debian stable main\" | sudo tee /etc/apt/sources.list.d/dart_stable.list"
  rldyour::run sudo apt-get update
  rldyour::run sudo apt-get install -y dart
}

install_ai_runtimes() {
  rldyour::section "Install AI runtimes (pinned)"
  if ! command -v bun >/dev/null 2>&1; then
    if [ "$STRICT" -eq 1 ]; then
      rldyour::log "error" "bun is required for AI runtime install"
      exit 1
    fi
    rldyour::log "warn" "skip AI runtime install until bun is available"
    return 0
  fi

  if command -v claude-code >/dev/null 2>&1; then
    rldyour::log "ok" "claude-code already present"
  elif command -v claude >/dev/null 2>&1; then
    rldyour::log "ok" "claude already present (treated as claude-code-compatible entrypoint)"
  else
    rldyour::run bun add -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"
  fi

  if ! command -v codex >/dev/null 2>&1; then
    rldyour::run bun add -g "@openai/codex@${CODEX_VERSION}"
  else
    rldyour::log "ok" "codex already present"
  fi

  if ! command -v opencode >/dev/null 2>&1; then
    rldyour::run bun add -g "opencode-ai@${OPENCODE_VERSION}"
  else
    rldyour::log "ok" "opencode already present"
  fi

  if ! command -v agy >/dev/null 2>&1; then
    rldyour::run bash -c "curl -fsSL ${ANTIGRAVITY_INSTALL_SCRIPT} | bash"
  else
    rldyour::log "ok" "antigravity agy already present"
  fi

  if ! command -v mimo >/dev/null 2>&1; then
    rldyour::run bun add -g "@mimo-ai/cli@${MIMOCODE_VERSION}"
  else
    rldyour::log "ok" "mimo already present"
  fi
}

install_python_tooling() {
  rldyour::section "Install Python tooling"
  if ! command -v uv >/dev/null 2>&1; then
    if [ "$STRICT" -eq 1 ]; then
      rldyour::log "error" "uv is required for Python tooling"
      exit 1
    fi
    rldyour::log "warn" "skip Python tooling until uv is available"
    return 0
  fi
  for pkg in "${PYTHON_TOOLING_PACKAGES[@]}"; do
    if uv tool list | grep -q "^$pkg"; then
      rldyour::log "ok" "$pkg already managed by uv"
    else
      rldyour::run uv tool install --upgrade "$pkg"
    fi
  done
}

install_go_lsp() {
  rldyour::section "Install Go language server"
  if command -v gopls >/dev/null 2>&1; then
    rldyour::log "ok" "gopls already available"
    return 0
  fi
  rldyour::run sudo apt-get install -y "$APT_GOPLS_PACKAGE"
}

# Install the extended Homebrew/Go/R-packaged LSPs that mirror the macOS
# baseline: Supabase postgres-language-server, sqls (multi-DB), and the R
# languageserver. Each is best-effort on Ubuntu because the runtime may not yet
# be present when this runs in plan mode.
ensure_extended_lsps() {
  rldyour::section "Install extended SQL / R LSPs (best-effort)"

  if command -v sqls >/dev/null 2>&1; then
    rldyour::log "ok" "sqls already installed"
  elif command -v go >/dev/null 2>&1; then
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] go install github.com/sqls-server/sqls@latest"
    else
      rldyour::run go install github.com/sqls-server/sqls@latest
    fi
  else
    rldyour::log "warn" "go required for sqls; skipping"
  fi

  if command -v R >/dev/null 2>&1; then
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] R install.packages('languageserver')"
    elif R -q -e 'library(languageserver)' >/dev/null 2>&1; then
      rldyour::log "ok" "R languageserver already installed"
    else
      rldyour::run R -e 'ncpus <- parallel::detectCores(); ncpus <- if (is.na(ncpus) || ncpus < 1) 1 else ncpus; install.packages("languageserver", repos="https://cloud.r-project.org", Ncpus=ncpus)'
    fi
  else
    rldyour::log "warn" "R runtime required for languageserver; skipping"
  fi
}

# Install bun-global quality-gate CLIs that are not packaged via apt on Ubuntu.
install_quality_packages() {
  rldyour::section "Install bun-global quality CLIs"
  if ! command -v bun >/dev/null 2>&1; then
    rldyour::log "warn" "bun required for quality CLIs; skipping"
    return 0
  fi
  for pkg in "${BUN_QUALITY_PACKAGES[@]}"; do
    rldyour::run bun add -g "$pkg"
  done
}

# Install the SAST/secret/dependency scanners that verify.sh requires but apt
# does not ship. Each scanner is installed via the channel its upstream publishes
# (uv tool, pipx, go install, or the official install script). All best-effort:
# a missing channel only logs a warning and does not abort the bootstrap.
install_security_scanners() {
  rldyour::section "Install security/quality scanners (verify.sh required)"

  # basedpyright ships as a Python wheel; uv tool gives an isolated install.
  if command -v basedpyright >/dev/null 2>&1; then
    rldyour::log "ok" "basedpyright already on PATH"
  elif command -v uv >/dev/null 2>&1; then
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] uv tool install basedpyright"
    else
      rldyour::run uv tool install basedpyright
    fi
  else
    rldyour::log "warn" "uv required for basedpyright; skipping"
  fi

  # osv-scanner ships a binary install script from Google.
  if command -v osv-scanner >/dev/null 2>&1; then
    rldyour::log "ok" "osv-scanner already on PATH"
  else
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] osv-scanner install script"
    else
      mkdir -p "$HOME/.local/bin"
      rldyour::run bash -c "curl -sSfL https://raw.githubusercontent.com/google/osv-scanner/main/install.sh | bash -s -- -b $HOME/.local/bin"
    fi
  fi

  # gitleaks ships a binary install script from GitHub.
  if command -v gitleaks >/dev/null 2>&1; then
    rldyour::log "ok" "gitleaks already on PATH"
  else
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] gitleaks install script"
    else
      mkdir -p "$HOME/.local/bin"
      rldyour::run bash -c "curl -sSfL https://raw.githubusercontent.com/gitleaks/gitleaks/master/install.sh | bash -s -- -b $HOME/.local/bin"
    fi
  fi

  # semgrep ships as a Python wheel.
  if command -v semgrep >/dev/null 2>&1; then
    rldyour::log "ok" "semgrep already on PATH"
  elif command -v pip3 >/dev/null 2>&1; then
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] pip3 install --user semgrep"
    else
      rldyour::run pip3 install --user semgrep
    fi
  else
    rldyour::log "warn" "pip3 required for semgrep; skipping"
  fi

  # hadolint ships a static binary on GitHub.
  if command -v hadolint >/dev/null 2>&1; then
    rldyour::log "ok" "hadolint already on PATH"
  else
    local arch asset
    case "$(uname -m)" in
      x86_64 | amd64) arch="x86_64" ;;
      aarch64 | arm64) arch="arm64" ;;
      *)
        rldyour::log "warn" "unsupported arch for hadolint; skipping"
        arch=""
        ;;
    esac
    if [ -n "$arch" ]; then
      if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
        rldyour::log "info" "[DRY-RUN] hadolint binary -> ~/.local/bin"
      else
        asset="hadolint-Linux-${arch}"
        mkdir -p "$HOME/.local/bin"
        if curl -fsSL "https://github.com/hadolint/hadolint/releases/latest/download/${asset}" -o "$HOME/.local/bin/hadolint"; then
          chmod +x "$HOME/.local/bin/hadolint"
          rldyour::log "ok" "hadolint installed -> ~/.local/bin/hadolint"
        else
          rldyour::log "warn" "hadolint download failed (best-effort)"
        fi
      fi
    fi
  fi

  # actionlint ships a binary install script from rhysd.
  if command -v actionlint >/dev/null 2>&1; then
    rldyour::log "ok" "actionlint already on PATH"
  else
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] actionlint install script"
    else
      mkdir -p "$HOME/.local/bin"
      rldyour::run bash -c "curl -sSfL https://raw.githubusercontent.com/rhysd/actionlint/main/scripts/download-actionlint.bash | bash -s -- -o $HOME/.local/bin/actionlint"
    fi
  fi
}

# Install the JDK and R runtime baselines required by jdtls/Kotlin LSP and the R
# language server respectively. Ubuntu has good apt coverage for both.
ensure_java_and_r() {
  rldyour::section "Ensure JDK and R runtimes"
  if command -v java >/dev/null 2>&1; then
    rldyour::log "ok" "java already available: $(java -version 2>&1 | head -n 1)"
  else
    rldyour::run sudo apt-get install -y default-jdk
  fi
  if command -v R >/dev/null 2>&1; then
    rldyour::log "ok" "R already available: $(R --version 2>&1 | head -n 1)"
  else
    rldyour::run sudo apt-get install -y r-base
  fi
}

# Install the macOS-parity "modern-unix" CLI wave that has no reliable apt
# package on supported LTS. Each is a Rust binary from crates.io, so cargo is the
# single portable channel. Best-effort and idempotent: a present binary is
# skipped and a failed build only warns (never aborts the bootstrap).
# NOTE: gitlab-ci-ls is intentionally NOT installed (the owner does not use
# GitLab); it was removed in 0.2.8 to match the macOS baseline.
CARGO_PARITY_TOOLS=(
  # crate:binary
  "du-dust:dust"
  "procs:procs"
  "sd:sd"
  "difftastic:difft"
  "jaq:jaq"
  "hyperfine:hyperfine"
  "just:just"
  "tealdeer:tldr"
  "ast-grep:ast-grep"
  "watchexec-cli:watchexec"
  "gping:gping"
  "cargo-nextest:cargo-nextest"
  # markdown LSP parity (macOS installs markdown-oxide via brew)
  "markdown-oxide:markdown-oxide"
)

ensure_cargo_parity_tools() {
  rldyour::section "Install cargo-hosted macOS-parity CLIs (best-effort)"
  if ! command -v cargo >/dev/null 2>&1; then
    rldyour::log "warn" "cargo required for parity CLIs; skipping"
    return 0
  fi
  local entry crate bin
  for entry in "${CARGO_PARITY_TOOLS[@]}"; do
    crate="${entry%%:*}"
    bin="${entry##*:}"
    if command -v "$bin" >/dev/null 2>&1; then
      rldyour::log "ok" "$bin already installed"
      continue
    fi
    if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
      rldyour::log "info" "[DRY-RUN] cargo install $crate"
      continue
    fi
    if cargo install "$crate"; then
      rldyour::log "ok" "$bin installed via cargo ($crate)"
    else
      rldyour::log "warn" "cargo install $crate failed (best-effort)"
    fi
  done
}

# Install macOS-parity runtimes/tools that publish an official install script or
# a first-party apt channel. All best-effort and idempotent.
ensure_extra_runtimes() {
  rldyour::section "Install extra macOS-parity runtimes (best-effort)"

  # Deno JS/TS runtime (official installer -> ~/.deno/bin).
  if command -v deno >/dev/null 2>&1; then
    rldyour::log "ok" "deno already installed"
  elif [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] deno install script"
  else
    rldyour::run bash -c "curl -fsSL https://deno.land/install.sh | sh -s -- -y" ||
      rldyour::log "warn" "deno install failed (best-effort)"
  fi

  # mise version manager (official installer -> ~/.local/bin).
  if command -v mise >/dev/null 2>&1; then
    rldyour::log "ok" "mise already installed"
  elif [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] mise install script"
  else
    rldyour::run bash -c "curl -fsSL https://mise.run | sh" ||
      rldyour::log "warn" "mise install failed (best-effort)"
  fi

  # carapace completion engine (official install script -> ~/.local/bin).
  if command -v carapace >/dev/null 2>&1; then
    rldyour::log "ok" "carapace already installed"
  elif [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] carapace install script"
  else
    rldyour::run bash -c "curl -fsSL https://carapace.sh/install.sh | sh -s -- -b $HOME/.local/bin" ||
      rldyour::log "warn" "carapace install failed (best-effort)"
  fi
}

ensure_marksman() {
  rldyour::section "Install marksman markdown LSP (pinned GitHub release)"
  if command -v marksman >/dev/null 2>&1; then
    rldyour::log "ok" "marksman already available"
    return 0
  fi
  local arch asset dest
  case "$(uname -m)" in
    x86_64 | amd64) arch="x64" ;;
    aarch64 | arm64) arch="arm64" ;;
    *)
      rldyour::log "warn" "unknown arch $(uname -m); skipping marksman"
      return 0
      ;;
  esac
  asset="marksman-linux-${arch}"
  dest="$HOME/.local/bin/marksman"
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] download ${MARKSMAN_REPOSITORY}@${MARKSMAN_VERSION} ${asset} -> ${dest}"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL "https://github.com/${MARKSMAN_REPOSITORY}/releases/download/${MARKSMAN_VERSION}/${asset}" -o "$dest"; then
    chmod +x "$dest"
    rldyour::log "ok" "marksman ${MARKSMAN_VERSION} installed -> ${dest}"
  elif [ "$STRICT" -eq 1 ]; then
    rldyour::log "error" "marksman download failed"
    exit 1
  else
    rldyour::log "warn" "marksman install skipped (best-effort)"
  fi
}

install_lsp() {
  rldyour::section "Install LSP set"
  if ! command -v bun >/dev/null 2>&1; then
    if [ "$STRICT" -eq 1 ]; then
      rldyour::log "error" "bun required for language-server bootstrap"
      exit 1
    fi
    rldyour::log "warn" "skip LSP bootstrap without bun"
    return 0
  fi
  for pkg in "${BUN_LSP_PACKAGES[@]}"; do
    rldyour::run bun add -g "$pkg"
  done
}

# Desktop-only GUI layer (profile=desktop): a GUI terminal emulator and a Nerd
# font for glyph rendering. The headless server profile intentionally skips this
# — a server still gets the full terminal-first CLI stack above, just no GUI.
# All best-effort: a missing snap/apt channel warns and never aborts.
NERD_FONT_VERSION="${NERD_FONT_VERSION:-v3.4.0}"
install_desktop_layer() {
  if [ "$PROFILE" != "desktop" ]; then
    rldyour::log "info" "server profile: skipping GUI desktop layer (terminal-first CLI stack is installed)"
    return 0
  fi
  rldyour::section "Install desktop GUI layer (profile=desktop)"

  # JetBrainsMono Nerd Font -> ~/.local/share/fonts (matches the macOS terminal glyphs).
  local font_dir="$HOME/.local/share/fonts"
  if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    rldyour::log "ok" "JetBrainsMono Nerd Font already installed"
  elif [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] install JetBrainsMono Nerd Font ${NERD_FONT_VERSION} -> ${font_dir}"
  else
    mkdir -p "$font_dir"
    if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/JetBrainsMono.zip" -o /tmp/JetBrainsMono.zip &&
      unzip -oq /tmp/JetBrainsMono.zip -d "$font_dir/JetBrainsMonoNerd"; then
      command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$font_dir" >/dev/null 2>&1
      rm -f /tmp/JetBrainsMono.zip
      rldyour::log "ok" "JetBrainsMono Nerd Font installed"
    else
      rldyour::log "warn" "Nerd Font install failed (best-effort)"
    fi
  fi

  # Ghostty terminal emulator (macOS uses the Ghostty cask; on Ubuntu the
  # first-party channel is snap). Best-effort so headless/snapless hosts skip it.
  if command -v ghostty >/dev/null 2>&1; then
    rldyour::log "ok" "ghostty already installed"
  elif ! command -v snap >/dev/null 2>&1; then
    rldyour::log "warn" "snap unavailable; install a terminal emulator manually (ghostty/kitty/alacritty)"
  elif [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] sudo snap install ghostty --classic"
  else
    rldyour::run sudo snap install ghostty --classic ||
      rldyour::log "warn" "ghostty snap install failed (best-effort; try kitty/alacritty via apt)"
  fi

  # Optional personal desktop apps (0.2.8): Discord + OBS Studio via snap.
  # Best-effort; skipped without snap. Set RLDYOUR_SKIP_PERSONAL_APPS=1 to opt out.
  if [ "${RLDYOUR_SKIP_PERSONAL_APPS:-0}" = "1" ]; then
    rldyour::log "info" "personal desktop apps skipped (RLDYOUR_SKIP_PERSONAL_APPS=1)"
  elif ! command -v snap >/dev/null 2>&1; then
    rldyour::log "warn" "snap unavailable; skip Discord/OBS (install manually if desired)"
  else
    for snapname in discord obs-studio; do
      if snap list "$snapname" >/dev/null 2>&1; then
        rldyour::log "ok" "$snapname already installed"
      elif [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
        rldyour::log "info" "[DRY-RUN] sudo snap install $snapname"
      else
        rldyour::run sudo snap install "$snapname" ||
          rldyour::log "warn" "$snapname snap install failed (best-effort)"
      fi
    done
  fi
}

# macOS-parity language servers that ship as brew formulae on macOS but need
# per-tool channels on Ubuntu (verified against official sources, 0.2.8).
# All best-effort + idempotent + dry-run aware: a failed download only warns.
HELM_LS_VERSION="${HELM_LS_VERSION:-v0.5.4}"
KOTLIN_LS_VERSION="${KOTLIN_LS_VERSION:-1.3.13}"
POSTGRES_LS_VERSION="${POSTGRES_LS_VERSION:-0.25.5}"

ensure_terraform_ls() {
  if command -v terraform-ls >/dev/null 2>&1; then
    rldyour::log "ok" "terraform-ls already installed"
    return 0
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] add HashiCorp apt repo + apt install terraform-ls"
    return 0
  fi
  local codename
  codename="$(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release 2>/dev/null || lsb_release -cs 2>/dev/null)"
  if curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg >/dev/null &&
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com ${codename} main" | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null &&
    sudo apt-get update && sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y terraform-ls; then
    rldyour::log "ok" "terraform-ls installed via HashiCorp apt"
  else
    rldyour::log "warn" "terraform-ls install failed (best-effort)"
  fi
}

ensure_helm_ls() {
  if command -v helm_ls >/dev/null 2>&1; then
    rldyour::log "ok" "helm_ls already installed"
    return 0
  fi
  local arch
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64) arch=arm64 ;;
    armv7l | armhf) arch=arm ;;
    *)
      rldyour::log "warn" "unknown arch for helm-ls; skipping"
      return 0
      ;;
  esac
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] download helm_ls_linux_${arch} ${HELM_LS_VERSION} -> ~/.local/bin/helm_ls"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL "https://github.com/mrjosh/helm-ls/releases/download/${HELM_LS_VERSION}/helm_ls_linux_${arch}" -o "$HOME/.local/bin/helm_ls"; then
    chmod +x "$HOME/.local/bin/helm_ls"
    rldyour::log "ok" "helm_ls ${HELM_LS_VERSION} installed"
  else
    rldyour::log "warn" "helm_ls install failed (best-effort)"
  fi
}

ensure_jdtls() {
  if command -v jdtls >/dev/null 2>&1; then
    rldyour::log "ok" "jdtls already installed"
    return 0
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] apt openjdk-21-jdk python3 + Eclipse jdtls snapshot -> ~/.local/share/jdtls"
    return 0
  fi
  sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y openjdk-21-jdk python3 >/dev/null 2>&1 || true
  local dest="$HOME/.local/share/jdtls"
  mkdir -p "$dest" "$HOME/.local/bin"
  if curl -fsSL https://download.eclipse.org/jdtls/snapshots/jdt-language-server-latest.tar.gz | tar -xz -C "$dest"; then
    ln -sf "$dest/bin/jdtls" "$HOME/.local/bin/jdtls"
    rldyour::log "ok" "jdtls (Eclipse snapshot) installed -> ~/.local/bin/jdtls"
  else
    rldyour::log "warn" "jdtls install failed (best-effort; needs Java 21 + python3)"
  fi
}

ensure_kotlin_ls() {
  if command -v kotlin-language-server >/dev/null 2>&1; then
    rldyour::log "ok" "kotlin-language-server already installed"
    return 0
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] apt openjdk-21-jre + kotlin-language-server ${KOTLIN_LS_VERSION} server.zip -> ~/.local/share"
    return 0
  fi
  sudo -E DEBIAN_FRONTEND=noninteractive apt-get install -y unzip openjdk-21-jre >/dev/null 2>&1 || true
  local dest="$HOME/.local/share/kotlin-language-server"
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL "https://github.com/fwcd/kotlin-language-server/releases/download/${KOTLIN_LS_VERSION}/server.zip" -o /tmp/kls.zip &&
    rm -rf "$dest" && mkdir -p "$dest" && unzip -q -o /tmp/kls.zip -d "$dest"; then
    ln -sf "$dest/server/bin/kotlin-language-server" "$HOME/.local/bin/kotlin-language-server"
    rm -f /tmp/kls.zip
    rldyour::log "ok" "kotlin-language-server ${KOTLIN_LS_VERSION} installed"
  else
    rldyour::log "warn" "kotlin-language-server install failed (best-effort)"
  fi
}

ensure_postgres_ls() {
  if command -v postgres-language-server >/dev/null 2>&1; then
    rldyour::log "ok" "postgres-language-server already installed"
    return 0
  fi
  local target
  case "$(uname -m)" in
    x86_64 | amd64) target=x86_64-unknown-linux-gnu ;;
    aarch64 | arm64) target=aarch64-unknown-linux-gnu ;;
    *)
      rldyour::log "warn" "unknown arch for postgres-language-server; skipping"
      return 0
      ;;
  esac
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] download postgres-language-server_${target} ${POSTGRES_LS_VERSION} -> ~/.local/bin"
    return 0
  fi
  mkdir -p "$HOME/.local/bin"
  if curl -fsSL "https://github.com/supabase-community/postgres-language-server/releases/download/${POSTGRES_LS_VERSION}/postgres-language-server_${target}" -o "$HOME/.local/bin/postgres-language-server"; then
    chmod +x "$HOME/.local/bin/postgres-language-server"
    rldyour::log "ok" "postgres-language-server ${POSTGRES_LS_VERSION} installed"
  else
    rldyour::log "warn" "postgres-language-server install failed (best-effort)"
  fi
}

# Full macOS-parity LSP set on Ubuntu (0.2.8): closes the previously-documented gap.
ensure_parity_lsps() {
  rldyour::section "Install macOS-parity language servers (best-effort)"
  ensure_terraform_ls
  ensure_helm_ls
  ensure_jdtls
  ensure_kotlin_ls
  ensure_postgres_ls
}

# Google Cloud CLI via the official apt repo (0.2.8). Binary: gcloud.
ensure_gcloud() {
  rldyour::section "Install Google Cloud CLI (gcloud)"
  if command -v gcloud >/dev/null 2>&1; then
    rldyour::log "ok" "gcloud already installed"
    return 0
  fi
  if [ "$RLDYOUR_DRY_RUN" -eq 1 ]; then
    rldyour::log "info" "[DRY-RUN] add packages.cloud.google.com apt repo + apt install google-cloud-cli"
    return 0
  fi
  if curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg &&
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null &&
    sudo apt-get update && sudo CLOUDSDK_SKIP_PY_COMPILATION=1 DEBIAN_FRONTEND=noninteractive apt-get install -y google-cloud-cli; then
    rldyour::log "ok" "gcloud (google-cloud-cli) installed"
  else
    rldyour::log "warn" "gcloud install failed (best-effort)"
  fi
}

run_post_checks() {
  rldyour::section "Post-checks"
  bash "$SCRIPT_DIR/verify.sh" --strict --skip-optional
}

if [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

rldyour::assert_root "$REPO_ROOT"
rldyour::ensure_path

rldyour::section "rldyour-new-mac-or-ubuntu (Ubuntu) installer"
rldyour::log "info" "mode: $([ "$RLDYOUR_DRY_RUN" -eq 1 ] && echo dry-run || echo apply); profile: ${PROFILE}"

if [ "$SKIP_SYSTEM" -eq 0 ]; then
  ensure_apt_repo_updates
  apt_with_retries install -y software-properties-common
  apt_with_retries install -y ca-certificates
  ensure_apt_packages
  ensure_eza
  ensure_starship
  ensure_atuin
  ensure_xh
  ensure_antidote_clone
  rldyour::ensure_git_perf
  rldyour::ensure_git_delta_config
  rldyour::install_terminal_configs "$REPO_ROOT/templates/terminal"
  ensure_node
  ensure_uv
  ensure_bun
  rldyour::ensure_path
  install_python_tooling
  ensure_rust
  ensure_dart
  install_go_lsp
  ensure_marksman
  ensure_java_and_r
  ensure_gcloud
else
  rldyour::log "warn" "system layer skipped by --skip-system"
fi

if [ "$SKIP_AI" -eq 0 ]; then
  install_ai_runtimes
else
  rldyour::log "warn" "AI runtimes skipped by --skip-ai"
fi

if [ "$SKIP_LSPS" -eq 0 ]; then
  install_lsp
  install_quality_packages
  install_security_scanners
  ensure_extended_lsps
  ensure_cargo_parity_tools
  ensure_extra_runtimes
  ensure_parity_lsps
else
  rldyour::log "warn" "LSP layer skipped by --skip-lsps"
fi

if [ "$SKIP_BROWSER" -eq 0 ]; then
  rldyour::install_browser_providers
  rldyour::install_rtk
else
  rldyour::log "warn" "browser tooling skipped by --skip-browser"
fi

install_desktop_layer

if [ "$SKIP_CHECKS" -eq 0 ]; then
  run_post_checks
fi
