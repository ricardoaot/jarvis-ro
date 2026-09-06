#!/usr/bin/env bash
# Aplica los parches de patches/ sobre el código de Hermes. Idempotente.
#
# POR QUÉ HAY PARCHES: Hermes tiene un bug abierto (#74328) que deja mudos los
# turnos lanzados por wake word. El workaround oficial es entrar a /voice a mano
# en cada arranque; el parche lo arregla de raíz.
#
# IMPORTANTE: `hermes update` sobrescribe el código y se lleva los parches por
# delante. Vuelve a pasar este script después de cada actualización.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${HERMES_SRC:-$HOME/.hermes/hermes-agent}"

[ -d "$SRC/.git" ] || { echo "error: $SRC no es un repo git" >&2; exit 1; }
shopt -s nullglob
parches=("$REPO_ROOT"/patches/*.patch)
[ ${#parches[@]} -gt 0 ] || { echo "no hay parches que aplicar"; exit 0; }

fallos=0
for p in "${parches[@]}"; do
  nombre="$(basename "$p")"
  if git -C "$SRC" apply --reverse --check "$p" >/dev/null 2>&1; then
    echo "  ✓ $nombre — ya aplicado"
  elif git -C "$SRC" apply --check "$p" >/dev/null 2>&1; then
    git -C "$SRC" apply "$p" && echo "  ✓ $nombre — aplicado"
  else
    echo "  ✗ $nombre — NO aplica limpio." >&2
    echo "    Probablemente upstream cambió esa zona del código. Comprueba si el" >&2
    echo "    bug ya está arreglado antes de rehacer el parche:" >&2
    echo "    https://github.com/NousResearch/hermes-agent/issues/74328" >&2
    fallos=$((fallos+1))
  fi
done
[ "$fallos" -eq 0 ] || exit 1
