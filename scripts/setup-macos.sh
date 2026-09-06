#!/usr/bin/env bash
# Instalación de Jarvis (Hermes Agent) en macOS Apple Silicon. Idempotente.
# Ver docs/portabilidad.md para lo que es específico de esta plataforma.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HERMES_HOME="$HOME/.hermes"

log() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()  { printf '\033[32m✓\033[0m %s\n' "$*"; }

# ── 1. Dependencias de sistema ───────────────────────────────────────────────
# Se instalan explícitamente ANTES del instalador de Hermes: si ya están, la
# rama "best-effort" del instalador no se dispara y no toca nada del sistema.
install_system_deps() {
  command -v brew >/dev/null || { echo "error: falta Homebrew (https://brew.sh)" >&2; exit 1; }
  # portaudio: captura de micrófono (STT y wake word). Imprescindible.
  # git/ripgrep/ffmpeg: los usaría el instalador; los ponemos nosotros a la vista.
  for pkg in portaudio git ripgrep ffmpeg; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      ok "$pkg ya instalado"
    else
      log "instalando $pkg vía Homebrew"
      brew install "$pkg"
    fi
  done
}

# ── 2. Hermes Agent ──────────────────────────────────────────────────────────
# Se descarga y se ejecuta desde fichero: nunca `curl | bash` a ciegas.
# --skip-setup evita el asistente inicial, que empuja `hermes setup --portal`
# (OAuth de suscripción). Configuramos con nuestra config versionada.
install_hermes() {
  if [ -x "$HOME/.local/bin/hermes" ]; then
    ok "Hermes ya instalado ($("$HOME/.local/bin/hermes" --version 2>/dev/null | head -1))"
    return
  fi
  local tmp; tmp="$(mktemp -d)"
  log "descargando instalador"
  curl -fsSL -o "$tmp/install.sh" https://hermes-agent.nousresearch.com/install.sh
  echo "  revísalo si quieres: $tmp/install.sh"
  log "ejecutando instalador (--skip-setup)"
  bash "$tmp/install.sh" --skip-setup
}

# ── 3. Config versionada ─────────────────────────────────────────────────────
# ~/.hermes/config.yaml pasa a ser un symlink al fichero del repo.
link_config() {
  local target="$REPO_ROOT/config/hermes.config.yaml"
  if [ -f "$HERMES_HOME/config.yaml" ] && [ ! -L "$HERMES_HOME/config.yaml" ]; then
    cp "$HERMES_HOME/config.yaml" "$HERMES_HOME/config.yaml.installer-template"
    ok "plantilla del instalador respaldada en config.yaml.installer-template"
  fi
  ln -sfn "$target" "$HERMES_HOME/config.yaml"
  ok "config enlazada: ~/.hermes/config.yaml -> config/hermes.config.yaml"
}

# ── 4. Secretos ──────────────────────────────────────────────────────────────
setup_env() {
  if [ ! -f "$REPO_ROOT/.env" ]; then
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    ok "creado .env desde .env.example — rellena ANTHROPIC_API_KEY"
  else
    ok ".env ya existe"
  fi
}

# ── 5. Dependencias de voz (dentro del venv de Hermes, no del sistema) ───────
install_voice_deps() {
  local venv="$HERMES_HOME/hermes-agent/venv"
  export VIRTUAL_ENV="$venv"
  log "instalando extra [voice] (faster-whisper, sounddevice, numpy)"
  (cd "$HERMES_HOME/hermes-agent" && "$HERMES_HOME/bin/uv" pip install -e ".[voice]")
  log "instalando piper-tts (TTS local)"
  (cd "$HERMES_HOME/hermes-agent" && "$HERMES_HOME/bin/uv" pip install piper-tts)
}

# ── 6. Pre-descarga de la voz de Piper ───────────────────────────────────────
# La PRIMERA síntesis con una voz nueva la descarga, y ahí hay una carrera que
# puede tumbar el proceso entero con:
#   libc++abi: terminating due to uncaught exception ... recursive_mutex lock failed
# El fichero sí queda bajado y el segundo intento va bien. Descargarla aquí
# evita que eso te explote en mitad de una conversación.
predownload_piper_voice() {
  local venv="$HERMES_HOME/hermes-agent/venv"
  local voice; voice=$(grep -A2 '^  piper:' "$REPO_ROOT/config/hermes.config.yaml" \
                       | grep 'voice:' | sed -E 's/.*"(.*)".*/\1/')
  local dir="$HERMES_HOME/cache/piper-voices"
  if [ -f "$dir/$voice.onnx" ]; then ok "voz $voice ya descargada"; return; fi
  log "pre-descargando voz de Piper: $voice"
  mkdir -p "$dir"
  "$venv/bin/python" -m piper.download_voices "$voice" --download-dir "$dir" \
    || log "descarga fallida; el primer arranque la reintentará"
}

install_system_deps
install_hermes
link_config
setup_env
install_voice_deps
predownload_piper_voice

echo
ok "Setup completo. Arranca con: ./scripts/jarvis.sh"
echo "  Si .env está vacío, genera la key en https://console.anthropic.com"
