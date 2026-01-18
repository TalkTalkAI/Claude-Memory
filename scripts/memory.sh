#!/bin/bash
# Claude Memory Plugin - CLI Interface
# Portable version that uses ~/.claude-memory for data

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DATA_DIR="${CLAUDE_MEMORY_DATA_DIR:-$HOME/.claude-memory}"
CONFIG_DIR="$DATA_DIR/config"
KEY_FILE="$CONFIG_DIR/encryption.key"

# Load database config
load_config() {
    if [ -f "$CONFIG_DIR/db.env" ]; then
        source "$CONFIG_DIR/db.env"
    else
        CLAUDE_DB_NAME="claude_memory"
        CLAUDE_DB_USER="claude"
        CLAUDE_DB_PASSWORD="claude_memory_plugin_2026"
        CLAUDE_DB_HOST="localhost"
        CLAUDE_DB_PORT="5433"
    fi
}

load_config

get_key() {
    if [ -f "$KEY_FILE" ]; then
        cat "$KEY_FILE"
    else
        echo "ERROR: Encryption key not found at $KEY_FILE" >&2
        echo "Run setup first: $SCRIPT_DIR/setup.sh" >&2
        exit 1
    fi
}

db_query() {
    docker exec claude-memory-postgres psql -U "$CLAUDE_DB_USER" -d "$CLAUDE_DB_NAME" -t -A -c "$1"
}

db_query_formatted() {
    docker exec claude-memory-postgres psql -U "$CLAUDE_DB_USER" -d "$CLAUDE_DB_NAME" -c "$1"
}

escape_sql() {
    echo "$1" | sed "s/'/''/g"
}

get_context() {
    echo "==========================================="
    echo "       CLAUDE MEMORY CONTEXT"
    echo "==========================================="
    echo ""
    echo "=== USER CONTEXT ==="
    db_query "SELECT context_key || ': ' || context_value FROM user_context ORDER BY last_updated DESC;"
    echo ""
    echo "=== KEY MEMORIES ==="
    db_query "SELECT '[' || memory_type || '/' || COALESCE(category, 'general') || '] ' || content FROM memories WHERE is_active = TRUE AND importance >= 7 AND is_encrypted = FALSE ORDER BY importance DESC LIMIT 50;"
    echo ""
    echo "=== ACTIVE TASKS ==="
    db_query "SELECT '- [' || status || '] ' || title FROM tasks WHERE status IN ('pending', 'in_progress') ORDER BY priority DESC LIMIT 20;"
    echo ""
    echo "=== PROJECTS ==="
    db_query "SELECT name || ' - ' || path FROM projects ORDER BY last_accessed DESC;"
    echo ""
    echo "=== LEARNING INTERESTS ==="
    db_query "SELECT '[' || status || '] (p' || priority || ') ' || topic FROM learning_interests WHERE status IN ('curious', 'exploring') ORDER BY priority DESC LIMIT 10;"
    echo ""
    echo "=== SECRETS (names only) ==="
    db_query "SELECT '[' || secret_type || '] ' || name FROM secrets WHERE is_active = TRUE ORDER BY secret_type, name;"
}

case "$1" in
    context)
        get_context
        ;;
    list)
        db_query_formatted "SELECT id, memory_type, category, importance, LEFT(content, 80) as content FROM memories WHERE is_active = TRUE ORDER BY created_at DESC LIMIT ${2:-20};"
        ;;
    search)
        query=$(escape_sql "$2")
        db_query_formatted "SELECT id, memory_type, importance, LEFT(content, 80) FROM memories WHERE is_active = TRUE AND content ILIKE '%$query%' ORDER BY importance DESC LIMIT ${3:-20};"
        ;;
    add)
        content=$(escape_sql "$2")
        type="${3:-fact}"
        category="${4:-general}"
        importance="${5:-5}"
        id=$(db_query "INSERT INTO memories (memory_type, category, content, importance) VALUES ('$type', '$category', '$content', $importance) RETURNING id;")
        echo "Added memory #$id"
        ;;
    add-secret)
        type="$2"
        name=$(escape_sql "$3")
        value=$(escape_sql "$4")
        desc=$(escape_sql "${5:-}")
        key=$(get_key)
        id=$(db_query "SELECT add_secret('$type', '$name', '$value', '$key', '$desc');")
        echo "Added secret #$id: [$type] $name"
        ;;
    get-secret)
        type="$2"
        name="$3"
        key=$(get_key)
        db_query "SELECT get_secret('$type', '$name', '$key');"
        ;;
    secrets)
        if [ -n "$2" ]; then
            db_query_formatted "SELECT * FROM list_secrets('$2');"
        else
            db_query_formatted "SELECT * FROM list_secrets();"
        fi
        ;;
    projects)
        db_query_formatted "SELECT id, name, path FROM projects ORDER BY last_accessed DESC;"
        ;;
    tasks)
        db_query_formatted "SELECT id, status, priority, title FROM tasks WHERE status IN ('pending', 'in_progress') ORDER BY priority DESC;"
        ;;
    add-task)
        title=$(escape_sql "$2")
        desc=$(escape_sql "${3:-}")
        priority="${4:-5}"
        id=$(db_query "INSERT INTO tasks (title, description, priority) VALUES ('$title', '$desc', $priority) RETURNING id;")
        echo "Added task #$id"
        ;;
    update-task)
        task_id="$2"
        status="$3"
        if [ "$status" = "completed" ]; then
            db_query "UPDATE tasks SET status = '$status', completed_at = CURRENT_TIMESTAMP WHERE id = $task_id;"
        else
            db_query "UPDATE tasks SET status = '$status' WHERE id = $task_id;"
        fi
        echo "Updated task #$task_id to $status"
        ;;
    set-context)
        ctx_key=$(escape_sql "$2")
        value=$(escape_sql "$3")
        db_query "INSERT INTO user_context (context_key, context_value) VALUES ('$ctx_key', '$value') ON CONFLICT (context_key) DO UPDATE SET context_value = EXCLUDED.context_value, last_updated = CURRENT_TIMESTAMP;"
        echo "Set context: $ctx_key"
        ;;
    learn)
        python3 "$SCRIPT_DIR/claude_learning.py" learn
        ;;
    interests)
        db_query_formatted "SELECT id, status, priority, topic, LEFT(why_interested, 60) as why FROM learning_interests WHERE status IN ('curious', 'exploring', 'deepening') ORDER BY priority DESC LIMIT ${2:-20};"
        ;;
    add-interest)
        topic=$(escape_sql "$2")
        why=$(escape_sql "$3")
        priority="${4:-5}"
        id=$(db_query "SELECT add_learning_interest('$topic', '$why', NULL, $priority, '[]'::jsonb);")
        echo "Added learning interest #$id: $2"
        ;;
    insights)
        db_query_formatted "SELECT id, topic, LEFT(summary, 80) as summary, confidence_level, created_at FROM learning_insights ORDER BY created_at DESC LIMIT ${2:-10};"
        ;;
    pending-research)
        db_query_formatted "SELECT id, priority, topic, requested_at FROM research_requests WHERE status = 'pending' ORDER BY requested_at;"
        ;;
    learning-context)
        echo "=== LEARNING INTERESTS ==="
        db_query "SELECT '[' || status || '] (p' || priority || ') ' || topic FROM learning_interests WHERE status IN ('curious', 'exploring') ORDER BY priority DESC LIMIT 10;"
        echo ""
        echo "=== PENDING RESEARCH ==="
        db_query "SELECT '[' || priority || '] ' || topic FROM research_requests WHERE status = 'pending' LIMIT 10;"
        echo ""
        echo "=== RECENT INSIGHTS ==="
        db_query "SELECT topic || ': ' || LEFT(summary, 100) FROM learning_insights ORDER BY created_at DESC LIMIT 5;"
        ;;
    log-change)
        file_path=$(escape_sql "$2")
        change_type="$3"
        description=$(escape_sql "${4:-}")
        db_query "INSERT INTO code_changes (file_path, change_type, description) VALUES ('$file_path', '$change_type', '$description');"
        ;;
    query)
        db_query_formatted "$2"
        ;;
    status)
        echo "Claude Memory System Status"
        echo ""
        if docker ps --filter name=claude-memory-postgres --format '{{.Status}}' | grep -q "Up"; then
            echo "Database: Running"
            echo "Container: claude-memory-postgres"
            mem_count=$(db_query "SELECT COUNT(*) FROM memories WHERE is_active = TRUE;")
            secret_count=$(db_query "SELECT COUNT(*) FROM secrets WHERE is_active = TRUE;")
            interest_count=$(db_query "SELECT COUNT(*) FROM learning_interests WHERE status IN ('curious', 'exploring');")
            echo "Memories: $mem_count"
            echo "Secrets: $secret_count"
            echo "Active interests: $interest_count"
        else
            echo "Database: Not running"
            echo "Run: cd $DATA_DIR && docker compose up -d"
        fi
        echo ""
        echo "Data directory: $DATA_DIR"
        ;;
    *)
        echo "Claude Memory System (Plugin Edition)"
        echo ""
        echo "Usage: $0 <command> [args]"
        echo ""
        echo "CONTEXT & MEMORIES:"
        echo "  context                     - Show full session context"
        echo "  list [limit]                - List memories"
        echo "  search <query> [limit]      - Search memories"
        echo "  add <content> [type] [cat] [importance]"
        echo "  status                      - Show system status"
        echo ""
        echo "SECRETS (encrypted):"
        echo "  add-secret <type> <name> <value> [desc]"
        echo "  get-secret <type> <name>"
        echo "  secrets [type]"
        echo "  Types: password, api_key, certificate, token, credential"
        echo ""
        echo "TASKS & PROJECTS:"
        echo "  projects                    - List projects"
        echo "  tasks                       - List active tasks"
        echo "  add-task <title> [desc] [priority]"
        echo "  update-task <id> <status>"
        echo ""
        echo "LEARNING:"
        echo "  learn                       - Run autonomous learning"
        echo "  interests [limit]           - List learning interests"
        echo "  add-interest <topic> <why> [priority]"
        echo "  insights [limit]            - Recent insights"
        echo "  pending-research            - View research queue"
        echo "  learning-context            - Learning summary"
        echo ""
        echo "OTHER:"
        echo "  set-context <key> <value>"
        echo "  log-change <file> <type> [desc]"
        echo "  query <sql>"
        echo ""
        echo "Data directory: $DATA_DIR"
        ;;
esac
