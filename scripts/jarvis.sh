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

exec "$HOME/.local/bin/hermes" "$@"
