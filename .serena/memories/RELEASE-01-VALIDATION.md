<!-- Memory Metadata
Last updated: 2026-07-10
Last verified: 2026-07-10
Last commit: 911265b feat: add secure role-aware bootstrap profiles
Scope: README.md, VERSION, CHANGELOG.md, config/rldyour-contract.json, scripts/**, templates/**, tests/**, .github/workflows/**
Area: RELEASE
-->

# RELEASE-01-VALIDATION

## Scope
Release, validation, CI, and public README contract for the macOS/Ubuntu bootstrap module.

## Applies to
- `README.md`
- `VERSION`
- `CHANGELOG.md`
- `config/rldyour-contract.json`
- `scripts/bootstrap.sh`
- `scripts/macos/install.sh`
- `scripts/ubuntu/install.sh`
- `scripts/macos/verify.sh`
- `scripts/ubuntu/verify.sh`
- `.github/workflows/**`

## Source of truth
- `VERSION` and `config/rldyour-contract.json`: canonical product/config version source of truth (see the Current State section for the live value).
- `CHANGELOG.md`: dated release entries per version, with an empty `[Unreleased]` section.
- `scripts/bootstrap.sh`: platform selector for `macos` and `ubuntu`.
- `scripts/macos/install.sh` and `scripts/ubuntu/install.sh`: OS-specific installer profiles.
- `scripts/macos/verify.sh` and `scripts/ubuntu/verify.sh`: per-platform verification gates.
- `scripts/ubuntu/server.sh` and `scripts/ubuntu/verify-server.sh`: explicit Ubuntu server mutation and read-only verification surfaces.
- `templates/ai-cli/` and `templates/browser/`: frozen runtime manifests, locks, and fail-closed provider configuration.
- `.github/workflows/**`: CI, security, dependency, scorecard, cross-platform, and release workflows.

## Invariants
- Installer default mode is plan/dry-run; `--apply` is required for mutation.
- Runtime pins stay synchronized across README, installer scripts, and contract.
- Release workflow is tag-driven and must match `VERSION` plus `CHANGELOG.md`.
- Public security workflows remain enabled for the public repository posture.
- Browser automation always resolves through the managed CloakBrowser endpoint; stock-browser fallback and alternate endpoints are rejected.
- Existing unmanaged state is preserved. Managed runtime and service publication is content-addressed, health-gated, and rollback-aware.

## Current State
- Current product/config version is `0.3.0`.
- Supported targets are Apple Silicon macOS desktop and Ubuntu 24.04/26.04 desktop/server on amd64 or arm64. Desktop Docker mode is always `none`; server Docker is explicit `none`, `rootful`, or `rootless`.
- Exact AI pins are Claude Code `2.1.206`, Codex CLI `0.144.1`, OpenCode `1.17.18`, MiMoCode `0.1.5`, and Antigravity `1.1.0` with self-update disabled.
- The mandatory browser baseline is CloakBrowser `0.4.10`, Chrome DevTools MCP `1.5.0`, Playwright CLI `0.1.17`, and Webwright commit `4a46f282ec37f27d6003cc498a977939d62d9015` on loopback CDP `127.0.0.1:9222`.
- AI, browser Node, CloakBrowser, and Webwright runtimes install from repository-owned frozen locks into content-addressed directories before an atomic wrapper/service handoff.
- Ubuntu server hardening is opt-in. SSH key/algorithm/Match context, UFW operator CIDR, Docker ownership, APT key identity, time service, Fail2ban, systemd linger, and rollback state are validated fail closed.
- Existing Homebrew/APT packages and healthy Docker workloads are preserved instead of implicitly upgraded.
- Local CI entrypoints are `bash scripts/ci/lint.sh` and `bash scripts/ci/validate.sh`.
- The verified 0.3.0 implementation gate is 55 pytest tests plus lint, validate, ShellCheck, actionlint, gitleaks, and diff checks.

## Evidence
- path:VERSION
- path:CHANGELOG.md
- path:config/rldyour-contract.json
- path:scripts/bootstrap.sh
- path:scripts/ci/validate.sh
- path:scripts/macos/install.sh
- path:scripts/ubuntu/install.sh
- path:scripts/ubuntu/server.sh
- path:scripts/ubuntu/verify-server.sh
- path:templates/ai-cli/bun.lock
- path:templates/browser/cloakbrowser-uv.lock
- path:.github/workflows/ci.yml
- path:.github/workflows/release.yml
- commit:911265b

## Do Not Infer
- Do not infer a successful live GitHub Actions run or release publication from local files. Check GitHub Actions and Releases before claiming live release readiness.

## Update Triggers
- Update when runtime pins, installer behavior, verification scripts, workflow names, release policy, README baseline, `VERSION`, or `CHANGELOG.md` change.

## Validation Commands
- `bash scripts/ci/lint.sh`
- `bash scripts/ci/validate.sh`
- `python3 -m pytest -q`
- `find scripts -type f -name '*.sh' -print0 | xargs -0 shellcheck`
- `actionlint`
- `bash scripts/macos/verify.sh --strict --skip-optional`
- `bash scripts/ubuntu/verify.sh --strict --skip-optional`
- `bash scripts/ubuntu/verify-server.sh --docker-mode <none|rootful|rootless>`
- `python3 ../../../scripts/validate_release_version_policy.py`

## Repair Procedure
- Reconcile `VERSION`, `CHANGELOG.md`, contract, README, and installer pins, then rerun local CI and root release validators.

## Update policy
Keep this memory synchronized with release, validation, and public CI contract changes only.
