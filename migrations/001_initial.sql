-- Claude Memory System - Initial Schema
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- User context (key-value store)
CREATE TABLE IF NOT EXISTS user_context (
    id SERIAL PRIMARY KEY,
    context_key VARCHAR(100) UNIQUE NOT NULL,
    context_value TEXT NOT NULL,
    last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Projects
CREATE TABLE IF NOT EXISTS projects (
    id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL,
    path VARCHAR(500) UNIQUE NOT NULL,
    description TEXT,
    tech_stack JSONB DEFAULT '[]'::jsonb,
    last_accessed TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
    id SERIAL PRIMARY KEY,
    session_id VARCHAR(100) UNIQUE,
    working_directory VARCHAR(500),
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP,
    is_active BOOLEAN DEFAULT TRUE,
    summary TEXT
);

-- Memories
CREATE TABLE IF NOT EXISTS memories (
    id SERIAL PRIMARY KEY,
    memory_type VARCHAR(50) NOT NULL DEFAULT 'fact',
    category VARCHAR(50) DEFAULT 'general',
    content TEXT NOT NULL,
    content_encrypted BYTEA,
    is_encrypted BOOLEAN DEFAULT FALSE,
    importance INTEGER DEFAULT 5 CHECK (importance >= 1 AND importance <= 10),
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Secrets (always encrypted)
CREATE TABLE IF NOT EXISTS secrets (
    id SERIAL PRIMARY KEY,
    secret_type VARCHAR(50) NOT NULL,
    name VARCHAR(200) NOT NULL,
    encrypted_value BYTEA NOT NULL,
    description TEXT,
    tags JSONB DEFAULT '[]'::jsonb,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    UNIQUE(secret_type, name)
);

-- Encrypted preferences
CREATE TABLE IF NOT EXISTS encrypted_preferences (
    id SERIAL PRIMARY KEY,
    category VARCHAR(100) NOT NULL,
    preference_key VARCHAR(200) NOT NULL,
    encrypted_value BYTEA NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(category, preference_key)
);

-- Tasks
CREATE TABLE IF NOT EXISTS tasks (
    id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    description TEXT,
    status VARCHAR(50) DEFAULT 'pending',
    priority INTEGER DEFAULT 5,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    parent_task_id INTEGER REFERENCES tasks(id) ON DELETE SET NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

-- Code changes
CREATE TABLE IF NOT EXISTS code_changes (
    id SERIAL PRIMARY KEY,
    session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    file_path VARCHAR(500) NOT NULL,
    change_type VARCHAR(50) NOT NULL,
    description TEXT,
    before_snippet TEXT,
    after_snippet TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Conversations
CREATE TABLE IF NOT EXISTS conversations (
    id SERIAL PRIMARY KEY,
    session_id INTEGER REFERENCES sessions(id) ON DELETE CASCADE,
    role VARCHAR(20) NOT NULL,
    content TEXT NOT NULL,
    is_important BOOLEAN DEFAULT FALSE,
    tags TEXT[],
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Entities
CREATE TABLE IF NOT EXISTS entities (
    id SERIAL PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    name VARCHAR(200) NOT NULL,
    description TEXT,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(entity_type, name)
);

-- Relationships
CREATE TABLE IF NOT EXISTS relationships (
    id SERIAL PRIMARY KEY,
    entity1_id INTEGER REFERENCES entities(id) ON DELETE CASCADE,
    entity2_id INTEGER REFERENCES entities(id) ON DELETE CASCADE,
    relationship_type VARCHAR(100) NOT NULL,
    metadata JSONB DEFAULT '{}'::jsonb,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_memories_type ON memories(memory_type);
CREATE INDEX IF NOT EXISTS idx_memories_importance ON memories(importance DESC);
CREATE INDEX IF NOT EXISTS idx_memories_active ON memories(is_active);
CREATE INDEX IF NOT EXISTS idx_tasks_status ON tasks(status);
CREATE INDEX IF NOT EXISTS idx_code_changes_file ON code_changes(file_path);
CREATE INDEX IF NOT EXISTS idx_secrets_type ON secrets(secret_type);
CREATE INDEX IF NOT EXISTS idx_memories_content_fts ON memories USING gin(to_tsvector('english', content));

-- Helper function: Add encrypted memory
CREATE OR REPLACE FUNCTION add_encrypted_memory(
    p_type VARCHAR(50),
    p_category VARCHAR(50),
    p_content TEXT,
    p_key TEXT,
    p_importance INTEGER DEFAULT 5
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO memories (memory_type, category, content, content_encrypted, is_encrypted, importance)
    VALUES (p_type, p_category, '[ENCRYPTED]', pgp_sym_encrypt(p_content, p_key), TRUE, p_importance)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Get decrypted memory
CREATE OR REPLACE FUNCTION get_decrypted_memory(p_id INTEGER, p_key TEXT) RETURNS TEXT AS $$
DECLARE
    v_content TEXT;
    v_encrypted BYTEA;
    v_is_encrypted BOOLEAN;
BEGIN
    SELECT content, content_encrypted, is_encrypted INTO v_content, v_encrypted, v_is_encrypted
    FROM memories WHERE id = p_id;
    IF v_is_encrypted THEN
        RETURN pgp_sym_decrypt(v_encrypted, p_key);
    ELSE
        RETURN v_content;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Add secret
CREATE OR REPLACE FUNCTION add_secret(
    p_type VARCHAR(50),
    p_name VARCHAR(200),
    p_value TEXT,
    p_key TEXT,
    p_description TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO secrets (secret_type, name, encrypted_value, description)
    VALUES (p_type, p_name, pgp_sym_encrypt(p_value, p_key), p_description)
    ON CONFLICT (secret_type, name) DO UPDATE SET
        encrypted_value = pgp_sym_encrypt(p_value, p_key),
        description = COALESCE(p_description, secrets.description)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Get secret
CREATE OR REPLACE FUNCTION get_secret(p_type VARCHAR(50), p_name VARCHAR(200), p_key TEXT) RETURNS TEXT AS $$
BEGIN
    RETURN (
        SELECT pgp_sym_decrypt(encrypted_value, p_key)
        FROM secrets
        WHERE secret_type = p_type AND name = p_name AND is_active = TRUE
    );
END;
$$ LANGUAGE plpgsql;

-- Helper function: List secrets (no values)
CREATE OR REPLACE FUNCTION list_secrets(p_type VARCHAR(50) DEFAULT NULL)
RETURNS TABLE(id INTEGER, secret_type VARCHAR, name VARCHAR, description TEXT, tags JSONB, created_at TIMESTAMP, expires_at TIMESTAMP) AS $$
BEGIN
    IF p_type IS NULL THEN
        RETURN QUERY SELECT s.id, s.secret_type, s.name, s.description, s.tags, s.created_at, s.expires_at
        FROM secrets s WHERE s.is_active = TRUE ORDER BY s.secret_type, s.name;
    ELSE
        RETURN QUERY SELECT s.id, s.secret_type, s.name, s.description, s.tags, s.created_at, s.expires_at
        FROM secrets s WHERE s.secret_type = p_type AND s.is_active = TRUE ORDER BY s.name;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Set preference
CREATE OR REPLACE FUNCTION set_preference(
    p_category VARCHAR(100),
    p_key VARCHAR(200),
    p_value TEXT,
    p_encryption_key TEXT,
    p_description TEXT DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO encrypted_preferences (category, preference_key, encrypted_value, description)
    VALUES (p_category, p_key, pgp_sym_encrypt(p_value, p_encryption_key), p_description)
    ON CONFLICT (category, preference_key) DO UPDATE SET
        encrypted_value = pgp_sym_encrypt(p_value, p_encryption_key),
        description = COALESCE(p_description, encrypted_preferences.description),
        updated_at = CURRENT_TIMESTAMP
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Get preference
CREATE OR REPLACE FUNCTION get_preference(p_category VARCHAR(100), p_key VARCHAR(200), p_encryption_key TEXT) RETURNS TEXT AS $$
BEGIN
    RETURN (
        SELECT pgp_sym_decrypt(encrypted_value, p_encryption_key)
        FROM encrypted_preferences
        WHERE category = p_category AND preference_key = p_key
    );
END;
$$ LANGUAGE plpgsql;

-- Helper function: Start session
CREATE OR REPLACE FUNCTION start_session(p_session_id VARCHAR(100), p_working_dir VARCHAR(500) DEFAULT NULL) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO sessions (session_id, working_directory)
    VALUES (p_session_id, p_working_dir)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Search memories
CREATE OR REPLACE FUNCTION search_memories(
    p_query TEXT,
    p_type VARCHAR(50) DEFAULT NULL,
    p_category VARCHAR(50) DEFAULT NULL,
    p_limit INTEGER DEFAULT 20
) RETURNS TABLE(id INTEGER, memory_type VARCHAR, category VARCHAR, content TEXT, importance INTEGER, created_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id, m.memory_type, m.category,
           CASE WHEN m.is_encrypted THEN '[ENCRYPTED]' ELSE m.content END,
           m.importance, m.created_at
    FROM memories m
    WHERE m.is_active = TRUE
      AND (p_type IS NULL OR m.memory_type = p_type)
      AND (p_category IS NULL OR m.category = p_category)
      AND (m.content ILIKE '%' || p_query || '%' OR to_tsvector('english', m.content) @@ plainto_tsquery('english', p_query))
    ORDER BY m.importance DESC, m.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Get recent memories
CREATE OR REPLACE FUNCTION get_recent_memories(p_limit INTEGER DEFAULT 50, p_type VARCHAR(50) DEFAULT NULL)
RETURNS TABLE(id INTEGER, memory_type VARCHAR, category VARCHAR, content TEXT, importance INTEGER, created_at TIMESTAMP) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id, m.memory_type, m.category,
           CASE WHEN m.is_encrypted THEN '[ENCRYPTED]' ELSE m.content END,
           m.importance, m.created_at
    FROM memories m
    WHERE m.is_active = TRUE AND (p_type IS NULL OR m.memory_type = p_type)
    ORDER BY m.created_at DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Get session context
CREATE OR REPLACE FUNCTION get_session_context(p_memory_limit INTEGER DEFAULT 100) RETURNS TEXT AS $$
DECLARE
    v_context TEXT := '';
    v_row RECORD;
BEGIN
    v_context := v_context || '=== USER CONTEXT ===' || E'\n';
    FOR v_row IN SELECT context_key, context_value FROM user_context ORDER BY last_updated DESC LOOP
        v_context := v_context || v_row.context_key || ': ' || v_row.context_value || E'\n';
    END LOOP;

    v_context := v_context || E'\n=== KEY MEMORIES ===' || E'\n';
    FOR v_row IN SELECT memory_type, category, content FROM memories
                 WHERE is_active = TRUE AND importance >= 7 AND is_encrypted = FALSE
                 ORDER BY importance DESC, created_at DESC LIMIT p_memory_limit LOOP
        v_context := v_context || '[' || v_row.memory_type || '/' || COALESCE(v_row.category, 'general') || '] ' || v_row.content || E'\n';
    END LOOP;

    v_context := v_context || E'\n=== ACTIVE TASKS ===' || E'\n';
    FOR v_row IN SELECT status, title FROM tasks WHERE status IN ('pending', 'in_progress') ORDER BY priority DESC LIMIT 20 LOOP
        v_context := v_context || '- [' || v_row.status || '] ' || v_row.title || E'\n';
    END LOOP;

    v_context := v_context || E'\n=== PROJECTS ===' || E'\n';
    FOR v_row IN SELECT name, path FROM projects ORDER BY last_accessed DESC LOOP
        v_context := v_context || v_row.name || ' - ' || v_row.path || E'\n';
    END LOOP;

    RETURN v_context;
END;
$$ LANGUAGE plpgsql;
