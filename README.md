# Claude Memory

**Persistent memory and autonomous learning system for Claude Code**

Give your Claude Code sessions persistent memory across conversations. Store facts, decisions, and learnings that survive session restarts. Securely manage API keys and secrets with AES-256 encryption. Enable autonomous learning where Claude researches topics of interest via web search.

## Features

- **Persistent Memory** - Store facts, decisions, preferences, and learnings across sessions
- **Encrypted Secrets** - Securely store API keys, passwords, and tokens (AES-256 via pgcrypto)
- **Autonomous Learning** - Claude explores topics via DuckDuckGo search and synthesizes insights
- **Task Tracking** - Manage tasks that persist across sessions
- **Code Change Logging** - Automatic tracking of file modifications via hooks

## Requirements

- Docker (for PostgreSQL database)
- Python 3.10+
- Claude Code CLI
- Anthropic API key (for autonomous learning feature)

## Installation

### From GitHub

```bash
git clone https://github.com/TalkTalkAI/Claude-Memory.git
claude plugin install ./Claude-Memory --scope user
```

### First-Time Setup

In Claude Code, run:
```
/claude-memory:setup
```

This creates:
- PostgreSQL database in Docker (port 5433)
- AES-256 encryption key
- All database tables

### Post-Setup

1. **Store your Anthropic API key** (required for autonomous learning):
   ```
   /claude-memory:secrets add api_key anthropic "sk-ant-xxx" "For learning"
   ```

2. **Install Python dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

## Quick Start

```bash
# View memory context
/claude-memory:memory context

# Add a memory
/claude-memory:memory add "User prefers TypeScript over JavaScript" preference user 8

# Search memories
/claude-memory:memory search "TypeScript"

# Store a secret
/claude-memory:secrets add api_key openai "sk-xxx" "OpenAI API key"

# Add learning interest
/claude-memory:learn add-interest "Rust async patterns" "Systems programming" 8

# Run learning session
/claude-memory:learn run
```

## Commands

| Command | Description |
|---------|-------------|
| `/claude-memory:setup` | First-time installation and database setup |
| `/claude-memory:memory` | Manage memories (add, search, list, context) |
| `/claude-memory:secrets` | Manage encrypted secrets (add, get, list) |
| `/claude-memory:learn` | Autonomous learning (interests, run, insights) |
| `/claude-memory:tasks` | Task management (add, update, list) |

## Memory Types

| Type | Purpose |
|------|---------|
| `fact` | Objective information |
| `decision` | Choices made during development |
| `preference` | User preferences |
| `learning` | Insights from research |
| `context` | Session-specific context |
| `todo` | Things to remember |
| `warning` | Important cautions |

## Importance Levels

- **1-4**: Low priority (not shown in context)
- **5-6**: Normal priority
- **7-8**: Important (shown in context)
- **9-10**: Critical (always shown first)

## Data Storage

All data stored in `~/.claude-memory/`:

```
~/.claude-memory/
├── config/
│   ├── db.env           # Database configuration
│   └── encryption.key   # AES-256 key (chmod 600)
├── logs/
│   └── learning.log     # Learning session logs
└── docker-compose.yml   # PostgreSQL container
```

## Autonomous Learning

The learning system allows Claude to:

1. **Track interests** - Topics you want Claude to learn about
2. **Research via web** - DuckDuckGo searches with content extraction
3. **Synthesize insights** - AI-powered reflection on findings
4. **Build knowledge** - Insights stored as searchable memories

### Scheduled Learning

For automatic learning sessions, add to crontab:
```bash
0 */6 * * * ~/.claude-memory/scripts/claude_learning_cron.py >> ~/.claude-memory/logs/learning.log 2>&1
```

## Security

- Encryption key at `~/.claude-memory/config/encryption.key` has chmod 600
- All secrets encrypted with AES-256 via PostgreSQL pgcrypto
- Database stores encrypted blobs - useless without the key
- Back up both database AND encryption key separately
- Never commit encryption key to version control

## Backup & Restore

```bash
# Backup database
docker exec claude-memory-postgres pg_dump -U claude claude_memory > backup.sql

# Backup encryption key (store separately!)
cp ~/.claude-memory/config/encryption.key ~/secure-backup/

# Restore database
docker exec -i claude-memory-postgres psql -U claude -d claude_memory < backup.sql
```

## Troubleshooting

### Database not running
```bash
cd ~/.claude-memory && docker compose up -d
```

### Check database logs
```bash
docker logs claude-memory-postgres
```

### Port 5433 in use
Edit `~/.claude-memory/docker-compose.yml` to use a different port.

### Docker permission denied
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

## Uninstall

```bash
# Remove plugin
claude plugin uninstall claude-memory

# Stop and remove database
cd ~/.claude-memory && docker compose down -v

# Remove data directory
rm -rf ~/.claude-memory
```

## License

MIT

## Contributing

Contributions welcome! Please open an issue or submit a pull request.
