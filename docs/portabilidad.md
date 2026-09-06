# Portabilidad y problemas conocidos

Estado: fase 1 en curso, sobre macOS 26.6.2 Apple Silicon (arm64), Hermes Agent
v0.21.0 (2026.8.31). Linux todavía sin probar.

---

## 1. Qué es específico de macOS

### Dependencias de sistema
| macOS | Linux (Debian/Ubuntu) |
|---|---|
| `brew install portaudio` | `apt install portaudio19-dev` (headers de desarrollo) |
| `brew install ffmpeg` | `apt install ffmpeg` |
| `brew install ripgrep` | `apt install ripgrep` |
| — | `apt install libopus0` (solo si algún día hay voz en Discord) |

### El instalador se comporta distinto
En macOS solo usa Homebrew y nunca pide `sudo`. En **Linux sí ejecuta
`sudo apt-get` / `dnf` / `pacman`** para instalar `git` y `build-essential` si
faltan. Por eso ambos scripts de setup instalan las dependencias explícitamente
*antes*: así esa rama no llega a dispararse.

### Permisos de micrófono (TCC)
En macOS el permiso de micrófono es **por proceso**, y el backend de Python
necesita su propio permiso, aparte del terminal:

> Ajustes del Sistema → Privacidad y seguridad → Micrófono

Síntoma cuando falta: `/wake status` dice *"mic delivers only silence"*, y en
`agent.log` aparece `wake word: mic delivers only silence (peak<=N for Ns)`.
Puede fallar aunque el push-to-talk del escritorio sí funcione.

En Linux no existe este modelo. El equivalente es pertenecer al grupo `audio` y
que el dispositivo no esté ocupado en exclusiva por otro cliente.

### Backend de audio
macOS: CoreAudio a través de PortAudio, y el dispositivo por defecto suele
bastar (`wake_word.input_device: null`). En Linux hay ALSA / PulseAudio /
PipeWire de por medio; casi seguro habrá que fijar `input_device` a un índice o
a un substring del nombre del dispositivo.

---

## 2. Problemas conocidos encontrados

### 2.1 openWakeWord con ONNX no dispara nunca en Apple Silicon
**Upstream:** [openWakeWord #336](https://github.com/dscripka/openWakeWord/issues/336), abierto.
El modelo de embeddings ONNX devuelve scores ~1e-05 en macOS ARM64 pase lo que
pase, así que la detección nunca cruza el umbral.

**Impacto real en Hermes: ninguno, ya está mitigado.** Hermes v0.21.0 conoce el
bug y lo esquiva por dos vías, ambas en `tools/wake_word.py`:

- Si pones `inference_framework: "onnx"` en macOS ARM64, **lo coacciona a
  `tflite`** con un warning explícito que cita el issue #336.
- openWakeWord importa `tflite_runtime`, que **no tiene wheel para macOS
  arm64**. Hermes puentea en memoria `tflite_runtime` → `ai_edge_litert` (la
  wheel que sí existe en macOS), sin tocar site-packages.

**Qué significa para nosotros:** dejar `inference_framework: ""` (auto). No
forzar `onnx` jamás en este Mac. En Linux esto no aplica: allí `tflite-runtime`
es nativo y no hace falta puente.

### 2.2 El wake word no habla: bug abierto de Hermes
**Upstream:** [hermes-agent #74328](https://github.com/NousResearch/hermes-agent/issues/74328),
abierto. PR #74637 sin mergear.

**Verificado en el código instalado (v0.21.0), no solo en el issue.** En
`hermes_cli/cli_voice_mixin.py`:

- `_enter_voice_mode()` (~línea 516) consulta `voice.auto_tts` y pone
  `self._voice_tts = True`.
- `_on_wake_word()` (~línea 712) pone `self._voice_mode = True` pero **nunca
  mira `auto_tts` ni toca `_voice_tts`**.

Resultado: los turnos lanzados por wake word transcriben y responden, pero
**salen mudos**. El texto aparece en pantalla y no hay audio.

**Workaround oficial:** entrar una vez a `/voice` manualmente en cada arranque.
Basta una vez por proceso, no por disparo: `new_session()` no toca `_voice_tts`,
solo lo apaga `_disable_voice_mode`.

**Lo que hacemos aquí: parchearlo.** `patches/0001-wake-word-auto-tts.patch`
replica en `_on_wake_word` la comprobación de `auto_tts` que ya hace
`_enter_voice_mode`, más el `_tts_lease_async(True)` que calienta el motor para
que la primera respuesta no llegue tarde. Se aplica con
`scripts/aplicar-parches.sh`, que es idempotente y lo llama el setup.

⚠️ **`hermes update` sobrescribe el código y se lleva el parche.** Después de
cada actualización hay que volver a pasar `scripts/aplicar-parches.sh`. Si el
parche deja de aplicar limpio, probablemente upstream ya lo arregló (PR #74637):
comprueba el issue antes de rehacerlo.

**Por qué importa:** sin saberlo, esto se diagnostica como un fallo de Piper o
de la configuración de TTS, y no lo es. Es el primer sitio donde mirar si el
loop responde pero no suena.

### 2.3 No hay evento de hook para el wake word
El sistema de hooks de Hermes es amplio (`on_session_start`, `pre_tool_call`,
`agent:start`…), pero **no existe ningún evento específico de wake word**, y el
contexto de `on_session_start` (`session_id`, `model`, `platform`) no indica el
origen de la sesión: no distingue una sesión abierta por voz de una tecleada.

Por eso la medición de falsos positivos se hace leyendo `agent.log`, que sí
tiene una línea fiable a nivel INFO. Ver `scripts/falsos-positivos.sh`.

### 2.4 La primera descarga de una voz de Piper puede tumbar el proceso
Al sintetizar por primera vez con una voz no cacheada, Piper la descarga y a
veces revienta con un fallo nativo:

```
libc++abi: terminating due to uncaught exception of type std::__1::system_error:
recursive_mutex lock failed: Invalid argument
```

Observado con `es_AR-daniela-high`. Es una carrera entre la descarga y la carga
del modelo: **el .onnx sí queda bien escrito en disco**, y el segundo intento
funciona sin problema (1.20s). No es corrupción, es un crash de arranque.

**Mitigación:** `scripts/setup-macos.sh` pre-descarga la voz configurada con
`python -m piper.download_voices` antes del primer uso, para que esto no ocurra
en mitad de una conversación. Si cambias `tts.piper.voice`, vuelve a pasar el
setup o descarga la voz a mano.

### 2.5 No hay TTS bilingüe
`tools/tts_tool_local.py` resuelve la voz así:

```python
voice_name = piper_config.get("voice") or DEFAULT_PIPER_VOICE
```

Una voz estática de la config. **Hermes no detecta el idioma de la respuesta ni
enruta a otra voz**, y cada modelo de Piper habla un solo idioma.

Lo que sí es bilingüe:
- **STT**: con `stt.language: ""` Whisper autodetecta ES/EN.
- **El modelo**: contesta en el idioma en que le hables, sin configurar nada.

Lo que no: el habla. Una respuesta en inglés se locuta con fonética española.
Sale inteligible pero suena mal.

Si algún día hace falta de verdad, la vía sería un hook que detecte el idioma
de la respuesta y reescriba `tts.piper.voice` antes de sintetizar — pero eso es
código propio sobre un punto de extensión que Hermes no ofrece hoy, y queda muy
fuera del alcance de la fase 1.

### 2.6 Al probar el wake word con ficheros, deja silencio al final
No es un bug, es una trampa de la metodología, y cuesta una tarde si no la ves.

openWakeWord puntúa frames de 80 ms y exige `confirmation_frames` frames
**consecutivos** por encima del umbral. Un .wav que acaba justo al terminar la
frase se queda sin frames mientras la puntuación todavía está subiendo:

```
"hey jarvis" (0.81s, sin cola):  0.00 ... 0.01 0.15 0.82   -> racha 1, NO dispara
"hey jarvis" + 1.5s de silencio: 0.00 ... 0.12 0.93 1.00 1.00 ...  -> racha 8, dispara
```

El mismo audio, el mismo umbral, veredicto opuesto. En uso real el stream del
micro sigue corriendo, así que esto solo afecta a las pruebas offline: **añade
al menos 1 segundo de cola** (`ffmpeg -af apad=pad_dur=1.5`) o concluirás que
el detector está roto cuando no lo está.

Separación medida con la config actual (umbral 0.6):

| audio | pico |
|---|---|
| "hey jarvis, turn on the lights" | 1.00 |
| "hey there, what is the weather" | 0.011 |
| "the car is very fast" | 0.000 |

Casi dos órdenes de magnitud entre positivo y negativo. Buena señal de partida
para el criterio de aceptación, pero **no sustituye a medir con ruido real**:
esto es voz sintética en una habitación en silencio.

### 2.7 Los modelos de wake word son fonéticamente ingleses
**Este es el fallo que tumbó el primer intento de la fase 1.** El detector
arrancaba, el micro entregaba audio, y aun así "hey jarvis" no disparaba nunca.

Los modelos de openWakeWord están entrenados con voz sintética **inglesa**.
Dicho con fonética española, `hey_jarvis` se queda muy por debajo del umbral.
Medido con voces de `say` de macOS, cola de silencio y umbral 0.6:

| audio | pico | dispara |
|---|---|---|
| "hey jarvis", voz inglesa (Samantha), 16 kHz | 0.999 | sí |
| "hey jarvis", voz inglesa, 48 kHz → remuestreo | 0.999 | sí |
| "hey jarvis", voz española (Mónica) | **0.397** | **no** |
| "hey yarvis" / "hey llarvis" (aproximaciones) | 0.34-0.37 | no |

Las dos primeras filas descartan el remuestreo 48k→16k como causa: da el mismo
resultado. La variable es la pronunciación.

**Qué modelos aguantan el español** (mismo umbral, voz de Mónica):

| modelo | dicho como | pico | |
|---|---|---|---|
| `hey_mycroft` | "hey maicroft" | **1.000** | ✅ |
| `hey_hermes` | "hey hermes" | **0.965** | ✅ |
| `alexa` | "alexa" | 0.829 | ⚠️ ver abajo |
| `hey_rhasspy` | "hey raspi" | 0.851 | ❌ sin racha |
| `hey_jarvis` | "hey yarvis" | 0.343 | ❌ |

**No uses `alexa`.** Puntúa bien, pero es la peor frase posible para el criterio
de aceptación: hay anuncios en televisión y aparatos reales que la dicen.

**No bajes `sensitivity` para compensar.** Es la tentación obvia y arruina la
fase 1: para que 0.397 dispare habría que bajar el umbral a ~0.35, que es
territorio de ruido, y el objetivo de esta fase es precisamente medir falsos
positivos. Cambia de modelo, no de umbral.

**Aviso metodológico:** todo esto está medido con TTS, que es un sustituto de
una voz humana, no la voz humana. Usa `scripts/probar-wake.sh` para ver la
puntuación real con tu voz antes de decidir.

**Trampa al instrumentar openWakeWord:** `predict()` es *stateful* — mantiene un
búfer temporal de features. Llamarlo dos veces sobre el mismo frame (por ejemplo
una vez para mostrar la puntuación y otra dentro de `process()`) le duplica el
audio y hunde la puntuación a cero:

| mismo audio, mismo modelo | pico |
|---|---|
| una predicción por frame | 0.960 |
| dos predicciones por frame | **0.000** |

Hermes hace lo correcto (`process()` una vez por frame en `_run`). Pero cualquier
herramienta de diagnóstico que quiera *enseñar* la puntuación y además decidir si
dispara tiene que llamar a `predict()` una sola vez y replicar a mano la lógica
de racha. `scripts/probar_wake.py` lo hace así; la primera versión no, y producía
ceros que parecían un micrófono muerto.

### 2.8 PortAudio corrompe la interfaz y Hermes parece colgado
Tras un turno de voz, al reabrir el micrófono, macOS suele soltar:

```
||PaMacCore (AUHAL)|| Error on line 2523: err='-50', msg=Unknown Error
```

Lo escribe la librería **C** de PortAudio directamente a stderr, saltándose el
logging de Python — por eso **no aparece en `agent.log`**. Cae encima del
dibujado de prompt_toolkit y se incrusta en la línea de entrada:

```
🎤 ❯ ||PaMacCore (AUHAL)|| Error on line 2523: err='-50'
```

A partir de ahí la interfaz deja de repintarse bien y **parece colgada**.

**No lo está.** Verificado sobre una instancia que el usuario daba por muerta:
reproduciendo la frase por los altavoces, el detector siguió disparando
(`phrase detected`) y arrancando grabación con normalidad. El backend funciona;
lo único roto es el dibujado.

**Mitigación:** `scripts/jarvis.sh` desvía stderr a `logs/stderr.log`. No se
pierde nada, porque el logging real de Hermes va a `~/.hermes/logs/`.

**Cómo distinguir "colgado" de "parece colgado"** — mira siempre el log, nunca
la pantalla:

```bash
tail -3 ~/.hermes/logs/agent.log     # ¿sigue escribiendo?
grep -c "phrase detected" ~/.hermes/logs/agent.log
```

### 2.9 El nivel de voz importa más de lo que parece
El detector no dispara si hablas lejos o bajo, y el síntoma es idéntico al de
un sistema roto: silencio absoluto, sin errores en ninguna parte.

Niveles medidos con `scripts/probar-wake.sh`:

| situación | nivel de pico | resultado |
|---|---|---|
| hablando lejos / bajo | 150-200 | **no dispara** |
| hablando cerca del portátil | ~3000 | dispara, pico 0.970 |

Un factor de quince. Antes de tocar `sensitivity` o cambiar de modelo,
comprueba el nivel: si ronda los cientos en vez de los miles, el problema es la
distancia al micrófono, no la configuración.

### 2.10 Carrera entre el watchdog del wake word y la grabación
**Síntoma:** el primer turno de voz funciona; en alguno posterior el wake word
detecta, aparece `● Recording...` y ahí se queda para siempre.

**Causa.** `_on_wake_word` pausa el detector para soltar el micro, y después
llama a `new_session()` antes de arrancar la grabación. Mientras tanto el
watchdog (`_start_wake_watchdog`) comprueba cada 0.25s si la CLI está ociosa:

```python
busy = (self._agent_running or self._voice_recording
        or getattr(self, "_voice_processing", False)
        or not self._pending_input.empty())
```

Ninguna de esas banderas está puesta todavía durante ese hueco. Si
`new_session()` tarda más de los ~0.75s que el watchdog espera, **reanuda el
detector**, que reabre el micrófono justo cuando la grabación va a usarlo. Los
dos streams se pelean y la grabación se cuelga.

Visto en el log, el turno que falla:

```
00:33:01,459  wake word: stream closed        <- pausa (correcto)
00:33:02,034  wake word: opening microphone   <- el watchdog reanuda
00:33:03,614  Voice recording started         <- micro ya ocupado -> cuelgue
```

Y el turno que funciona, sin reanudación intermedia:

```
00:32:21,452  wake word: stream closed
00:32:22,492  Voice recording started
00:32:24,124  Speech confirmed
```

**Arreglo** (en `patches/0001-wake-word-auto-tts.patch`): un cerrojo
`_wake_arming` que `_on_wake_word` levanta al pausar el detector y suelta en un
`finally` tras arrancar la grabación; el watchdog lo añade a su comprobación de
`busy`. Cierra el hueco sin tocar `_voice_processing`, que la barra de estado y
el manejo de teclas usan para otra cosa.

Es el mismo tipo de fallo que §2.2 y probablemente merezca un issue upstream.

### 2.11 Responde en inglés a preguntas en español
`~/.hermes/SOUL.md` —el prompt de persona que instala Hermes— está escrito en
inglés. Con entradas cortas, y especialmente en modo voz donde la transcripción
llega sin marcas de idioma, eso arrastra las respuestas al inglés aunque
preguntes en español.

**Arreglo:** `SOUL.md` pasa a estar versionado en `config/SOUL.md` (con
`~/.hermes/SOUL.md` como symlink, igual que `config.yaml`) y se le añade una
sección que fija la regla: responder siempre en el idioma de la entrada.

Verificado: "¿qué hora es en Perú?" responde en español, "what time is it in
Peru?" en inglés.

---

## 3. Decisiones de diseño para que el port sea barato

- **Config versionada por symlink.** `~/.hermes/config.yaml` apunta a
  `config/hermes.config.yaml` del repo. Igual en ambas plataformas.
- **Config mínima, no la plantilla completa.** El instalador genera un
  `config.yaml` de 2155 líneas comentadas. Versionamos solo las claves que
  fijamos nosotros; el resto son defaults del código. La plantilla original
  queda en `~/.hermes/config.yaml.installer-template` para diffs al actualizar.
- **El secreto vive en un único sitio.** Solo en el `.env` del repo (ignorado
  por git). `scripts/jarvis.sh` lo exporta al entorno antes de arrancar Hermes,
  así que **no se copia a `~/.hermes/.env`**. Un fichero que proteger, no dos.
- **`--skip-setup` siempre.** El asistente inicial de Hermes empuja
  `hermes setup --portal`, que es OAuth de suscripción. Además de estar
  prohibido en este proyecto, la propia documentación de Hermes avisa de que
  por esa vía **todo el uso se factura como "extra usage" aunque tu cuota de
  suscripción esté sin tocar**. La API key por tokens evita eso.
