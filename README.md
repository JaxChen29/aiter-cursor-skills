# aiter-cursor-skills

Cursor Agent Skills, Rules, and practices for aiter kernel development on AMD MI300X (gfx942).

## What's in this repo

| Directory | Purpose |
|-----------|---------|
| `skills/general/` | Shared team skills -- add these to Cursor to automate common workflows |
| `skills/personal/` | Personal skills tuned to individual setups |
| `practices/` | Case studies of real problems solved (problem / investigation / solution / lessons) |
| `rules/` | Cursor rules providing project context (copy into your project's `.cursor/rules/`) |

## Quick Start

### Adding a skill to Cursor

1. Open **Cursor Settings > Features > Skills**
2. Click **Add Skill** and point to a `SKILL.md` file from this repo
3. Cursor will automatically invoke the skill when you ask it to perform the matching task

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
| [kernel-workflow](skills/general/kernel-workflow.md) | Full SP3 shader build/test/debug cycle for FMHA BWD kernels |
| [code-review](skills/general/code-review.md) | PR and code review conventions for aiter |
| [env-setup](skills/general/env-setup.md) | Docker container, toolchain, and environment setup |

### Personal

Add your own skills here. See `skills/personal/` for examples.

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
