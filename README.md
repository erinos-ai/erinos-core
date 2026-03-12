# ErinOS

ErinOS is a local-first AI assistant built with Ruby. It runs on a dedicated Arch Linux appliance with full-disk encryption, local LLM inference via Ollama, voice input/output, and integrations with console, Telegram, and voice hardware. Erin's skills currently include Google Workspace, Home Assistant, Hue lights, Spotify, and Sonos.

Everything runs locally. The only external dependency is an OAuth relay service that holds provider secrets so the appliance never needs them.


## How It Works

The core is a Sinatra API server. All user-facing interfaces (console, Telegram, voice hardware) are thin HTTP clients that talk to this API. The API manages an AI agent (Erin) powered by RubyLLM, which can use tools to control smart home devices, manage schedules, store memories, and run commands against third-party services.

When a voice request comes in, the server chains three steps: speech-to-text (Whisper), AI chat (Erin), and text-to-speech (Kokoro). The result is a WAV audio file sent back to the caller.


## Project Layout

```
erinos/
  api/                  Sinatra API (routes, helpers)
  agents/               AI agent configuration
  prompts/              Agent prompt templates (ERB)
  channels/             User interfaces (console CLI, Telegram bot)
  services/             Shared logic (HTTP client, skill registry, notifier)
  tools/                Agent tools (OAuth, commands, schedules, memory)
  entities/             ActiveRecord models (User, Memory, Schedule, UserCredential)
  skills/               Provider configs and skill documentation
  config/               Application boot and initializers
  db/                   Migrations and seeds
  bin/                  Process entrypoints (server, console, telegram, scheduler)
  oauth_relay/          OAuth relay service (deployed separately)
  speaker/              ESP32-S3 voice hardware firmware
  iso/                  Arch Linux installer (archiso profile)
  dev/                  Development tools (Procfile, start script, USB flash script)
  .github/workflows/    CI (ISO builder)
```


## Architecture

### API Server

The server (`bin/server`) starts a Sinatra app on port 4567 using Puma. It exposes four route groups:

**Authentication** (`api/routes/auth.rb`): Register a user with a name and PIN, or look up the current user. Authentication is header-based: every request includes an `X-User-ID` header containing either a PIN or a Telegram ID. There are no tokens or sessions.

**Chat** (`api/routes/chat.rb`): Send a text message and get a response. There are two modes: synchronous (POST `/api/chat` returns JSON) and streaming (POST `/api/chat/stream` returns Server-Sent Events). The server maintains in-memory chat sessions per user, protected by a mutex for thread safety.

**Voice** (`api/routes/voice.rb`): Send an audio file and get an audio response. The endpoint accepts a multipart WAV upload, transcribes it with Whisper, sends the text to Erin, synthesizes the response with Kokoro, and returns WAV audio. This is the endpoint used by both the Telegram bot (for voice messages) and the ESP32 speaker hardware.

**Health**: GET `/health` returns `{"status": "ok"}`.

### Erin Agent

Erin (`agents/erin.rb`) is a RubyLLM agent configured with a model and provider from environment variables (`ERIN_PROVIDER` and `ERIN_MODEL`). The system prompt is an ERB template (`prompts/erin.md.erb`) that includes the user's name, connected providers, stored memories, and a catalog of available skills.

Erin has seven tools:

- **AuthorizeProvider**: Starts an OAuth flow by requesting a URL from the OAuth relay. The user clicks the link to authorize, then Erin polls for the resulting tokens.
- **CheckAuthorization**: Polls the OAuth relay every 3 seconds (up to 120 seconds) waiting for the user to complete authorization.
- **StoreCredential**: Saves non-OAuth credentials (like a Hue bridge IP and API key) to the database.
- **ReadSkill**: Loads the full documentation for a skill so Erin knows how to use it.
- **RunCommand**: Executes a shell command with credential injection. For OAuth providers, it refreshes expired tokens automatically. Credentials are injected as environment variables.
- **ManageSchedule**: Creates, lists, or cancels scheduled tasks. Supports cron expressions (parsed by Fugit) and one-off schedules.
- **ManageMemory**: Saves, lists, or deletes user memories that persist across conversations.

### Channels

Channels are thin HTTP clients that use the shared `ErinosClient` (`services/erinos_client.rb`) to talk to the API.

**Console** (`channels/console.rb`): An interactive CLI. Authenticates with a PIN, then streams responses via SSE with a spinner that shows tool names as they execute.

**Telegram** (`channels/telegram_bot.rb`): A long-polling Telegram bot. Unknown users are asked for their PIN to link their account. Supports both text and voice messages. Voice messages are downloaded as OGG, converted to WAV with ffmpeg, sent to `/api/chat`, and the audio response is sent back as a Telegram voice message.

**Scheduler** (`bin/scheduler`): A polling loop that checks for due schedules every 30 seconds. When a schedule fires, it sends the prompt to `/api/chat` and delivers the response via the Notifier service (currently Telegram only).

### Skills System

Skills are organized under `skills/` by provider. Each provider has a `provider.yml` defining its authentication type (OAuth or local) and environment variable mappings. Each skill has a `SKILL.md` file with YAML frontmatter (name, description) and markdown body (setup instructions, API reference, command examples).

The `SkillRegistry` service loads all skills at boot and provides a catalog that gets included in Erin's system prompt. When Erin needs to use a skill, it calls `ReadSkill` to get the full documentation, then `RunCommand` to execute commands with the appropriate credentials injected.

Current providers: Google Workspace (calendar, gmail, drive, sheets, docs, slides, people, tasks), Spotify (playback), Hue (lights), Sonos (speakers), Home Assistant (control).

### OAuth Relay

The OAuth relay (`oauth_relay/`) is a separate Sinatra app deployed to Fly.io at `oauth.erinos.ai`. It holds OAuth client secrets for all providers so the appliance never needs them.

The flow works like this: Erin calls `AuthorizeProvider`, which POSTs to the relay's `/auth/start` with a provider name and random state token. The relay returns an authorization URL. The user clicks it, authorizes with the provider, and the provider redirects back to the relay's `/callback`. The relay exchanges the code for tokens and stores them keyed by the state token. Meanwhile, Erin polls `/poll?state=...` until the tokens appear, then saves them to the database.

Token refresh works similarly: `RunCommand` checks if a token is expired, and if so, POSTs the refresh token to `/auth/refresh` to get a new access token.

The relay stores sessions in memory with a 300-second TTL. Provider configurations are in `oauth_relay/providers.yml`.

### Voice Pipeline

Voice processing chains three local services:

1. **Whisper** (port 8080): whisper.cpp server for speech-to-text. Takes a WAV file, returns transcribed text.
2. **Erin**: The AI agent processes the text and generates a response.
3. **Kokoro** (port 8880): Kokoro-FastAPI for text-to-speech. Takes text, returns WAV audio. Uses an OpenAI-compatible API (`/v1/audio/speech`).

The voice endpoint in the API orchestrates all three steps in a single request.

### Database

SQLite database at `db/data/erinos.sqlite3`. Four tables:

**users**: `name` (unique), `pin` (unique), `telegram_id` (optional, unique). A user can authenticate via PIN (console, API) or Telegram ID (bot).

**user_credentials**: `user_id`, `provider`, `data` (JSON). Stores OAuth tokens or local credentials (like Hue bridge IP/API key). Unique index on (user_id, provider).

**schedules**: `user_id`, `prompt`, `cron` (optional), `channel`, `next_run_at`, `active`. Supports recurring (cron) and one-off schedules. The `advance!` method calculates the next run time or deactivates the schedule.

**memories**: `user_id`, `content`. Simple key-value store for things Erin should remember about a user.


## Speaker Firmware

The `speaker/` directory contains an ESP-IDF 5.5 project for the Waveshare ESP32-S3-AUDIO-Board. This is a push-to-talk voice client that communicates with the ErinOS API over WiFi.

The board has an ESP32-S3 processor, an ES7210 microphone codec (dual mic array), an ES8311 speaker codec, 7 WS2812 RGB LEDs, 8MB PSRAM, and a BOOT button used for push-to-talk.

The firmware flow is:

1. On boot, connect to WiFi and initialize audio codecs via I2C. LEDs breathe white when idle.
2. When the BOOT button is pressed, LEDs pulse pink and the mic records audio into a PSRAM buffer (16kHz, 16-bit, mono, up to 10 seconds).
3. On button release, LEDs spin pink and the firmware builds a WAV file from the recorded PCM data, wraps it in a multipart HTTP POST, and sends it to `/api/chat` on the ErinOS server.
4. The server responds with WAV audio. The firmware strips the 44-byte WAV header and plays the raw PCM through the speaker. LEDs turn green during playback.
5. When playback finishes, LEDs return to idle breathing.

All configuration (WiFi credentials, server address, user ID) is in `main/config.h`. Copy `config.h.example` to `config.h` and fill in your values.


## Appliance Installer

The `iso/` directory is an archiso profile that builds a bootable Arch Linux installer. GitHub Actions builds the ISO automatically on every push to main.

### What the Installer Does

The installer (`erinos-install`) is an interactive 7-step process powered by `gum` for the UI:

1. **Check internet**: Pings archlinux.org. Offers nmtui for WiFi if no connection.
2. **Select disk**: Shows available disks, user picks one.
3. **Disk encryption**: Prompts for a LUKS2 passphrase. Full-disk encryption is mandatory.
4. **Partition and format**: Creates a 512MB EFI partition and an encrypted root partition. Formats EFI as FAT32 and root as ext4.
5. **Install base system**: Runs pacstrap with all required packages (base, linux, amd-ucode, ollama-rocm, ffmpeg, git, sqlite, gum, etc.). Copies the ErinOS application to `/opt/erinos`. Loads `.env` from a USB config partition if present.
6. **Configure system**: Sets up locale, timezone, hostname, systemd-boot with LUKS, initramfs, NetworkManager, mDNS. Creates an `erinos` system user. Installs rbenv and builds Ruby 4.0.0 (without YJIT). Runs `bundle install`. Creates systemd services for all ErinOS processes.
7. **Set root password**: Interactive prompt.

After installation, the system reboots. On first boot, a one-shot service (`erinos-firstboot`) runs automatically:

- Waits for network
- Pulls the Ollama model (if `ERIN_PROVIDER=ollama`)
- Downloads the Whisper speech recognition model from Hugging Face
- Initializes the database
- Enables and starts all services

A console status display (`erinos-console`) runs on tty1 with auto-login. It shows the ErinOS logo, SSH connection info, and an activity log parsed from journalctl (Telegram messages, SSH logins, model loading, scheduler events).

### USB Configuration

The installer can load a pre-configured `.env` file from the USB drive. The `dev/flash` script handles this automatically: it downloads the latest ISO from GitHub Actions, opens `.env.example` in your editor (pre-populated from your local `.env`), flashes the ISO to a USB drive, and copies your `.env` to the USB's EFI partition.


## Development Setup

### Prerequisites

- Ruby 4.0.0 (via rbenv)
- SQLite
- Foreman (`gem install foreman`)
- ffmpeg (for Telegram voice messages)
- whisper.cpp server (for speech-to-text)
- Kokoro-FastAPI (for text-to-speech, optional)
- ESP-IDF 5.5 (for speaker firmware, optional)

### Getting Started

Clone the repository and install dependencies:

```bash
git clone git@github.com:fconforti/erinos.git
cd erinos
bundle install
```

Create your environment file:

```bash
cp .env.example .env
# Edit .env with your configuration
```

At minimum, set `ERIN_PROVIDER` and `ERIN_MODEL`. If using Ollama locally, make sure it's running and the model is pulled:

```bash
ollama pull qwen3:8b
```

Initialize the database:

```bash
bundle exec bin/erinos db:reset
```

### Running in Development

Start all services with Foreman:

```bash
./dev/start
```

This starts the API server, Telegram bot, scheduler, Whisper server, and Kokoro. It kills any leftover processes on ports 4567, 8080, and 8880 first.

To test interactively, open a second terminal:

```bash
bundle exec bin/console
```

Enter your PIN when prompted. Type messages to chat with Erin.

### Running Individual Components

If you don't need everything at once:

```bash
# API server only
bundle exec bin/server

# Telegram bot only (requires server running)
bundle exec bin/telegram

# Scheduler only (requires server running)
bundle exec bin/scheduler

# Console (requires server running)
bundle exec bin/console
```

### Voice Services

**Whisper** (speech-to-text): Install whisper.cpp and run the server:

```bash
# macOS
brew install whisper-cpp
whisper-server --model /opt/homebrew/share/whisper-cpp/ggml-base.bin --port 8080
```

**Kokoro** (text-to-speech): Clone and run Kokoro-FastAPI:

```bash
git clone https://github.com/remsky/Kokoro-FastAPI.git
cd Kokoro-FastAPI
ESPEAK_DATA_PATH=$(brew --prefix)/share/espeak-ng-data ./start-cpu.sh
```

Set the voice in your `.env`:

```
KOKORO_VOICE=af_heart
```

### Speaker Firmware

The speaker firmware requires ESP-IDF 5.5:

```bash
# Install ESP-IDF
brew install cmake ninja dfu-util
mkdir -p ~/esp && cd ~/esp
git clone -b v5.5 --recursive https://github.com/espressif/esp-idf.git
cd esp-idf && ./install.sh esp32s3

# Source environment (needed in each terminal)
source ~/esp/esp-idf/export.sh
```

Configure and build:

```bash
cd speaker
cp main/config.h.example main/config.h
# Edit main/config.h: set WIFI_SSID, WIFI_PASS, ERINOS_HOST (use your Mac's LAN IP), ERINOS_USER_ID
idf.py set-target esp32s3
idf.py build
```

Flash the board (connect via USB-C):

```bash
idf.py -p /dev/tty.usbmodem* flash monitor
```

The serial monitor shows WiFi connection status, recording events, HTTP requests, and playback. Press the BOOT button on the board to record, release to send.

### OAuth Relay

The OAuth relay is a separate Sinatra app that must be publicly accessible (OAuth providers redirect back to it). For development, expose it via ngrok or deploy it somewhere like Fly.io:

```bash
# Deploy to Fly.io (production)
cd oauth_relay
fly launch

# Or for development: run locally + expose via ngrok
cd oauth_relay
bundle install
ruby app.rb
ngrok http 9292   # in another terminal
```

Set `OAUTH_RELAY_URL` in your `.env` to the public URL (e.g. `https://oauth.erinos.ai` or your ngrok URL). It cannot be localhost — OAuth providers need to redirect back to a reachable address.

Provider OAuth credentials (client ID and secret) go in the relay's environment, not in the appliance's `.env`.

### Adding a New Skill

1. Create a directory under `skills/` for the provider (if new):

```
skills/mydevice/
  provider.yml
  control/SKILL.md
```

2. Define the provider configuration in `provider.yml`:

```yaml
auth:
  type: local  # or "oauth"
env:
  MY_DEVICE_TOKEN: api_key
```

For OAuth providers, add the provider to `oauth_relay/providers.yml` with its OAuth URLs and scopes.

3. Write the skill documentation in `SKILL.md`:

```markdown
---
name: mydevice-control
description: Control my device
---

## Setup

Explain how to get credentials.

## Commands

Document the CLI commands or API calls that Erin should use.
```

The skill registry loads everything automatically. Erin will see the new skill in her catalog and can read the documentation when needed.

### Adding a New Tool

Tools live in `tools/` and extend `RubyLLM::Tool`. Each tool defines its parameters and an `execute` method. Register new tools in `agents/erin.rb`.

### Adding a New Channel

A channel is any process that uses `ErinosClient` to talk to the API. Create a new file in `channels/`, add a bin script in `bin/`, and optionally add it to `dev/Procfile`.


## Deploying the Appliance

### Building the ISO

Push to the `main` branch. GitHub Actions builds the ISO automatically. Download it from the Actions tab, or create a git tag to generate a GitHub Release:

```bash
git tag v1.0.0
git push --tags
```

### Flashing a USB Drive

The `dev/flash` script automates everything:

```bash
./dev/flash
```

It will:
1. Download the latest ISO from GitHub Actions
2. Open your `.env` for editing (pre-populated from your local `.env`)
3. Ask you to select a USB drive and confirm
4. Flash the ISO and copy your `.env` to the USB

You need the GitHub CLI (`gh`) installed and authenticated.

### Installing on the appliance

1. Plug the USB drive into the appliance
2. Boot from USB (press F12 for boot menu)
3. At the motd prompt, run `erinos-install`
4. Follow the 7-step installer
5. Remove the USB drive and reboot
6. Enter your LUKS passphrase at boot
7. Wait for first-boot setup to complete (pulls AI model, downloads Whisper, initializes database)

After setup, the console on tty1 shows the ErinOS logo and SSH connection info. SSH in as root to manage the appliance. The `erinos` CLI wrapper is available system-wide.


## Environment Variables

All configuration is in `.env`. See `.env.example` for the full list with documentation.

**Required:**
- `ERIN_PROVIDER`: LLM provider (ollama, anthropic, openai, gemini, deepseek, mistral, openrouter)
- `ERIN_MODEL`: Model name (e.g., `qwen3:8b` for Ollama, `claude-sonnet-4-20250514` for Anthropic)

**Voice (optional):**
- `WHISPER_URL`: Whisper server URL (default: `http://localhost:8080`)
- `KOKORO_URL`: Kokoro TTS URL (default: `http://localhost:8880`)
- `KOKORO_VOICE`: TTS voice (default: `af_heart`)

**Telegram (optional):**
- `TELEGRAM_BOT_TOKEN`: Get one from @BotFather on Telegram

**Provider API keys** (only for cloud LLM providers):
- `OLLAMA_API_BASE`, `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, etc.

**System (installer only):**
- `HOSTNAME`, `TIMEZONE`, `KEYMAP`


## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test locally with `./dev/start`
5. Push and open a pull request

The ISO builds automatically on every push to main. Test installer changes by flashing a USB with `./dev/flash` and running through the installation on hardware or in a VM (QEMU/UTM).

Keep things simple. ErinOS is a single Ruby app by design. Avoid adding Docker, microservices, or unnecessary abstractions.
