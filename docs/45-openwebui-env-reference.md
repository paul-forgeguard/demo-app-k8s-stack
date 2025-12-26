# Open WebUI Environment Variable Reference

This document provides a comprehensive reference for Open WebUI environment variables, focusing on audio (TTS/STT) configuration used in this homelab.

> **Source:** https://docs.openwebui.com/getting-started/env-configuration/

---

## Audio Configuration (TTS/STT)

### Text-to-Speech (TTS) Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AUDIO_TTS_ENGINE` | (empty) | TTS engine: `openai`, `azure`, `elevenlabs`, `transformers`, or empty for WebAPI |
| `AUDIO_TTS_API_KEY` | (none) | API key for TTS service |
| `AUDIO_TTS_MODEL` | `tts-1` | TTS model name |
| `AUDIO_TTS_VOICE` | `alloy` | TTS voice option |
| `AUDIO_TTS_SPLIT_ON` | `punctuation` | Text split method for TTS |
| `AUDIO_TTS_OPENAI_API_BASE_URL` | `${OPENAI_API_BASE_URL}` | OpenAI-compatible TTS endpoint |
| `AUDIO_TTS_OPENAI_API_KEY` | `${OPENAI_API_KEY}` | API key for OpenAI TTS |
| `AUDIO_TTS_AZURE_SPEECH_REGION` | (none) | Azure region for TTS |
| `AUDIO_TTS_AZURE_SPEECH_OUTPUT_FORMAT` | (none) | Azure TTS output format |
| `ELEVENLABS_API_BASE_URL` | `https://api.elevenlabs.io` | ElevenLabs API endpoint |
| `VOICE_MODE_PROMPT_TEMPLATE` | (default) | Custom system prompt for voice mode |

### Speech-to-Text (STT) Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AUDIO_STT_ENGINE` | (empty) | STT engine: `openai`, `deepgram`, `azure`, or empty for local Whisper |
| `AUDIO_STT_MODEL` | `whisper-1` | STT model for OpenAI-compatible endpoints |
| `AUDIO_STT_OPENAI_API_BASE_URL` | `${OPENAI_API_BASE_URL}` | OpenAI-compatible STT endpoint |
| `AUDIO_STT_OPENAI_API_KEY` | `${OPENAI_API_KEY}` | API key for OpenAI STT |
| `AUDIO_STT_AZURE_API_KEY` | (none) | Azure API key for STT |
| `AUDIO_STT_AZURE_REGION` | (none) | Azure region for STT |
| `AUDIO_STT_AZURE_LOCALES` | (none) | Azure STT locales |
| `DEEPGRAM_API_KEY` | (none) | Deepgram API key for STT |

### Whisper Configuration (Local)

| Variable | Default | Description |
|----------|---------|-------------|
| `WHISPER_MODEL` | `base` | Whisper model size for local STT |
| `WHISPER_MODEL_DIR` | `${DATA_DIR}/cache/whisper/models` | Directory for Whisper models |
| `WHISPER_VAD_FILTER` | `False` | Voice Activity Detection filter |
| `WHISPER_MODEL_AUTO_UPDATE` | `False` | Auto-update Whisper models |
| `WHISPER_LANGUAGE` | (none) | ISO 639-1 language code |

---

## VX Home Configuration

This homelab uses local Kokoro (TTS) and Faster-Whisper (STT) services with GPU acceleration.

### TTS Configuration (Kokoro)

```yaml
env:
  - name: AUDIO_TTS_ENGINE
    value: "openai"
  - name: AUDIO_TTS_OPENAI_API_BASE_URL
    value: "http://kokoro:8880/v1"
  - name: AUDIO_TTS_OPENAI_API_KEY
    value: "not-needed"
  - name: AUDIO_TTS_MODEL
    value: "kokoro"
  - name: AUDIO_TTS_VOICE
    value: "af_bella"
```

**Why this configuration:**
- `AUDIO_TTS_ENGINE=openai` - Kokoro exposes an OpenAI-compatible API
- `AUDIO_TTS_OPENAI_API_BASE_URL` - Points to Kokoro service within cluster
- `AUDIO_TTS_OPENAI_API_KEY=not-needed` - Kokoro doesn't require auth
- `AUDIO_TTS_VOICE=af_bella` - Default Kokoro voice

### STT Configuration (Faster-Whisper)

```yaml
env:
  - name: AUDIO_STT_ENGINE
    value: "openai"
  - name: AUDIO_STT_OPENAI_API_BASE_URL
    value: "http://faster-whisper:8000/v1"
  - name: AUDIO_STT_OPENAI_API_KEY
    value: "not-needed"
  - name: AUDIO_STT_MODEL
    value: "Systran/faster-whisper-base"
```

**Why this configuration:**
- `AUDIO_STT_ENGINE=openai` - Faster-Whisper exposes an OpenAI-compatible API
- `AUDIO_STT_OPENAI_API_BASE_URL` - Points to Faster-Whisper service
- `AUDIO_STT_MODEL` - Specifies the Whisper model to use

---

## Other Common Environment Variables

### Database

| Variable | Description |
|----------|-------------|
| `DATABASE_URL` | PostgreSQL connection string |
| `POSTGRES_DB` | Database name |
| `POSTGRES_USER` | Database user |
| `POSTGRES_PASSWORD` | Database password |

### Redis

| Variable | Description |
|----------|-------------|
| `REDIS_URL` | Redis connection string (e.g., `redis://redis:6379/0`) |

### OpenAI / LLM

| Variable | Description |
|----------|-------------|
| `OPENAI_API_KEY` | OpenAI API key |
| `OPENAI_API_BASE_URL` | OpenAI API base URL |
| `OLLAMA_BASE_URL` | Ollama server URL (if using Ollama) |

### Application

| Variable | Description |
|----------|-------------|
| `WEBUI_URL` | Public URL for Open WebUI |
| `WEBUI_SECRET_KEY` | Secret key for sessions |
| `ENABLE_SIGNUP` | Allow new user registration (`True`/`False`) |
| `DEFAULT_USER_ROLE` | Default role for new users |

---

## Kokoro Voice Options

Available voices for `AUDIO_TTS_VOICE`:

| Voice | Description |
|-------|-------------|
| `af_bella` | American Female - Bella (default) |
| `af_nicole` | American Female - Nicole |
| `af_sarah` | American Female - Sarah |
| `am_adam` | American Male - Adam |
| `am_michael` | American Male - Michael |
| `bf_emma` | British Female - Emma |
| `bf_isabella` | British Female - Isabella |
| `bm_george` | British Male - George |
| `bm_lewis` | British Male - Lewis |

See https://github.com/remsky/Kokoro-FastAPI for full voice list.

---

## Faster-Whisper Model Options

Available models for `AUDIO_STT_MODEL`:

| Model | Size | Speed | Accuracy |
|-------|------|-------|----------|
| `Systran/faster-whisper-tiny` | 39M | Fastest | Lower |
| `Systran/faster-whisper-base` | 74M | Fast | Good |
| `Systran/faster-whisper-small` | 244M | Medium | Better |
| `Systran/faster-whisper-medium` | 769M | Slower | High |
| `Systran/faster-whisper-large-v3` | 1.5G | Slowest | Best |

With GPU acceleration on A2, `large-v3` is recommended for best accuracy.

---

## Testing Audio Configuration

### Verify TTS Connection

```bash
# From Open WebUI pod
kubectl exec -it deploy/openwebui -n ai -- \
  curl -s http://kokoro:8880/health

# Test TTS endpoint
kubectl exec -it deploy/openwebui -n ai -- \
  curl -X POST http://kokoro:8880/v1/audio/speech \
  -H "Content-Type: application/json" \
  -d '{"input": "Hello world", "voice": "af_bella"}' \
  --output /dev/null -w "%{http_code}"
```

### Verify STT Connection

```bash
# From Open WebUI pod
kubectl exec -it deploy/openwebui -n ai -- \
  curl -s http://faster-whisper:8000/health
```

### Check Configuration in Logs

```bash
kubectl logs -l app=openwebui -n ai | grep -i "audio\|tts\|stt"
```

---

*Last Updated: December 24, 2025*
