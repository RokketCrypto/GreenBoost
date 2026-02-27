# Quick Start Guide

## Installation

```bash
# Install dependencies
sudo apt-get install build-essential linux-headers-$(uname -r)

# Clone repository
git clone https://github.com/bogdanovby/greenboost.git
cd greenboost

# Build the driver
make

# Load the module with default settings (RTX 5070, 12GB physical + 44GB virtual)
sudo insmod greenboost.ko

# Or specify custom settings
sudo insmod greenboost.ko gpu_model=5090 physical_vram_gb=24 virtual_vram_gb=8
```

## Configuration

Edit `greenboost.conf` for persistent settings:

```ini
# GPU model (4060, 4070, 4080, 4090, 5060, 5070, 5080, 5090)
gpu_model=5070

# Memory sizes in GB
physical_vram_gb=12
virtual_vram_gb=44

# Allocation strategy
allocation_strategy=lazy_allocation
```

## Verification

```bash
# Check module is loaded
lsmod | grep greenboost

# View VRAM information
cat /sys/class/greenboost/greenboost/vram_info

# Read through device
sudo cat /dev/greenboost

# Check kernel logs
dmesg | grep greenboost
```

##Expected Output

```
greenboost: Initializing virtual GPU memory emulator
greenboost: Emulating NVIDIA GeForce RTX 5070
greenboost: VRAM configuration: 12 GB physical + 44 GB virtual = 56 GB total
greenboost: Virtual GPU device created successfully
greenboost: Device registered as /dev/greenboost (major XXX)
greenboost: Driver initialized successfully
```

## Testing

```bash
# Run basic tests
sudo ./tests/test_greenboost.sh

# Run stress test
sudo ./tools/run_stress_test.sh

# Python test
sudo python3 ./tests/test_greenboost.py
```

## Unloading

```bash
sudo rmmod greenboost
```

## Supported GPUs

### GeForce 40xx Series
- RTX 4060 (8 GB default)
- RTX 4060 Ti (8 GB default)
- RTX 4070 (12 GB default)
- RTX 4070 Ti (12 GB default)
- RTX 4080 (16 GB default)
- RTX 4090 (24 GB default)

### GeForce 50xx Series
- RTX 5060 (8 GB default)
- RTX 5070 (12 GB default)
- RTX 5080 (16 GB default)
- RTX 5090 (24 GB default)

## Troubleshooting

**Module won't load:**
```bash
sudo dmesg | tail -20
```

**Device not created:**
```bash
ls -l /dev/greenboost
ls -l /sys/class/greenboost
```

**Out of memory:**
- Reduce `virtual_vram_gb`
- Use `lazy_allocation=1`
- Check available RAM: `free -h`

