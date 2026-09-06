"""Diagnóstico en vivo del wake word. Lo lanza scripts/probar-wake.sh."""
import sys, time
sys.path.insert(0, "/Users/ricardoolivari/.hermes/hermes-agent")

import numpy as np
import sounddevice as sd
from hermes_cli.config import load_config
import tools.wake_word as ww
from tools.wake_word_engines import _OpenWakeWordEngine

DURACION = int(sys.argv[1]) if len(sys.argv) > 1 else 20

cfg = load_config().get("wake_word", {})
eng = _OpenWakeWordEngine.__new__(_OpenWakeWordEngine)
eng._build(cfg, cfg.get("openwakeword", {}), ww)
eng._confirm_streak = 0
umbral, need = eng._threshold, eng._confirm_needed

dev = sd.query_devices(kind="input")
cap_rate = int(dev["default_samplerate"])
frame_engine = eng.frame_length                                  # 1280 @ 16 kHz
frame_cap = max(1, round(frame_engine * cap_rate / ww.SAMPLE_RATE))

print(f"dispositivo : {dev['name']}")
print(f"captura     : {cap_rate} Hz  (bloques de {frame_cap})")
print(f"motor       : {ww.SAMPLE_RATE} Hz (frames de {frame_engine}) modelo={eng._labels}")
print(f"umbral      : {umbral}   frames consecutivos necesarios: {need}")
print()
frase = cfg.get("phrase") or eng._labels[0].replace("_", " ")
print(f"Di '{frase}' varias veces durante {DURACION}s. Ctrl+C para cortar.")
print("  nivel = volumen de entrada | punt = puntuación del modelo (0..1)")
print()

max_punt, disparos, frames = 0.0, 0, 0
t0 = time.time()
try:
    with sd.InputStream(samplerate=cap_rate, channels=1, dtype="int16",
                        blocksize=frame_cap) as stream:
        while time.time() - t0 < DURACION:
            bloque, _ = stream.read(frame_cap)
            crudo = bloque[:, 0]
            frame = (ww._resample_audio_frame(np, crudo, frame_engine)
                     if cap_rate != ww.SAMPLE_RATE else crudo)
            # UNA sola llamada a predict() por frame. openWakeWord mantiene un
            # búfer temporal de features, así que predecir dos veces el mismo
            # frame (p.ej. una para mostrar la puntuación y otra dentro de
            # process()) le duplica el audio y hunde la puntuación a 0.000.
            # Por eso aquí se replica a mano la lógica de racha de process().
            punt = max(eng._model.predict(frame).values())
            frames += 1
            max_punt = max(max_punt, punt)
            eng._confirm_streak = eng._confirm_streak + 1 if punt >= umbral else 0
            if eng._confirm_streak >= need:
                eng._confirm_streak = 0
                disparos += 1
                print(f"\r  ✦ ¡DISPARO! (punt={punt:.3f})" + " " * 30)
            nivel = int(abs(frame).max())
            barra = "█" * min(30, nivel // 200)
            marca = "  <-- SOBRE UMBRAL" if punt >= umbral else ""
            print(f"\r  nivel {nivel:5d} |{barra:<30}| punt {punt:.3f}{marca}   ",
                  end="", flush=True)
except KeyboardInterrupt:
    pass

print("\n")
print(f"RESULTADO tras {frames} frames:")
print(f"  puntuación máxima : {max_punt:.3f}   (umbral {umbral})")
print(f"  disparos          : {disparos}")
print()
if disparos:
    print("  ✅ El detector funciona. Si en Hermes no salta, el problema no es el modelo.")
elif max_punt >= umbral:
    print("  ⚠️  Cruzó el umbral pero sin racha suficiente.")
    print(f"     Baja confirmation_frames de {need} a 2 en config/hermes.config.yaml.")
elif max_punt > 0.15:
    print("  ⚠️  Te reconoce a medias: es la PRONUNCIACIÓN.")
    print("     Los modelos están entrenados con inglés. Dicho con fonética")
    print("     española una frase inglesa se queda sobre 0.4, bajo el umbral.")
    print()
    print("     NO bajes sensitivity para compensar: para que dispare habría que")
    print("     dejarla en territorio de ruido, y eso arruina la medición de falsos")
    print("     positivos, que es el objetivo de la fase 1. Cambia de MODELO:")
    print("       hey_mycroft  (1.000 con voz española)")
    print("       hey_hermes   (0.965)")
    print("     Ver docs/portabilidad.md §2.7")
else:
    print(f"  ❌ Puntuación 0: el modelo cargado es '{eng._labels[0]}'.")
    print(f"     ¿Dijiste exactamente '{frase}'? Un 0.000 clavado suele ser eso:")
    print("     estar diciendo una frase distinta a la del modelo.")
    print("     Si la dijiste bien y el nivel se movía, es pronunciación o distancia;")
    print("     si el nivel estaba plano en 0, es el micrófono.")
