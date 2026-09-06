# Jarvis

Asistente de voz personal montado sobre [Hermes Agent](https://github.com/NousResearch/hermes-agent)
de Nous Research.

Este repo **no contiene el código del agente**: es la configuración, los scripts
de instalación y la documentación. El agente lo pone Hermes; aquí solo se
configura y se automatiza el montaje para que sea reproducible.

## Estado actual

**Fase 1 en curso** — el objetivo es dejar corriendo el loop mínimo de voz:

```
wake word → STT → modelo → TTS
```

Sin MCP, sin herramientas, sin integraciones, sin cron. El único riesgo técnico
que se está validando es si la wake word aguanta ruido de fondo real.

| Paso | Estado |
|---|---|
| Instalación de Hermes (v0.21.0) | ✅ hecho |
| Config versionada + secretos externalizados | ✅ hecho |
| Responde por texto | ✅ hecho — `anthropic/claude-haiku-4.5` |
| STT (Whisper local) | ✅ hecho — bilingüe ES/EN por autodetección |
| TTS (Piper local) | ✅ hecho — voz `es_ES-davefx-medium`, 0.66s |
| Wake word (`hey hermes`) | ✅ funcionando end-to-end con voz real |
| Medición de falsos positivos | ⏳ **te toca a ti**: un día de uso normal |

**Criterio de aceptación de la fase 1:** un día completo de uso normal (música,
videollamadas, conversación, TV de fondo) con **menos de 3 falsos positivos**.
Si no se cumple, la salida es ajustar el umbral o cambiar la frase de wake word
— no pasar a la fase 2.

## Cómo levantarlo

```bash
./scripts/setup-macos.sh        # instala dependencias, Hermes, y enlaza la config
cp .env.example .env            # (el setup ya lo hace si no existe)
# rellena ANTHROPIC_API_KEY en .env
./scripts/jarvis.sh             # arranca
```

La API key se genera en [console.anthropic.com](https://console.anthropic.com)
→ Settings → API Keys. Ponle un límite de gasto: esto acabará siendo un proceso
always-on.

En Linux: `scripts/setup-linux.sh` es un **stub sin probar**. Léelo junto a
[docs/portabilidad.md](docs/portabilidad.md) antes de intentar el port.

## La palabra de activación

Ahora mismo es **"hey hermes"**.

Se eligió tras medir: `hey_jarvis` no funciona con pronunciación española
(0.23 con voz real contra un umbral de 0.60). Ver docs/portabilidad.md §2.7.

Arranca sola: `wake_word.enabled: true` hace que la CLI levante el detector al
iniciarse, así que **no hay que escribir `/wake on` ni `/voice`**. Lanzas
`./scripts/jarvis.sh`, dices "hey jarvis", y te contesta hablando.

```
/wake status     # ver estado del detector
/wake off        # apagarlo un rato
```

### Si parece que no responde

Mira el log, no la pantalla. PortAudio corrompe el dibujado de la interfaz y
Hermes **parece colgado cuando no lo está** (ver docs/portabilidad.md §2.8):

```bash
tail -3 ~/.hermes/logs/agent.log
```

Y antes de tocar nada: **acércate al micrófono**. Hablando lejos el nivel se
queda en 150-200 y no dispara; cerca sube a ~3000 y dispara con pico 0.970.

### Si no dispara

```bash
./scripts/probar-wake.sh          # cierra Hermes antes; te enseña la puntuación en vivo
```

Te dice cuál de las tres causas es: el micro no entrega audio, el modelo no te
reconoce, o te reconoce pero no cruza el umbral.

La causa más probable es la pronunciación: los modelos están entrenados con
inglés y "hey jarvis" dicho en español puntúa ~0.40 contra un umbral de 0.60.
`hey_mycroft` (1.000) y `hey_hermes` (0.965) sí aguantan la fonética española.
Ver docs/portabilidad.md §2.7.

### Cambiarla

Ojo con una sutileza: con openWakeWord, el campo `phrase` de la config es solo
una **etiqueta cosmética**. Quien detecta es el *modelo*, así que cambiar la
frase significa cambiar `openwakeword.model`.

Modelos entrenados disponibles sin hacer nada:

| `model:` | dices |
|---|---|
| `hey_jarvis` | "hey jarvis" — ⚠️ solo con acento inglés |
| `hey_hermes` | "hey hermes" ← **actual**, lo trae Hermes de serie |
| `alexa` | "alexa" |
| `hey_mycroft` | "hey mycroft" |
| `hey_rhasspy` | "hey rhasspy" |

Cambias las dos líneas en `config/hermes.config.yaml` y reinicias:

```yaml
wake_word:
  phrase: "hey mycroft"
  openwakeword:
    model: hey_mycroft
```

**¿Y una frase totalmente tuya?** Tres caminos, de menos a más lío:

1. **Porcupine** — trae `jarvis` entre sus keywords integradas y acepta ficheros
   `.ppn` propios. Necesita `PORCUPINE_ACCESS_KEY` (gratis) en `.env`; la
   detección sigue siendo on-device. Ya está la variable en `.env.example`.
2. **sherpa** — vocabulario abierto: escribes cualquier frase y la tokeniza al
   vuelo. Pero es **solo inglés** y no tiene `confirmation_frames`, que es la
   mejor palanca contra falsos positivos. Mal cambio para la fase 1.
3. **Entrenar un modelo openWakeWord propio** y apuntar `model:` a tu `.onnx`.
   Es lo que da mejor resultado y lo que más cuesta.

Si los falsos positivos se disparan, prueba primero a subir `sensitivity` y
`confirmation_frames` antes de cambiar de frase.

## Medir los falsos positivos (el objetivo de la fase 1)

Esto es lo único que queda por validar, y no lo puede hacer la máquina sola:
hace falta un día de uso normal con música, videollamadas, conversación y tele
de fondo.

```bash
./scripts/jarvis.sh              # deja Hermes corriendo el día entero
```

Al final del día:

```bash
./scripts/falsos-positivos.sh              # lista los disparos con su hora
./scripts/falsos-positivos.sh --falso 2 5  # marca los que NO provocaste tú
```

El script lee la línea INFO que `tools/wake_word.py` escribe en `agent.log` al
disparar, así que **registra los disparos aunque no lo tengas abierto**. Si
prefieres verlos en vivo con un pitido, `--seguir`.

El script cuenta disparos; cuáles fueron falsos lo decides tú, porque saber si
dijiste "hey jarvis" a propósito no está en ningún log. Cuando no quede ninguno
sin revisar, te da el veredicto contra el criterio de aceptación.

## Cómo está organizado

| Ruta | Qué es |
|---|---|
| `config/hermes.config.yaml` | Config de Hermes, versionada. `~/.hermes/config.yaml` es un symlink aquí. |
| `config/SOUL.md` | Prompt de persona, versionado. Fija que responda en tu idioma. |
| `.env` | El único sitio donde vive la API key. Ignorado por git. |
| `.env.example` | Plantilla versionada, con las variables vacías. |
| `scripts/jarvis.sh` | Lanzador: exporta `.env` al entorno y arranca Hermes. |
| `scripts/setup-macos.sh` | Instalación idempotente en macOS. |
| `scripts/setup-linux.sh` | Stub del port a Linux. |
| `scripts/falsos-positivos.sh` | Instrumento de medición de la fase 1. |
| `scripts/aplicar-parches.sh` | Aplica `patches/` sobre el código de Hermes. |
| `patches/` | Arreglo del bug #74328. **Repasar tras cada `hermes update`.** |
| `docs/portabilidad.md` | Qué es específico de macOS y los bugs conocidos. |

## Decisiones que conviene no revertir sin pensarlo

- **Sin `hermes proxy` ni OAuth de suscripción.** El cerebro va con API key por
  tokens. La documentación de Hermes empuja `hermes setup --portal`, y por esa
  vía **todo el uso se factura como "extra usage" aunque tengas cuota de
  suscripción sin consumir**. Por eso el setup pasa siempre `--skip-setup`.
- **Ningún secreto en el repo.** Ni en `~/.hermes/.env` tampoco: el `.env` del
  repo es el único, y se inyecta por entorno.
- **TTS local (Piper).** Sin TTS de red. El default de Hermes es `edge`, que sí
  es de red, así que hay que sobrescribirlo explícitamente.
- **El habla es solo en español.** Le puedes hablar en inglés o español y te
  entiende y te contesta en tu idioma, pero la voz siempre será española:
  Hermes no sabe cambiar de voz según el idioma. Ver docs/portabilidad.md §2.5.
- **Nada se instala a nivel de sistema sin que esté en `setup-macos.sh`**, a la
  vista y en una función aparte.
