---
name: fmha-bwd-sbhd-lsed-fix
description: Diagnose and fix FMHA backward-v3 SP3 kernel failures caused by SBHD Lse/D or dq_acc address computation. Use when editing fmha_bwd_asm shaders, debugging SBHD vs BSHD/BHSD mismatches, investigating QGrad/KGrad/VGrad errors with D passing, or porting the same fix pattern to gfx942 or gfx950.
---
# FMHA Backward SBHD LSE/D Fix

## When to Use

Use this skill when working on backward-v3 FMHA `sp3` kernels and any of these are true:

- `SBHD` fails while `BSHD` or `BHSD` passes.
- `QGrad Incorrect results`, `KGrad Incorrect results`, or `VGrad Incorrect results` appear only for one layout family.
- `D`/`O*dO` checks pass, but the main backward outputs fail.
- You are editing files under `poc_kl/mi300/fmha_bwd_asm/shaders/`.
- You need to port the same class of fix to `gfx950`.

## Core Rule

If the failure is layout-specific and `D` passes, suspect a side-buffer address bug first:

- `Lse/D` base
- `dq_acc` / 32-bit `dQ` temporary base
- sometimes `dK` / `dV` side-buffer descriptors

Do **not** assume the visible `sp3` file is the active runtime source. Always map the live source family first.

## Workflow

1. Map the active runtime source family.
   - Inspect `aiter/csrc/cpp_itfs/mha_bwd.cu`.
   - Inspect `aiter/hsa/gfx942/fmha_v3_bwd/fmha_bwd_dqdkdv.csv`.
   - Inspect integration logs such as `poc_kl/mi300/fmha_bwd_asm/scripts/poc.log`.
   - Current `gfx942` note: `D128 32mx1` is skipped by `auto_integration.py`; live D128 runtime kernels come from the `16mx1_48nx4` family.

2. Reproduce a single failing case and compare layouts.
   - Run one failing `SBHD` case and matching `BSHD` or `BHSD` controls.
   - Prefer `-kname=1 -v=1`.

3. Stage-split the failure.
   - Add `-v3_dump_args=1 -v3_check_d=1`.
   - If `D` passes and gradients fail, the bug is in the main `dqdkdv` shader path.

4. Audit the shader math.
   - Search for comments like:
     - `LseD always in bhs layout`
     - `dQ always in bhsd layout`
     - `when dQ in 32bits, its offset is Hdim*s_LseD_base`
   - Look for any batch term derived from `s_BAs` for side buffers.

5. Pick the fix style.
   - Use the ABI-based fix when SGPR headroom exists.
   - Use the SBHD heuristic when SGPRs are tight.
   - If `dQ` derives from `Hdim * s_LseD_base`, fixing `s_LseD_base` is enough.
   - If `dQ` has its own `s_BAs`-based batch term, patch that too.

6. Rebuild from the real source path.
   - Use `auto_integration.py` only for supported `Gen` / `Genl` flows.
   - For direct kernels, rebuild from the actual direct source file, not from a similarly named but skipped pipeline.

7. Reverify.
   - Run the focused regression script.
   - Run the broad runtime-mapped verifier.
   - Re-check one `SBHD` case against a `BSHD` control before concluding.

## Fix Decision Table

### Pattern A: ABI-Based `Lse/D` Base Fix

Use when the kernel has spare SGPRs and the packed ABI exposes the needed fields.

Target formula:

```text
LseD_base = batch_id * nhead_q * Hs_lsed + head_id * Hs_lsed
```

This is the cleanest fix because it is layout-independent.

### Pattern B: SGPR-Safe Heuristic

Use when there is no SGPR room for new `nhead_q` / `Hs_lsed` aliases.

Detect `SBHD` with:

```text
s_BAs < s_Seqs
```

Then rebuild the `BHS` batch term from the batch stride instead of using the non-`SBHD` shortcut.

### Pattern C: `dQ` Already Uses `Hdim * s_LseD_base`

If the shader comment or code shows that 32-bit `dQ` offset is derived from `Hdim * s_LseD_base`, only fix `s_LseD_base`.

### Pattern D: `dQ` Has Its Own `s_BAs` Batch Term

If the shader separately computes `s_dQ_base` from `s_BAs`, apply the same `SBHD` branching logic there.

## High-Risk Gotchas

- Do not patch `mi300_sp3_to_asm` unless that path is the real build source.
- Do not assume `32mx1` is active just because it looks closer to the loaded kernel name.
- `auto_integration.py` may replace many `.co` files in one run.
- `SWA`, `group`, and `causal_br` may map to different source families than plain / causal direct kernels.
- A one-off `SWA` failure can be flaky; rerun the exact case before patching.
- For `gfx950`, repeat the source-family mapping step instead of copying the `gfx942` assumptions.

## Files to Inspect First

- `aiter/csrc/cpp_itfs/mha_bwd.cu`
- `aiter/hsa/gfx942/fmha_v3_bwd/fmha_bwd_dqdkdv.csv`
- `poc_kl/mi300/fmha_bwd_asm/scripts/auto_integration.py`
- `poc_kl/mi300/fmha_bwd_asm/scripts/poc.log`
- `aiter/op_tests/cpp/mha/verify_a16_sbhd_kernels.sh`
- `aiter/op_tests/cpp/mha/verify_sbhd_source_kernels.sh`

## Additional Resources

- For root cause patterns, formulas, rebuild commands, and `gfx950` porting notes, read [reference.md](reference.md).
