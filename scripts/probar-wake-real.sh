#!/usr/bin/env bash
# Prueba el wake word por el camino de producción (start_listening de Hermes),
# con todos los DEBUG visibles. CIERRA HERMES ANTES.
set -euo pipefail
exec "$HOME/.hermes/hermes-agent/venv/bin/python" \
     "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/probar_wake_real.py" "${1:-25}"
