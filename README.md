# aiter-cursor-skills

Cursor Agent Skills, Rules, and practices for aiter kernel development on AMD MI300X (gfx942).

## What's in this repo

| Directory | Purpose |
|-----------|---------|
| `skills/general/` | Shared team skills -- add these to Cursor to automate common workflows |
| `skills/personal/` | Personal skills tuned to individual setups |
| `scripts/` | Installer and helper scripts for setting up Cursor skills from this repo |
| `hooks/` | Hook scripts that can be linked into `~/.cursor/hooks/` |
| `practices/` | Case studies of real problems solved (problem / investigation / solution / lessons) |
| `rules/` | Cursor rules providing project context (copy into your project's `.cursor/rules/`) |
| `reports/` | Weekly report files with daily entries (progress, problems, achievements) |
| `tasks.md` | Persistent task pool (Active / Backlog / Completed) |

## Quick Start

### Install skills into `~/.cursor/skills`

Recommended setup:

```bash
cd /mnt/raid0/jingchao/aiter-cursor-skills
./scripts/install-cursor-skills.sh
```

Install only selected skills:

```bash
./scripts/install-cursor-skills.sh commit-review code-review
```

Skip the post-commit hook:

```bash
./scripts/install-cursor-skills.sh --skip-hook
```

The installer uses symlinks so this repo stays the source of truth:

- folder-based skills such as `commit-review` and `doc-analysis` are linked directly
- legacy flat skills such as `code-review.md` are exposed through wrapper directories whose `SKILL.md` symlinks back to the repo file

If Cursor does not pick up the new skills immediately, restart Cursor.

### Optional project-scoped install

If a specific repository should carry its own shared skills, create entries under that repo's `.cursor/skills/`. The user-level installer above targets `~/.cursor/skills/` by default because it is the easiest setup to reuse when moving to a new server.

### Post-commit review hook

By default, the installer also registers `hooks/commit-review-post-commit.sh` into `~/.cursor/hooks.json`.

What it does:

- watches successful agent-run Shell `git commit` commands
- injects follow-up context encouraging a `commit-review` pass on the new commit

Limitations:

- it does not force a skill invocation
- it only sees commits made through Cursor's agent Shell flow
- it does not automatically catch commits created in an external terminal or Source Control UI

### Manual commit-review prompts

When the automatic hook does not fire, invoke the skill directly with prompts such as:

- `Review commit 874a6ae356381f4b0e9ebdf8c13412f827f29dd1 in poc_kl.`
- `Review the latest commit in poc_kl.`
- `Review HEAD and focus on correctness, tests, and aiter SP3 risks.`

### Adding a rule to your project

```bash
# From your aiter checkout:
cp /path/to/aiter-cursor-skills/rules/aiter.md .cursor/rules/
```

## Skills Index

### General (team-shared)

| Skill | Description |
|-------|-------------|
| [aiter-dev](skills/general/aiter-dev.md) | Build, test, and contribute to the aiter project |
| [commit-review](skills/general/commit-review/SKILL.md) | Review one commit or the latest fresh commit with findings-first feedback and aiter SP3 checks |
| [kernel-workflow](skills/general/kernel-workflow.md) | Generic SP3 shader build/test/debug cycle for any kernel change |
| [code-review](skills/general/code-review.md) | Code review, auto PR description, and push workflow (general + aiter) |
| [doc-analysis](skills/general/doc-analysis/SKILL.md) | Parse PDFs/markdown/code and export tech reports (MD, PDF, PPTX) |
| [env-setup](skills/general/env-setup.md) | Docker container, toolchain, and environment setup |

### Personal

| Skill | Description |
|-------|-------------|
| [daily-report](skills/personal/daily-report.md) | Daily work report, task pool management, and workday reminders |

## Practices Index

| Case Study | Summary |
|------------|---------|
| [64bit-addr-overflow-fix](practices/64bit-addr-overflow-fix.md) | Fixing 32-bit address overflow in SP3 buffer descriptor computations for large tensors |

## Adding a new practice

Create a markdown file in `practices/` following this structure:

```markdown
# [Title: short description of the problem]

## Problem
What went wrong and how it was discovered.

## Investigation
Steps taken to root-cause the issue.

## Solution
The fix, with code snippets and rationale.

## Lessons
What to watch out for next time.
```

## Contributing

1. Fork and clone this repo
2. Add or edit skills/practices
3. Submit a PR with a clear description of what was added
