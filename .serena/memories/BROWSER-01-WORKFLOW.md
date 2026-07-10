<!-- Memory Metadata
Last updated: 2026-07-10
Last verified: 2026-07-10
Last commit: 25e5b7bbf07ca90192022ac8fb9f300d443b9410 chore(release): new-mac-or-ubuntu 0.3.7 (other)
Scope: browser-visible validation and debugging workflows
Area: BROWSER
-->

# Browser Workflow

## Scope
browser-visible validation and debugging workflows

## Current source of truth
- `path:README.md`
- `path:scripts/lib/common.sh`
- `path:scripts/browser_runtime_integrity.py`
- `path:scripts/verify-browser-runtime.sh`

## Last verified
- date: 2026-07-10
- commit: `25e5b7bbf07ca90192022ac8fb9f300d443b9410`
- checked by: Codex final consistency sync

## Facts
- This module installs and verifies the mandatory CloakBrowser backend plus managed Playwright CLI and Chrome DevTools MCP wrappers; browser task routing remains adapter-owned and has no stock-browser fallback.
- An exact pre-marker rldyour CloakBrowser home, launcher set, and launchd/systemd service may be migrated once through a bounded transaction; any failed handoff preserves the candidate and restores the prior home, wrapper set, and active service state.
- Browser Node runtimes are published from the frozen Bun lock only after owner and permission validation. Group/world-writable trees are rebuilt into the same content-addressed destination while the rejected tree is retained outside the active namespace.

## Evidence
- `commit:25e5b7bbf07ca90192022ac8fb9f300d443b9410`
- `path:README.md`
- `path:scripts/lib/common.sh`
- `path:scripts/browser_runtime_integrity.py`
- `path:scripts/verify-browser-runtime.sh`

## Known pitfalls
- Treat this memory as derived context. Current code, configuration, runtime output, and GitHub state override stale memory text.

## Update policy
Update after verified changes to the referenced source-of-truth files.

## Delete / merge policy
- Delete or merge only when the referenced source-of-truth files no longer support this memory and the replacement memory preserves the durable facts.

## Applies to

- The scope and source-of-truth paths declared in this memory.

## Source of truth

- The `Current source of truth` entries above, plus current code, configuration, tests, git state, and live GitHub state where this memory references live release or repository surfaces.

## Invariants

- Current code, configuration, tests, validators, git state, and live GitHub state override this memory whenever they disagree.

## Current State

- Treat the `Facts` section as the current durable state. Do not treat historical evidence, superseded notes, or previous release entries as current.

## Do Not Infer

- Do not infer runtime versions, product versions, commits, permissions, release state, security posture, or tool behavior from this memory without checking the source of truth.

## Update Triggers

- Update after verified changes to the source-of-truth files, runtime baselines, release tuple, validation gates, live release state, or durable agent-workflow contracts.

## Validation Commands

- Run the rldyour control-plane Serena memory validators in strict mode: `validate_serena_memory_schema` (`--strict-mode strict-all`) and `validate_serena_memory_semantics` (`--strict-current-facts --strict-metadata-dates --strict-evidence-commits`).

## Repair Procedure

1. Re-read the source-of-truth files listed above.
2. Update only verified current facts; move stale facts into historical evidence.
3. Rerun the validation commands until green.
