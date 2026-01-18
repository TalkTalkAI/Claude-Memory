-- Claude Learning System Migration
-- Adds autonomous learning capabilities similar to Amy's system

-- Learning Interests: Topics Claude wants to explore
CREATE TABLE IF NOT EXISTS learning_interests (
    id SERIAL PRIMARY KEY,
    topic VARCHAR(200) NOT NULL,
    why_interested TEXT NOT NULL,
    current_understanding TEXT,
    questions JSONB DEFAULT '[]'::jsonb,
    status VARCHAR(50) DEFAULT 'curious',  -- curious, exploring, deepening, integrated, paused
    sparked_by TEXT,  -- what triggered this interest
    sparked_by_session_id INTEGER REFERENCES sessions(id) ON DELETE SET NULL,
    insights_gained JSONB DEFAULT '[]'::jsonb,
    remaining_questions JSONB DEFAULT '[]'::jsonb,
    learning_resources JSONB DEFAULT '[]'::jsonb,
    priority INTEGER DEFAULT 5,  -- 1-10
    tags JSONB DEFAULT '[]'::jsonb,
    last_explored_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Research Requests: Queued web searches
CREATE TABLE IF NOT EXISTS research_requests (
    id SERIAL PRIMARY KEY,
    topic VARCHAR(255) NOT NULL,
    search_queries JSONB DEFAULT '[]'::jsonb,
    why_researching TEXT,
    hoping_to_learn TEXT,
    priority VARCHAR(20) DEFAULT 'medium',  -- low, medium, high, urgent
    status VARCHAR(50) DEFAULT 'pending',  -- pending, in_progress, completed, failed, cancelled
    related_interest_id INTEGER REFERENCES learning_interests(id) ON DELETE SET NULL,
    related_project_id INTEGER REFERENCES projects(id) ON DELETE SET NULL,
    requested_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    expires_at TIMESTAMP DEFAULT (CURRENT_TIMESTAMP + INTERVAL '14 days'),
    error_message TEXT
);

-- Research Results: Outcomes of web searches
CREATE TABLE IF NOT EXISTS research_results (
    id SERIAL PRIMARY KEY,
    request_id INTEGER REFERENCES research_requests(id) ON DELETE CASCADE,
    query_used VARCHAR(500),
    source_url TEXT,
    source_title VARCHAR(500),
    snippet TEXT,
    full_content TEXT,
    content_type VARCHAR(50),  -- article, documentation, code, forum, video
    relevance_score FLOAT,
    fetched_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Learning Insights: Synthesized knowledge from research
CREATE TABLE IF NOT EXISTS learning_insights (
    id SERIAL PRIMARY KEY,
    request_id INTEGER REFERENCES research_requests(id) ON DELETE SET NULL,
    interest_id INTEGER REFERENCES learning_interests(id) ON DELETE SET NULL,
    topic VARCHAR(255) NOT NULL,
    summary TEXT NOT NULL,
    key_insights JSONB DEFAULT '[]'::jsonb,
    new_questions JSONB DEFAULT '[]'::jsonb,
    confidence_level VARCHAR(20),  -- low, medium, high
    sources_used JSONB DEFAULT '[]'::jsonb,
    applicable_to JSONB DEFAULT '[]'::jsonb,  -- projects, tasks, etc.
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Learning Sessions: Track autonomous learning runs
CREATE TABLE IF NOT EXISTS learning_sessions (
    id SERIAL PRIMARY KEY,
    session_type VARCHAR(50) DEFAULT 'autonomous',  -- autonomous, triggered, manual
    topic_chosen VARCHAR(255),
    choice_reason TEXT,
    status VARCHAR(50) DEFAULT 'started',  -- started, completed, failed, skipped
    insights_count INTEGER DEFAULT 0,
    new_questions_count INTEGER DEFAULT 0,
    new_interests_sparked INTEGER DEFAULT 0,
    duration_seconds INTEGER,
    error_message TEXT,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    completed_at TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_learning_interests_status ON learning_interests(status);
CREATE INDEX IF NOT EXISTS idx_learning_interests_priority ON learning_interests(priority DESC);
CREATE INDEX IF NOT EXISTS idx_learning_interests_tags ON learning_interests USING GIN(tags);
CREATE INDEX IF NOT EXISTS idx_research_requests_status ON research_requests(status);
CREATE INDEX IF NOT EXISTS idx_research_requests_priority ON research_requests(priority);
CREATE INDEX IF NOT EXISTS idx_research_results_request ON research_results(request_id);
CREATE INDEX IF NOT EXISTS idx_learning_insights_topic ON learning_insights(topic);
CREATE INDEX IF NOT EXISTS idx_learning_sessions_started ON learning_sessions(started_at DESC);

-- Update trigger for learning_interests
CREATE OR REPLACE FUNCTION update_learning_interest_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_update_learning_interest ON learning_interests;
CREATE TRIGGER trigger_update_learning_interest
    BEFORE UPDATE ON learning_interests
    FOR EACH ROW
    EXECUTE FUNCTION update_learning_interest_timestamp();

-- Helper function: Add a learning interest
CREATE OR REPLACE FUNCTION add_learning_interest(
    p_topic VARCHAR(200),
    p_why_interested TEXT,
    p_sparked_by TEXT DEFAULT NULL,
    p_priority INTEGER DEFAULT 5,
    p_tags JSONB DEFAULT '[]'::jsonb
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO learning_interests (topic, why_interested, sparked_by, priority, tags)
    VALUES (p_topic, p_why_interested, p_sparked_by, p_priority, p_tags)
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Queue a research request
CREATE OR REPLACE FUNCTION queue_research(
    p_topic VARCHAR(255),
    p_queries JSONB,
    p_why TEXT DEFAULT NULL,
    p_hoping TEXT DEFAULT NULL,
    p_priority VARCHAR(20) DEFAULT 'medium',
    p_interest_id INTEGER DEFAULT NULL,
    p_project_id INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
    v_pending_count INTEGER;
BEGIN
    -- Check queue limit (max 20 pending)
    SELECT COUNT(*) INTO v_pending_count
    FROM research_requests
    WHERE status = 'pending';

    IF v_pending_count >= 20 THEN
        RAISE EXCEPTION 'Research queue full (max 20 pending requests)';
    END IF;

    INSERT INTO research_requests (
        topic, search_queries, why_researching, hoping_to_learn,
        priority, related_interest_id, related_project_id
    ) VALUES (
        p_topic, p_queries, p_why, p_hoping,
        p_priority, p_interest_id, p_project_id
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- Helper function: Record learning insight
CREATE OR REPLACE FUNCTION record_insight(
    p_topic VARCHAR(255),
    p_summary TEXT,
    p_insights JSONB,
    p_questions JSONB DEFAULT '[]'::jsonb,
    p_confidence VARCHAR(20) DEFAULT 'medium',
    p_sources JSONB DEFAULT '[]'::jsonb,
    p_request_id INTEGER DEFAULT NULL,
    p_interest_id INTEGER DEFAULT NULL
) RETURNS INTEGER AS $$
DECLARE
    v_id INTEGER;
BEGIN
    INSERT INTO learning_insights (
        topic, summary, key_insights, new_questions,
        confidence_level, sources_used, request_id, interest_id
    ) VALUES (
        p_topic, p_summary, p_insights, p_questions,
        p_confidence, p_sources, p_request_id, p_interest_id
    )
    RETURNING id INTO v_id;
    RETURN v_id;
END;
$$ LANGUAGE plpgsql;

-- View: Learning context for sessions
CREATE OR REPLACE VIEW learning_context AS
SELECT
    'interest' as type,
    li.topic,
    li.status,
    li.priority,
    li.why_interested as description,
    li.last_explored_at as last_activity,
    jsonb_array_length(COALESCE(li.insights_gained, '[]'::jsonb)) as insight_count
FROM learning_interests li
WHERE li.status IN ('curious', 'exploring')
UNION ALL
SELECT
    'pending_research' as type,
    rr.topic,
    rr.status,
    CASE rr.priority
        WHEN 'urgent' THEN 10
        WHEN 'high' THEN 8
        WHEN 'medium' THEN 5
        ELSE 3
    END as priority,
    rr.why_researching as description,
    rr.requested_at as last_activity,
    0 as insight_count
FROM research_requests rr
WHERE rr.status = 'pending'
ORDER BY priority DESC, last_activity DESC;

-- Cleanup function for old data
CREATE OR REPLACE FUNCTION cleanup_learning_data(
    p_results_days INTEGER DEFAULT 90,
    p_sessions_days INTEGER DEFAULT 180
) RETURNS TABLE(results_deleted INTEGER, sessions_deleted INTEGER) AS $$
DECLARE
    v_results INTEGER;
    v_sessions INTEGER;
BEGIN
    -- Delete old research results
    DELETE FROM research_results
    WHERE fetched_at < CURRENT_TIMESTAMP - (p_results_days || ' days')::INTERVAL;
    GET DIAGNOSTICS v_results = ROW_COUNT;

    -- Delete old learning sessions
    DELETE FROM learning_sessions
    WHERE started_at < CURRENT_TIMESTAMP - (p_sessions_days || ' days')::INTERVAL;
    GET DIAGNOSTICS v_sessions = ROW_COUNT;

    RETURN QUERY SELECT v_results, v_sessions;
END;
$$ LANGUAGE plpgsql;

-- Grant permissions
GRANT ALL ON learning_interests TO claude;
GRANT ALL ON research_requests TO claude;
GRANT ALL ON research_results TO claude;
GRANT ALL ON learning_insights TO claude;
GRANT ALL ON learning_sessions TO claude;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO claude;
