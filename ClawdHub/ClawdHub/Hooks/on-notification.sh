#!/bin/bash
# ClawdHub hook - notification event
# Only sets waiting_input for actionable notification types
# Extracts notification message for display

# Read JSON from stdin
INPUT=$(cat)

# Extract session ID and notification type
SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

NOTIFICATION_TYPE=$(echo "$INPUT" | /usr/bin/jq -r '.notification_type // empty')

# Only set waiting_input for actionable notification types
case "$NOTIFICATION_TYPE" in
    permission_prompt|elicitation_dialog)
        # These need user attention
        ;;
    *)
        # Other notification types (auth_success, etc.) - no state change
        exit 0
        ;;
esac

# Extract notification message
NOTIFICATION_MSG=$(echo "$INPUT" | /usr/bin/jq -r '.message // empty')
[ -z "$NOTIFICATION_MSG" ] && NOTIFICATION_MSG="Needs attention"

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

# Update or add session with waiting_input status and notification message
/usr/bin/jq --arg sid "$SESSION_ID" \
   --arg cwd "$CWD" \
   --arg tty "$TTY" \
   --arg term "$TERM_PROGRAM" \
   --arg ts "$TIMESTAMP" \
   --arg msg "$NOTIFICATION_MSG" \
   '
   if any(.[]; .session_id == $sid) then
     map(if .session_id == $sid then . + {status: "waiting_input", cwd: $cwd, tty: $tty, terminal: $term, updated_at: $ts, notification_message: $msg} else . end)
   else
     . + [{session_id: $sid, status: "waiting_input", cwd: $cwd, tty: $tty, terminal: $term, started_at: $ts, updated_at: $ts, notification_message: $msg}]
   end
   ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
