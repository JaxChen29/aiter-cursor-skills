# 64-bit Address Overflow Fix for FMHA BWD SP3 Kernels

## Problem

When running MHA backward pass with large tensors (e.g., `batch=8, nhead=40, seqlen=75600, hdim=128`),
buffer addresses exceed the 32-bit range. SP3 assembly kernels compute buffer descriptor base addresses
by accumulating tile, head, and batch offsets in a single 32-bit register, which silently truncates
when the sum exceeds 2^32, causing incorrect memory accesses and wrong output.

Symptom: `test_large_addr.py --large-q` fails with large dQ diff (e.g., 0.9375 vs tolerance 0.3125).
Normal-sized tests pass because offsets stay within 32-bit range.

## Investigation

### Root cause analysis

Two buggy patterns were identified across all SP3 files:

**Variant A: No 64-bit handling at all**

The code computes a 32-bit base offset and adds it to the buffer descriptor with `s_addc_u32 ... 0 ...`
(zero for high word):

```asm
s_mul_i32        s_tmp2,      batch_idx,    batch_stride   // 32-bit only!
s_add_u32        s_X_base,    s_X_base,     s_tmp2         // can overflow
s_add_u32        buf[0],      s_X_base,     buf_save[0]    // SCC = carry
s_addc_u32       buf[1],      0,            buf_save[1]    // high word always 0 -- BUG
```

**Variant B: Has `s_mul_hi_u32` but carry lost**

The code captures high bits, but `s_and_b32 0xffff` clobbers SCC between the `s_add_u32`
and `s_addc_u32`:

```asm
s_add_u32        s_X_base,    s_X_base,     s_tmp2         // SCC = CARRY
s_mul_hi_u32     s_tmp2,      batch_idx,    batch_stride   // SCC unchanged
s_and_b32        s_tmp2,      s_tmp2,       0xffff         // SCC CLOBBERED!
s_add_u32        buf[0],      s_X_base,     buf_save[0]    // new SCC
s_addc_u32       buf[1],      s_tmp2,       buf_save[1]    // MISSING old carry!
```

### Key ISA insight

| Instruction      | Modifies SCC? |
|-----------------|---------------|
| `s_mul_i32`     | No            |
| `s_mul_hi_u32`  | No            |
| `s_add_u32`     | Yes (carry)   |
| `s_addc_u32`    | Yes (carry), reads SCC as carry-in |
| `s_and_b32`     | Yes (!=0)     |
| `s_mov_b32`     | No            |

**Critical rule:** Between `s_add_u32` (sets carry) and `s_addc_u32` (reads carry),
no SCC-modifying instructions are allowed.

## Solution

**Principle:** Never accumulate the batch/seq offset into the 32-bit base register.
Add it to the buffer descriptor as a separate 64-bit addition with its own carry chain.

### Fix pattern

```asm
// Before: batch offset baked into s_X_base (32-bit overflow risk)
// After: add tile+head to buf, then add 64-bit batch offset separately

s_add_u32        s_X_base,    s_tmp0,       s_tmp1         // tile + head only (no batch!)
s_add_u32        buf[0],      s_X_base,     buf_save[0]    // SCC = carry
s_addc_u32       buf[1],      0,            buf_save[1]    // propagate carry
// Add 64-bit batch offset
s_mul_i32        s_tmp0,      batch_idx,    batch_stride   // batch_low
s_mul_hi_u32     s_tmp1,      batch_idx,    batch_stride   // batch_high
s_and_b32        s_tmp1,      s_tmp1,       0xffff         // mask to 48-bit (clobbers SCC, OK here)
s_add_u32        buf[0],      buf[0],       s_tmp0         // SCC = carry from batch_low
s_addc_u32       buf[1],      buf[1],       s_tmp1         // + batch_high + carry
```

### Special cases handled

- **Shared base registers** (e.g., `s_Q_base = s_dO_base`): apply batch offset to BOTH buffer descriptors
- **Different strides per buffer**: compute 64-bit offset separately for each (K, V, dK, dV may differ)
- **MODE==0 vs MODE==1**: batch mode uses `s_tg_idz * s_BAs_X`, group mode uses `s_sq_start * s_Seqs_X`
- **dQ VGPR overflow (D64)**: move `s_dQ_base` from VGPR to buffer descriptor `buf[0:1]` with 64-bit carry chain
- **LseD intermediate overflow**: use 64-bit multiply then combine shifted halves

### Fix progression

| Version | Date | What was fixed |
|---------|------|----------------|
| V1 | 2026-01-26 | Added `s_mul_hi_u32` for batch stride (but carry still lost) |
| V2 | 2026-01-27 | Separated batch offset, own carry chain (K,V,Q,dO in D128 Genl) |
| V3 | 2026-01-27 | dQ_convert head offset overflow in group mode |
| V4 | 2026-01-27 | dK/dV/LseD/dQ overflow in non-Genl batch-mode kernels |
| V5 | 2026-03-04 | dQ VGPR overflow in D64 Genl kernels |

### Files fixed

**Main dQdKdV kernels:** All D64, D128, D192 SP3 files (BF16/FP16, batch/group, A16/A32 variants)

**Helper kernels:** `FMHA_BWD_ODO.sp3` (O, dO, D buffers), `FMHA_BWD_DQ_CONVERT.sp3` (dQ_acc, dQ buffers)

## Lessons

1. **Always use 64-bit arithmetic for buffer offsets** that multiply batch/head indices by strides.
   Even if individual components fit 32-bit, their sum or product may not.

2. **SCC carry chain is fragile.** Any SCC-modifying instruction between `s_add_u32` and `s_addc_u32`
   silently breaks the carry propagation. `s_and_b32`, `s_lshr_b32`, `s_or_b32`, `s_sub_i32`,
   and `s_cmp_*` all modify SCC.

3. **Test with overflow-inducing sizes.** Normal-sized tests (seqlen=256) pass even with the bug.
   The `test_large_addr.py` tool dynamically computes seqlens per hdim to guarantee 32-bit overflow.

4. **Isolate kernel stages.** Use `AITER_V3_BWD_CK_ODO=1` and `AITER_V3_BWD_CK_DQ_CONVERT=1`
   to force CK fallback for helper kernels and isolate the dQdKdV ASM kernel.

5. **Check VGPR overflow too.** D64 kernels add `s_dQ_base` to VGPRs via `v_add_u32`, which also
   truncates at 32-bit. The fix is to move the large offset into the buffer descriptor instead.

6. **V1 fix introduced V2 bug.** Adding `s_mul_hi_u32` without fixing the carry chain created
   a false sense of security. Always verify the full carry chain end-to-end.
