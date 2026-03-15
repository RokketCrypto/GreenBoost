#!/bin/bash
# GreenBoost — Benchmark: CPU offloading vs GreenBoost DMA-BUF
#
# Compara el rendimiento de Qwen3.5-122B-A10B con dos estrategias:
#   A) CPU offloading (expertos capas 10-47 en CPU)
#   B) GreenBoost (todo en GPU, overflow a DDR4 via DMA-BUF)
#
# Mide: tokens/segundo (decode) y TTFT (prompt eval time)

set -e

TEST="${1:-ab}"  # uso: bench_transcribe.sh [a|b|ab]

MODEL="/home/daniel/Git/Qwen3.5/models/Qwen3.5-122B-A10B-UD-IQ3_S.gguf"
LLAMA_CLI="$(command -v llama-cli || echo /home/daniel/Git/Qwen3.5/llama.cpp/build/bin/llama-cli)"
GREENBOOST_SHIM="/home/daniel/Git/GreenBoost/libgreenboost_cuda.so"

# Misma config que run-server.sh 122b
COMMON_ARGS=(
    -m "$MODEL"
    -c 131072
    -ngl 99
    -ctk q4_0
    -ctv q4_0
    -fa on
    -t 8
    -tb 16
    --temp 0.6
    --top-k 20
    --top-p 0.95
    --min-p 0
    --presence-penalty 1.5
    --logit-bias 248046-4
    --reasoning off
    --reasoning-budget 0
    --no-display-prompt
    -n 512
)

PROMPT="Transcribe el siguiente texto, escribelo igual, no agregues nada, no elimines nada, esto es una prueba:

La exploración del espacio profundo ha revelado que nuestro universo es mucho más complejo de lo que imaginábamos. Las observaciones del telescopio James Webb han permitido detectar galaxias formadas apenas 300 millones de años después del Big Bang, desafiando los modelos cosmológicos existentes. Estas galaxias primitivas muestran una masa y luminosidad sorprendentes para su edad, sugiriendo que los procesos de formación estelar en el universo temprano fueron significativamente más eficientes de lo previsto."

echo "================================================================"
echo "  GreenBoost Benchmark — Qwen3.5-122B-A10B IQ3_S (44 GB)"
echo "  Prompt: transcripción de texto (~200 palabras)"
echo "================================================================"
echo ""

# ── Test A: CPU offloading ────────────────────────────────────
if [[ "$TEST" == *a* ]]; then
echo "══════════════════════════════════════════════════════════"
echo "  TEST A: CPU Offloading (capas 10-47 expertos en CPU)"
echo "══════════════════════════════════════════════════════════"
echo ""

echo "/exit" | "$LLAMA_CLI" \
    "${COMMON_ARGS[@]}" \
    -p "$PROMPT" \
    -ot "blk\.([1-4][0-9])\..*_exps\.=CPU" \
    2>&1 | tee /tmp/claude-1000/bench_cpu_offload.log

echo ""
echo ""
fi

# ── Test B: GreenBoost ────────────────────────────────────────
if [[ "$TEST" == *b* ]]; then
echo "══════════════════════════════════════════════════════════"
echo "  TEST B: GreenBoost (todo GPU, overflow DDR4 via DMA-BUF)"
echo "══════════════════════════════════════════════════════════"
echo ""

echo "/exit" | \
LD_PRELOAD="$GREENBOOST_SHIM" \
GREENBOOST_VIRTUAL_VRAM_MB=$((28 * 1024)) \
GREENBOOST_DEBUG=1 \
"$LLAMA_CLI" \
    "${COMMON_ARGS[@]}" \
    -p "$PROMPT" \
    2>&1 | tee /tmp/claude-1000/bench_greenboost.log

echo ""
echo ""
fi

# ── Resumen ───────────────────────────────────────────────────
echo "================================================================"
echo "  RESUMEN"
echo "================================================================"
echo ""
if [[ "$TEST" == *a* ]] && [ -f /tmp/claude-1000/bench_cpu_offload.log ]; then
echo "── CPU Offloading ──"
grep -E "Prompt:|Generation:|prompt eval time|eval time|total time" /tmp/claude-1000/bench_cpu_offload.log | tail -4
echo ""
fi
if [[ "$TEST" == *b* ]] && [ -f /tmp/claude-1000/bench_greenboost.log ]; then
echo "── GreenBoost ──"
grep -E "Prompt:|Generation:|prompt eval time|eval time|total time" /tmp/claude-1000/bench_greenboost.log | tail -4
echo ""
fi
