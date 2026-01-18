---
name: setup
description: Set up the Claude Memory system (first-time installation)
arguments: none
---

# Claude Memory System Setup

Run this command to set up the persistent memory and learning system.

## What This Does

1. Creates a PostgreSQL database in Docker (port 5433)
2. Generates an AES-256 encryption key for secrets
3. Creates all required database tables
4. Configures the memory CLI

## Prerequisites

- Docker must be installed and running
- Python 3.10+ with pip
- User must have permission to run Docker commands

## Setup Instructions

Execute the setup script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/setup.sh
```

After setup completes:

1. Store your Anthropic API key (required for autonomous learning):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-secret api_key anthropic "sk-ant-your-key"
   ```

2. Add initial learning interests:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-interest "Topic" "Why interested" 7
   ```

3. Test with:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh context
   ```

## Troubleshooting

- If Docker fails, ensure Docker daemon is running
- If database connection fails, check port 5433 is available
- Run `docker logs claude-memory-postgres` to see database logs
