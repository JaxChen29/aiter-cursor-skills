# aiter Project Context

## What is aiter

aiter is a high-performance GPU kernel library for AMD Instinct accelerators (MI300X/gfx942, MI350/gfx950).
It provides optimized operators for LLM inference and training: MHA (Multi-Head Attention), MLA, fused MoE,
GEMM, and more. Kernels are implemented in C++/HIP, Composable Kernel (CK), Triton, and hand-written
SP3 assembly (HSA).

## Key Paths

| Path | What |
|------|------|
| `aiter/` | Python package |
| `csrc/cpp_itfs/` | C++ pybind interfaces (e.g., `mha_bwd.cu`) |
| `csrc/ck_*/` | Composable Kernel wrappers |
| `hsa/gfx942/fmha_v3_bwd/` | Compiled `.co` kernel binaries for MI300X |
| `hsa/gfx950/` | Kernels for MI350 |
| `op_tests/` | Python operator tests |
| `3rdparty/composable_kernel/` | CK submodule |

## FMHA Backward Architecture

The backward pass has 3 kernel stages dispatched in sequence:
1. **ODO** -- computes `D[b][h][s] = sum_d(O * dO)`
2. **dQdKdV** -- main attention backward (the largest, most complex kernel)
3. **dQ_convert** -- converts accumulated FP32 dQ to FP16/BF16

Each stage can independently use ASM or CK (fallback). The C++ dispatch code in `mha_bwd.cu`
selects ASM when tile sizes match, otherwise falls back to CK automatically.

## SP3 Assembly Conventions

- Files live in `poc_kl/mi300/fmha_bwd_asm/shaders/`
- Naming: `{DTYPE}_FMHA_BWD_{HDIM}_{CONFIG}_{MASK}_{VARIANT}.sp3`
- Variables `RDM` (rounding mode) and `HDP` (head-dim padding) control BF16/group variants
- `MODE==0` = batch mode, `MODE==1` = group/varlen mode
- Buffer descriptors: `buf[0]` = base address low, `buf[1]` = base address high + flags, `buf[2]` = num_records

## 64-bit Address Safety

When computing buffer base addresses in SP3, always use 64-bit arithmetic for offsets
that can exceed 2^32 (batch stride * batch_idx, head stride * head_idx for large tensors).
Never place `s_and_b32` or any SCC-modifying instruction between `s_add_u32` and `s_addc_u32`.

## Naming Conventions

- CO files: `bwd_hd{dim}_{dtype}_{atomic}_{rounding}_{padding}[_group].co`
- Kernel symbols: `ZN5aiter{len}{name}E`
- dtype: `fp16` or `bf16`
- atomic: `a16` (atomic16) or `a32` (atomic32)
- rounding: `rtne` / `rtna` / `rtz` (BF16 only)
- padding: `pssk` (D64), `psskddv` (D128/D192), `pddv` (legacy)

## Build & Test Commands

```bash
# Build single kernel
python3 auto_integration.py --target=<sp3_file> --lib=<sp3_toolchain> --aiter=<aiter_path>

# Test kernel
python test_large_addr.py --kernel=<co_file>
```
