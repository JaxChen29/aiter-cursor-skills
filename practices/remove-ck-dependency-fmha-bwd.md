# Remove CK Dependency from FMHA BWD (ONLY_FAV3)

## Problem

The FMHA backward V3 ASM build (`module_fmha_v3_bwd`, `module_fmha_v3_varlen_bwd`) compiled with
`ONLY_FAV3=1` depends only on precompiled `.co` ASM kernel binaries, yet the build system still
required the full Composable Kernel (CK) submodule at `3rdparty/composable_kernel/` for:

- `ck_tile/core.hpp` (via `aiter_hip_common.h`) -- provides `stream_config`, `index_t`, `log2e_v`, `launch_kernel`
- `fmha_bwd.hpp` (via `mha_bwd.h`) -- provides `fmha_bwd_traits`, CK `fmha_bwd_args`, CK dispatch functions
- `mask.hpp` -- provides `mask_enum`, `mask_info`, `make_generic_attention_mask_coordinates_from_lr_window`
- `bias.hpp` -- provides `bias_enum`
- `CK_DIR/example/ck_tile/01_fmha` include path in `optCompilerConfig.json`
- `-DCK_TILE_FMHA_FWD_FAST_EXP2=1` compile flag

This made the V3-only build unnecessarily slow and tightly coupled to CK.

## Solution

Use the existing `ONLY_FAV3` macro (already set to 1 for V3 modules) to gate CK-only headers
at compile time, and provide a self-contained shim header (`ck_tile_shim.h`) that replaces all
CK types, enums, and utility functions the V3 path needs.

### Design principle

The shim provides standalone implementations of everything the V3 code path uses, so
downstream source files (`asm_mha_bwd.cu`, `asm_mha_varlen_bwd.cu`, `mha_bwd.cu`) need
**zero `#if ONLY_FAV3` guards** for mask/bias logic -- they use `mask_info::decode()`,
`bias_enum::alibi`, etc. identically whether CK or the shim provides them.

### Include chain

```
mha_bwd.cu / asm_mha_bwd.cu / asm_mha_varlen_bwd.cu
  -> aiter_hip_common.h (or py_itfs_common.h -> aiter_hip_common.h)
       -> #if ONLY_FAV3
            #include "ck_tile_shim.h"     // standalone shim
          #else
            #include "ck_tile/core.hpp"   // real CK
          #endif
  -> mha_bwd.h
       -> #if !ONLY_FAV3
            #include "fmha_bwd.hpp"       // CK FMHA (skipped for V3)
          #endif
```

### What the shim provides (`ck_tile_shim.h`)

| Category | Symbols | Notes |
|----------|---------|-------|
| **ck_tile:: types** | `index_t`, `long_index_t`, `stream_config`, `log2e_v<T>`, `get_warp_size()`, `launch_kernel()` | Mirror CK's types/API |
| **Enums** | `mask_enum` (no_mask, mask_top_left, mask_bottom_right, window_generic), `bias_enum` (no_bias, elementwise_bias, alibi) | Copied from CK's `mask.hpp` / `bias.hpp` |
| **Mask utilities** | `mask_info` struct with full `decode()`, `serialize()` | Self-contained reimplementation using `compute_mask_coordinates()` instead of CK's `make_generic_attention_mask_coordinates_from_lr_window()` |
| **Coordinate helper** | `compute_mask_coordinates()` | Equivalent to CK's `make_generic_attention_mask_coordinates_from_lr_window` but returns `std::pair<int,int>` |

### Files changed

**1. NEW: `csrc/include/ck_tile_shim.h`**

Self-contained shim (~220 lines) providing all types above. No CK headers included.
No `__has_include` -- always provides standalone definitions.

**2. `csrc/include/aiter_hip_common.h`**

```cpp
#if ONLY_FAV3
#include "ck_tile_shim.h"
#else
#include "ck_tile/core.hpp"
#endif
```

Safe for all other modules: `#if ONLY_FAV3` evaluates to 0 when the macro is undefined.

**3. `csrc/include/mha_bwd.h`**

```cpp
#if !ONLY_FAV3
#include "fmha_bwd.hpp"
#endif
```

**4. `csrc/include/py_itfs_common.h`**

Guard `t2ck` template specializations (which use `ck_tile::fp32_t`, `fp16_t`, `bf16_t`,
`int8_t`) with `#if !ONLY_FAV3`. These types are CK-specific and unused by V3 code.

**5. `csrc/cpp_itfs/mha_bwd.cu`**

- SWA mask coordinate block dual-pathed: shim's `compute_mask_coordinates()` vs CK's
  `make_generic_attention_mask_coordinates_from_lr_window`
- CK fallback in `mha_bwd()` already guarded by existing `#if ONLY_FAV3` / `#else`

**6. `csrc/py_itfs_cu/asm_mha_bwd.cu` and `asm_mha_varlen_bwd.cu`**

No changes needed -- `mask_info::decode()`, `bias_enum`, `mask.type`, `mask.left`,
`mask.right` all work identically via the shim. Zero `#if ONLY_FAV3` guards in these files.

**7. `aiter/jit/optCompilerConfig.json`**

For `module_fmha_v3_bwd` and `module_fmha_v3_varlen_bwd`:

```json
"flags_extra_hip": [],       // was: ["-DCK_TILE_FMHA_FWD_FAST_EXP2=1"]
"extra_include": [],         // was: ["CK_DIR/example/ck_tile/01_fmha"]
```

Kept: `flags_extra_cc: ["-DONLY_FAV3=1"]`, `blob_gen_cmd` (ASM codegen).

**8. `op_tests/cpp/mha/build_mha.sh`**

The benchmark binary (`bwd.exe`) still uses CK include paths -- it needs CK for reference
computation. Only the library is CK-free.

## Key patterns

### Guard pattern

Use `#if ONLY_FAV3` (not `#ifdef`) because the macro may be defined as 0 for full CK modules:

```cpp
#if ONLY_FAV3
// V3-only path: shim provides types
#else
// Full path: real CK headers
#endif
```

### Shim design: no `__has_include`

Do NOT use `__has_include("ck_tile/core.hpp")` in the shim -- it defeats the purpose by
pulling in CK when the 3rdparty dir or system ROCm provides the headers. The shim must
always provide its own standalone definitions.

### Keep pybind files clean

By putting `mask_enum`, `bias_enum`, and `mask_info` (with full `decode()`) into the shim,
the pybind interface files (`asm_mha_bwd.cu`, `asm_mha_varlen_bwd.cu`) need zero
`#if ONLY_FAV3` guards. The calling code is identical whether CK or the shim is used.
Avoid magic numbers -- use the enum types from the shim.

### Stale blob cleanup

When switching between CK and CK-free builds, old CK-generated `.cpp` blob files
(e.g., `fmha_bwd_convert_dq_*.cpp`, `fmha_bwd_api.cpp`) may persist in the blob directory
and cause `fmha_bwd.hpp not found` errors. Fix:

```bash
rm -rf aiter/jit/build/libmha_bwd/
rm -rf aiter/jit/build/module_fmha_v3_bwd/
rm -rf aiter/jit/build/module_fmha_v3_varlen_bwd/
```

## Verification

### 1. Build without CK

```bash
mv 3rdparty/composable_kernel 3rdparty/composable_kernel.bak
rm -rf aiter/jit/build/libmha_bwd/
# inside docker:
cd op_tests/cpp/mha && python3 compile.py --api=bwd_v3
# should succeed with EXIT=0
mv 3rdparty/composable_kernel.bak 3rdparty/composable_kernel
```

### 2. Symbol check

```bash
nm -D aiter/jit/build/libmha_bwd/build/libmha_bwd.so | grep -c 'fmha_bwd_dot\|fmha_bwd_convert_dq\|FmhaBwd'
# expected: 0
```

### 3. C++ smoke test

```bash
cd op_tests/cpp/mha
bash build_mha.sh bwd_v3
export AITER_ASM_DIR=/path/to/aiter/hsa
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH
bash smoke_test_bwd_v3.sh
```

### 4. Python API test

```bash
# inside docker:
cd op_tests && python3 test_mha.py
```

### 5. Non-regression (full CK path)

```bash
cd op_tests/cpp/mha
bash build_mha.sh bwd   # builds with full CK, ONLY_FAV3 not set
```

## Gotchas

1. **Library vs benchmark**: The library (`libmha_bwd.so`) is CK-free. The benchmark
   (`bwd.exe` / `benchmark_mha_bwd.cpp`) still needs CK for `ck_tile::HostTensor`,
   `ck_tile::reference_batched_gemm`, `mask_info::decode` (CK version), etc. These are
   test utilities, not part of the shipped library.

2. **Non-regression**: Full CK modules (`module_mha_bwd`, `module_mha_varlen_bwd` with
   `ONLY_FAV3=0`) are unaffected -- guards only activate when `ONLY_FAV3==1`.

3. **`aiter_hip_common.h` is shared**: ~40 files include it. The conditional include
   affects only compilation units where `ONLY_FAV3` is defined (the 2 V3 bwd modules).
   All other modules (MoE, PA, MLA, GEMM, etc.) get the real CK header as before.

4. **Global CK include path**: The build system adds `CK_3RDPARTY_DIR/include` globally
   for all modules when CK exists. This is harmless -- the shim controls what gets included
   via the `#if ONLY_FAV3` guard, not via include path removal.

5. **CI pybind compilation**: The V3 modules compile `asm_mha_bwd.cu` and
   `asm_mha_varlen_bwd.cu` which include `py_itfs_common.h`. The `t2ck` templates in
   that header use CK-specific types (`ck_tile::fp32_t` etc.) that the shim doesn't provide.
   Guard them with `#if !ONLY_FAV3` -- they are unused by V3 code.

6. **`fmha_bwd_traits` struct mismatch**: The CK fallback path (`#else` in `mha_bwd()`)
   must match the field order of the CK `fmha_bwd_traits` struct on the current branch.
   This struct's layout varies across CK versions -- verify after submodule updates.
