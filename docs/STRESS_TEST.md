# GreenBoost v2.2 — Stress Test Guide

## Quick run

```bash
# Fills T1 (12 GB VRAM) + T2 (51 GB DDR4) — default
sudo ./tools/run_stress_test.sh

# Custom size — triggers T3 NVMe spillover above 63 GB
sudo ./tools/run_stress_test.sh 80
```

## What the test does

- Allocates the requested GB through `/dev/greenboost` IOCTLs
- Verifies data integrity across all tiers
- Reports per-tier allocation split in real time
- Exercises T3 NVMe spillover when size exceeds T1+T2 capacity (63 GB)

## Monitor during the test (separate terminal)

```bash
# Pool info (all 3 tiers)
watch -n1 'cat /sys/class/greenboost/greenboost/pool_info'

# RAM pressure (T2)
watch -n1 'free -h'

# NVMe swap pressure (T3)
watch -n1 'swapon --show'
```

## VRAM usage test

```bash
gcc -o tests/vram_usage_test tests/vram_usage_test.c
sudo ./tests/vram_usage_test        # default
sudo ./tests/vram_usage_test 5      # 5 GB
```

## Notes

- T2 DDR4 pages are pinned (2 MB hugepages) — fast DMA, no swap
- T3 NVMe pages are 4K swappable — kernel can page them to NVMe under pressure
- Start small (10 GB) before running full-capacity tests
- Safety reserve (12 GB) is always kept free; OOM guard fires if breached
- Watch `dmesg | grep greenboost` for T3 swap pressure warnings
