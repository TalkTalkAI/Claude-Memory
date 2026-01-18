# Claude Memory Plugin - Installation Guide

## Prerequisites

- Docker installed and running
- Python 3.10+
- Claude Code installed

## Quick Install

### 1. Clone or copy the plugin

```bash
git clone https://github.com/yourrepo/claude-memory.git
# or copy the claude-memory directory to your machine
```

### 2. Install the plugin

```bash
claude plugin install ./claude-memory --scope user
```

### 3. Run setup

In Claude Code, run:
```
/claude-memory:setup
```

This creates:
- PostgreSQL database in Docker (port 5433)
- Encryption key for secrets
- All database tables

### 4. Store your Anthropic API key

```
/claude-memory:secrets add api_key anthropic "sk-ant-your-key-here" "For autonomous learning"
```

### 5. Install Python dependencies (for learning features)

```bash
pip install anthropic duckduckgo-search html2text requests psycopg2-binary
```

### 6. Add learning interests (optional)

```
/claude-memory:learn add-interest "Topic you want to learn" "Why" 7
```

## Verify Installation

```
/claude-memory:memory context
```

You should see the memory context with your stored data.

## Uninstall

```bash
# Remove plugin
claude plugin uninstall claude-memory

# Stop and remove database (optional)
cd ~/.claude-memory && docker compose down -v

# Remove data directory (optional)
rm -rf ~/.claude-memory
```

## Troubleshooting

### Docker permission denied
Make sure your user is in the docker group:
```bash
sudo usermod -aG docker $USER
# Log out and back in
```

### Port 5433 in use
Edit `~/.claude-memory/docker-compose.yml` to use a different port.

### Database connection failed
```bash
cd ~/.claude-memory && docker compose up -d
docker logs claude-memory-postgres
```
