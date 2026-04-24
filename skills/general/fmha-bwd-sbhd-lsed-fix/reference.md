# FMHA Backward SBHD LSE/D Fix Reference

## Symptom Pattern

This issue usually looks like:

- `SBHD` fails.
- `BSHD` and `BHSD` pass.
- `D` validation passes.
- `QGrad`, `KGrad`, or `VGrad` fail in the main backward kernel.

That combination strongly points to a side-buffer address bug rather than a primary tensor stride bug.

Primary suspects:

- `Lse/D` base
- `dq_acc` or 32-bit `dQ` temporary base
- sometimes `dK` / `dV` descriptor base on special paths

## Why This Happens

The main Q/K/V/O/dO tensors usually use runtime layout strides packed by the host, so they survive layout changes.

The side buffers do not:

- `Lse/D` is always logically `[B, H, S]` in fp32.
- some kernels infer its batch term from `s_BAs`
- some kernels derive `dq_acc` from the same bad base

That shortcut works for non-`SBHD` layouts and breaks for `SBHD`.

## Stage Split

Use:

```bash
./bwd.exe ... -kname=1 -v=1 -v3_dump_args=1 -v3_check_d=1
```

Interpretation:

- `D` passes, gradients fail:
  main `dqdkdv` shader is broken
- `D` already fails:
  earlier `ODO` / side-buffer path is broken

## Layout Triage

Always compare the same runtime kernel across:

- `-ilayout=2 -olayout=2` (`SBHD`)
- `-iperm=0 -operm=0` (`BSHD`)
- `-iperm=1 -operm=1` (`BHSD`)

If only `SBHD` fails, focus on layout-invariant side buffers first.

## Active Source Mapping

Before editing a shader, verify it is really the live source for the runtime kernel.

Use:

1. `aiter/csrc/cpp_itfs/mha_bwd.cu`
   - dispatch logic
   - `pddv` and `pssk` selection
2. `aiter/hsa/gfx942/fmha_v3_bwd/fmha_bwd_dqdkdv.csv`
   - runtime row to `.co` mapping
3. `poc_kl/mi300/fmha_bwd_asm/scripts/auto_integration.py`
   - supported source families
4. `poc_kl/mi300/fmha_bwd_asm/scripts/poc.log`
   - which source `sp3` was translated to which runtime `.co`

### Current gfx942 Findings

These are repo-specific, not universal:

- `D128 32mx1` is skipped by `auto_integration.py`
- active `D128 A32` direct runtime kernels map to:
  - `BF16_FMHA_BWD_D128_1TG_4W_16mx1_48nx4_A32.sp3`
  - `FP16_FMHA_BWD_D128_1TG_4W_16mx1_48nx4_A32.sp3`
  - `BF16_FMHA_BWD_D128_1TG_4W_16mx1_48nx4_A32_cas_kb.sp3`
  - `FP16_FMHA_BWD_D128_1TG_4W_16mx1_48nx4_A32_cas_kb.sp3`
- active `D128 A32 psskddv/group/swa/causal_br` runtime kernels map to the `Genl` family

Do not reuse these assumptions blindly on `gfx950`.

## Fix Pattern A: ABI-Based `Lse/D` Base

Use this when SGPR headroom exists and the ABI exposes the required values.

Typical packed values:

- `nhead_q`
- `Hs_lsed`

Target math:

```text
LseD_base = batch_id * nhead_q * Hs_lsed + head_id * Hs_lsed
```

This is the most robust fix because it stops inferring `BHS` side-buffer math from a layout-dependent tensor batch stride.

Use this when:

- the source already has spare SGPR aliases, or
- you can safely add them without blowing SGPR limits

## Fix Pattern B: SGPR-Safe Heuristic

Use this when the kernel is SGPR-tight.

Detect `SBHD` with:

```text
s_BAs < s_Seqs
```

That is not a general mathematical truth; it is a practical runtime discriminator for this kernel family and test regime.

For the `Lse/D` batch term, the common structure is:

```text
batch_term = batch_id * s_BAs

if SBHD:
    batch_term >>= (H_DIM_LOG2 + 1)
    batch_term *= s_seq_len
    batch_term <<= 2
else:
    batch_term >>= (H_DIM_LOG2 - 1)
```

Then:

```text
LseD_base = head_id * s_seq_len * 4 + batch_term
```

For causal direct kernels, keep any extra per-tile term such as `SUB_KV * 4 * s_tg_idx` after fixing the base.

## Fix Pattern C: `dQ` Derives from `Hdim * s_LseD_base`

If the direct kernel says something like:

```text
when dQ in 32bits, its offset is Hdim*s_LseD_base
```

then fixing `s_LseD_base` is usually enough for `dq_acc`.

This was the important distinction in the active `D128 A32` direct source family.

## Fix Pattern D: Separate `dQ` Batch Fix

If the shader separately computes `s_dQ_base` from `s_BAs`, patch that batch term too.

Typical clue:

```text
// dQ always in bhsd layout
s_mul_i32 s_tmp2, s_tg_idz, s_BAs
...
s_add_u32 s_dQ_base, ...
```

Then mirror the same `SBHD` branch used for `Lse/D`, but in the units expected by the `dQ` path.

Do not apply this blindly if `dQ` already derives from `s_LseD_base`.

## SWA / Group / causal_br

Do not assume these share the same bug.

Rules:

- rerun the exact failing case once or twice before patching
- inspect whether `LseD_base`, `dQ`, and `dK`/`dV` already use layout-invariant math
- only patch when the failing path actually uses `s_BAs` incorrectly

In this repo, the final broad rerun passed all runtime-mapped `SWA`, `group`, and `causal_br` cases without extra SWA-specific source edits.

## Rebuild Workflows

### Supported `Gen` / `Genl` via `auto_integration.py`

Use when the source family is supported by integration:

```bash
docker exec cjc_aiter bash -lc '
  cd /mnt/raid0/jingchao/poc_kl/mi300/fmha_bwd_asm/scripts &&
  python3 auto_integration.py \
    --target=<SOURCE_SP3> \
    --lib=/mnt/raid0/jingchao/mi300_sp3_to_asm/ \
    --aiter=/mnt/raid0/jingchao/aiter/
'
```

Warnings:

- this may replace many `.co` files at once
- inspect the source-family mapping first

### Direct Source Rebuild

Use when the live kernel is sourced from a direct `sp3` and not a supported integrated family.

Run inside Docker and export `libsp3.so`:

```bash
export LD_LIBRARY_PATH=/mnt/raid0/jingchao/mi300_sp3_to_asm:${LD_LIBRARY_PATH:-}
```

Then:

1. source `sp3` -> binary
2. binary -> raw expanded `sp3`
3. raw expanded `sp3` -> `.s` via `scripts/hsa.py`
4. `.s` -> `.co` via `clang++`

Pattern:

```bash
cd /mnt/raid0/jingchao/mi300_sp3_to_asm
./sp3 /path/to/source.sp3 -binary /path/to/tmp.bin
./sp3 -binary /path/to/tmp.bin /path/to/raw.sp3

python3 /mnt/raid0/jingchao/poc_kl/mi300/fmha_bwd_asm/scripts/hsa.py \
  /path/to/raw.sp3 \
  /path/to/out.s \
  <aiter_symbol_suffix>

/opt/rocm/llvm/bin/clang++ -x assembler -target amdgcn--amdhsa \
  --offload-arch=gfx942 \
  /path/to/out.s \
  -o /mnt/raid0/jingchao/aiter/hsa/gfx942/fmha_v3_bwd/<kernel>.co
```

## Verification Workflows

### Focused A16 Regressions

```bash
docker exec cjc_aiter bash -lc '
  cd /mnt/raid0/jingchao/aiter/op_tests/cpp/mha &&
  bash verify_a16_sbhd_kernels.sh
'
```

### Broad Runtime-Mapped Sweep

```bash
docker exec cjc_aiter bash -lc '
  cd /mnt/raid0/jingchao/aiter/op_tests/cpp/mha &&
  bash verify_sbhd_source_kernels.sh
'
```

This script is the highest-signal check for the current repo because it:

- walks the runtime `dqdkdv` CSV
- chooses representative `SBHD` cases
- validates actual loaded `.co` names

### One-Off Control Cases

Use single representative cases to compare:

- `SBHD`
- `BSHD`
- `BHSD`

and add:

```bash
-v3_dump_args=1 -v3_check_d=1
```

when you need packed stride evidence or stage split.

## gfx950 Porting Checklist

Before applying any fix on `gfx950`:

1. map the live runtime source family again
2. do not assume `gfx942` source-family choices still hold
3. reproduce one plain and one causal failing `SBHD` case
4. compare against `BSHD` / `BHSD`
5. use `-v3_check_d=1`
6. inspect `Lse/D` base first
7. inspect `dq_acc` / `dQ` next
8. only then inspect `dK` / `dV`
9. choose ABI or heuristic fix based on SGPR headroom
10. rebuild from the real source path, not the convenient-looking one

## Short Lessons Learned

- The first named `sp3` file is often not the live source.
- `D` passing is a very strong clue that the bug is in the main backward stage, not `ODO`.
- `SBHD`-only failures usually come from layout-invariant side buffers, not Q/K/V stride packing.
- `dQ` may or may not need a second fix depending on whether it already uses `Hdim * s_LseD_base`.
- A broad runtime-mapped verifier is worth having before touching multiple kernel families.
