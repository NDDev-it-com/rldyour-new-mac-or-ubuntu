import subprocess
from pathlib import Path
import re


def run_shell(cmd: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        check=False,
        text=True,
    )


def test_bootstrap_help() -> None:
    result = run_shell(["bash", "scripts/bootstrap.sh", "--help"])
    assert result.returncode == 0
    assert "Usage: scripts/bootstrap.sh" in result.stdout
    assert "--platform macos|ubuntu" in result.stdout


def test_bootstrap_plan_is_dry_run_safe() -> None:
    result = run_shell(
        [
            "bash",
            "scripts/bootstrap.sh",
            "--platform",
            "ubuntu",
            "--plan",
            "--skip-system",
            "--skip-ai",
            "--skip-lsps",
            "--skip-checks",
        ]
    )
    assert result.returncode == 0
    assert "rldyour-new-mac-or-ubuntu (Ubuntu) installer" in result.stdout
    assert "mode: dry-run" in result.stdout


def test_profile_pin_and_lsp_parity() -> None:
    macos = Path("scripts/macos/install.sh").read_text(encoding="utf-8")
    ubuntu = Path("scripts/ubuntu/install.sh").read_text(encoding="utf-8")

    pattern = re.compile(r"^(CLAUDE_CODE_VERSION|CODEX_VERSION|OPENCODE_VERSION|MIMOCODE_VERSION)=\"([^\"]+)\"$", re.MULTILINE)

    macos_versions = {k: v for k, v in pattern.findall(macos)}
    ubuntu_versions = {k: v for k, v in pattern.findall(ubuntu)}

    assert macos_versions and ubuntu_versions
    assert macos_versions == ubuntu_versions
    assert "2.1.199" in macos_versions.get("CLAUDE_CODE_VERSION", "")
    assert "0.142.5" in macos_versions.get("CODEX_VERSION", "")
    assert "1.17.13" in macos_versions.get("OPENCODE_VERSION", "")
    assert "0.1.4" in macos_versions.get("MIMOCODE_VERSION", "")

    assert "gopls" in macos
