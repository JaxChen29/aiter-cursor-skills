# Remove CK Dependency from FMHA BWD (ONLY_FAV3)

## Problem

The FMHA backward V3 ASM build (`module_fmha_v3_bwd`, `module_fmha_v3_varlen_bwd`) compiled with
`ONLY_FAV3=1` depends only on precompiled `.co` ASM kernel binaries, yet the build system still
required the full Composable Kernel (CK) submodule at `3rdparty/composable_kernel/` for:

- `ck_tile/core.hpp` (via `aiter_hip_common.h`) -- provides `stream_config`, `index_t`, `log2e_v`, `launch_kernel`
- `fmha_bwd.hpp` (via `mha_bwd.h`) -- provides `fmha_bwd_traits`, CK `fmha_bwd_args`, `mask_enum`, `bias_enum`, CK dispatch functions
- `mask.hpp` -- provides `mask_enum`, `mask_info`, `make_generic_attention_mask_coordinates_from_lr_window`
- `CK_DIR/example/ck_tile/01_fmha` include path in `optCompilerConfig.json`
- `-DCK_TILE_FMHA_FWD_FAST_EXP2=1` compile flag

This made the V3-only build unnecessarily slow and tightly coupled to CK.

## Solution

Use the existing `ONLY_FAV3` macro (already set to 1 for V3 modules) to gate all CK dependencies
at compile time, and provide a minimal shim header for the few `ck_tile::` types the V3 path needs.

### Approach

```
When ONLY_FAV3==1:
  aiter_hip_common.h  -->  ck_tile_shim.h  (instead of ck_tile/core.hpp)
  mha_bwd.h           -->  skip fmha_bwd.hpp
  mha_bwd.cu          -->  local mask_enum + compute_mask_coordinates()
  optCompilerConfig    -->  no CK include path, no CK flags
```

### Files changed

**1. NEW: `csrc/include/ck_tile_shim.h`**

Standalone shim providing `ck_tile::` types without any CK headers:

```cpp
namespace ck_tile {
  using index_t = int32_t;
  using long_index_t = int64_t;
  struct stream_config { hipStream_t stream_id_ = nullptr; ... };
  template <typename T> constexpr T log2e_v = ...;
  inline int get_warp_size() { return 64; }
  template <typename... Cs> float launch_kernel(const stream_config& s, Cs&&... cs) { ... }
}
```

**2. `csrc/include/aiter_hip_common.h`**

```cpp
// Before:
#include "ck_tile/core.hpp"
// After:
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

**4. `csrc/cpp_itfs/mha_bwd.cu`**

- Local `mask_enum` and `compute_mask_coordinates()` defined under `#if ONLY_FAV3`
- SWA mask coordinate block dual-pathed: local function vs CK's `make_generic_attention_mask_coordinates_from_lr_window`
- CK fallback in `mha_bwd()` already guarded by existing `#if ONLY_FAV3` / `#else`

**5. `aiter/jit/optCompilerConfig.json`**

For `module_fmha_v3_bwd` and `module_fmha_v3_varlen_bwd`:

```json
"flags_extra_hip": [],       // was: ["-DCK_TILE_FMHA_FWD_FAST_EXP2=1"]
"extra_include": [],         // was: ["CK_DIR/example/ck_tile/01_fmha"]
```

Kept: `flags_extra_cc: ["-DONLY_FAV3=1"]`, `blob_gen_cmd` (ASM codegen).

**6. `op_tests/cpp/mha/build_mha.sh`**

The benchmark binary (`bwd.exe`) still uses CK include paths -- it needs CK for reference
computation (`ck_tile::HostTensor`, `ck_tile::reference_batched_gemm`, etc.). Only the library
is CK-free.

## Key patterns

### Guard pattern

Use `#if ONLY_FAV3` (not `#ifdef`) because the macro may be defined as 0 for full CK modules:

```cpp
#if ONLY_FAV3
// V3-only path: no CK
#else
// Full path: uses CK
#endif
```

### Shim vs `__has_include`

Do NOT use `__has_include("ck_tile/core.hpp")` in the shim -- it defeats the purpose by
pulling in CK when the 3rdparty dir or system ROCm provides the headers. The shim should
always provide its own standalone definitions.

### Stale blob cleanup

When switching between CK and CK-free builds, old CK-generated `.cpp` blob files
(e.g., `fmha_bwd_convert_dq_*.cpp`, `fmha_bwd_api.cpp`) may persist in the blob directory
and cause `fmha_bwd.hpp not found` errors. Fix:

```bash
rm -rf aiter/jit/build/libmha_bwd/
```

## Verification

### 1. Build without CK

```bash
mv 3rdparty/composable_kernel 3rdparty/composable_kernel.bak
rm -rf aiter/jit/build/libmha_bwd/
# inside docker:
cd op_tests/cpp/mha && python3 compile.py --api=bwd_v3
# should succeed
mv 3rdparty/composable_kernel.bak 3rdparty/composable_kernel
```

### 2. Symbol check

```bash
nm -D aiter/jit/build/libmha_bwd/build/libmha_bwd.so | grep -c 'fmha_bwd_dot\|fmha_bwd_convert_dq\|FmhaBwd'
# expected: 0
```

### 3. Smoke test

```bash
cd op_tests/cpp/mha
bash build_mha.sh bwd_v3
export AITER_ASM_DIR=/path/to/aiter/hsa
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH
bash smoke_test_bwd_v3.sh
```

## Gotchas

1. **Library vs benchmark**: The library (`libmha_bwd.so`) is CK-free. The benchmark
   (`bwd.exe` / `benchmark_mha_bwd.cpp`) still needs CK for `ck_tile::HostTensor`,
   `ck_tile::reference_batched_gemm`, `mask_info::decode`, etc. These are test utilities,
   not part of the shipped library.

2. **Non-regression**: Full CK modules (`module_mha_bwd`, `module_mha_varlen_bwd` with
   `ONLY_FAV3=0`) are unaffected -- guards only activate when `ONLY_FAV3==1`.

3. **`aiter_hip_common.h` is shared**: The conditional include affects only compilation
   units where `ONLY_FAV3` is defined. Other modules (MoE, PA, etc.) get the real CK
   header as before.

4. **Global CK include path**: The build system adds `CK_3RDPARTY_DIR/include` globally
   for all modules when CK exists. This is harmless -- the shim controls what gets included
   via the `#if ONLY_FAV3` guard, not via include path removal.
