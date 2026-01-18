---
name: autonomous-learning
description: Manage Claude's autonomous learning interests and research
---

# Autonomous Learning System

This skill helps Claude explore topics of interest through web research and synthesize insights.

## When to Use

Use this skill when:
- Claude encounters a topic it's curious about
- The user asks Claude to research something
- Working on projects that could benefit from updated knowledge
- Claude wants to proactively learn about relevant technologies

## Adding Learning Interests

When Claude becomes curious about a topic during conversation:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-interest "Topic name" "Why interested in this" 7
```

Good candidates for learning interests:
- Technologies used in user's projects
- Best practices for frameworks being used
- Security considerations for current work
- Performance optimization techniques
- New features in languages/tools

## Running a Learning Session

To explore a topic now:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh learn
```

This will:
1. Select a topic from interests or pending research
2. Generate search queries
3. Search the web via DuckDuckGo
4. Fetch and analyze top results
5. Generate insights and new questions
6. Store learnings in the database

## Viewing Learning Status

```bash
# View current interests
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh interests

# View recent insights
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh insights

# View full learning context
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh learning-context
```

## Interest Statuses

- **curious**: Initial state, hasn't been explored yet
- **exploring**: Currently researching
- **deepening**: Has insights, going deeper
- **integrated**: Knowledge fully absorbed
- **paused**: Temporarily stopped exploring

## Requirements

- Anthropic API key stored as secret:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-secret api_key anthropic "sk-ant-xxx"
  ```
- Python dependencies installed:
  ```bash
  pip install anthropic duckduckgo-search html2text requests
  ```

## Scheduled Learning

For autonomous learning on a schedule, add to crontab:
```bash
0 */6 * * * ${CLAUDE_PLUGIN_ROOT}/scripts/claude_learning_cron.py >> ~/.claude-memory/logs/learning.log 2>&1
```
