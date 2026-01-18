# Claude Memory Plugin

Persistent memory and autonomous learning system for Claude Code.

## Features

- **Persistent Memory**: Store facts, decisions, learnings, and preferences across sessions
- **Encrypted Secrets**: Securely store API keys, passwords, and tokens (AES-256)
- **Autonomous Learning**: Claude can explore topics of interest via web research
- **Task Tracking**: Manage tasks that persist across sessions
- **Code Change Logging**: Automatic tracking of file modifications

## Installation

### From Local Directory

```bash
claude plugin install ./claude-memory --scope user
```

### From GitHub (when published)

```bash
claude plugin install claude-memory@your-marketplace
```

## Setup

After installing the plugin, run the setup command:

```
/claude-memory:setup
```

This will:
1. Create a PostgreSQL database in Docker (port 5433)
2. Generate an AES-256 encryption key
3. Initialize all database tables
4. Configure the system

### Prerequisites

- Docker installed and running
- Python 3.10+ with pip
- For autonomous learning: Anthropic API key

### Post-Setup

1. **Store your Anthropic API key** (required for autonomous learning):
   ```
   /claude-memory:secrets add api_key anthropic "sk-ant-xxx" "For learning"
   ```

2. **Install Python dependencies** (for learning features):
   ```bash
   pip install anthropic duckduckgo-search html2text requests
   ```

3. **Add learning interests**:
   ```
   /claude-memory:learn add-interest "FastAPI patterns" "Help with API development" 7
   ```

## Usage

### Slash Commands

| Command | Description |
|---------|-------------|
| `/claude-memory:setup` | First-time installation |
| `/claude-memory:memory` | Manage memories (add, search, list) |
| `/claude-memory:secrets` | Manage encrypted secrets |
| `/claude-memory:learn` | Autonomous learning operations |
| `/claude-memory:tasks` | Task management |

### Memory Operations

```bash
# View full context
/claude-memory:memory context

# Add a memory
/claude-memory:memory add "User prefers TypeScript" preference user 8

# Search memories
/claude-memory:memory search "database"

# List recent memories
/claude-memory:memory list 20
```

### Secret Management

```bash
# Store API key
/claude-memory:secrets add api_key openai "sk-xxx" "OpenAI key"

# Retrieve secret
/claude-memory:secrets get api_key openai

# List secrets (names only)
/claude-memory:secrets list
```

### Learning System

```bash
# Add interest
/claude-memory:learn add-interest "Rust async" "Systems programming" 8

# Run learning session
/claude-memory:learn run

# View insights
/claude-memory:learn insights

# View interests
/claude-memory:learn interests
```

### Task Management

```bash
# Add task
/claude-memory:tasks add "Implement auth" "Add OAuth2 support" 8

# Update task
/claude-memory:tasks update 5 completed

# List tasks
/claude-memory:tasks list
```

## Data Storage

All data is stored in `~/.claude-memory/`:

```
~/.claude-memory/
├── config/
│   ├── db.env           # Database configuration
│   └── encryption.key   # AES-256 key (chmod 600)
├── logs/
│   └── learning.log     # Learning session logs
└── docker-compose.yml   # PostgreSQL container config
```

## Database Tables

| Table | Purpose |
|-------|---------|
| memories | Facts, decisions, learnings, preferences |
| secrets | Encrypted API keys, passwords, tokens |
| tasks | Ongoing and completed tasks |
| projects | Known codebases |
| learning_interests | Topics to explore |
| research_requests | Queued web searches |
| learning_insights | Synthesized knowledge |

## Memory Types

- `fact` - Objective information
- `decision` - Choices made during development
- `preference` - User preferences
- `learning` - Insights from research
- `context` - Session-specific context
- `todo` - Things to remember
- `warning` - Important cautions

## Importance Levels

- **1-4**: Low priority (not shown in context)
- **5-6**: Normal priority
- **7-8**: Important (shown in context)
- **9-10**: Critical (always shown first)

## Scheduled Learning

For autonomous learning on a schedule, add to crontab:

```bash
0 */6 * * * ~/.claude-memory/scripts/claude_learning_cron.py >> ~/.claude-memory/logs/learning.log 2>&1
```

## Security Notes

1. Encryption key at `~/.claude-memory/config/encryption.key` has chmod 600
2. All secrets encrypted with AES-256 via pgcrypto
3. Database stores encrypted blobs - useless without the key
4. Back up both database AND encryption key separately
5. Never commit encryption key to version control

## Backup

```bash
# Backup database
docker exec claude-memory-postgres pg_dump -U claude claude_memory > backup.sql

# Backup encryption key (store separately!)
cp ~/.claude-memory/config/encryption.key ~/secure-backup/

# Restore
docker exec -i claude-memory-postgres psql -U claude -d claude_memory < backup.sql
```

## Troubleshooting

### Database not running
```bash
cd ~/.claude-memory && docker compose up -d
```

### Check status
```bash
~/.claude-memory/scripts/memory.sh status
```

### View logs
```bash
docker logs claude-memory-postgres
```

## License

MIT
