---
name: kernel-workflow
description: Full SP3 shader build, test, and debug cycle for FMHA backward kernels on MI300X. Use when the user wants to build SP3 shaders, run auto_integration.py, test kernel correctness, fix 64-bit address overflow, or debug kernel failures.
---

# FMHA BWD Kernel Workflow

## Overview

The FMHA backward pass has 3 kernel stages: **ODO**, **dQdKdV**, **dQ_convert**.
SP3 assembly shaders are compiled to `.co` (code object) binaries and loaded at runtime by aiter.

## Build: SP3 to CO

### Single kernel

```bash
cd /path/to/poc_kl/mi300/fmha_bwd_asm/scripts

python3 auto_integration.py \
    --target=BF16_FMHA_BWD_D64_1TG_4W_32mx1_48nx4_A32_Genl.sp3 \
    --lib=/path/to/poc_kl_merg/scripts/common/ \
    --aiter=/path/to/aiter/
```

### All Genl kernels

```bash
python3 auto_integration.py --target=all \
    --lib=/path/to/poc_kl_merg/scripts/common/ \
    --aiter=/path/to/aiter/
```

### What the build does

1. Reads SP3 from `shaders/`
2. For BF16: generates 3 rounding-mode variants (`_rtne`, `_rtna`, `_rtz`)
3. For group-mode D128: generates padding variants (`_pssk`, `_psskddv`)
4. Assembles: SP3 -> `sp3` binary -> `.bin` -> `.s` -> `clang++` -> `.co`
5. Copies `.co` to `aiter/hsa/gfx942/fmha_v3_bwd/`

### SP3 to CO name mapping

| SP3 source pattern | Generated CO pattern |
|---------------------|----------------------|
| `BF16_..._D64_..._A32_Genl.sp3` | `bwd_hd64_bf16_a32_{rtne,rtna,rtz}_pssk.co` |
| `FP16_..._D64_..._A32_Genl.sp3` | `bwd_hd64_fp16_a32_pssk.co` |
| `BF16_..._D128_..._A32_Genl.sp3` | `bwd_hd128_bf16_a32_{rtne,rtna,rtz}_psskddv.co` |
| `BF16_..._D192_..._A32_Genl.sp3` | `bwd_hd192_bf16_a32_{rtne,rtna,rtz}_psskddv.co` |
| `*_group.sp3` | `*_group.co` |

## Test: Large Address Correctness

```bash
cd /path/to/aiter/op_tests

# All modes (normal + large-q + large-k):
python test_large_addr.py --kernel=bwd_hd64_bf16_a32_rtz_pssk.co

# Specific modes:
python test_large_addr.py --kernel=... --large-q   # Q/dO/dQ overflow
python test_large_addr.py --kernel=... --large-k   # K/V/dK/dV overflow
python test_large_addr.py --kernel=... --normal     # baseline
python test_large_addr.py --list                    # list kernels
```

### Test modes

| Flag | Buffers tested for overflow |
|------|-----------------------------|
| `--large-q` | Q, dO, dQ, ODO |
| `--large-k` | K, V, dK, dV |
| `--normal` | None (baseline) |
| *(no flag)* | All three modes |

### Interpreting results

- `PASSED` / `FAILED` per test
- `Kernel match: check-mark` confirms correct kernel dispatched
- Buffer overflow analysis shows which buffers exceed 32-bit
- dQ/dK/dV diffs vs tolerances

## Debug: Isolating Failures

### Isolate dQdKdV kernel (force CK for ODO & dQ_convert)

```bash
AITER_V3_BWD_CK_ODO=1 AITER_V3_BWD_CK_DQ_CONVERT=1 \
    python test_large_addr.py --kernel=bwd_hd192_bf16_a32_rtz_psskddv.co --large-q
```

### Diagnosis logic

- If CK-fallback test passes but full-ASM fails: bug is in ASM ODO or dQ_convert
- If both fail: bug is in ASM dQdKdV kernel

### CK fallback behavior

In large-q/large-k modes, ODO and dQ_convert **automatically** fall back to CK when
the seqlen doesn't match ASM tile configurations. This is by design and does not
affect dQdKdV testing.

## Common Issues

| Problem | Solution |
|---------|----------|
| No kernels matching | Use just the `.co` filename, not a full path |
| GPU OOM | `rocm-smi --showmemuse`, pick a free GPU with `HIP_VISIBLE_DEVICES` |
| Missing `.co` file | Re-run `auto_integration.py` for the SP3 source |
| Stale `.co` file | Compare timestamps: SP3 vs CO, rebuild if SP3 is newer |
| Kernel match fail | Check CO file is in `aiter/hsa/gfx942/fmha_v3_bwd/` |

## Key Scripts

| Script | Purpose |
|--------|---------|
| `auto_integration.py` | Main build: SP3 -> CO, copies to aiter |
| `update_sp3_offsets.py` | Updates `s_load` offsets to match struct layout changes |
| `fix_64bit_addr_all.py` | Applies 64-bit address overflow fix to all SP3 files |
| `generate.py` | Alternative generator (batch/group, fp16/bf16) |
