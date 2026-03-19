# Remove CK Dependency from FMHA FWD V3 with ENABLE_CK

## Problem

The FMHA forward V3 ASM build (`module_fmha_v3_fwd`, `module_fmha_v3_varlen_fwd`) compiled with
`FAV3_ON=1` depends only on precompiled `.co` ASM kernel binaries, yet the build system still
required the full Composable Kernel (CK) submodule for:

- `ck_tile/core.hpp` (via `aiter_hip_common.h`) -- provides `stream_config`, `index_t`, etc.
- `fmha_fwd.hpp` (via `mha_fwd.h`) -- provides `fmha_fwd_traits`, CK arg types, CK dispatch functions
- `mask.hpp` -- provides `mask_enum`, `mask_info`
- `CK_DIR/example/ck_tile/01_fmha` include path
- `-DCK_TILE_FMHA_FWD_FAST_EXP2=1` compile flag

Additionally, the original `ONLY_FAV3` macro was renamed to a more general `ENABLE_CK` mechanism
that applies to both forward and backward V3 modules.

## Solution

### ENABLE_CK macro (replaces ONLY_FAV3 for header guards)

Introduced `ENABLE_CK` as the unified CK toggle for public headers. The semantic mapping from
the original `ONLY_FAV3`:

```
ONLY_FAV3=1  (CK disabled)  -->  ENABLE_CK=0
ONLY_FAV3=0  (CK enabled)   -->  ENABLE_CK=1  (default, set by core.py)
```

The default is injected by `core.py`'s `build_module()`:

```python
enable_ck = int(os.environ.get("ENABLE_CK", "1"))
if not any("ENABLE_CK" in f for f in flags_extra_cc):
    flags_cc.append(f"-DENABLE_CK={enable_ck}")
```

This reads the same `ENABLE_CK` env var that `setup.py` uses (defaults to `1`). Modules with
explicit `-DENABLE_CK=0` in their config (V3 modules) skip the global default.

### Guard pattern

```cpp
#if ENABLE_CK
// CK code -- compiled when CK is enabled (default)
#else
// Shim/standalone code -- compiled when CK is disabled
#endif

#if !ENABLE_CK
// CK-free path -- e.g., use ck_tile_shim.h
#endif
```

### Include chain when ENABLE_CK=0

```
mha_fwd.cu / asm_mha_fwd.cu
  -> mha_fwd.h
       -> aiter_hip_common.h
            -> #if !ENABLE_CK
                 #include "ck_tile_shim.h"     // standalone shim
               #else
                 #include "ck_tile/core.hpp"   // real CK
               #endif
       -> #if ENABLE_CK
            #include "fmha_fwd.hpp"            // CK FMHA (skipped)
            #include "mask.hpp"
          #endif
       -> <variant>                            // always needed by mha_fwd_args
```

### Files changed

**1. `csrc/include/mha_fwd.h`**

Guard CK-only includes and declarations with `#if ENABLE_CK`:

```cpp
#include "aiter_hip_common.h"
#if ENABLE_CK
#include "fmha_fwd.hpp"
#include "mask.hpp"
#endif
#include <variant>  // needed by mha_fwd_args regardless of CK

namespace aiter {
#if ENABLE_CK
struct mha_fwd_traits : public fmha_fwd_traits { ... };
struct mha_batch_prefill_traits : public fmha_batch_prefill_traits { ... };
struct mha_fwd_splitkv_traits : public fmha_fwd_splitkv_traits { ... };
#endif

struct mha_fwd_args { ... };  // Always available (uses ck_tile::index_t from shim)

#if ENABLE_CK
using mha_fwd_splitkv_args = fmha_fwd_splitkv_args;
using mha_batch_prefill_args = fmha_batch_prefill_args;
float mha_fwd_splitkv(...);
float mha_batch_prefill(...);
#endif

struct fmha_fwd_v3_args { ... };  // Always available (uses p2, p3 from aiter_hip_common.h)
float mha_fwd(...);               // Always available
float fmha_fwd_v3(...);           // Always available
```

**2. `csrc/include/aiter_hip_common.h`** (from BWD work, applies to FWD too)

```cpp
#if !ENABLE_CK
#include "ck_tile_shim.h"
#else
#include "ck_tile/core.hpp"
#endif
```

**3. `csrc/include/py_itfs_common.h`** (from BWD work, applies to FWD too)

```cpp
#if ENABLE_CK
template <typename T> struct t2ck;
// ... CK type mappings
#endif
```

**4. `csrc/include/mha_bwd.h`** (from BWD work)

```cpp
#if ENABLE_CK
#include "fmha_bwd.hpp"
#endif
```

**5. `aiter/jit/optCompilerConfig.json`**

For `module_fmha_v3_fwd` and `module_fmha_v3_varlen_fwd`:

```json
"flags_extra_cc": [
    "'-DFAV3_ON=1'",
    "'-DENABLE_CK=0'"
],
"flags_extra_hip": [],
"extra_include": [],
```

For `module_fmha_v3_bwd` and `module_fmha_v3_varlen_bwd`:

```json
"flags_extra_cc": [
    "'-DONLY_FAV3=1'",
    "'-DENABLE_CK=0'"
],
```

Note: `ONLY_FAV3=1` is still needed for BWD because `mha_bwd.cu` lines 133/135 still use it.
FWD does not need `ONLY_FAV3` because `FAV3_ON` is already in `core.py`'s `v3_flags` list.

**6. `aiter/jit/core.py`**

Added default `-DENABLE_CK=1` for all modules:

```python
enable_ck = int(os.environ.get("ENABLE_CK", "1"))
if not any("ENABLE_CK" in f for f in flags_extra_cc):
    flags_cc.append(f"-DENABLE_CK={enable_ck}")

flags_cc += flags_extra_cc
```

**7. `op_tests/cpp/mha/compile.py`**

Added `-DENABLE_CK=0` when `ck_exclude=True` for both fwd and bwd:

```python
# fwd
flag_use_v3 = "-DFAV3_ON=1 -DENABLE_CK=0" if ck_exclude else "-DFAV3_ON=1 -DFAV2_ON=1"

# bwd
flags_extra_cc = ["-DONLY_FAV3", "-DENABLE_CK=0"] if ck_exclude else []
```

**8. `op_tests/cpp/mha/build_mha.sh`**

Added `-DENABLE_CK=1` to benchmark binary `hipcc` commands (both fwd.exe and bwd.exe),
since they need real CK headers for reference computation.

## What does NOT need changing

- `ck_tile_shim.h` -- already provides everything fwd/bwd V3 needs
- `mha_fwd.cu` -- V3 and CK paths already separated by `FAV3_ON` / `FAV2_ON`
- `asm_mha_fwd.cu` / `asm_mha_varlen_fwd.cu` -- use shim-provided types, no guards needed

## Verification

### 1. Build without CK

```bash
mv 3rdparty/composable_kernel 3rdparty/composable_kernel.bak
rm -rf aiter/jit/build/module_fmha_v3_fwd/
rm -rf aiter/jit/build/module_fmha_v3_varlen_fwd/

# inside docker:
python -c "
from aiter.jit.core import get_args_of_build, build_module
d = get_args_of_build('module_fmha_v3_fwd')
build_module('module_fmha_v3_fwd', d['srcs'], d['flags_extra_cc'], d['flags_extra_hip'],
             d['blob_gen_cmd'], d['extra_include'], d['extra_ldflags'], d['verbose'],
             d['is_python_module'], d['is_standalone'], d['torch_exclude'],
             d.get('third_party', []))
"
# should succeed

mv 3rdparty/composable_kernel.bak 3rdparty/composable_kernel
```

### 2. Verify ENABLE_CK default

```bash
# Rebuild a non-V3 module, then inspect ninja file
grep -o 'ENABLE_CK=[01]' aiter/jit/build/module_aiter_enum/build/build.ninja
# expected: ENABLE_CK=1

grep -o 'ENABLE_CK=[01]' aiter/jit/build/module_fmha_v3_fwd/build/build.ninja
# expected: ENABLE_CK=0
```

### 3. Symbol check

```bash
nm -D aiter/jit/module_fmha_v3_fwd.so | grep -c 'fmha_fwd_traits\|fmha_fwd_splitkv\|fmha_batch_prefill'
# expected: 0
```

### 4. C++ smoke test

```bash
cd op_tests/cpp/mha
bash build_mha.sh fwd_v3
export AITER_ASM_DIR=/path/to/aiter/hsa
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH
bash smoke_test_fwd_v3.sh -a gfx942
```

## Gotchas

1. **`<variant>` include**: When guarding CK headers in `mha_fwd.h`, `std::variant` (used by
   `mha_fwd_args`) was previously pulled in transitively through CK headers. Must add explicit
   `#include <variant>` outside the `#if ENABLE_CK` guard.

2. **`core.py` default vs `build_mha.sh`**: The `core.py` default only applies to modules built
   through `build_module()`. Direct `hipcc` calls in `build_mha.sh` bypass this, so they need
   explicit `-DENABLE_CK=1`.

3. **`setup.py` connection**: `setup.py` has `ENABLE_CK = int(os.environ.get("ENABLE_CK", "1"))`.
   The `core.py` default reads the same env var, so setting `ENABLE_CK=0` globally disables CK
   at both the Python build system level (which modules to build) and the C preprocessor level
   (which headers to include).

4. **`ONLY_FAV3` vs `ENABLE_CK`**: `ONLY_FAV3` is still used in `mha_bwd.cu` (lines 133/135)
   and `core.py`'s `v3_flags` list. For BWD V3 modules, both flags coexist. For FWD V3 modules,
   only `FAV3_ON` and `ENABLE_CK=0` are needed (since `FAV3_ON` is already in `v3_flags`).

5. **Non-regression**: Full CK modules (`module_mha_fwd`, `module_mha_varlen_fwd`) are
   unaffected -- they get `ENABLE_CK=1` from the core.py default, so all CK code is compiled.

6. **`compile_template_op` path**: Modules built via `csrc/cpp_itfs/utils.py`'s `compile_lib()`
   (e.g., `pa_ragged`, `pa_v1`) bypass `core.py`'s `build_module()` entirely. They have their
   own flag list in `compile_lib()` and need `-DENABLE_CK=1` added there explicitly. Missing
   this caused CI failures where PA modules got the shim instead of real CK headers.
