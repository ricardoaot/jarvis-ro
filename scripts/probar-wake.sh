#!/usr/bin/env bash
# Diagnóstico del wake word: enseña en vivo el nivel del micro y la puntuación
# del modelo mientras hablas, usando EXACTAMENTE el mismo camino que Hermes
# (captura a la tasa nativa del dispositivo -> su remuestreo -> su motor).
#
# Sirve para separar tres causas que desde fuera parecen la misma:
#   - el micro no entrega audio        -> nivel plano en 0
#   - el audio llega pero no reconoce  -> nivel OK, puntuación siempre baja
#   - reconoce pero no cruza el umbral -> puntuación alta pero < umbral
#
# CIERRA HERMES ANTES: si no, se pelean por el micrófono.
set -euo pipefail
SEGUNDOS="${1:-20}"
exec "$HOME/.hermes/hermes-agent/venv/bin/python" \
     "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/probar_wake.py" "$SEGUNDOS"
