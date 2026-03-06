---
name: aiter-dev
description: Build, install, and test the aiter project. Use when the user wants to build aiter from source, run operator tests, add new ops, or contribute code to the aiter repository.
---

# aiter Development Workflow

## Project Structure

| Directory | Purpose |
|-----------|---------|
| `aiter/` | Python package: ops, fused MoE, MLA, jit, dist |
| `csrc/` | C++/CUDA/HIP kernels and pybind interfaces |
| `3rdparty/` | Dependencies: `composable_kernel`, `ck_helper` |
| `hsa/` | HSA assembly kernels (`gfx942/`, `gfx950/`) |
| `op_tests/` | Operator tests, benchmarks, triton tests |
| `gradlib/` | Gradient library |

## Build from Source

```bash
# Inside the docker container
cd /path/to/aiter
pip install -e . --verbose 2>&1 | tee build.log
```

Key build files:
- `setup.py` -- main build (setuptools, pybind11, HIP extensions)
- `pyproject.toml` -- build config
- `requirements.txt` -- Python dependencies

## Running Tests

```bash
cd /path/to/aiter/op_tests

# Run a specific operator test
python test_mha.py

# Run backward MHA tests
python test_large_addr.py --list    # list available kernels
python test_large_addr.py --kernel=bwd_hd64_bf16_a32_rtz_pssk.co

# Run benchmarks
cd op_benchmarks
python bench_mha.py
```

## Adding a New Op

1. Implement the kernel in `csrc/` (C++/HIP/CK)
2. Add pybind interface in `csrc/cpp_itfs/`
3. Add Python wrapper in `aiter/ops/`
4. Add test in `op_tests/`
5. Update `setup.py` if new source files were added

## Code Style

- C/C++: `.clang-format` and `.clang-tidy` in repo root
- Python: standard PEP 8
- Commit messages: descriptive, prefix with area (e.g., `mha: fix backward pass`)

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `AITER_ASM_DIR` | Path to HSA directory containing `.co` binaries |
| `AITER_V3_BWD_CK_ODO=1` | Force CK fallback for ODO kernel |
| `AITER_V3_BWD_CK_DQ_CONVERT=1` | Force CK fallback for dQ_convert kernel |
| `AITER_DISABLE_V3_FWD=1` | Use CK for forward pass |
