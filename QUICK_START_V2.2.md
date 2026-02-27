# GreenBoost v2.2 — Quick Start Guide

**Ubuntu 26.04 · RTX 5070 · 64 GB DDR4 · 4 TB Samsung 990 Evo Plus NVMe**

## Memory hierarchy

| Tier | Device        | Capacity | Bandwidth  | Role               |
|------|---------------|----------|------------|--------------------|
| T1   | RTX 5070 VRAM |   12 GB  | ~336 GB/s  | Hot layers (GPU)   |
| T2   | DDR4 RAM      |   51 GB  |  ~50 GB/s  | Cold layers (PCIe) |
| T3   | NVMe swap     |  576 GB  |  ~1.8 GB/s | Frozen pages       |
| **∑**| **Combined**  | **639 GB**|           | **Total model cap**|

---

## 1. Build

```bash
cd /home/ferran/Dev/greenboost
make clean && make
```

Expected output:
```
LD [M]  greenboost.ko
[GreenBoost] Built libgreenboost_cuda.so
```

---

## 2. Load

### Via setup script (recommended)

```bash
sudo ./greenboost_setup.sh load
```

### Via Makefile

```bash
sudo make load
# Override any tier param:
sudo make load NVME_GB=576 VIRT_GB=51 RESERVE_GB=12
```

### Direct insmod

```bash
sudo insmod greenboost.ko \
    physical_vram_gb=12  \
    virtual_vram_gb=51   \
    safety_reserve_gb=12 \
    nvme_swap_gb=576     \
    nvme_pool_gb=512
```

---

## 3. Verify

```bash
cat /sys/class/greenboost/greenboost/pool_info
```

Expected output:
```
=== GreenBoost v2.2 — 3-Tier Pool Info ===

Tier 1  RTX 5070 VRAM      :   12 GB   ~336 GB/s  [hot layers]
Tier 2  DDR4 pool cap      :   51 GB   ~50 GB/s   [cold layers]
Tier 3  NVMe swap          :  576 GB   ~1.8 GB/s  [frozen pages]
        ─────────────────────────────────
        Combined model view:  639 GB

── Tier 2 (DDR4) ──────────────────────────
  Total RAM                : 65536 MB
  Free RAM                 : ...
  Safety reserve           : 12288 MB
  T2 allocated             : 0 MB
  T2 available             : ...
  Active DMA-BUF objects   : 0
  OOM guard                : no
  Page mode                : 2 MB hugepages (T2) / 4K swappable (T3)

── Tier 3 (NVMe swap) ──────────────────────
  Swap total               : 589824 MB  (576 GB configured)
  Swap used                : ...
  Swap free                : ...
  T3 GreenBoost alloc      : 0 MB
  Swap pressure            : ok
```

---

## 4. System-wide install (permanent)

```bash
sudo ./greenboost_setup.sh install
# Then load at boot:
sudo modprobe greenboost
```

This writes `/etc/modprobe.d/greenboost.conf` with all 3-tier params.

---

## 5. Run a large model (Ollama)

```bash
# These env vars are already optimised for the 3-tier setup:
export OLLAMA_FLASH_ATTENTION=1
export OLLAMA_KV_CACHE_TYPE=q8_0
export OLLAMA_NUM_CTX=16384

ollama run qwen3-coder-next   # 52 GB model, fits in T1+T2
# Or for models > 63 GB — T3 NVMe handles the overflow automatically
```

---

## 6. Monitor all 3 tiers

```bash
# T1 — GPU VRAM
watch -n1 'nvidia-smi --query-gpu=memory.used,memory.free --format=csv'

# T2 — DDR4 pool
watch -n1 'cat /sys/class/greenboost/greenboost/pool_info'

# T3 — NVMe swap pressure
watch -n1 'swapon --show'

# All-in-one
watch -n1 '
  nvidia-smi | grep MiB
  echo ""
  cat /sys/class/greenboost/greenboost/pool_info
  echo ""
  swapon --show
'
```

---

## 7. Unload

```bash
sudo ./greenboost_setup.sh unload
# or
sudo make unload
```

---

## Module parameters reference

| Parameter          | Default | Description                        |
|--------------------|---------|------------------------------------|
| `physical_vram_gb` | 12      | T1: RTX 5070 VRAM                  |
| `virtual_vram_gb`  | 51      | T2: DDR4 pool cap (80% of 64 GB)   |
| `safety_reserve_gb`| 12      | T2: always keep ≥N GB free in RAM  |
| `nvme_swap_gb`     | 576     | T3: total NVMe swap capacity       |
| `nvme_pool_gb`     | 512     | T3: GreenBoost soft cap            |
| `use_hugepages`    | 1       | T2: use 2 MB compound pages        |
| `debug_mode`       | 0       | Verbose kernel log                 |

---

## Troubleshooting

**`insmod` fails — check dmesg:**
```bash
dmesg | grep greenboost | tail -20
```

**Swap pressure CRITICAL (>90%):**
```bash
# Check what's using swap
smem -s swap -r | head -20
# Reduce T2 pool to free RAM so kernel can reclaim
sudo rmmod greenboost
sudo insmod greenboost.ko virtual_vram_gb=40 nvme_swap_gb=576
```

**Module won't unload (busy):**
```bash
# Close all apps using /dev/greenboost, then:
sudo rmmod greenboost
```

---

**Version**: GreenBoost v2.2
**Date**: February 2026
**Status**: Production ready — 639 GB model capacity
