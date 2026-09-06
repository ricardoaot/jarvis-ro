"""Prueba el camino de PRODUCCIÓN del wake word: el mismo start_listening() que
usa la CLI de Hermes, pero fuera de la CLI. Lo lanza scripts/probar-wake-real.sh.

Sirve para separar dos cosas que desde fuera parecen la misma:
  - el detector no dispara            -> problema en captura/motor
  - dispara pero la CLI no reacciona  -> problema en la integración (_on_wake_word)
"""
import sys, time, logging
sys.path.insert(0, "/Users/ricardoolivari/.hermes/hermes-agent")

# Ver TODO lo que registra el módulo, incluidos los DEBUG que Hermes se traga.
logging.basicConfig(level=logging.DEBUG, format="  %(levelname)-7s %(message)s",
                    stream=sys.stdout)
for ruidoso in ("urllib3", "httpx", "httpcore", "openwakeword"):
    logging.getLogger(ruidoso).setLevel(logging.WARNING)

from hermes_cli.config import load_config
import tools.wake_word as ww

DURACION = int(sys.argv[1]) if len(sys.argv) > 1 else 25
cfg = load_config().get("wake_word", {})

print(f"frase configurada : {cfg.get('phrase')!r}")
print(f"modelo            : {cfg.get('openwakeword', {}).get('model')!r}")
print(f"sensitivity       : {ww._sensitivity(cfg)}")
print(f"confirmation      : {ww._confirmation_frames(cfg)}")
print(f"framework         : {ww.resolve_inference_framework(cfg)}")
print(f"enabled           : {cfg.get('enabled')}")
print()

disparos = []
def al_despertar():
    disparos.append(time.time())
    print(f"\n  ✦✦✦ ¡CALLBACK DE WAKE WORD DISPARADO!  (#{len(disparos)})\n")

class Duenyo:  # start_listening exige un "owner" para la concesión del micro
    pass
duenyo = Duenyo()

print(f"Arrancando el detector real. Di '{cfg.get('phrase')}' durante {DURACION}s...\n")
try:
    ww.start_listening(al_despertar, owner=duenyo, config=cfg)
except Exception as e:
    print(f"  ✗ start_listening falló: {type(e).__name__}: {e}")
    raise SystemExit(1)

# Instrumentar el motor REAL que acaba de construir start_listening, para ver
# qué puntuaciones y qué niveles de audio está viendo él (y no una réplica).
espia = {"frames": 0, "max_punt": 0.0, "max_nivel": 0, "sobre_umbral": 0}
det = ww._detector
if det is not None:
    _predict_original = det.engine._model.predict
    umbral = det.engine._threshold

    def predict_espiado(frame, *a, **kw):
        r = _predict_original(frame, *a, **kw)
        try:
            p = max(r.values())
            espia["frames"] += 1
            espia["max_punt"] = max(espia["max_punt"], p)
            espia["max_nivel"] = max(espia["max_nivel"], int(abs(frame).max()))
            if p >= umbral:
                espia["sobre_umbral"] += 1
        except Exception:
            pass
        return r

    det.engine._model.predict = predict_espiado
    print(f"  (motor real instrumentado; umbral efectivo {umbral})\n")
else:
    print("  ⚠ no se pudo acceder al detector para instrumentarlo\n")

try:
    time.sleep(DURACION)
finally:
    ww.stop_listening(owner=duenyo)

print()
print("LO QUE VIO EL MOTOR REAL:")
print(f"  frames procesados   : {espia['frames']}")
print(f"  nivel máximo audio  : {espia['max_nivel']}   (<=10 sería silencio)")
print(f"  puntuación máxima   : {espia['max_punt']:.3f}")
print(f"  frames sobre umbral : {espia['sobre_umbral']}")
print()
print(f"RESULTADO: {len(disparos)} disparos del callback de producción.")
if disparos:
    print("  ✅ El camino real del detector FUNCIONA.")
    print("     Si dentro de Hermes no salta, el fallo está en la integración")
    print("     con la CLI (_on_wake_word), no en el detector.")
else:
    print("  ❌ El detector de producción no disparó.")
    print("     Mira arriba los DEBUG: 'engine error', 'within cooldown' o silencio.")
