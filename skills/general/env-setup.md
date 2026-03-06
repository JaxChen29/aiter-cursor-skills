---
name: env-setup
description: Set up the development environment for aiter kernel work on MI300X. Use when the user needs to configure docker, toolchain paths, GPU selection, or environment variables for aiter development.
---

# Environment Setup

## Docker Container

```bash
docker exec -it cjc_aiter bash
```

## Required Environment Variables

Set these in every new shell session:

```bash
export AITER_ASM_DIR=/path/to/aiter/hsa
export LD_LIBRARY_PATH=/path/to/aiter/op_tests/cpp/mha:$LD_LIBRARY_PATH
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
```

## GPU Selection

Large-address tests need ~40-100 GB VRAM. Always check GPU availability first:

```bash
rocm-smi --showmemuse --showuse
```

Pick a GPU with low memory usage:

```bash
export HIP_VISIBLE_DEVICES=2   # use GPU 2
```

## Directory Layout

| Path | Description |
|------|-------------|
| `poc_kl/mi300/fmha_bwd_asm/shaders/` | SP3 source files |
| `poc_kl/mi300/fmha_bwd_asm/scripts/` | Build scripts (`auto_integration.py`) |
| `poc_kl_merg/scripts/common/` | SP3 assembler toolchain (`sp3`, `hsa.py`) |
| `aiter/hsa/gfx942/fmha_v3_bwd/` | Compiled `.co` kernel binaries |
| `aiter/op_tests/` | Test scripts |

## Toolchain Dependencies

| Tool | Location | Purpose |
|------|----------|---------|
| `sp3` | `poc_kl_merg/scripts/common/` | SP3 assembler |
| `hsa.py` | `poc_kl/mi300/fmha_bwd_asm/scripts/` | SP3 binary to HSA assembly |
| `clang++` | ROCm installation | Assembles `.s` to `.co` |
| `elf2hex` | `poc_kl/mi300/fmha_bwd_asm/hsaco_to_hex/` | CO to hex (for CK integration) |

## All Environment Variables

| Variable | Purpose |
|----------|---------|
| `AITER_ASM_DIR` | Path to HSA directory with `.co` binaries |
| `HIP_VISIBLE_DEVICES` | Select GPU(s) |
| `PYTORCH_CUDA_ALLOC_CONF` | PyTorch memory allocator config |
| `AITER_V3_BWD_CK_ODO=1` | Force CK fallback for ODO kernel |
| `AITER_V3_BWD_CK_DQ_CONVERT=1` | Force CK fallback for dQ_convert |
| `AITER_DISABLE_V3_FWD=1` | Use CK for forward pass |
| `LD_LIBRARY_PATH` | Must include MHA test library path |

## Verification

After setup, verify everything works:

```bash
# Check GPU is visible
rocm-smi

# Check aiter is importable
python -c "import aiter; print(aiter.__file__)"

# Check ASM dir is set
ls $AITER_ASM_DIR/gfx942/fmha_v3_bwd/*.co | head -5

# Quick correctness test
cd /path/to/aiter/op_tests
python test_large_addr.py --kernel=bwd_hd64_bf16_a32_rtz_pssk.co --normal
```
