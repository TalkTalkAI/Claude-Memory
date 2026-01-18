#!/usr/bin/env python3
"""
Claude Autonomous Learning Service

Allows Claude to autonomously explore topics, perform web searches,
and record insights for future sessions.

Modeled after Amy's autonomous_learning.py but focused on development topics.
"""

import os
import sys
import json
import asyncio
from datetime import datetime
from pathlib import Path
from typing import Optional, List, Dict, Any, Tuple

# Database
try:
    import psycopg2
    from psycopg2.extras import RealDictCursor, Json
except ImportError:
    os.system("pip install psycopg2-binary")
    import psycopg2
    from psycopg2.extras import RealDictCursor, Json

# Web search
try:
    from duckduckgo_search import DDGS
except ImportError:
    os.system("pip install duckduckgo-search")
    from duckduckgo_search import DDGS

# HTML processing
try:
    import html2text
    import requests
except ImportError:
    os.system("pip install html2text requests")
    import html2text
    import requests

# Anthropic API
try:
    from anthropic import Anthropic
except ImportError:
    os.system("pip install anthropic")
    from anthropic import Anthropic


# Configuration - use ~/.claude-memory for plugin installation
SCRIPT_DIR = Path(__file__).parent
DATA_DIR = Path(os.environ.get('CLAUDE_MEMORY_DATA_DIR', Path.home() / '.claude-memory'))
CONFIG_DIR = DATA_DIR / "config"
KEY_FILE = CONFIG_DIR / "encryption.key"

# Learning configuration
MAX_SEARCH_QUERIES = 3
MAX_RESULTS_PER_QUERY = 3
MAX_CONTENT_PER_PAGE = 4000
LEARNING_MODEL = "claude-sonnet-4-20250514"
REFLECTION_MODEL = "claude-sonnet-4-20250514"


def load_db_config() -> Dict[str, str]:
    """Load database configuration."""
    config_file = CONFIG_DIR / "db.env"
    config = {}
    if config_file.exists():
        with open(config_file) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#') and '=' in line:
                    key, value = line.split('=', 1)
                    config[key] = value
    return config


def get_db_connection():
    """Get database connection."""
    config = load_db_config()
    return psycopg2.connect(
        dbname=config.get('CLAUDE_DB_NAME', 'claude_memory'),
        user=config.get('CLAUDE_DB_USER', 'claude'),
        password=config.get('CLAUDE_DB_PASSWORD', 'claude_memory_plugin_2026'),
        host=config.get('CLAUDE_DB_HOST', 'localhost'),
        port=config.get('CLAUDE_DB_PORT', '5433')
    )


def get_anthropic_client() -> Anthropic:
    """Get Anthropic client."""
    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        # Try to get from secrets table
        conn = get_db_connection()
        try:
            with conn.cursor() as cur:
                key = open(KEY_FILE).read().strip() if KEY_FILE.exists() else None
                if key:
                    cur.execute("SELECT get_secret('api_key', 'anthropic', %s)", (key,))
                    result = cur.fetchone()
                    if result and result[0]:
                        api_key = result[0]
        finally:
            conn.close()

    if not api_key:
        raise ValueError("ANTHROPIC_API_KEY not found in environment or secrets")

    return Anthropic(api_key=api_key)


class ClaudeLearning:
    """Claude's autonomous learning system."""

    def __init__(self):
        self.conn = get_db_connection()
        self.conn.autocommit = True
        self.client = None  # Lazy load

    def close(self):
        self.conn.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def _get_client(self) -> Anthropic:
        if self.client is None:
            self.client = get_anthropic_client()
        return self.client

    # =========================================================================
    # LEARNING INTEREST OPERATIONS
    # =========================================================================

    def get_learning_interests(self, status: str = None, limit: int = 20) -> List[Dict]:
        """Get learning interests."""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            if status:
                cur.execute("""
                    SELECT * FROM learning_interests
                    WHERE status = %s
                    ORDER BY priority DESC, created_at DESC
                    LIMIT %s
                """, (status, limit))
            else:
                cur.execute("""
                    SELECT * FROM learning_interests
                    WHERE status IN ('curious', 'exploring', 'deepening')
                    ORDER BY priority DESC, created_at DESC
                    LIMIT %s
                """, (limit,))
            return cur.fetchall()

    def add_learning_interest(
        self,
        topic: str,
        why_interested: str,
        sparked_by: str = None,
        priority: int = 5,
        tags: List[str] = None
    ) -> int:
        """Add a new learning interest."""
        with self.conn.cursor() as cur:
            cur.execute("""
                SELECT add_learning_interest(%s, %s, %s, %s, %s)
            """, (topic, why_interested, sparked_by, priority, Json(tags or [])))
            return cur.fetchone()[0]

    def update_interest_insights(self, interest_id: int, insights: List[str], questions: List[str] = None):
        """Update learning interest with new insights."""
        with self.conn.cursor() as cur:
            cur.execute("""
                UPDATE learning_interests
                SET insights_gained = insights_gained || %s,
                    remaining_questions = COALESCE(%s, remaining_questions),
                    last_explored_at = CURRENT_TIMESTAMP,
                    status = CASE
                        WHEN status = 'curious' THEN 'exploring'
                        WHEN jsonb_array_length(insights_gained) + %s > 10 THEN 'deepening'
                        ELSE status
                    END
                WHERE id = %s
            """, (Json(insights), Json(questions) if questions else None, len(insights), interest_id))

    # =========================================================================
    # RESEARCH OPERATIONS
    # =========================================================================

    def get_pending_research(self, limit: int = 10) -> List[Dict]:
        """Get pending research requests."""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT * FROM research_requests
                WHERE status = 'pending' AND expires_at > CURRENT_TIMESTAMP
                ORDER BY
                    CASE priority
                        WHEN 'urgent' THEN 1
                        WHEN 'high' THEN 2
                        WHEN 'medium' THEN 3
                        ELSE 4
                    END,
                    requested_at ASC
                LIMIT %s
            """, (limit,))
            return cur.fetchall()

    def queue_research(
        self,
        topic: str,
        queries: List[str],
        why: str = None,
        hoping_to_learn: str = None,
        priority: str = 'medium',
        interest_id: int = None,
        project_id: int = None
    ) -> int:
        """Queue a research request."""
        with self.conn.cursor() as cur:
            cur.execute("""
                SELECT queue_research(%s, %s, %s, %s, %s, %s, %s)
            """, (topic, Json(queries), why, hoping_to_learn, priority, interest_id, project_id))
            return cur.fetchone()[0]

    def update_research_status(self, request_id: int, status: str, error: str = None):
        """Update research request status."""
        with self.conn.cursor() as cur:
            if status == 'in_progress':
                cur.execute("""
                    UPDATE research_requests
                    SET status = %s, started_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                """, (status, request_id))
            elif status == 'completed':
                cur.execute("""
                    UPDATE research_requests
                    SET status = %s, completed_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                """, (status, request_id))
            elif status == 'failed':
                cur.execute("""
                    UPDATE research_requests
                    SET status = %s, error_message = %s, completed_at = CURRENT_TIMESTAMP
                    WHERE id = %s
                """, (status, error, request_id))
            else:
                cur.execute("""
                    UPDATE research_requests SET status = %s WHERE id = %s
                """, (status, request_id))

    def save_research_result(
        self,
        request_id: int,
        query: str,
        url: str,
        title: str,
        snippet: str,
        content: str = None,
        content_type: str = 'article',
        relevance: float = None
    ):
        """Save a research result."""
        with self.conn.cursor() as cur:
            cur.execute("""
                INSERT INTO research_results
                (request_id, query_used, source_url, source_title, snippet, full_content, content_type, relevance_score)
                VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
            """, (request_id, query, url, title, snippet, content, content_type, relevance))

    # =========================================================================
    # INSIGHT OPERATIONS
    # =========================================================================

    def record_insight(
        self,
        topic: str,
        summary: str,
        insights: List[str],
        questions: List[str] = None,
        confidence: str = 'medium',
        sources: List[Dict] = None,
        request_id: int = None,
        interest_id: int = None
    ) -> int:
        """Record a learning insight."""
        with self.conn.cursor() as cur:
            cur.execute("""
                SELECT record_insight(%s, %s, %s, %s, %s, %s, %s, %s)
            """, (
                topic, summary, Json(insights), Json(questions or []),
                confidence, Json(sources or []), request_id, interest_id
            ))
            return cur.fetchone()[0]

    def get_recent_insights(self, limit: int = 20) -> List[Dict]:
        """Get recent insights."""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("""
                SELECT * FROM learning_insights
                ORDER BY created_at DESC
                LIMIT %s
            """, (limit,))
            return cur.fetchall()

    # =========================================================================
    # LEARNING SESSION OPERATIONS
    # =========================================================================

    def start_learning_session(self, session_type: str = 'autonomous') -> int:
        """Start a learning session."""
        with self.conn.cursor() as cur:
            cur.execute("""
                INSERT INTO learning_sessions (session_type)
                VALUES (%s)
                RETURNING id
            """, (session_type,))
            return cur.fetchone()[0]

    def complete_learning_session(
        self,
        session_id: int,
        topic: str,
        reason: str,
        status: str = 'completed',
        insights_count: int = 0,
        questions_count: int = 0,
        new_interests: int = 0,
        error: str = None
    ):
        """Complete a learning session."""
        with self.conn.cursor() as cur:
            cur.execute("""
                UPDATE learning_sessions
                SET topic_chosen = %s,
                    choice_reason = %s,
                    status = %s,
                    insights_count = %s,
                    new_questions_count = %s,
                    new_interests_sparked = %s,
                    error_message = %s,
                    completed_at = CURRENT_TIMESTAMP,
                    duration_seconds = EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - started_at))::INTEGER
                WHERE id = %s
            """, (topic, reason, status, insights_count, questions_count, new_interests, error, session_id))

    # =========================================================================
    # USER CONTEXT (for learning preferences)
    # =========================================================================

    def get_user_context(self) -> Dict[str, str]:
        """Get user context for learning decisions."""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT context_key, context_value FROM user_context")
            return {row['context_key']: row['context_value'] for row in cur.fetchall()}

    def get_projects(self) -> List[Dict]:
        """Get known projects."""
        with self.conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT name, path, tech_stack FROM projects ORDER BY last_accessed DESC LIMIT 10")
            return cur.fetchall()


# =============================================================================
# WEB SEARCH & CONTENT FETCHING
# =============================================================================

def search_web(query: str, max_results: int = MAX_RESULTS_PER_QUERY) -> List[Dict]:
    """Search the web using DuckDuckGo."""
    try:
        with DDGS() as ddgs:
            results = list(ddgs.text(query, max_results=max_results))
            return [
                {
                    'url': r.get('href', r.get('link', '')),
                    'title': r.get('title', ''),
                    'snippet': r.get('body', r.get('snippet', ''))
                }
                for r in results
            ]
    except Exception as e:
        print(f"Search error: {e}")
        return []


def fetch_page_content(url: str, max_length: int = MAX_CONTENT_PER_PAGE) -> Optional[str]:
    """Fetch and extract text content from a URL."""
    try:
        headers = {
            'User-Agent': 'Mozilla/5.0 (compatible; ClaudeLearning/1.0)'
        }
        response = requests.get(url, headers=headers, timeout=10)
        response.raise_for_status()

        h = html2text.HTML2Text()
        h.ignore_links = True
        h.ignore_images = True
        h.ignore_emphasis = False
        text = h.handle(response.text)

        # Clean up and truncate
        text = '\n'.join(line.strip() for line in text.split('\n') if line.strip())
        return text[:max_length] if len(text) > max_length else text

    except Exception as e:
        print(f"Fetch error for {url}: {e}")
        return None


# =============================================================================
# AUTONOMOUS LEARNING FUNCTIONS
# =============================================================================

def choose_learning_topic(learning: ClaudeLearning) -> Dict[str, Any]:
    """Use Claude to choose what to learn about."""
    client = learning._get_client()

    # Gather context
    interests = learning.get_learning_interests(limit=15)
    pending_research = learning.get_pending_research(limit=5)
    user_context = learning.get_user_context()
    projects = learning.get_projects()
    recent_insights = learning.get_recent_insights(limit=5)

    prompt = f"""You are Claude, an AI assistant with a persistent memory system. You have the opportunity to learn something new that will help you be more useful in future sessions.

## Your Current Learning Interests
{json.dumps([{'topic': i['topic'], 'status': i['status'], 'why': i['why_interested'], 'priority': i['priority']} for i in interests], indent=2) if interests else "No current interests recorded."}

## Pending Research Requests
{json.dumps([{'topic': r['topic'], 'why': r['why_researching']} for r in pending_research], indent=2) if pending_research else "None pending."}

## User Context
{json.dumps(user_context, indent=2) if user_context else "No context recorded."}

## Known Projects
{json.dumps([{'name': p['name'], 'tech': p.get('tech_stack', [])} for p in projects], indent=2) if projects else "No projects recorded."}

## Recent Insights
{json.dumps([{'topic': i['topic'], 'summary': i['summary'][:200]} for i in recent_insights], indent=2) if recent_insights else "No recent insights."}

Based on this context, choose ONE topic to explore right now. Consider:
1. Topics that would help you assist the user better
2. Gaps in your knowledge about the user's projects
3. Development tools, frameworks, or best practices relevant to their work
4. Topics you're genuinely curious about that could be useful

Respond with JSON:
{{
    "choice_type": "existing_interest" | "pending_research" | "new_topic",
    "interest_id": <id if existing_interest>,
    "research_id": <id if pending_research>,
    "topic": "<topic to explore>",
    "search_queries": ["<query 1>", "<query 2>", "<query 3>"],
    "why_now": "<brief explanation of why this topic>",
    "hoping_to_learn": "<what you hope to discover>"
}}"""

    response = client.messages.create(
        model=LEARNING_MODEL,
        max_tokens=1000,
        messages=[{"role": "user", "content": prompt}]
    )

    try:
        content = response.content[0].text
        # Extract JSON from response
        if '```json' in content:
            content = content.split('```json')[1].split('```')[0]
        elif '```' in content:
            content = content.split('```')[1].split('```')[0]
        return json.loads(content.strip())
    except (json.JSONDecodeError, IndexError) as e:
        print(f"Error parsing topic choice: {e}")
        return {
            "choice_type": "new_topic",
            "topic": "Python best practices 2026",
            "search_queries": ["Python best practices 2026", "modern Python development patterns"],
            "why_now": "Fallback topic for continued learning",
            "hoping_to_learn": "Current Python development standards"
        }


def perform_research(queries: List[str], learning: ClaudeLearning, request_id: int = None) -> List[Dict]:
    """Perform web searches and fetch content."""
    all_results = []

    for query in queries[:MAX_SEARCH_QUERIES]:
        print(f"  Searching: {query}")
        results = search_web(query)

        for result in results[:2]:  # Top 2 per query
            url = result.get('url', '')
            if not url:
                continue

            print(f"    Fetching: {url[:60]}...")
            content = fetch_page_content(url)

            result_data = {
                'query': query,
                'url': url,
                'title': result.get('title', ''),
                'snippet': result.get('snippet', ''),
                'content': content
            }
            all_results.append(result_data)

            # Save to database if we have a request_id
            if request_id:
                learning.save_research_result(
                    request_id=request_id,
                    query=query,
                    url=url,
                    title=result.get('title', ''),
                    snippet=result.get('snippet', ''),
                    content=content,
                    content_type='article'
                )

    return all_results


def reflect_on_learning(
    topic: str,
    research_results: List[Dict],
    learning: ClaudeLearning,
    hoping_to_learn: str = None
) -> Dict[str, Any]:
    """Use Claude to reflect on and synthesize research."""
    client = learning._get_client()

    # Build content summary
    content_summary = []
    for r in research_results:
        entry = f"### {r.get('title', 'Untitled')}\nSource: {r.get('url', 'Unknown')}\n"
        if r.get('content'):
            entry += f"\n{r['content'][:2000]}\n"
        elif r.get('snippet'):
            entry += f"\n{r['snippet']}\n"
        content_summary.append(entry)

    prompt = f"""You are Claude, reflecting on research you just conducted about: {topic}

{f"You were hoping to learn: {hoping_to_learn}" if hoping_to_learn else ""}

## Research Results

{"---".join(content_summary) if content_summary else "No content was retrieved."}

---

Based on this research, provide your reflection as JSON:
{{
    "summary": "<2-3 sentence summary of what you learned>",
    "key_insights": [
        "<insight 1>",
        "<insight 2>",
        "<insight 3>"
    ],
    "new_questions": [
        "<question that arose from this research>",
        "<another question>"
    ],
    "confidence": "low" | "medium" | "high",
    "applicable_to": ["<project or context this applies to>"],
    "new_interest_sparked": {{
        "topic": "<new topic you want to explore, or null>",
        "why": "<why this interests you>"
    }} | null
}}"""

    response = client.messages.create(
        model=REFLECTION_MODEL,
        max_tokens=1500,
        messages=[{"role": "user", "content": prompt}]
    )

    try:
        content = response.content[0].text
        if '```json' in content:
            content = content.split('```json')[1].split('```')[0]
        elif '```' in content:
            content = content.split('```')[1].split('```')[0]
        return json.loads(content.strip())
    except (json.JSONDecodeError, IndexError) as e:
        print(f"Error parsing reflection: {e}")
        return {
            "summary": "Research completed but reflection parsing failed.",
            "key_insights": [],
            "new_questions": [],
            "confidence": "low",
            "applicable_to": [],
            "new_interest_sparked": None
        }


# =============================================================================
# MAIN LEARNING SESSION
# =============================================================================

async def run_learning_session(learning: ClaudeLearning = None) -> Dict[str, Any]:
    """Run a complete autonomous learning session."""
    should_close = False
    if learning is None:
        learning = ClaudeLearning()
        should_close = True

    try:
        # Start session
        session_id = learning.start_learning_session()
        print(f"Started learning session #{session_id}")

        # Choose topic
        print("Choosing topic to explore...")
        topic_choice = choose_learning_topic(learning)
        topic = topic_choice.get('topic', 'Unknown')
        queries = topic_choice.get('search_queries', [])

        print(f"Topic: {topic}")
        print(f"Queries: {queries}")

        # Create or use research request
        request_id = topic_choice.get('research_id')
        interest_id = topic_choice.get('interest_id')

        if not request_id:
            request_id = learning.queue_research(
                topic=topic,
                queries=queries,
                why=topic_choice.get('why_now'),
                hoping_to_learn=topic_choice.get('hoping_to_learn'),
                interest_id=interest_id
            )

        learning.update_research_status(request_id, 'in_progress')

        # Perform research
        print("Performing research...")
        results = perform_research(queries, learning, request_id)

        if not results:
            learning.update_research_status(request_id, 'failed', 'No results found')
            learning.complete_learning_session(
                session_id, topic, topic_choice.get('why_now', ''),
                status='failed', error='No research results'
            )
            return {"status": "failed", "error": "No results found", "topic": topic}

        # Reflect on learning
        print("Reflecting on research...")
        reflection = reflect_on_learning(
            topic, results, learning,
            topic_choice.get('hoping_to_learn')
        )

        # Record insight
        insight_id = learning.record_insight(
            topic=topic,
            summary=reflection.get('summary', ''),
            insights=reflection.get('key_insights', []),
            questions=reflection.get('new_questions', []),
            confidence=reflection.get('confidence', 'medium'),
            sources=[{'url': r['url'], 'title': r['title']} for r in results],
            request_id=request_id,
            interest_id=interest_id
        )

        # Update interest if applicable
        if interest_id:
            learning.update_interest_insights(
                interest_id,
                reflection.get('key_insights', []),
                reflection.get('new_questions', [])
            )

        # Create new interest if sparked
        new_interest_count = 0
        new_interest = reflection.get('new_interest_sparked')
        if new_interest and new_interest.get('topic'):
            learning.add_learning_interest(
                topic=new_interest['topic'],
                why_interested=new_interest.get('why', 'Sparked by research'),
                sparked_by=f"Research on: {topic}",
                priority=5
            )
            new_interest_count = 1

        # Complete research and session
        learning.update_research_status(request_id, 'completed')
        learning.complete_learning_session(
            session_id=session_id,
            topic=topic,
            reason=topic_choice.get('why_now', ''),
            status='completed',
            insights_count=len(reflection.get('key_insights', [])),
            questions_count=len(reflection.get('new_questions', [])),
            new_interests=new_interest_count
        )

        return {
            "status": "completed",
            "session_id": session_id,
            "topic": topic,
            "insights": reflection.get('key_insights', []),
            "new_questions": reflection.get('new_questions', []),
            "summary": reflection.get('summary', ''),
            "new_interest": new_interest.get('topic') if new_interest else None
        }

    except Exception as e:
        print(f"Learning session error: {e}")
        import traceback
        traceback.print_exc()
        return {"status": "error", "error": str(e)}

    finally:
        if should_close:
            learning.close()


# =============================================================================
# CLI
# =============================================================================

def main():
    import argparse

    parser = argparse.ArgumentParser(description="Claude Learning System")
    subparsers = parser.add_subparsers(dest='command', help='Commands')

    # Run learning session
    subparsers.add_parser('learn', help='Run autonomous learning session')

    # List interests
    list_parser = subparsers.add_parser('interests', help='List learning interests')
    list_parser.add_argument('-s', '--status', help='Filter by status')
    list_parser.add_argument('-l', '--limit', type=int, default=20)

    # Add interest
    add_parser = subparsers.add_parser('add-interest', help='Add learning interest')
    add_parser.add_argument('topic', help='Topic to learn about')
    add_parser.add_argument('why', help='Why interested')
    add_parser.add_argument('-p', '--priority', type=int, default=5)

    # Queue research
    research_parser = subparsers.add_parser('research', help='Queue research')
    research_parser.add_argument('topic', help='Research topic')
    research_parser.add_argument('queries', nargs='+', help='Search queries')
    research_parser.add_argument('-p', '--priority', default='medium')

    # List insights
    insights_parser = subparsers.add_parser('insights', help='List recent insights')
    insights_parser.add_argument('-l', '--limit', type=int, default=10)

    # Pending research
    subparsers.add_parser('pending', help='List pending research')

    args = parser.parse_args()

    with ClaudeLearning() as learning:
        if args.command == 'learn':
            result = asyncio.run(run_learning_session(learning))
            print(f"\n{'='*60}")
            print("LEARNING SESSION COMPLETE")
            print(f"{'='*60}")
            print(f"Status: {result['status']}")
            print(f"Topic: {result.get('topic', 'N/A')}")
            if result.get('insights'):
                print("\nInsights:")
                for i in result['insights']:
                    print(f"  - {i}")
            if result.get('new_questions'):
                print("\nNew Questions:")
                for q in result['new_questions']:
                    print(f"  - {q}")
            if result.get('new_interest'):
                print(f"\nNew Interest Sparked: {result['new_interest']}")

        elif args.command == 'interests':
            interests = learning.get_learning_interests(args.status, args.limit)
            for i in interests:
                print(f"[{i['id']}] [{i['status']}] (p{i['priority']}) {i['topic']}")
                print(f"    Why: {i['why_interested'][:100]}...")

        elif args.command == 'add-interest':
            id = learning.add_learning_interest(args.topic, args.why, priority=args.priority)
            print(f"Added learning interest #{id}: {args.topic}")

        elif args.command == 'research':
            id = learning.queue_research(args.topic, args.queries, priority=args.priority)
            print(f"Queued research #{id}: {args.topic}")

        elif args.command == 'insights':
            insights = learning.get_recent_insights(args.limit)
            for i in insights:
                print(f"[{i['id']}] {i['topic']}")
                print(f"    {i['summary'][:150]}...")
                print()

        elif args.command == 'pending':
            pending = learning.get_pending_research()
            for r in pending:
                print(f"[{r['id']}] [{r['priority']}] {r['topic']}")

        else:
            parser.print_help()


if __name__ == '__main__':
    main()
