---
name: code-review
description: Review code for quality, security, and best practices. Auto-generate PR descriptions and push PRs. Use when reviewing code changes, preparing pull requests, checking code style, or when the user asks for a code review. Works for any project, with extended checks for aiter SP3/HIP/CUDA code.
---

# Code Review, PR Description, and Push Workflow

## 1. Code Review Checklist

### General (all languages)

**Correctness**
- [ ] Logic is correct and handles edge cases
- [ ] Error handling is comprehensive (no silent failures)
- [ ] Null/None/undefined cases handled
- [ ] Boundary conditions tested (empty input, max values, zero-length)
- [ ] Concurrent access is safe (if applicable)

**Code Style and Readability**
- [ ] Consistent naming conventions (variables, functions, classes)
- [ ] Functions are focused and appropriately sized (single responsibility)
- [ ] No dead code, commented-out blocks, or debug prints left behind
- [ ] Comments explain *why*, not *what* (code should be self-documenting)
- [ ] No magic numbers -- use named constants

**Security**
- [ ] No hardcoded secrets, tokens, or passwords
- [ ] Input is validated and sanitized
- [ ] No SQL injection, command injection, or path traversal risks
- [ ] Sensitive data is not logged

**Performance**
- [ ] No unnecessary allocations in hot paths
- [ ] Appropriate algorithmic complexity (no O(n^2) where O(n) is possible)
- [ ] No redundant I/O or network calls
- [ ] Large data structures are not copied unnecessarily

**Testing**
- [ ] Changes have corresponding tests
- [ ] Edge cases are tested
- [ ] Tests are deterministic (no flaky tests)

### Python specific

- [ ] Type hints on public functions
- [ ] f-strings preferred over `.format()` or `%`
- [ ] Context managers used for resource handling (`with open(...)`)
- [ ] No bare `except:` clauses

### C/C++/CUDA/HIP specific

- [ ] Memory is freed (no leaks), RAII used where possible
- [ ] Buffer sizes checked before access
- [ ] Pointer arithmetic is bounds-safe
- [ ] Kernel launch configs are valid (grid/block dimensions)
- [ ] Shared memory usage doesn't exceed hardware limits

### aiter SP3 Assembly Extensions

When reviewing SP3 shader code in the aiter project, also check:

- [ ] **64-bit address safety:** `s_mul_hi_u32` used for any multiply that can exceed 32-bit
- [ ] **Carry chain integrity:** no SCC-clobbering instructions between `s_add_u32` and `s_addc_u32`
- [ ] **`s_and_b32` placement:** must be *after* `s_addc_u32`, never between `s_add_u32`/`s_addc_u32`
- [ ] **Both modes handled:** MODE==0 (batch) and MODE==1 (group/varlen)
- [ ] **Buffer descriptor num_records:** updated if base offset moved from VGPR to buf[0]
- [ ] **All buffer types covered:** Q, K, V, dO, dQ, dK, dV, ODO, LseD

**ISA SCC quick reference:**

| Instruction | Modifies SCC? | Notes |
|-------------|---------------|-------|
| `s_mul_i32` | No | |
| `s_mul_hi_u32` | No | |
| `s_add_u32` | Yes (carry) | |
| `s_addc_u32` | Yes (carry) | Reads SCC as carry-in |
| `s_and_b32` | Yes (!=0) | Dangerous between add/addc |
| `s_mov_b32` | No | Safe between add/addc |
| `s_lshr_b32` | Yes (!=0) | |

## 2. Review Feedback Format

Categorize findings by severity:

- **Critical** -- Must fix before merge (bugs, security issues, data loss risks)
- **Warning** -- Should fix, but not a blocker (performance issues, missing tests)
- **Suggestion** -- Nice to have (style improvements, minor refactors)
- **Praise** -- Highlight good patterns worth keeping

Format each finding as:

```
[Critical/Warning/Suggestion/Praise] <file>:<line>
<description>
<suggested fix if applicable>
```

## 3. Auto-Generate PR Description

When the user asks to create or summarize a PR, follow this workflow:

### Step 1: Gather changes

```bash
# See what's changed
git status
git diff --staged          # staged changes
git diff                   # unstaged changes
git log --oneline -10      # recent commits

# For branch-based PR:
git log main..HEAD --oneline
git diff main..HEAD
```

### Step 2: Analyze the changes

Classify the change type:
- **fix** -- bug fix (corrects wrong behavior)
- **feat** -- new feature or capability
- **refactor** -- restructuring without behavior change
- **perf** -- performance improvement
- **test** -- adding or fixing tests
- **docs** -- documentation only
- **chore** -- build, CI, dependency updates

### Step 3: Generate PR description

Use this template:

```markdown
## What
[One-line summary: <type>(<scope>): <description>]

## Why
[Root cause of the bug / motivation for the feature / reason for refactoring]

## How
[Key technical details of the implementation]
[Mention any trade-offs or design decisions]

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manual verification: [describe what was tested]
[For aiter kernel changes:]
- [ ] `test_large_addr.py --kernel=... --normal` PASSED
- [ ] `test_large_addr.py --kernel=... --large-q` PASSED
- [ ] `test_large_addr.py --kernel=... --large-k` PASSED
- Tested variants: [list CO files]

## Notes
[Any follow-up work, known limitations, or things reviewers should pay attention to]
```

### Step 4: Generate commit message

```
<type>(<scope>): <short description>

<body: what changed and why, 72-char wrapped>

<footer: references to issues, breaking changes>
```

Examples:
- `fix(mha_bwd): correct 64-bit address overflow in D64 dQ buffer`
- `feat(sp3): add SWA mask support for D192 backward kernels`
- `refactor(test): dynamic seqlen computation in test_large_addr.py`

## 4. Push PR Workflow

Step-by-step workflow to commit, push, and create a PR.

### Step 1: Stage and commit

```bash
# Review what will be committed
git status
git diff

# Stage changes
git add <files>           # specific files
git add -A                # all changes

# Commit with generated message
git commit -m "<type>(<scope>): <description>"
```

### Step 2: Push to remote

```bash
# Create branch if on main
git checkout -b <branch-name>   # e.g., fix/64bit-addr-d64

# Push with tracking
git push -u origin HEAD
```

### Step 3: Create PR via gh CLI

```bash
gh pr create \
    --title "<type>(<scope>): <short description>" \
    --body "$(cat <<'EOF'
## What
...

## Why
...

## How
...

## Testing
...
EOF
)"
```

### Optional: add reviewers and labels

```bash
gh pr create \
    --title "..." \
    --body "..." \
    --reviewer teammate1,teammate2 \
    --label "bug,kernel"
```

### Step 4: Verify

```bash
# Check PR was created
gh pr view --web         # open in browser
gh pr status             # see PR status
gh pr checks             # see CI status
```

## Quick Reference

| Task | Command |
|------|---------|
| View diff | `git diff` or `git diff main..HEAD` |
| Stage all | `git add -A` |
| Commit | `git commit -m "msg"` |
| Push new branch | `git push -u origin HEAD` |
| Create PR | `gh pr create --title "..." --body "..."` |
| View PR | `gh pr view` |
| List PRs | `gh pr list` |
| Check CI | `gh pr checks` |
| Add reviewer | `gh pr edit --add-reviewer <user>` |
