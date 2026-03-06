---
name: kernel-workflow
description: General workflow for modifying SP3 assembly shaders, building them into CO binaries, integrating into aiter, and validating correctness. Use when the user modifies any SP3 shader (bug fix, new feature, optimization, new variant) and needs to build, deploy, and test it end-to-end.
---

# SP3 Kernel Development Workflow

Generic end-to-end workflow: **Edit SP3 -> Build CO -> Deploy to aiter -> Test -> Verify**.
Applies to any SP3 change: bug fixes, new features, optimizations, new kernel variants.

## Step 1: Edit the SP3 Shader

Identify and modify the target SP3 file(s) in the shaders directory.

```
poc_kl/mi300/fmha_bwd_asm/shaders/    # SP3 source files live here
```

### Determine which files to edit

| If your change targets... | Edit these SP3 files |
|---------------------------|----------------------|
| A specific hdim (e.g., D64) | All `*_D64_*` variants (BF16/FP16, batch/group, A16/A32) |
| A specific dtype | All `BF16_*` or `FP16_*` files for the relevant hdim |
| All backward kernels | All `*_Genl.sp3` and `*_Genl_group.sp3` files |
| ODO stage only | `FMHA_BWD_ODO.sp3` |
| dQ_convert stage only | `FMHA_BWD_DQ_CONVERT.sp3` (and `*_rtne.sp3`, `*_rtna.sp3`, `*_rtz.sp3` variants) |

### Key variables in SP3 files

| Variable | Controls |
|----------|----------|
| `MODE` | 0 = batch mode, 1 = group/varlen mode |
| `RDM` | BF16 rounding mode (0=rtne, 1=rtna, 2=rtz) |
| `HDP` | Head-dim padding variant (0=pssk, 1=psskddv) |

When editing, make sure your change works for **all combinations** of MODE, RDM, and HDP
that the file supports. Use `if (MODE==0) ... else ... end` guards where behavior differs.

## Step 2: Build CO from SP3

```bash
cd poc_kl/mi300/fmha_bwd_asm/scripts

# Build a single kernel (replace with your target SP3):
python3 auto_integration.py \
    --target=<YOUR_SP3_FILE>.sp3 \
    --lib=<path_to>/poc_kl_merg/scripts/common/ \
    --aiter=<path_to>/aiter/

# Build ALL Genl kernels (after broad changes):
python3 auto_integration.py \
    --target=all \
    --lib=<path_to>/poc_kl_merg/scripts/common/ \
    --aiter=<path_to>/aiter/
```

### What happens during build

1. Reads SP3 from `shaders/`
2. For BF16: generates 3 rounding-mode variants (`_rtne`, `_rtna`, `_rtz`)
3. For group-mode D128: generates padding variants (`_pssk`, `_psskddv`)
4. Assembles: SP3 -> `sp3` binary -> `.bin` -> `.s` -> `clang++` -> `.co`
5. Copies `.co` files into `aiter/hsa/gfx942/fmha_v3_bwd/`

### SP3 to CO name mapping

| SP3 source pattern | Generated CO files |
|---------------------|----------------------|
| `BF16_..._D64_..._A32_Genl.sp3` | `bwd_hd64_bf16_a32_{rtne,rtna,rtz}_pssk.co` |
| `FP16_..._D64_..._A32_Genl.sp3` | `bwd_hd64_fp16_a32_pssk.co` |
| `BF16_..._D128_..._A32_Genl.sp3` | `bwd_hd128_bf16_a32_{rtne,rtna,rtz}_psskddv.co` |
| `BF16_..._D192_..._A32_Genl.sp3` | `bwd_hd192_bf16_a32_{rtne,rtna,rtz}_psskddv.co` |
| `*_group.sp3` | `*_group.co` |

### Build verification

After build, confirm the CO files were updated:

```bash
ls -lt aiter/hsa/gfx942/fmha_v3_bwd/*.co | head -10   # newest files on top
```

If timestamps don't match, the build may have failed silently -- check `auto_integration.py` output.

## Step 3: Test

### Prerequisites

```bash
export AITER_ASM_DIR=<path_to>/aiter/hsa
export LD_LIBRARY_PATH=<path_to>/aiter/op_tests/cpp/mha:$LD_LIBRARY_PATH
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# Find a free GPU
rocm-smi --showmemuse --showuse
export HIP_VISIBLE_DEVICES=<free_gpu_id>
```

### Run correctness tests

```bash
cd <path_to>/aiter/op_tests

# Baseline correctness (small tensors):
python test_large_addr.py --kernel=<your_co_file>.co --normal

# Large tensor tests (if your change affects address computation or buffer handling):
python test_large_addr.py --kernel=<your_co_file>.co --large-q   # Q/dO/dQ overflow
python test_large_addr.py --kernel=<your_co_file>.co --large-k   # K/V/dK/dV overflow

# All modes at once:
python test_large_addr.py --kernel=<your_co_file>.co

# List all available kernel CO files:
python test_large_addr.py --list
```

### Test all affected variants

If you changed a BF16 D64 Genl kernel, test all generated CO variants:

```bash
for co in bwd_hd64_bf16_a32_rtz_pssk.co bwd_hd64_bf16_a32_rtne_pssk.co bwd_hd64_bf16_a32_rtna_pssk.co; do
    echo "=== Testing $co ==="
    python test_large_addr.py --kernel=$co --normal 2>&1 | tail -5
done
```

For group variants, add `_group.co` files to the loop.

### Run other relevant op_tests

```bash
# General MHA tests (if your change might affect forward/backward integration):
python test_mha.py

# Benchmark (to check for performance regressions):
cd op_benchmarks
python bench_mha.py
```

## Step 4: Debug Failures

### Isolate which kernel stage has the bug

The backward pass runs 3 stages: ODO -> dQdKdV -> dQ_convert.
Force CK fallback for helper stages to isolate the main kernel:

```bash
# Test only the dQdKdV ASM kernel (CK handles ODO & dQ_convert):
AITER_V3_BWD_CK_ODO=1 AITER_V3_BWD_CK_DQ_CONVERT=1 \
    python test_large_addr.py --kernel=<co_file>.co

# Test only ODO + dQ_convert ASM (compare with above):
# If above passes but full-ASM fails -> bug is in ASM ODO or dQ_convert
# If above also fails -> bug is in ASM dQdKdV kernel
```

### Check kernel dispatch

Look for these lines in test output:

```
Kernel dispatch info:
    ODO:        ASM / CK (fallback)
    dQdKdV:     ASM (fmha_v3_bwd/<co_file>)
    dQ_convert: ASM / CK (fallback)
    Kernel match: <check or cross>
```

If `Kernel match` fails, the wrong CO file was dispatched -- check the CSV mapping
and verify the CO file is in the correct directory.

### Compare against known-good state

```bash
# Revert your SP3 change, rebuild, and test to confirm the issue is from your edit:
git stash   # in the SP3 repo
# rebuild & test
git stash pop
```

## Step 5: Verify and Submit

### Verification checklist

- [ ] Build succeeds for all target SP3 files
- [ ] `--normal` test passes (baseline correctness)
- [ ] `--large-q` test passes (if change touches Q/dO/dQ address computation)
- [ ] `--large-k` test passes (if change touches K/V/dK/dV address computation)
- [ ] Both BF16 and FP16 variants pass
- [ ] Both batch and group mode variants pass
- [ ] Kernel dispatch shows correct CO file (`Kernel match: check`)
- [ ] No performance regression (benchmark if relevant)

### Batch build and test example

```bash
# Build all D64 A32 Genl kernels
cd poc_kl/mi300/fmha_bwd_asm/scripts
for sp3 in \
    BF16_FMHA_BWD_D64_1TG_4W_32mx1_48nx4_A32_Genl.sp3 \
    FP16_FMHA_BWD_D64_1TG_4W_32mx1_48nx4_A32_Genl.sp3 \
    BF16_FMHA_BWD_D64_1TG_4W_32mx1_48nx4_A32_Genl_group.sp3 \
    FP16_FMHA_BWD_D64_1TG_4W_32mx1_48nx4_A32_Genl_group.sp3; do
    echo "=== Building $sp3 ==="
    python3 auto_integration.py --target="$sp3" --lib=<LIB> --aiter=<AITER>
done

# Test all generated COs
cd <path_to>/aiter/op_tests
python test_large_addr.py --kernel=bwd_hd64_bf16_a32_rtz_pssk.co 2>&1 | tee test.log
python test_large_addr.py --kernel=bwd_hd64_fp16_a32_pssk.co 2>&1 | tee -a test.log
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Build error in `sp3` | Check SP3 syntax; common issues: mismatched `if/end`, undefined variables |
| No kernels matching | Use just the CO filename (e.g., `bwd_hd64_bf16_a32_rtz_pssk.co`) |
| GPU OOM | `rocm-smi --showmemuse`, pick a free GPU, run tests one at a time |
| Stale CO file | Compare timestamps: `ls -lt shaders/*.sp3` vs CO files, rebuild if needed |
| Kernel match fail | Verify CO is in `aiter/hsa/gfx942/fmha_v3_bwd/` and matches CSV mapping |
| CK fallback for ODO/dQ_convert | Normal in large-q/large-k modes (tile-size constraints) |
| All GPUs busy | Wait or check `rocm-smi` for processes to finish |

## Environment Variables Reference

| Variable | Purpose |
|----------|---------|
| `AITER_ASM_DIR` | Path to HSA directory with CO binaries |
| `HIP_VISIBLE_DEVICES` | GPU selection |
| `PYTORCH_CUDA_ALLOC_CONF` | Memory allocator config |
| `AITER_V3_BWD_CK_ODO=1` | Force CK for ODO (isolate dQdKdV) |
| `AITER_V3_BWD_CK_DQ_CONVERT=1` | Force CK for dQ_convert (isolate dQdKdV) |
| `AITER_DISABLE_V3_FWD=1` | Use CK for forward pass |
