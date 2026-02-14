#!/bin/bash
# ClawdHub hook - SessionEnd event (session terminated)
# Removes session from JSON immediately

# Read JSON from stdin
INPUT=$(cat)

# Extract session ID
SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# Sessions file location
SESSIONS_FILE="$HOME/.clawdhub/sessions.json"

# Only update if file exists
[ ! -f "$SESSIONS_FILE" ] && exit 0

# Remove session from the array
/usr/bin/jq --arg sid "$SESSION_ID" \
   'map(select(.session_id != $sid))' \
   "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
