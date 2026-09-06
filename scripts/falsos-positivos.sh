#!/usr/bin/env bash
# Instrumento de medición de la fase 1.
#
# Registra con timestamp cada vez que la wake word dispara, para poder contar
# los falsos positivos al final del día.
#
# El script NO puede saber si un disparo fue falso: si dijiste "hey jarvis" a
# propósito es correcto, y si saltó con la tele de fondo es un falso positivo.
# Eso lo marcas tú. El script se encarga de que no se te escape ninguno y de
# que tengas la hora exacta para reconstruir qué pasaba.
#
# Fuente: la línea INFO que emite tools/wake_word.py al disparar
#   "wake word: phrase detected — firing callback"
# Sale en ~/.hermes/logs/agent.log con el nivel de log por defecto.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG="${HERMES_LOG:-$HOME/.hermes/logs/agent.log}"
STORE="$REPO_ROOT/data/wake-events.tsv"
PATRON='wake word: phrase detected'
PATRON_COOLDOWN='wake word: detection within cooldown'
UMBRAL_ACEPTACION=3

mkdir -p "$(dirname "$STORE")"
[ -f "$STORE" ] || printf 'timestamp\testado\tnota\n' > "$STORE"

# Extrae "YYYY-MM-DD HH:MM:SS" del principio de una línea de agent.log
_timestamps() { grep -F "$PATRON" "$@" 2>/dev/null | cut -c1-19 || true; }

# ── Importar disparos del log que aún no estén registrados ───────────────────
importar() {
  [ -f "$LOG" ] || { echo "no existe $LOG — ¿has arrancado Hermes ya?" >&2; return; }
  local nuevos=0 ts
  while IFS= read -r ts; do
    [ -n "$ts" ] || continue
    if ! cut -f1 "$STORE" | grep -qxF "$ts"; then
      printf '%s\tsin_revisar\t\n' "$ts" >> "$STORE"; nuevos=$((nuevos+1))
    fi
  done < <(_timestamps "$LOG" $(ls "$LOG".* 2>/dev/null || true))
  [ "$nuevos" -gt 0 ] && echo "importados $nuevos disparos nuevos del log"
  return 0
}

# ── Seguir en vivo ───────────────────────────────────────────────────────────
seguir() {
  echo "siguiendo $LOG — Ctrl+C para parar"
  echo "cada disparo se anota en data/wake-events.tsv"
  tail -n0 -F "$LOG" 2>/dev/null | while IFS= read -r linea; do
    case "$linea" in
      *"$PATRON"*)
        ts="${linea:0:19}"
        printf '%s\tsin_revisar\t\n' "$ts" >> "$STORE"
        printf '\a\033[33m✦ DISPARO\033[0m %s\n' "$ts" ;;
    esac
  done
}

# ── Informe del día ──────────────────────────────────────────────────────────
informe() {
  local dia="${1:-$(date +%Y-%m-%d)}"
  importar
  echo
  echo "Disparos del $dia"
  echo "─────────────────────────────────────────────"
  local n=0
  while IFS=$'\t' read -r ts estado nota; do
    case "$ts" in "$dia"*) ;; *) continue ;; esac
    n=$((n+1))
    local marca
    case "$estado" in
      falso) marca=$'\033[31mFALSO\033[0m      ' ;;
      real)  marca=$'\033[32mreal\033[0m       ' ;;
      *)     marca=$'\033[90msin revisar\033[0m' ;;
    esac
    printf '  %3d  %s  %b  %s\n' "$n" "${ts:11:8}" "$marca" "$nota"
  done < <(tail -n +2 "$STORE")
  [ "$n" -eq 0 ] && echo "  (ninguno)"
  echo "─────────────────────────────────────────────"

  local falsos sin
  falsos=$(awk -F'\t' -v d="$dia" '$1 ~ "^"d && $2=="falso"' "$STORE" | wc -l | tr -d ' ')
  sin=$(awk -F'\t' -v d="$dia" '$1 ~ "^"d && $2=="sin_revisar"' "$STORE" | wc -l | tr -d ' ')
  echo "  total: $n | falsos: $falsos | sin revisar: $sin"
  if [ "$sin" -gt 0 ]; then
    echo
    echo "  Marca los que NO provocaste tú:"
    echo "    ./scripts/falsos-positivos.sh --falso N [N...]"
  fi
  echo
  if [ "$falsos" -lt "$UMBRAL_ACEPTACION" ] && [ "$sin" -eq 0 ]; then
    echo "  ✅ CRITERIO CUMPLIDO: $falsos falsos positivos (< $UMBRAL_ACEPTACION)"
  elif [ "$falsos" -ge "$UMBRAL_ACEPTACION" ]; then
    echo "  ❌ CRITERIO NO CUMPLIDO: $falsos falsos positivos (>= $UMBRAL_ACEPTACION)"
    echo "     Salida: sube wake_word.sensitivity (0.6 -> 0.8) o"
    echo "     confirmation_frames (3 -> 4/5), o cambia la frase. NO pases a la fase 2."
  fi
}

# ── Marcar eventos ───────────────────────────────────────────────────────────
marcar() {
  local nuevo_estado="$1"; shift
  local dia; dia="$(date +%Y-%m-%d)"
  local tmp; tmp="$(mktemp)"
  local objetivos=" $* "
  awk -F'\t' -v OFS='\t' -v d="$dia" -v est="$nuevo_estado" -v obj="$objetivos" '
    NR==1 { print; next }
    { if ($1 ~ "^"d) { n++; if (index(obj, " " n " ")) $2 = est } print }
  ' "$STORE" > "$tmp" && mv "$tmp" "$STORE"
  echo "marcados como '$nuevo_estado': $*"
  informe
}

case "${1:-}" in
  --seguir|-s)     seguir ;;
  --falso|-f)      shift; marcar falso "$@" ;;
  --real|-r)       shift; marcar real "$@" ;;
  --informe|-i|"") informe "${2:-}" ;;
  --ayuda|-h)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) echo "opción desconocida: $1 (usa --ayuda)" >&2; exit 1 ;;
esac
