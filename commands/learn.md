---
name: learn
description: Run autonomous learning session or manage learning interests
arguments: action [...args]
---

# Claude Autonomous Learning

Let Claude explore topics of interest via web search and synthesize insights.

## Usage

`/claude-memory:learn <action> [args]`

## Actions

### Run Learning Session
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh learn
```
Claude will:
1. Choose a topic from interests or spark a new one
2. Search the web with relevant queries
3. Fetch and analyze content
4. Reflect and generate insights
5. Store learnings in the database

### List Learning Interests
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh interests ${1:-20}
```

### Add Learning Interest
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-interest "$1" "$2" ${3:-5}
```
Arguments: `<topic> <why_interested> [priority]`

Priority: 1-10 (higher = more likely to be explored)

### View Recent Insights
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh insights ${1:-10}
```

### View Learning Context
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh learning-context
```

### View Pending Research
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh pending-research
```

## Interest Statuses

- **curious**: Initial state, wants to learn
- **exploring**: Actively researching
- **deepening**: Has insights, going deeper
- **integrated**: Knowledge absorbed
- **paused**: Temporarily stopped

## Examples

- Add interest: `/claude-memory:learn add-interest "Rust async patterns" "Help with systems programming" 8`
- Run session: `/claude-memory:learn run`
- View insights: `/claude-memory:learn insights 5`

## Requirements

- Anthropic API key must be stored: `/claude-memory:secrets add api_key anthropic "sk-ant-xxx"`
- Python dependencies: `pip install anthropic duckduckgo-search html2text requests`
