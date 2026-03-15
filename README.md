# ErinOS Core

Local-first AI assistant built with Ruby. Runs on a dedicated Arch Linux appliance with local LLM inference via Ollama, voice input/output, and integrations with console, Telegram, and voice hardware.

Everything runs locally. The only external dependency is a [cloud relay](https://github.com/erinos-ai/erinos-relay) that holds OAuth provider secrets and provides a WebSocket tunnel for remote access.


## How It Works

The core is a Sinatra API server. All user-facing interfaces (console, Telegram, voice hardware) are thin HTTP clients that talk to this API. The API manages an AI agent (Erin) powered by RubyLLM, which can use tools to control smart home devices, manage schedules, store memories, and run commands against third-party services.

When a voice request comes in, the server chains three steps: speech-to-text (Whisper), AI chat (Erin), and text-to-speech (Kokoro). The result is a WAV audio file sent back to the caller.


## Project Layout

```
api/                  Sinatra API (routes, helpers)
agents/               AI agent configuration
prompts/              Agent prompt templates (ERB)
channels/             User interfaces (console CLI, Telegram bot)
services/             Shared logic (HTTP client, skill registry, notifier)
tools/                Agent tools (OAuth, commands, schedules, memory)
entities/             ActiveRecord models (User, Memory, Schedule, UserCredential)
config/               Application boot and initializers
db/                   Migrations and seeds
bin/                  CLI entrypoint and process scripts
dev/                  Development tools (Procfile, start script)
VERSION               Current version tag (stamped by CI on release)
```


## Architecture

### API Server

The server (`bin/server`) starts a Sinatra app on port 4567 using Puma. It exposes four route groups:

**Authentication** (`api/routes/auth.rb`): Register a user with a name and PIN, or look up the current user. Authentication is header-based: every request includes an `X-User-ID` header containing either a PIN or a Telegram ID. There are no tokens or sessions.

**Chat** (`api/routes/chat.rb`): Send a text message and get a response. Two modes: synchronous (POST `/api/chat` returns JSON) and streaming (POST `/api/chat/stream` returns Server-Sent Events). The server maintains in-memory chat sessions per user, protected by a mutex for thread safety.

**Voice** (`api/routes/voice.rb`): Send an audio file and get an audio response. Accepts a multipart WAV upload, transcribes it with Whisper, sends the text to Erin, synthesizes the response with Kokoro, and returns WAV audio.

**Health**: GET `/health` returns `{"status": "ok"}`.

### Erin Agent

Erin (`agents/erin.rb`) is a RubyLLM agent configured with a model and provider from environment variables (`ERIN_PROVIDER` and `ERIN_MODEL`). The system prompt is an ERB template (`prompts/erin.md.erb`) that includes the user's name, connected providers, stored memories, and a catalog of available skills.

Erin has seven tools:

- **AuthorizeProvider**: Starts an OAuth flow by requesting a URL from the relay.
- **CheckAuthorization**: Polls the relay waiting for the user to complete authorization.
- **StoreCredential**: Saves non-OAuth credentials (like a Hue bridge IP and API key).
- **ReadSkill**: Loads the full documentation for a skill.
- **RunCommand**: Executes a shell command with credential injection. Refreshes expired OAuth tokens automatically.
- **ManageSchedule**: Creates, lists, or cancels scheduled tasks. Supports cron expressions and one-off schedules.
- **ManageMemory**: Saves, lists, or deletes user memories that persist across conversations.

### Channels

Channels are thin HTTP clients that use `ErinosClient` (`services/erinos_client.rb`) to talk to the API.

**Console** (`channels/console.rb`): Interactive CLI. Authenticates with a PIN, streams responses via SSE.

**Telegram** (`channels/telegram_bot.rb`): Long-polling Telegram bot. Supports text and voice messages. Voice messages are converted to WAV, sent to the voice endpoint, and the audio response is sent back.

**Scheduler** (`bin/scheduler`): Polling loop that checks for due schedules every 30 seconds. Delivers responses via Telegram.

### Skills System

Skills are installed to `~/.erinos/skills/` from the [skill catalog](https://github.com/erinos-ai/erinos-skills). Each provider has a `provider.yml` defining its auth type and env mappings. Each skill has a `SKILL.md` with setup instructions and command reference.

The `SkillRegistry` loads all installed skills at boot. Erin sees them in her catalog and uses `ReadSkill` + `RunCommand` to execute them.

### Voice Pipeline

1. **Whisper** (port 8080): whisper.cpp server for speech-to-text.
2. **Erin**: AI agent processes the text.
3. **Kokoro** (port 8880): Kokoro-FastAPI for text-to-speech.

### Database

SQLite at `db/data/erinos.sqlite3`. Four tables: `users`, `user_credentials`, `schedules`, `memories`.


## CLI

On the appliance, `erinos` is the main entry point for all commands:

```bash
erinos server       # Start the API server
erinos console      # Interactive chat console
erinos telegram     # Telegram bot
erinos scheduler    # Scheduled task runner
erinos tunnel       # WebSocket tunnel to relay
erinos update       # Update to the latest release
erinos update v1.2  # Update to a specific version
erinos version      # Show current version
```

The CLI dispatcher (`bin/erinos`) routes subcommands to their respective scripts in `bin/`.


## Updating

The appliance can self-update from GitHub releases:

```bash
erinos update
```

This will:

1. Check GitHub for the latest release of erinos-core
2. Download the release tarball
3. Preserve local data (`.env`, database, vendor, rbenv, models)
4. Replace application files
5. Run `bundle install` and database migrations
6. Restart all services

To update to a specific version:

```bash
erinos update v1.2.0
```

To rollback, update to the previous version (shown after each update).


## Releasing

Tag a new version on erinos-core to create a release:

```bash
git tag v1.1.0
git push --tags
```

GitHub Actions creates a release automatically. Appliances can then pull it with `erinos update`.


## Development Setup

### Prerequisites

- Ruby 4.0.0 (via rbenv)
- SQLite
- Foreman (`gem install foreman`)
- ffmpeg (for Telegram voice messages)
- whisper.cpp server (for speech-to-text)
- Kokoro-FastAPI (for text-to-speech, optional)

### Getting Started

```bash
git clone git@github.com:erinos-ai/erinos-core.git
cd erinos-core
bundle install
cp .env.example .env
# Edit .env — at minimum set ERIN_PROVIDER and ERIN_MODEL
```

If using Ollama locally:

```bash
ollama pull qwen3:8b
```

Initialize the database:

```bash
bundle exec bin/erinos db:reset
```

### Running

Start all services:

```bash
./dev/start
```

In a second terminal:

```bash
bundle exec bin/console
```

### Running Individual Components

```bash
bundle exec bin/server      # API server
bundle exec bin/telegram    # Telegram bot (requires server)
bundle exec bin/scheduler   # Scheduler (requires server)
bundle exec bin/console     # Console (requires server)
```

### Voice Services

**Whisper** (speech-to-text):

```bash
brew install whisper-cpp
whisper-server --model /opt/homebrew/share/whisper-cpp/ggml-base.bin --port 8080
```

**Kokoro** (text-to-speech):

```bash
git clone https://github.com/remsky/Kokoro-FastAPI.git
cd Kokoro-FastAPI
ESPEAK_DATA_PATH=$(brew --prefix)/share/espeak-ng-data ./start-cpu.sh
```


## Environment Variables

See `.env.example` for the full list. Key variables:

| Variable | Description |
|----------|-------------|
| `ERIN_PROVIDER` | LLM provider (ollama, anthropic, openai, gemini, etc.) |
| `ERIN_MODEL` | Model name (e.g., `qwen3:8b`, `claude-sonnet-4-20250514`) |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token from @BotFather |
| `WHISPER_URL` | Whisper server URL (default: `http://localhost:8080`) |
| `KOKORO_URL` | Kokoro TTS URL (default: `http://localhost:8880`) |
| `RELAY_URL` | Cloud relay URL |
| `TUNNEL_KEY` | Shared secret for relay tunnel |


## Related Repos

- [erinos-relay](https://github.com/erinos-ai/erinos-relay) — Cloud relay (OAuth + tunnel)
- [erinos-skills](https://github.com/erinos-ai/erinos-skills) — Skill catalog
- [erinos-speaker](https://github.com/erinos-ai/erinos-speaker) — ESP32 voice hardware firmware
- [erinos-iso](https://github.com/erinos-ai/erinos-iso) — Arch Linux appliance ISO builder
