# Dredd - LLM Market Bot

A Telegram bot that orchestrates multiple LLM providers (OpenAI, Anthropic, Gemini) to reach consensus on questions through a "market" process. Dredd is the arbiter that synthesizes the final answer.

## How It Works

1. **Round 1**: All enabled providers answer your question with confidence scores
2. **Round 2**: Each provider sees others' responses and can revise their answer
3. **Dredd**: The arbiter model synthesizes the final consensus answer
4. **Result**: You get the final answer with agreements, conflicts, and confidence

## Quick Start

### Prerequisites

- Elixir 1.14+
- PostgreSQL
- At least one LLM API key (OpenAI, Anthropic, or Gemini)
- Telegram Bot Token (from [@BotFather](https://t.me/BotFather))

### Setup

1. **Clone and install dependencies**

```bash
cd dredd
mix deps.get
```

2. **Configure environment**

```bash
cp .env.example .env
# Edit .env with your values
```

Required environment variables:
- `TELEGRAM_BOT_TOKEN` - Your Telegram bot token
- `WHITELIST_CHAT_IDS` - Comma-separated list of allowed Telegram chat IDs
- `DATABASE_URL` - PostgreSQL connection string (or configure in dev.exs)

At least one provider API key:
- `OPENAI_API_KEY`
- `ANTHROPIC_API_KEY`
- `GEMINI_API_KEY`

3. **Setup database**

```bash
mix ecto.create
mix ecto.migrate
```

4. **Start the server**

```bash
# Load environment variables
source .env

# Start in development mode (polling)
mix phx.server
```

### Getting Your Telegram Chat ID

1. Start a chat with your bot
2. Send any message
3. Check the server logs - unauthorized attempts show the chat ID
4. Add that ID to `WHITELIST_CHAT_IDS`

## Bot Commands

| Command | Description |
|---------|-------------|
| `/ask <question>` | Ask a question to the model ensemble |
| `/last` | Show the last run result |
| `/run <id>` | Show a specific run |
| `/raw <id>` | Show raw provider answers |
| `/conflicts <id>` | Show detected conflicts |
| `/dredd <provider:model>` | Set default dredd model |
| `/providers` | List enabled providers |
| `/config` | Show current settings |
| `/help` | Show help message |

## Configuration

### Environment Variables

```bash
# Required
TELEGRAM_BOT_TOKEN=your_token
WHITELIST_CHAT_IDS=123456789
DATABASE_URL=postgres://user:pass@localhost/llm_market_dev

# Provider API Keys (at least one required)
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=...

# Optional
DEFAULT_DREDD=openai:gpt-4o
FALLBACK_DREDD=anthropic:claude-sonnet-4-20250514
MAX_ROUNDS=5
PROVIDER_TIMEOUT_MS=25000
DEBUG_MODE=false
```

### Webhook Setup (Production)

For production, use webhooks instead of polling:

1. Set up a public URL (e.g., via ngrok for testing)
2. Set `WEBHOOK_URL` environment variable
3. The bot will automatically register the webhook on startup

```bash
# For local development with ngrok
ngrok http 4000
export WEBHOOK_URL=https://your-ngrok-url.ngrok.io/webhook/telegram
```

## Architecture

```
lib/
├── llm_market/
│   ├── core/           # Business logic
│   │   ├── market.ex   # Main orchestration
│   │   ├── convergence.ex
│   │   ├── dredd.ex    # Arbiter logic
│   │   └── prompts.ex
│   ├── providers/      # LLM adapters
│   ├── orchestrator/   # OTP processes
│   ├── telegram/       # Bot interface
│   └── schemas/        # Ecto schemas
└── llm_market_web/     # Phoenix endpoints
```

## API Endpoints

- `GET /health` - Health check with provider status
- `GET /api/runs/:id` - Get run details
- `GET /api/runs/:id/replay` - Re-render a run

## Development

```bash
# Run tests
mix test

# Format code
mix format

# Start interactive console
iex -S mix
```

## License

MIT
