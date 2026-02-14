#!/bin/bash
# ClawdHub hook - UserPromptSubmit event (user sent a message)
# Sets status to "running" - user sent a prompt, Claude is about to work

# Read JSON from stdin
INPUT=$(cat)

# Extract session ID
SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# Gather context
CWD=$(pwd)
TTY=$(tty 2>/dev/null | tr -d '\n' || echo "unknown")
[[ "$TTY" == "not a tty" || "$TTY" == *"not a tty"* || -z "$TTY" ]] && TTY="unknown"
TERM_PROGRAM="${TERM_PROGRAM:-unknown}"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Sessions file location
SESSIONS_FILE="$HOME/.clawdhub/sessions.json"
mkdir -p "$(dirname "$SESSIONS_FILE")"

# Create file if it doesn't exist
[ ! -f "$SESSIONS_FILE" ] && echo "[]" > "$SESSIONS_FILE"

# Update or add session with running status
/usr/bin/jq --arg sid "$SESSION_ID" \
   --arg cwd "$CWD" \
   --arg tty "$TTY" \
   --arg term "$TERM_PROGRAM" \
   --arg ts "$TIMESTAMP" \
   '
   if any(.[]; .session_id == $sid) then
     map(if .session_id == $sid then . + {status: "running", cwd: $cwd, tty: $tty, terminal: $term, updated_at: $ts} else . end)
   else
     . + [{session_id: $sid, status: "running", cwd: $cwd, tty: $tty, terminal: $term, started_at: $ts, updated_at: $ts}]
   end
   ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
