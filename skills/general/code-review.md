---
name: code-review
description: Review aiter pull requests and code changes following team conventions. Use when reviewing PRs, examining code changes, or preparing code for submission to the aiter repository.
---

# aiter Code Review

## Review Checklist

### Correctness
- [ ] Logic handles edge cases (large tensors, boundary seqlens, mixed dtypes)
- [ ] 64-bit address safety: no 32-bit overflow in buffer address computations
- [ ] Carry chain integrity: no SCC-clobbering instructions between `s_add_u32` and `s_addc_u32`
- [ ] Kernel dispatch matches expected CO file (check CSV mapping)

### SP3/Assembly Specific
- [ ] `s_mul_hi_u32` used for any multiply that can exceed 32-bit
- [ ] `s_and_b32 ..., 0xffff` placed **after** the `s_addc_u32`, not between `s_add_u32`/`s_addc_u32`
- [ ] Both batch and group modes (MODE==0 / MODE==1) handled
- [ ] Buffer descriptor `num_records` updated if base offset moved from VGPR to buf[0]
- [ ] All buffer types covered: Q, K, V, dO, dQ, dK, dV, ODO, LseD

### Testing
- [ ] `test_large_addr.py` passes for all 3 modes (normal, large-q, large-k)
- [ ] Tests run with correct kernel CO (check `Kernel match` in output)
- [ ] Both BF16 and FP16 variants tested
- [ ] Both batch and group mode variants tested

### Build
- [ ] `auto_integration.py` produces expected CO files
- [ ] CO files copied to correct `aiter/hsa/gfx942/fmha_v3_bwd/` path
- [ ] No stale CO files left from previous builds

## ISA Quick Reference (SCC Behavior)

| Instruction | Modifies SCC? | Notes |
|-------------|---------------|-------|
| `s_mul_i32` | No | |
| `s_mul_hi_u32` | No | |
| `s_add_u32` | Yes (carry) | |
| `s_addc_u32` | Yes (carry) | Reads SCC as carry-in |
| `s_and_b32` | Yes (!=0) | **DANGEROUS between add/addc** |
| `s_mov_b32` | No | Safe between add/addc |
| `s_lshr_b32` | Yes (!=0) | |

## PR Description Template

```markdown
## What
[One-line summary of the change]

## Why
[Root cause / motivation]

## How
[Key technical details of the fix/feature]

## Testing
- [ ] `test_large_addr.py --kernel=... --normal` PASSED
- [ ] `test_large_addr.py --kernel=... --large-q` PASSED
- [ ] `test_large_addr.py --kernel=... --large-k` PASSED
- Tested variants: [list CO files tested]
```
