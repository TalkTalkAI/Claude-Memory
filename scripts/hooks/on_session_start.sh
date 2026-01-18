#!/bin/bash
# Claude Memory Plugin - Session Start Hook
# Loads memory context at the beginning of each session

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_SCRIPT="$(dirname "$SCRIPT_DIR")/memory.sh"

# Check if database is running
if docker ps --filter name=claude-memory-postgres --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
    # Output context to stdout (will be shown to Claude)
    "$MEMORY_SCRIPT" context 2>/dev/null
else
    echo "Claude Memory: Database not running. Run /claude-memory:setup to initialize."
fi
