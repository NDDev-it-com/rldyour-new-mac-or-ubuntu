import re
import shutil
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
ZSHRC = ROOT / "templates/terminal/zshrc"
ZSH_PLUGINS = ROOT / "templates/terminal/zsh_plugins.txt"
COMMON = ROOT / "scripts/lib/common.sh"
UBUNTU_INSTALL = ROOT / "scripts/ubuntu/install.sh"

# The pinned plugin set the materializer clones. Order matters and
# zsh-syntax-highlighting MUST stay last.
EXPECTED_PLUGINS = [
    "romkatv/zsh-defer",
    "Aloxaf/fzf-tab",
    "zsh-users/zsh-completions",
    "zsh-users/zsh-autosuggestions",
    "olets/zsh-abbr",
    "zsh-users/zsh-syntax-highlighting",
]


def _install_fake_command(bin_dir: Path, name: str) -> None:
    command = bin_dir / name
    command.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    command.chmod(0o755)


def test_ubuntu_command_names_do_not_create_broken_interactive_aliases(
    tmp_path: Path,
) -> None:
    zsh = shutil.which("zsh")
    assert zsh is not None, "zsh is required to verify the managed zsh template"

    home = tmp_path / "home"
    fake_bin = tmp_path / "bin"
    home.mkdir()
    fake_bin.mkdir()
    for name in ("ls", "cat", "batcat", "fdfind", "git", "duf", "btop", "hexyl"):
        _install_fake_command(fake_bin, name)

    probe = r'''
typeset -ga captured_abbrs
abbr() {
  local argument last
  for argument in "$@"; do last=$argument; done
  captured_abbrs+=("$last")
}
source "$1"
(( ${+aliases[ls]} == 0 )) || exit 10
(( ${+aliases[tree]} == 0 )) || exit 11
[[ ${aliases[cat]-} == batcat ]] || exit 12
[[ ${FZF_DEFAULT_COMMAND-} == "fdfind --type f --hidden --exclude .git" ]] || exit 13
[[ ${commands[ls]-} == "$2/ls" ]] || exit 14
[[ ${commands[cat]-} == "$2/cat" ]] || exit 15
(( ${+aliases[lg]} == 0 )) || exit 16
expected_abbrs=(
  'gs=git status'
  'gd=git diff'
  'df=duf'
  'top=btop'
  'htop=btop'
  'xxd=hexyl'
)
[[ ${(j:|:)captured_abbrs} == ${(j:|:)expected_abbrs} ]] || exit 17
'''
    result = subprocess.run(
        [zsh, "-f", "-i", "-c", probe, "_", str(ZSHRC), str(fake_bin)],
        check=False,
        capture_output=True,
        text=True,
        env={
            "HOME": str(home),
            "PATH": str(fake_bin),
            "TERM": "dumb",
            "ZDOTDIR": str(home),
        },
    )

    assert result.returncode == 0, result.stderr + result.stdout


def test_portable_aliases_are_guarded_in_the_template() -> None:
    template = ZSHRC.read_text(encoding="utf-8")
    assert "if command -v eza" in template
    assert "if command -v bat" in template
    assert "elif command -v batcat" in template
    assert "if command -v fd" in template
    assert "elif command -v fdfind" in template
    for command in (
        "lazygit",
        "difft",
        "jaq",
        "dust",
        "dua",
        "duf",
        "procs",
        "btop",
        "doggo",
        "gping",
        "hexyl",
        "viddy",
    ):
        assert f"command -v {command}" in template


def _plugin_lines() -> list[str]:
    lines = []
    for raw in ZSH_PLUGINS.read_text(encoding="utf-8").splitlines():
        stripped = raw.strip()
        if not stripped or stripped.startswith("#"):
            continue
        lines.append(raw)
    return lines


def test_zsh_plugins_are_sha_pinned_and_ordered() -> None:
    lines = _plugin_lines()
    repos = [line.split()[0] for line in lines]
    assert repos == EXPECTED_PLUGINS, repos
    # zsh-abbr is referenced by the zshrc abbr block; it must be in the manifest.
    assert "olets/zsh-abbr" in repos
    # zsh-syntax-highlighting must remain the final plugin.
    assert repos[-1] == "zsh-users/zsh-syntax-highlighting"
    # zsh-completions keeps its fpath-only annotation.
    completions = next(line for line in lines if line.startswith("zsh-users/zsh-completions"))
    assert "kind:fpath" in completions
    # Every plugin line records an exact 40-hex pinned commit.
    for line in lines:
        assert re.search(r"pin\s+[0-9a-f]{40}\b", line), line


def test_materializer_installs_pinned_antidote_and_bundle() -> None:
    common = COMMON.read_text(encoding="utf-8")
    # Shared materializer wired into install_terminal_configs (both platforms).
    assert "rldyour::materialize_zsh_plugins" in common
    assert "rldyour::materialize_zsh_plugins\n}" in common or (
        "rldyour::materialize_zsh_plugins" in common
        and "install_config_template" in common
    )
    # Ubuntu path git-clones antidote at the pinned SHA to $HOME/.antidote.
    assert "getantidote/antidote" in common
    assert "4913257e0ae3fee2a77e7189e526fe55b6ff9536" in common
    assert "$HOME/.antidote" in common
    # Clone home matches antidote's default (XDG_CACHE_HOME) full path style.
    assert "${XDG_CACHE_HOME:-$HOME/.cache}/antidote" in common
    assert "github.com/$repo" in common
    # A compiled static bundle is produced for offline startup.
    assert "antidote bundle" in common
    assert ".zsh_plugins.zsh" in common


def test_static_bundle_preferred_by_zshrc() -> None:
    template = ZSHRC.read_text(encoding="utf-8")
    # Startup sources the compiled offline bundle; there is no network fallback.
    assert '.zsh_plugins.zsh"' in template
    # `antidote load` must never run at shell startup — it resolves/clones plugins
    # over the network during shell init. A missing bundle fails closed (no plugins).
    assert "antidote load" not in template


def test_runtime_pillars_are_managed_pinned_artifacts() -> None:
    install = UBUNTU_INSTALL.read_text(encoding="utf-8")
    for tool in ("STARSHIP", "ATUIN", "CARAPACE"):
        assert f"{tool}_VERSION=" in install
        assert re.search(rf"{tool}_SHA256_X64=\"[0-9a-f]{{64}}\"", install), tool
        assert re.search(rf"{tool}_SHA256_ARM64=\"[0-9a-f]{{64}}\"", install), tool
    # Installed as managed content-addressed artifacts, never via apt/piped script.
    for fn in ("ensure_starship", "ensure_atuin", "ensure_carapace"):
        assert fn in install
        assert f"  {fn}\n" in install, f"{fn} must be wired into the system layer"
    assert "write_runtime_receipt" in install
    assert "ensure_managed_tool_link" in install
    # These pillars must not be added to the apt package list (apt is stale).
    for tool in ("starship", "atuin", "carapace"):
        assert f" {tool} " not in install.split("APT_SOURCE_PACKAGES=(", 1)[1].split(
            ")", 1
        )[0]


def test_login_shell_change_is_opt_in_only() -> None:
    install = UBUNTU_INSTALL.read_text(encoding="utf-8")
    assert "RLDYOUR_SET_LOGIN_SHELL" in install
    # Default OFF.
    assert 'SET_LOGIN_SHELL="${RLDYOUR_SET_LOGIN_SHELL:-0}"' in install
    # Guarded: the function returns early unless explicitly opted in.
    assert '[ "$SET_LOGIN_SHELL" -eq 1 ]' in install
    # Reversible: records the prior login shell for rollback.
    assert "previous-login-shell" in install
    assert "chsh -s" in install
    # /etc/shells is validated/updated before chsh.
    assert "/etc/shells" in install


def test_agent_gate_stays_first_in_zshrc() -> None:
    template = ZSHRC.read_text(encoding="utf-8")
    idx_gate = template.index("_is_agent")
    idx_plugins = template.index("Plugins via antidote")
    idx_history = template.index("HISTFILE")
    # Agent gate is defined and evaluated before history, plugins, and tools.
    assert idx_gate < idx_history < idx_plugins
    # The early `return` inside the agent branch precedes any plugin sourcing.
    idx_return = template.index("return", template.index("if _is_agent"))
    assert idx_return < idx_plugins
