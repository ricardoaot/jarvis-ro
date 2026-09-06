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
| Wake word + medición de falsos positivos | ⏳ siguiente |

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

## Cómo está organizado

| Ruta | Qué es |
|---|---|
| `config/hermes.config.yaml` | Config de Hermes, versionada. `~/.hermes/config.yaml` es un symlink aquí. |
| `.env` | El único sitio donde vive la API key. Ignorado por git. |
| `.env.example` | Plantilla versionada, con las variables vacías. |
| `scripts/jarvis.sh` | Lanzador: exporta `.env` al entorno y arranca Hermes. |
| `scripts/setup-macos.sh` | Instalación idempotente en macOS. |
| `scripts/setup-linux.sh` | Stub del port a Linux. |
| `scripts/falsos-positivos.sh` | Instrumento de medición de la fase 1. |
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
