#!/bin/bash
# ClawdHub hook - Stop event (Claude finished responding)
# Sets status to "idle" - Claude is done, waiting for next user prompt
# Preserves tool_name and activity as last activity

# Read JSON from stdin
INPUT=$(cat)

# Extract session ID
SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# Gather context
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Sessions file location
SESSIONS_FILE="$HOME/.clawdhub/sessions.json"

# Only update if file exists
[ ! -f "$SESSIONS_FILE" ] && exit 0

# Update session status to idle, keep existing tool_name/activity, clear notification_message
/usr/bin/jq --arg sid "$SESSION_ID" \
   --arg ts "$TIMESTAMP" \
   '
   map(if .session_id == $sid then . + {status: "idle", updated_at: $ts, notification_message: null} else . end)
   ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
