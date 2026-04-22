#!/bin/bash
# File: /usr/local/sbin/x2go-kill-suspended.sh
# Purpose: Terminate only suspended x2go sessions by session PID.
# Suspended sessions accumulate memory and can cause OOM kills or server crashes.
# Does NOT touch active running sessions even if same user has both.
# Also kills ghost processes of users with no active session.
# Created by Godfrey Padua

LOCKFILE=/var/run/x2go-kill-suspended.lock
TIMEOUT=60  # seconds before any x2go command is force-killed

echo "===== [$(date)] X2Go suspended session cleanup started ====="

# ---------------------------------------------------------------
# LOCK — Prevent overlapping runs
# ---------------------------------------------------------------
if [ -e "$LOCKFILE" ]; then
    LOCK_PID=$(cat "$LOCKFILE")
    if kill -0 "$LOCK_PID" 2>/dev/null; then
        echo "[$(date)] Previous run (PID $LOCK_PID) still active. Aborting."
        exit 0
    else
        echo "[$(date)] Stale lockfile found. Removing."
        rm -f "$LOCKFILE"
    fi
fi
echo $$ > "$LOCKFILE"
trap "rm -f $LOCKFILE" EXIT

# ---------------------------------------------------------------
# PART 1 — Kill suspended sessions by specific session PID
# ---------------------------------------------------------------
SESSION_LIST=$(timeout $TIMEOUT sudo x2golistsessions_root 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$SESSION_LIST" ]; then
    echo "[$(date)] WARNING: x2golistsessions_root timed out or returned empty. Skipping Part 1."
else
    echo "$SESSION_LIST" | awk -F'|' '$5 == "S" {print $1"|"$2"|"$12"|"$13}' | while IFS='|' read -r pid session_name username agent_pid; do

        echo "[$(date)] Terminating suspended session: $session_name (user: $username, PID: $pid, AgentPID: $agent_pid)"

        timeout $TIMEOUT sudo /usr/bin/x2goterminate-session "$session_name" && echo " - x2goterminate-session success"

        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            sudo kill -9 "$pid" && echo " - killed PID $pid"
        fi

        if [ -n "$agent_pid" ] && [ "$agent_pid" -gt 1000 ] 2>/dev/null && kill -0 "$agent_pid" 2>/dev/null; then
            sudo kill -9 "$agent_pid" && echo " - killed AgentPID $agent_pid"
        fi

    done
fi

# ---------------------------------------------------------------
# PART 2 — Kill ghost processes (no active session but still has processes)
# ---------------------------------------------------------------
echo "[$(date)] Checking for ghost processes..."

ACTIVE_USERS=$(echo "$SESSION_LIST" | awk -F'|' '$5=="R"||$5=="S" {print $12}' | sort -u)
ALL_PROCESS_USERS=$(ps aux | awk 'NR>1 {print $1}' | sort -u | grep -v "^root$" | grep -v "^godfrey$" | grep -v "^gdm$" | grep -v "^nobody$" | grep -v "^systemd" | grep -v "^www-data$" | grep -v "^syslog$" | grep -v "^messagebus$")

for user in $ALL_PROCESS_USERS; do
    if id "$user" 2>/dev/null | grep -q x2gousers; then
        if ! echo "$ACTIVE_USERS" | grep -q "^${user}$"; then
            echo "[$(date)] Ghost processes found for $user — killing"
            sudo pkill -9 -u "$user" && echo " - killed ghost processes for $user"
        fi
    fi
done

# PART 3 — Clean up x2go session database
# Kill any previously stuck x2gocleansessions before running a new one
STUCK=$(pgrep -f x2gocleansessions)
if [ -n "$STUCK" ]; then
    echo "[$(date)] Killing stuck x2gocleansessions PIDs: $STUCK"
    sudo pkill -f x2gocleansessions
    sleep 2
fi

timeout $TIMEOUT sudo /usr/sbin/x2gocleansessions && \
    echo "[$(date)] x2gocleansessions done" || \
    echo "[$(date)] WARNING: x2gocleansessions timed out or failed"

echo "===== [$(date)] Cleanup finished ====="
