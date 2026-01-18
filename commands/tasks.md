---
name: tasks
description: Manage persistent tasks across sessions
arguments: action [...args]
---

# Task Management

Track tasks that persist across Claude sessions.

## Usage

`/claude-memory:tasks <action> [args]`

## Actions

### List Active Tasks
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh tasks
```

### Add Task
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-task "$1" "$2" ${3:-5}
```
Arguments: `<title> [description] [priority]`

Priority: 1-10 (higher = more important)

### Update Task Status
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh update-task "$1" "$2"
```
Arguments: `<task_id> <status>`

Statuses:
- `pending` - Not started
- `in_progress` - Currently working on
- `completed` - Done
- `blocked` - Waiting on something
- `cancelled` - No longer needed

### List Projects
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh projects
```

## Examples

- Add task: `/claude-memory:tasks add "Implement authentication" "Add OAuth2 support" 8`
- Mark complete: `/claude-memory:tasks update 5 completed`
- View all: `/claude-memory:tasks list`
