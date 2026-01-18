---
name: secrets
description: Manage encrypted secrets (API keys, passwords, tokens)
arguments: action [...args]
---

# Encrypted Secrets Management

Store and retrieve sensitive data with AES-256 encryption.

## Usage

`/claude-memory:secrets <action> [args]`

## Actions

### Add Secret
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh add-secret "$1" "$2" "$3" "$4"
```
Arguments: `<type> <name> <value> [description]`

Types:
- `password` - Login credentials
- `api_key` - API keys and tokens
- `certificate` - SSL/TLS certificates
- `token` - OAuth/JWT tokens
- `credential` - Other credentials

### Get Secret (Decrypted)
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh get-secret "$1" "$2"
```
Arguments: `<type> <name>`

### List Secrets (Names Only)
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/memory.sh secrets $1
```
Arguments: `[type]` - Filter by type

## Examples

- Store API key: `/claude-memory:secrets add api_key openai "sk-xxx" "OpenAI production"`
- Store password: `/claude-memory:secrets add password db_admin "secretpass" "Database admin"`
- Retrieve: `/claude-memory:secrets get api_key openai`
- List all: `/claude-memory:secrets list`
- List by type: `/claude-memory:secrets list api_key`

## Security Notes

1. All secrets are encrypted with AES-256 (pgcrypto)
2. Encryption key stored at `~/.claude-memory/encryption.key` (chmod 600)
3. Database stores encrypted blobs - useless without the key
4. Never commit the encryption key to version control
5. Back up both database AND encryption key separately
