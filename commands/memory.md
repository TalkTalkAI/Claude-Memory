---
name: memory
description: Manage Claude's persistent memory (add, search, list memories)
arguments: action [...args]
---

# Claude Memory Management

Manage persistent memories that survive across sessions.

## Usage

`/claude-memory:memory <action> [args]`

## Actions

### View Context
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh context
```
Shows full session context including memories, tasks, projects, and learning interests.

### Add Memory
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add "$1" ${2:-fact} ${3:-general} ${4:-5}
```
Arguments: `<content> [type] [category] [importance]`

Types: fact, decision, preference, learning, context, todo, warning
Categories: user, project, system, code, architecture, api, security, general
Importance: 1-10 (7+ shown in context)

### Search Memories
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh search "$1" ${2:-20}
```
Arguments: `<query> [limit]`

### List Memories
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh list ${1:-20} $2
```
Arguments: `[limit] [type]`

### Set User Context
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh set-context "$1" "$2"
```
Arguments: `<key> <value>`

## Examples

- Add a fact: `/claude-memory:memory add "User prefers tabs over spaces" preference user 8`
- Search: `/claude-memory:memory search "database" 10`
- View all: `/claude-memory:memory context`
