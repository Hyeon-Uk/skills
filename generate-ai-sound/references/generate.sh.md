# generate.sh (generate-ai-sound)
**Description**: Entry point script for AI audio generation. Reads `{agent_config_path}/config.yaml`, determines the effective provider via smart routing (music always uses gemini, speech honors defaults.provider with fallback), and dispatches to the appropriate handler.
**Depends on**: `curl` — for HTTP requests to OpenAI/Gemini APIs.

## Usage

```bash
bash generate.sh "<text or music prompt>" [OPTIONS]
```

## Options

| Option | Default | Modes | Description |
|--------|---------|-------|-------------|
| `--mode music\|speech` | `speech` | both | Select music or speech generation |
| `--model NAME` | per (provider, mode) | both | Override the default model |
| `--voice NAME` | `alloy` (OpenAI), `Kore` (Gemini) | TTS only | Voice for speech synthesis |
| `--format FMT` | `wav` (TTS), `mp3` (Lyria) | both | Output audio format |
| `--speed N` | `1.0` | OpenAI TTS only | Speech speed (0.25–4.0) |
| `--output PATH` | `./audio_<timestamp>.<ext>` | both | Output file path |
| `--input-file PATH` | (positional text used) | TTS only | Read text from a file |
| `-h`, `--help` | | | Show help message |

## Exit Codes

| Code | Description |
|------|-------------|
| `0` | Success — outputs absolute path of saved audio |
| `1` | Usage error, config missing, or API failure |
| `2` | Invalid arguments or unsupported operation |

## Default Models

| Provider | Speech Default | Music Default |
|----------|----------------|---------------|
| `openai` | `tts-1-hd` | N/A |
| `gemini` | `gemini-2.5-flash-preview-tts` | `lyria-3-pro-preview` |

## Provider Routing

| `--mode` | `defaults.provider` | Effective Provider |
|----------|---------------------|-------------------|
| `music` | any | `gemini` |
| `speech` | `openai` | `openai` |
| `speech` | `gemini` | `gemini` |
| `speech` | `anthropic` | `gemini` → `openai` fallback |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `AGENT_CONFIG` | `{agent_config_path}/config.yaml` | Path to config file |

## Examples

```bash
# Generate music
bash generate.sh "upbeat electronic track" --mode music

# Generate speech with default provider
bash generate.sh "Hello world" --mode speech

# Specify voice
bash generate.sh "Welcome!" --mode speech --voice nova

# Read from file
bash generate.sh --mode speech --input-file script.txt

# Adjust speed (OpenAI only)
bash generate.sh "Slow down" --mode speech --speed 0.75
```

## Related Scripts

- `openai_tts.sh` — OpenAI text-to-speech
- `gemini_tts.sh` — Gemini text-to-speech (PCM → WAV)
- `gemini_music.sh` — Google Lyria 3 music generation
- `parse_yaml.sh` — YAML parsing utilities