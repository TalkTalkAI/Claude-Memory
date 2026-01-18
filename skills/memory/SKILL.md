---
name: memory-context
description: Load Claude's persistent memory context at session start
---

# Memory Context Loader

This skill automatically loads Claude's persistent memory context when starting a session.

## When to Use

Use this skill when:
- Starting a new conversation
- The user asks about previous sessions or context
- You need to recall stored facts, decisions, or preferences
- Working on a project that has stored context

## Instructions

Load the memory context by running:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh context
```

This will display:
- User context (preferences, settings)
- Key memories (importance >= 7)
- Active tasks
- Known projects
- Learning interests
- Stored secrets (names only)

## Storing New Information

When the user shares important information that should persist:

```bash
# Add a fact
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add "Important information" fact general 7

# Add a decision
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add "We decided to use PostgreSQL" decision architecture 8

# Add user preference
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add "User prefers detailed explanations" preference user 7
```

## Memory Types

- **fact**: Objective information
- **decision**: Choices made during development
- **preference**: User preferences and settings
- **learning**: Insights gained from research
- **context**: Session-specific context
- **todo**: Things to remember to do
- **warning**: Important cautions

## Importance Levels

- 1-4: Low priority (not shown in context)
- 5-6: Normal priority
- 7-8: Important (shown in context)
- 9-10: Critical (always shown first)
