#!/usr/bin/env bash
# Lanzador de Jarvis. Exporta los secretos de .env al entorno y arranca Hermes.
# El secreto vive SOLO en .env (ignorado por git); no se copia a ~/.hermes/.env.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "error: falta $ENV_FILE — cópialo de .env.example y rellena la API key." >&2
  exit 1
fi

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "error: ANTHROPIC_API_KEY está vacía en $ENV_FILE" >&2
  echo "genérala en https://console.anthropic.com -> Settings -> API Keys" >&2
  exit 1
fi

# Las librerías de audio en C (PortAudio/CoreAudio) escriben avisos DIRECTAMENTE
# a stderr, saltándose el logging de Python. En macOS es habitual ver
#   ||PaMacCore (AUHAL)|| Error on line 2523: err='-50'
# al reabrir el micrófono tras un turno de voz. Es inofensivo para el detector
# —sigue oyendo y disparando— pero cae encima del dibujado de prompt_toolkit y
# deja la interfaz corrompida: parece colgada cuando no lo está.
#
# Desviamos stderr a un fichero para que el terminal quede limpio. No perdemos
# nada: el logging real de Hermes va a ~/.hermes/logs/.
mkdir -p "$REPO_ROOT/logs"
STDERR_LOG="$REPO_ROOT/logs/stderr.log"
echo "--- $(date '+%Y-%m-%d %H:%M:%S') arranque ---" >> "$STDERR_LOG"
exec "$HOME/.local/bin/hermes" "$@" 2>> "$STDERR_LOG"
