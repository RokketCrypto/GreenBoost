#!/bin/bash
# GreenBoost — Benchmark: CPU offloading vs GreenBoost VMM
# Modelo: Qwen3.5-27B Q8_0 (denso, 28.6 GB)
#
# Compara el rendimiento con dos estrategias:
#   A) CPU offloading (-ngl parcial, capas restantes en CPU)
#   B) GreenBoost VMM (todo GPU, split VRAM + host-pinned DDR4)

set -e

TEST="${1:-ab}"    # uso: bench_27b.sh [a|b|ab] [modelo.gguf]
MODEL="${2:-/home/daniel/Git/Qwen3.5/models/Qwen3.5-27B-Q8_0.gguf}"
LLAMA_CLI="$(command -v llama-cli || echo /home/daniel/Git/Qwen3.5/llama.cpp/build/bin/llama-cli)"
GREENBOOST_SHIM="/home/daniel/Git/GreenBoost/libgreenboost_cuda.so"

# Calcula -ngl óptimo: cuántas capas caben en ~13 GB de VRAM
# (dejando ~2 GB para KV cache, compute, driver)
MODEL_SIZE_MB=$(stat -c%s "$MODEL" 2>/dev/null | awk '{printf "%.0f", $1/1048576}')
LAYER_COUNT=64  # Qwen3.5-27B tiene 64 capas
VRAM_FOR_LAYERS=13000  # MB disponibles para pesos
if [ "$MODEL_SIZE_MB" -gt 0 ] 2>/dev/null; then
    LAYER_SIZE_MB=$((MODEL_SIZE_MB / LAYER_COUNT))
    NGL_CPU_OFFLOAD=$((VRAM_FOR_LAYERS / LAYER_SIZE_MB))
    if [ "$NGL_CPU_OFFLOAD" -gt "$LAYER_COUNT" ]; then
        NGL_CPU_OFFLOAD=$LAYER_COUNT
    fi
else
    NGL_CPU_OFFLOAD=32
fi

COMMON_ARGS=(
    -m "$MODEL"
    -c 8192
    -fa on
    -t 8
    -tb 16
    --temp 0.6
    --top-k 20
    --top-p 0.95
    --min-p 0
    --reasoning off
    --reasoning-budget 0
    --no-display-prompt
    -n 256
)

PROMPT="Transcribe el siguiente texto, escribelo igual, no agregues nada, no elimines nada, esto es una prueba:

La exploración del espacio profundo ha revelado que nuestro universo es mucho más complejo de lo que imaginábamos. Las observaciones del telescopio James Webb han permitido detectar galaxias formadas apenas 300 millones de años después del Big Bang, desafiando los modelos cosmológicos existentes."

MODEL_NAME="$(basename "$MODEL")"
echo "================================================================"
echo "  GreenBoost Benchmark — $MODEL_NAME (denso)"
echo "  Hardware: RTX A4000 16 GB VRAM, 64 GB DDR4"
echo "================================================================"
echo ""

# ── Test A: CPU offloading ────────────────────────────────────
if [[ "$TEST" == *a* ]]; then
echo "══════════════════════════════════════════════════════════"
echo "  TEST A: CPU Offloading (-ngl $NGL_CPU_OFFLOAD de 64 capas)"
echo "══════════════════════════════════════════════════════════"
echo ""

echo "/exit" | "$LLAMA_CLI" \
    "${COMMON_ARGS[@]}" \
    -ngl $NGL_CPU_OFFLOAD \
    -p "$PROMPT" \
    2>&1 | tee /tmp/claude-1000/bench_27b_cpu.log

echo ""
echo ""
fi

# ── Test B: GreenBoost VMM ────────────────────────────────────
if [[ "$TEST" == *b* ]]; then
echo "══════════════════════════════════════════════════════════"
echo "  TEST B: GreenBoost VMM (todo GPU, split VRAM+host DDR4)"
echo "══════════════════════════════════════════════════════════"
echo ""

echo "/exit" | \
LD_PRELOAD="$GREENBOOST_SHIM" \
GREENBOOST_VIRTUAL_VRAM_MB=$((28 * 1024)) \
GREENBOOST_DEBUG=1 \
"$LLAMA_CLI" \
    "${COMMON_ARGS[@]}" \
    -ngl 99 \
    -p "$PROMPT" \
    2>&1 | tee /tmp/claude-1000/bench_27b_gb.log

echo ""
echo ""
fi

# ── Resumen ───────────────────────────────────────────────────
echo "================================================================"
echo "  RESUMEN — Qwen3.5-27B Q8_0 (denso)"
echo "================================================================"
echo ""
if [[ "$TEST" == *a* ]] && [ -f /tmp/claude-1000/bench_27b_cpu.log ]; then
echo "── CPU Offloading (-ngl $NGL_CPU_OFFLOAD) ──"
grep -E "Prompt:|Generation:|prompt eval time|eval time|total time" /tmp/claude-1000/bench_27b_cpu.log | tail -4
echo ""
fi
if [[ "$TEST" == *b* ]] && [ -f /tmp/claude-1000/bench_27b_gb.log ]; then
echo "── GreenBoost VMM (-ngl 99) ──"
grep -E "Prompt:|Generation:|prompt eval time|eval time|total time" /tmp/claude-1000/bench_27b_gb.log | tail -4
echo ""
fi
