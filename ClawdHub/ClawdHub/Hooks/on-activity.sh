#!/bin/bash
# ClawdHub hook - PreToolUse event (agent is running)
# Extracts tool_name and derives activity summary

# Read JSON from stdin
INPUT=$(cat)

# Extract session ID
SESSION_ID=$(echo "$INPUT" | /usr/bin/jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

# Extract tool name
TOOL_NAME=$(echo "$INPUT" | /usr/bin/jq -r '.tool_name // empty')

# Derive activity summary based on tool type
ACTIVITY=""
case "$TOOL_NAME" in
    Bash)
        ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.command // empty' | head -c 60 | head -1)
        ;;
    Read|Edit|Write)
        ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.file_path // empty' | xargs basename 2>/dev/null)
        ;;
    Grep)
        ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.pattern // empty' | head -c 40)
        ;;
    Glob)
        ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.pattern // empty' | head -c 40)
        ;;
    Task)
        ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.description // empty' | head -c 40)
        ;;
    WebFetch|WebSearch)
        ACTIVITY=$(echo "$INPUT" | /usr/bin/jq -r '.tool_input.url // .tool_input.query // empty' | head -c 40)
        ;;
    *)
        ACTIVITY=""
        ;;
esac

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

# Update or add session with running status, tool_name, and activity
/usr/bin/jq --arg sid "$SESSION_ID" \
   --arg cwd "$CWD" \
   --arg tty "$TTY" \
   --arg term "$TERM_PROGRAM" \
   --arg ts "$TIMESTAMP" \
   --arg tool "$TOOL_NAME" \
   --arg act "$ACTIVITY" \
   '
   if any(.[]; .session_id == $sid) then
     map(if .session_id == $sid then . + {status: "running", cwd: $cwd, tty: $tty, terminal: $term, updated_at: $ts, tool_name: $tool, activity: $act, notification_message: null} else . end)
   else
     . + [{session_id: $sid, status: "running", cwd: $cwd, tty: $tty, terminal: $term, started_at: $ts, updated_at: $ts, tool_name: $tool, activity: $act}]
   end
   ' "$SESSIONS_FILE" > "$SESSIONS_FILE.tmp" && mv "$SESSIONS_FILE.tmp" "$SESSIONS_FILE"
