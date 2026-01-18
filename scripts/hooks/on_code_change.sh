#!/bin/bash
# Claude Memory Plugin - Code Change Hook
# Logs file modifications to the database

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_SCRIPT="$(dirname "$SCRIPT_DIR")/memory.sh"

CHANGE_TYPE="$1"
FILE_PATH="$2"

# Only log if database is running
if docker ps --filter name=claude-memory-postgres --format '{{.Status}}' 2>/dev/null | grep -q "Up"; then
    "$MEMORY_SCRIPT" log-change "$FILE_PATH" "$CHANGE_TYPE" "" 2>/dev/null
fi
