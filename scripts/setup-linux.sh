#!/usr/bin/env bash
# STUB — Jarvis (Hermes Agent) en Linux. Todavía NO probado.
#
# Este fichero documenta el trabajo pendiente para el port. No lo ejecutes
# esperando que funcione; léelo junto a docs/portabilidad.md.
set -euo pipefail

echo "scripts/setup-linux.sh es un stub sin probar. Ver docs/portabilidad.md." >&2
exit 1

# ── Pendiente ────────────────────────────────────────────────────────────────
#
# 1. Dependencias de sistema (equivalente a install_system_deps de macOS):
#      sudo apt install portaudio19-dev ffmpeg libopus0 git ripgrep
#    - macOS usa el paquete "portaudio"; Debian/Ubuntu necesita los headers
#      de desarrollo: portaudio19-dev.
#    - Instalarlas ANTES del instalador de Hermes, igual que en macOS: así su
#      rama best-effort (que en Linux SÍ usa sudo apt/dnf/pacman) no se dispara.
#
# 2. Instalador de Hermes: mismo comando, misma bandera --skip-setup.
#      curl -fsSL -o install.sh https://hermes-agent.nousresearch.com/install.sh
#      bash install.sh --skip-setup
#    OJO: en Linux el instalador ejecuta apt/dnf/pacman con sudo si faltan
#    git o build-essential. Con el paso 1 hecho no debería hacer falta.
#
# 3. Config y .env: idénticos a macOS, sin cambios (link_config / setup_env).
#
# 4. Wake word: revisar el motor. La coacción onnx->tflite y el puente
#    ai_edge_litert son específicos de macOS ARM64; en Linux openWakeWord usa
#    tflite-runtime nativo. Reevaluar sensitivity/confirmation_frames, porque
#    el micro y el backend de audio cambian el perfil de falsos positivos.
#
# 5. Audio: macOS usa CoreAudio vía PortAudio. En Linux hay ALSA/PulseAudio/
#    PipeWire de por medio; wake_word.input_device casi seguro necesitará un
#    índice o nombre explícito en vez de null.
#
# 6. Permisos de micro: en macOS son por proceso (TCC). En Linux no existe ese
#    modelo; el problema equivalente es pertenecer al grupo "audio" y que el
#    dispositivo no esté acaparado por otro cliente.
