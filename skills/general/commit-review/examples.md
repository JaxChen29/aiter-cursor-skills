# Commit Review Examples

## Example prompts

- `Review commit 874a6ae356381f4b0e9ebdf8c13412f827f29dd1 in poc_kl.`
- `Review my latest commit in poc_kl.`
- `I just made a new commit. Please review HEAD for correctness and missing tests.`

## Worked example: `874a6ae356381f4b0e9ebdf8c13412f827f29dd1`

### Commit summary

- **Repo:** `poc_kl`
- **Message:** `fix other lse addr compute`
- **Scope:** 16 shader files under `mi300/fmha_bwd_asm/shaders/`
- **Intent:** fix LseD base-address computation when the old batch/head stride assumptions do not hold

### What the review should inspect

- New dispatch loads at offsets `0x180` and `0x240`
- New SGPR aliases for `nhead_q` and `Hs_lsed`
- A16 and D64 variants switching from `s_BAs / head_dim * 2` to `batch_idx * nhead_q * Hs_lsed + head_idx * Hs_lsed`
- A32 variants adding an SBHD-specific branch when `s_BAs < s_Seqs`
- Parity across BF16/FP16, D64/D128, `_Gen`, and `cas_kb` variants

### Example review output

```text
[Critical] mi300/fmha_bwd_asm/shaders/BF16_FMHA_BWD_D128_1TG_4W_16mx1_48nx4_A16_Gen.sp3:239
This generated shader now defines `_s_Hs_lsed` and `_s_nhead_q` twice, then repeats the matching `s_load_dword` instructions at lines 2643-2646. If redefinition is rejected, the file will not assemble; if it is accepted, the generated variant still diverges from the intended single-load fix used elsewhere.
Regenerate or patch the generator so each SGPR alias and each LseD metadata load is emitted exactly once, then recheck the matching `_Gen` variants.

[Warning] mi300/fmha_bwd_asm/shaders/BF16_FMHA_BWD_D128_1TG_4W_16mx1_48nx4_A32.sp3:2708
The SBHD fix changes behavior based on `s_BAs < s_Seqs`. That looks plausible, but the commit itself does not provide validation proving both sides of the branch are correct for all supported layouts and head-count shapes.
Add targeted tests for both `s_BAs < s_Seqs` and `s_BAs >= s_Seqs` across BF16/FP16 A32 and `cas_kb` kernels.

[Warning] mi300/fmha_bwd_asm/shaders:1
This fix spans 16 closely related shader variants. Reviews of changes like this should verify parity across BF16/FP16, D64/D128, `_Gen`, and `cas_kb` files instead of assuming the variant matrix stayed synchronized.
Diff sibling variants in pairs and call out any intentionally different address formulas.

Open questions / assumptions
- Assumed kernarg offsets `0x180` and `0x240` already match the host-side launch ABI.
- Did not verify runtime tests or perf numbers from the commit alone.

Summary
- The commit is trying to correct LseD pointer arithmetic for layouts where the previous `s_BAs / head_dim * 2` assumption breaks.
- The highest risk is inconsistent patching of generated variants plus unproven layout coverage for the A32 SBHD branch.
```

### Why this is a good example

- It shows that a strong review can find a concrete bug in a generated variant instead of only restating the diff.
- It separates a proven issue from evidence gaps.
- It focuses on the actual risk surface of the change: ABI offsets, scalar register usage, layout assumptions, variant parity, and missing validation.
