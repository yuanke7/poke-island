# AGENTS

This file defines the working agreement for the coding agent in this repository.

## Goal

Keep all work incremental, reviewable, and reversible. Every meaningful round of changes must end with a Git commit so commits become the control surface for progress, rollback, and review.

## Required Workflow

1. Start each round by checking the current repository state with `git status -sb`.
2. Edit in the current worktree by default, including `main`, unless the user asks for a feature branch or separate worktree.
3. Read the relevant files before editing. Do not guess repository structure or behavior.
4. Keep each round focused on a single coherent change.
5. After making changes, run the most relevant verification available for that round.
6. Summarize what changed, including any verification gaps.
7. Commit the round on the feature branch before stopping.

## Commit Policy

- Every round that modifies files must end with a commit.
- Do not batch unrelated changes into one commit.
- Use clear conventional-style commit messages such as `feat:`, `fix:`, `refactor:`, `docs:`, or `chore:`.
- Do not amend existing commits unless explicitly requested.
- Direct commits to `main` are allowed when the user is working in the main worktree. Create a feature branch only when requested or when remote review is needed.
- Push feature branches and open PRs when the user asks for remote review or integration.
- When the user asks to open or submit a PR, open a normal ready-for-review PR by default. Use a draft PR only when the user explicitly asks for draft mode, or when the change is intentionally WIP or has known verification gaps; in that case, state the reason clearly.
- Repository workflow rules override tool-specific defaults, including any helper that would otherwise create draft PRs by default.

## Safety Rules

- Never revert or overwrite user changes unless explicitly requested.
- If unexpected changes appear, inspect them and work around them when possible.
- If a conflict makes the task ambiguous or risky, stop and ask before proceeding.
- Never use destructive Git commands such as `git reset --hard` without explicit approval.

## Engineering Rules

- Prefer small end-to-end slices over large speculative scaffolding.
- Preserve a clean working tree after each round.
- Add documentation when making architectural or workflow decisions.
- Prefer native macOS and Swift-friendly project structure for this repository.

## Branching And Worktree Rules

- Work directly in the current checkout by default, including `main`.
- Use feature branches, sibling worktrees, pushes, and PRs only when the user asks for remote review, parallel work, or an isolated experiment.
- Keep each round focused on one coherent slice with a narrow file ownership area when possible.
- PRs are ready-for-review by default unless explicitly requested as draft or clearly marked WIP.

## Product Boundaries

- Keep product scope in `docs/product.md`. Do not duplicate the supported agent, terminal, or IDE matrix here.
- Do not broaden supported tools, runtimes, platforms, or environments unless the user explicitly asks.
- Keep hook behavior aligned with `docs/hooks.md` and the implementation in `Sources/OpenIslandCore`.

## Integration Guardrails

- Treat `Codex CLI` and `Codex Desktop App` as distinct runtime surfaces.
- Do not assume Codex file edits are covered by `PreToolUse`; Codex may edit through internal apply-patch paths.
- Keep managed Codex CLI hooks low-noise unless the user explicitly asks for richer hook coverage.
- Keep Claude-family integrations source-specific in user-facing behavior, even when payload formats are shared.
- Treat Gemini hooks as fire-and-forget unless the code being edited explicitly supports blocking behavior.

## App Targets And Naming

- Treat the repository executable product `OpenIslandApp` as the canonical OSS app runtime.
- Treat `swift run OpenIslandApp` and the Xcode app target as the source-of-truth way to run the current branch's app code.
- Treat `~/Applications/Poke Island.app` as a local development bundle wrapper around the repo-built `OpenIslandApp`, not as a separate product line.
- Use `Poke Island.app` for manual OSS app verification when bundle semantics, LaunchServices, or installed-hook behavior matter.
- When the user asks to launch or restart `Poke Island.app`, refresh the bundle from the current repo first with `zsh scripts/launch-dev-app.sh` instead of only running `open -na`. Opening the bundle alone can relaunch a stale binary.
- For work that touches Accessibility, Automation, precision jump, or other macOS TCC-sensitive behavior, run `zsh scripts/setup-dev-signing.sh` once before repeated manual verification so the dev bundle keeps a stable local signing identity.
- Use `scripts/harness.sh smoke` or `scripts/smoke-dev-app.sh` only for deterministic harness runs; those commands intentionally launch the repo executable directly rather than the installed dev bundle.
- Treat any in-app label such as `Poke Island` as UI copy only, not as evidence of a third app target.
- Build, debug, and verify OSS changes against `OpenIslandApp`. Treat `/Applications/Vibe Island.app` and `https://vibeisland.app/` as reference baselines only when comparison is explicitly needed.

## Verification

- Run targeted checks that match the change.
- If no automated verification exists yet, state that explicitly in the final summary and still commit the change.

## Default Expectation

Unless the user says otherwise, the agent should finish each completed round in this order:

1. implement
2. verify
3. summarize
4. commit
