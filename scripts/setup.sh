#!/bin/bash
# Claude Memory Plugin - Setup Script
# Creates database, encryption key, and initializes the system

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
DATA_DIR="${CLAUDE_MEMORY_DATA_DIR:-$HOME/.claude-memory}"
CONFIG_DIR="$DATA_DIR/config"
LOG_DIR="$DATA_DIR/logs"

echo "=============================================="
echo "  Claude Memory System Setup"
echo "=============================================="
echo ""
echo "Data directory: $DATA_DIR"
echo ""

# Create directories
echo "Creating directories..."
mkdir -p "$CONFIG_DIR" "$LOG_DIR"

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not in PATH"
    echo "Please install Docker and try again"
    exit 1
fi

# Check if docker daemon is running
if ! docker info &> /dev/null; then
    echo "ERROR: Docker daemon is not running"
    echo "Please start Docker and try again"
    exit 1
fi

# Generate encryption key if not exists
KEY_FILE="$CONFIG_DIR/encryption.key"
if [ ! -f "$KEY_FILE" ]; then
    echo "Generating encryption key..."
    openssl rand -base64 32 > "$KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "  Created: $KEY_FILE"
else
    echo "  Encryption key already exists"
fi

# Create database config
DB_CONFIG="$CONFIG_DIR/db.env"
if [ ! -f "$DB_CONFIG" ]; then
    echo "Creating database configuration..."
    cat > "$DB_CONFIG" << 'EOF'
CLAUDE_DB_NAME=claude_memory
CLAUDE_DB_USER=claude
CLAUDE_DB_PASSWORD=claude_memory_plugin_2026
CLAUDE_DB_HOST=localhost
CLAUDE_DB_PORT=5433
EOF
    echo "  Created: $DB_CONFIG"
else
    echo "  Database config already exists"
fi

# Create docker-compose.yml
COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    echo "Creating Docker Compose file..."
    cat > "$COMPOSE_FILE" << 'EOF'
version: '3.8'
services:
  claude-memory-postgres:
    image: postgres:15
    container_name: claude-memory-postgres
    environment:
      POSTGRES_USER: claude
      POSTGRES_PASSWORD: claude_memory_plugin_2026
      POSTGRES_DB: claude_memory
    volumes:
      - claude_memory_data:/var/lib/postgresql/data
    ports:
      - "5433:5432"
    restart: unless-stopped
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U claude -d claude_memory"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  claude_memory_data:
EOF
    echo "  Created: $COMPOSE_FILE"
fi

# Start PostgreSQL container
echo ""
echo "Starting PostgreSQL container..."
cd "$DATA_DIR"
docker compose up -d

# Wait for database to be ready
echo "Waiting for database to be ready..."
for i in {1..30}; do
    if docker exec claude-memory-postgres pg_isready -U claude -d claude_memory &> /dev/null; then
        echo "  Database is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Database did not become ready in time"
        exit 1
    fi
    sleep 1
done

# Run migrations
echo ""
echo "Running database migrations..."
docker exec -i claude-memory-postgres psql -U claude -d claude_memory < "$PLUGIN_DIR/migrations/001_initial.sql"
echo "  Applied: 001_initial.sql"
docker exec -i claude-memory-postgres psql -U claude -d claude_memory < "$PLUGIN_DIR/migrations/002_learning_system.sql"
echo "  Applied: 002_learning_system.sql"

# Create symlink to plugin scripts (for easier access)
SCRIPTS_LINK="$DATA_DIR/scripts"
if [ ! -L "$SCRIPTS_LINK" ]; then
    ln -sf "$PLUGIN_DIR/scripts" "$SCRIPTS_LINK"
fi

echo ""
echo "=============================================="
echo "  Setup Complete!"
echo "=============================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Store your Anthropic API key (for autonomous learning):"
echo "   $PLUGIN_DIR/scripts/memory.sh add-secret api_key anthropic \"sk-ant-xxx\""
echo ""
echo "2. Add some learning interests:"
echo "   $PLUGIN_DIR/scripts/memory.sh add-interest \"Topic\" \"Why interested\" 7"
echo ""
echo "3. Test the system:"
echo "   $PLUGIN_DIR/scripts/memory.sh context"
echo ""
echo "4. (Optional) Install Python dependencies for learning:"
echo "   pip install anthropic duckduckgo-search html2text requests"
echo ""
echo "Data stored in: $DATA_DIR"
echo ""
