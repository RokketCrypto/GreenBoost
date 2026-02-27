# GreenBoost v2.2 — Installation Guide

**Ubuntu 26.04 · RTX 5070 · 64 GB DDR4 · 4 TB Samsung 990 Evo Plus NVMe**

## 3-tier memory hierarchy

| Tier | Device        | Capacity  | Bandwidth  | Role             |
|------|---------------|-----------|------------|------------------|
| T1   | RTX 5070 VRAM |   12 GB   | ~336 GB/s  | Hot layers (GPU) |
| T2   | DDR4 RAM      |   51 GB   |  ~50 GB/s  | Cold layers      |
| T3   | NVMe swap     |  576 GB   |  ~1.8 GB/s | Frozen pages     |
| **∑**| **Combined**  | **639 GB**|            | **Total LLM cap**|

## Prerequisites

```bash
sudo apt install linux-headers-$(uname -r) build-essential gcc
nvidia-smi
sudo modprobe nvidia_uvm
```

## Build

```bash
cd /home/ferran/Dev/greenboost
make clean && make
```

## Install (system-wide, permanent)

```bash
sudo ./greenboost_setup.sh install
```

Creates:
- `/etc/modprobe.d/greenboost.conf` — default 3-tier params
- `/etc/profile.d/greenboost.sh` — `greenboost-run` shell function
- `/usr/local/bin/greenboost-run` — CUDA app wrapper
- `/usr/local/lib/libgreenboost_cuda.so` — CUDA shim

Auto-load at boot:
```bash
echo "greenboost" | sudo tee /etc/modules-load.d/greenboost.conf
```

## Load (one-shot)

```bash
sudo ./greenboost_setup.sh load
# or
sudo make load
```

## Verify

```bash
cat /sys/class/greenboost/greenboost/pool_info
dmesg | grep greenboost | tail -10
```

## Uninstall

```bash
sudo ./greenboost_setup.sh uninstall
```

## Module parameters

| Parameter            | Default | Description                         |
|----------------------|---------|-------------------------------------|
| `physical_vram_gb`   | 12      | T1: RTX 5070 VRAM                   |
| `virtual_vram_gb`    | 51      | T2: DDR4 pool (80% of 64 GB)        |
| `safety_reserve_gb`  | 12      | T2: minimum free RAM to maintain    |
| `nvme_swap_gb`       | 576     | T3: NVMe swap total capacity        |
| `nvme_pool_gb`       | 512     | T3: GreenBoost soft cap             |
| `use_hugepages`      | 1       | T2: 2 MB compound pages             |
| `debug_mode`         | 0       | Verbose kernel log                  |

## Monitoring

```bash
watch -n1 'cat /sys/class/greenboost/greenboost/pool_info'
watch -n1 'swapon --show'
dmesg | grep "greenboost.*swap"
```
