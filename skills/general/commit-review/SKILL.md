---
name: commit-review
description: Review a single git commit or the latest fresh commit with findings-first feedback. Use when the user asks to review a commit, provides a SHA, asks to review the latest commit or `HEAD`, shares `git show` output, or when post-commit context indicates a new commit was created. Focus on correctness, regression risk, missing tests, and aiter SP3/HIP/CUDA concerns.
---

# Commit Review

## Scope

Review one commit at a time.

- If the user gives a SHA, review that commit.
- If the user asks to review the latest or new commit, review `HEAD`.
- Run git commands on the host, not inside Docker.

## Gather the Commit

Start with:

```bash
git show --stat --summary <sha>
git show --format=fuller --no-patch <sha>
git show <sha>
```

For wide commits:

- Group changed files by pattern or variant matrix.
- Inspect representative diffs first, then spot-check sibling variants.
- Compare generated and non-generated peers when both exist.

## Review Priorities

1. Correctness and regression risk.
2. Missing validation, tests, or benchmarks.
3. Performance-sensitive changes on hot paths.
4. Maintainability issues only when they materially affect safety or future debugging.

Avoid turning the review into a style-only audit.

## Core Checks

### General

- Logic change matches the commit message and changed files.
- Edge cases, layout assumptions, and data-shape assumptions still hold.
- New constants, offsets, and branch conditions are traceable to real inputs.
- Tests or manual validation cover the new behavior, not just the default path.

### For generated or mirrored files

- The same logical fix lands in every required variant.
- Generated files do not introduce accidental duplicates, stale code, or drift from source templates.
- Variant-specific differences are intentional and explained by layout, dtype, or tile shape.

### aiter SP3 / kernel checks

- 64-bit address math is safe when stride or offset products can overflow 32-bit.
- No SCC-clobbering instruction sits between `s_add_u32` and `s_addc_u32`.
- New SGPR aliases do not overlap existing scalar register usage.
- New dispatch or kernarg offsets match the host-side ABI and packing.
- Buffer/layout assumptions hold for BHS, SBHD, varlen, GQA/MQA, and padding when relevant.
- Changes stay synchronized across BF16/FP16, D64/D128, `_Gen`, `cas_kb`, and A16/A32 variants as needed.
- New branches in hot paths are uniform or justified, and perf-sensitive changes call out expected impact.

## Output Format

Present findings first, ordered by severity.

Use this format:

```text
[Critical/Warning/Suggestion/Praise] <file>:<line>
<problem or positive observation>
<suggested fix or follow-up, if applicable>
```

Then include:

1. `Open questions / assumptions`
2. `Summary`

If you find no issues, say so clearly and still mention residual risk, missing tests, or missing perf data.

## Good Review Habits

- Prefer 2-5 high-signal findings over exhaustive nits.
- Call out missing evidence separately from proven bugs.
- When a commit touches many similar files, name the exact variant matrix you checked.
- If the change looks correct but risky, recommend the smallest useful validation matrix.

## Additional Resources

- For a worked example using a real FMHA shader commit, see [examples.md](examples.md).
