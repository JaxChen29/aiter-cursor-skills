# Identify MI300 vs MI308 Device by PCI Chip ID

## Problem

The FMHA V3 forward path loads pre-compiled `.co` (code object) kernel binaries from
device-specific subdirectories (`MI300/` or `MI308/` under `hsa/gfx942/fmha_v3_fwd/`).
The MI300 and MI308 `.co` files have identical names but are different binaries tuned for
each chip -- loading the wrong one causes kernel launch failures.

The original identification logic used `hipDeviceProp_t.multiProcessorCount` (CU count)
with hardcoded values (`304` = MI300, `80` or `64` = MI308). This breaks in DPX (Dynamic
Partition eXecution) mode where the visible CU count changes depending on the partition
configuration, causing device identification to fail and "file not found" errors.

### Methods investigated and why they don't work

| Method | Why it fails |
|--------|-------------|
| `hipDeviceProp_t.multiProcessorCount` | Changes in DPX partition mode |
| `hipDeviceAttributePhysicalMultiProcessorCount` | Also returns masked count in DPX mode, not true hardware count |
| `hipDeviceProp_t.name` | Empty string in Docker containers due to `libdrm` error (`amdgpu_get_marketing_name()` fails when container's libdrm version doesn't match the host kernel's amdgpu driver) |
| `rocminfo` Marketing Name | Also empty for the same libdrm reason |
| `hipDeviceProp_t.totalGlobalMem` | Heuristic; fragile across SKUs and memory configurations |

### Methods that work

| Method | How | Reliability |
|--------|-----|-------------|
| **`hipDeviceAttributePciChipId`** | `hipDeviceGetAttribute(&id, hipDeviceAttributePciChipId, dev)` | Hardware constant, never changes in any mode |
| **sysfs `product_name`** | Read `/sys/class/drm/cardN/device/product_name` (e.g. "AMD Instinct MI308X OAM") | Bypasses libdrm, reads from GPU firmware directly |
| **sysfs `vbios_version`** | Read `/sys/class/drm/cardN/device/vbios_version` (e.g. "113-M3080202-101", contains "M308") | Same reliability as product_name |

## Solution

Use `hipDeviceAttributePciChipId` to identify MI308 devices. This is a PCI device ID
burned into the silicon that never changes regardless of DPX mode, CU masking, or
container environments.

### MI308 PCI Chip IDs (no co-execution)

From the official AMD device ID registry (http://jumpgate.amd.com/ati_dev_id/):

| Chip ID | Device |
|---------|--------|
| `0x74A2` | MI308 |
| `0x74A8` | MI308 |
| `0x74B6` | MI308 |
| `0x74BC` | MI308 |

All other gfx942 device IDs have co-execution and use the MI300 kernel path.

### C++ implementation (`csrc/include/aiter_hip_common.h`)

```cpp
static int get_pci_chip_id()
{
    static const int chip_id = []() {
        hipDevice_t dev;
        int id = 0;
        HIP_CALL(hipGetDevice(&dev));
        HIP_CALL(hipDeviceGetAttribute(&id, hipDeviceAttributePciChipId, dev));
        return id;
    }();
    return chip_id;
}

static bool is_mi308_device()
{
    int chip_id = get_pci_chip_id();
    return chip_id == 0x74a2 || chip_id == 0x74a8 ||
           chip_id == 0x74b6 || chip_id == 0x74bc;
}
```

### Kernel path selection (`csrc/cpp_itfs/mha_fwd.cu`)

```cpp
if(arch_id == "gfx942")
{
    auto pos = cfg_co_name.rfind('/');
    if(is_mi308_device())
        co_name = cfg_co_name.substr(0, pos + 1) + "MI308/" + cfg_co_name.substr(pos + 1);
    else
        co_name = cfg_co_name.substr(0, pos + 1) + "MI300/" + cfg_co_name.substr(pos + 1);
}
```

### Python implementation (`aiter/jit/utils/chip_info.py`)

```python
def _get_pci_chip_id(device_id=0):
    import ctypes
    libhip = ctypes.CDLL("libamdhip64.so")
    chip_id = ctypes.c_int(0)
    hipDeviceAttributePciChipId = 10019
    err = libhip.hipDeviceGetAttribute(
        ctypes.byref(chip_id), hipDeviceAttributePciChipId, device_id)
    if err != 0:
        raise RuntimeError(f"hipDeviceGetAttribute(PciChipId) failed with error {err}")
    return chip_id.value

MI308_CHIP_IDS = {0x74A2, 0x74A8, 0x74B6, 0x74BC}

def get_device_name():
    gfx = get_gfx()
    if gfx == "gfx942":
        chip_id = _get_pci_chip_id()
        if chip_id in MI308_CHIP_IDS:
            return "MI308"
        return "MI300"
    elif gfx == "gfx950":
        return "MI350"
    else:
        raise RuntimeError("Unsupported gfx")
```

Note: The enum value `10019` for `hipDeviceAttributePciChipId` is specific to ROCm 6.x/7.x.
It is computed from `hipDeviceAttributeAmdSpecificBegin (10000)` plus the offset within the
AMD-specific attribute enum in `hip_runtime_api.h`.

## Files changed

| File | Change |
|------|--------|
| `csrc/include/aiter_hip_common.h` | Add `get_pci_chip_id()` and `is_mi308_device()` |
| `csrc/cpp_itfs/mha_fwd.cu` | Replace CU count check with `is_mi308_device()` in `get_kernel_co_name()` |
| `aiter/jit/utils/chip_info.py` | Add `_get_pci_chip_id()` via ctypes, update `get_device_name()` |

## Verification

### Build and run C++ smoke test

```bash
# inside docker:
cd op_tests/cpp/mha
bash build_mha.sh fwd_v3
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH
export CK_WARMUP=0 CK_REPEAT=1
./fwd.exe -prec=bf16 -b=2 -h=4 -h_k=2 -d=128 -d_v=128 -s=127 -s_k=0 \
  -iperm=0 -operm=0 -mask=0 -lse=0 -fwd_v3=1 -v3_bf16_cvt=0 -mode=0 -kname=1 -v=1
# Should print: pciChipId: 0x74a2, and load from MI308/ or MI300/ path
# Should print: valid:y
```

### Full smoke test

```bash
bash smoke_test_fwd_v3.sh -a gfx942 2>&1 | tee fwd_smoke.log
grep -c "valid:y" fwd_smoke.log   # all tests should pass
grep "file not found" fwd_smoke.log  # should be empty
```

## Gotchas

1. **`hipDeviceAttributePciChipId` enum value**: The numeric value `10019` is derived from
   the ROCm header enum ordering. If ROCm adds new AMD-specific attributes before
   `PciChipId` in a future version, this value could change. The C++ code uses the symbolic
   name `hipDeviceAttributePciChipId` directly and is immune to this. The Python ctypes code
   hardcodes `10019` and may need updating for future ROCm versions.

2. **sysfs card numbering**: `/sys/class/drm/card0/` is often the VGA/display device, not
   a GPU. AMD GPUs are at `card1`, `card9`, etc. The `product_name` and `vbios_version`
   files only exist on AMD GPU cards, not on the VGA card.

3. **libdrm in Docker**: `hipDeviceProp_t.name` is populated by libdrm's
   `amdgpu_get_marketing_name()`. In Docker containers where the container's libdrm doesn't
   match the host kernel's amdgpu driver, this returns empty. The `product_name` sysfs file
   bypasses libdrm and reads directly from the GPU firmware, so it works in containers.

4. **`get_num_cu_func()` still valid for tuning**: The existing `get_num_cu_func()` (which
   reads `multiProcessorCount`) is still used by other code for grid sizing and occupancy
   tuning (e.g., `asm_pa.cu`, `asm_fmoe.cu`, `rmsnorm_quant_kernels.cu`). Those uses are
   correct -- they need the actual runtime-visible CU count for performance tuning, not the
   hardware model identification.
