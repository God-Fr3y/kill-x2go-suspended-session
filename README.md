# x2go-kill-suspended

A production-grade Bash script for automatically cleaning up suspended X2Go sessions, ghost processes, and stale session entries on multi-user Linux servers.

---

## Overview

On busy X2Go servers, suspended sessions accumulate silently — consuming memory, holding Wine/application processes open, and eventually triggering OOM kills or full server crashes. This script runs on a cron schedule and handles all three phases of cleanup safely and automatically.

**Key design goals:**

- ✅ Terminate *only* suspended sessions — never touch active ones
- ✅ Kill ghost processes left behind by users with no live session
- ✅ Clean the X2Go session database without causing cascading deadlocks
- ✅ Prevent overlapping cron runs via lockfile
- ✅ All commands wrapped with `timeout` to avoid hanging

---

## Features

| Feature | Details |
|---|---|
| **Lockfile guard** | Aborts if a previous run is still active; removes stale locks automatically |
| **Suspended session termination** | Uses `x2golistsessions_root` to identify `S` (suspended) state sessions and terminates by session name, PID, and agent PID |
| **Ghost process cleanup** | Detects `x2gousers` group members who have no active/suspended session but still hold processes |
| **Database cleanup** | Kills any stuck `x2gocleansessions` before running a fresh one |
| **Timeout safety** | Every X2Go command runs under `timeout 60` — no hanging allowed |
| **Cron-ready logging** | Output is timestamped; redirect to a log file for persistent history |

---

## Installation

### 1. Clone and copy the script

```bash
git clone https://github.com/God-Fr3y/kill-x2go-suspended-session.git && cd kill-x2go-suspended-session
sudo cp x2go-kill-suspended.sh /usr/local/sbin/x2go-kill-suspended.sh
sudo chmod 700 /usr/local/sbin/x2go-kill-suspended.sh
sudo chown root:root /usr/local/sbin/x2go-kill-suspended.sh
```

### 2. Create the log file

```bash
sudo touch /var/log/x2go-cleanup.log
sudo chmod 640 /var/log/x2go-cleanup.log
```

### 3. Add to root's crontab

```bash
sudo crontab -e
```

Add the following line to run cleanup every 30 minutes:

```cron
*/30 * * * * /usr/local/sbin/x2go-kill-suspended.sh >> /var/log/x2go-cleanup.log 2>&1
```

---

## How It Works

### Part 1 — Kill suspended sessions

Queries `x2golistsessions_root` and filters for sessions in state `S` (suspended). For each one:

1. Calls `x2goterminate-session` to cleanly terminate the session
2. Force-kills the session PID if still alive
3. Force-kills the agent PID if valid and still alive

Active sessions (`R` state) are never touched.

### Part 2 — Kill ghost processes

Compares the list of users with active/suspended sessions against all non-system users currently running processes. Any user who is a member of the `x2gousers` group but has no live session gets their processes killed with `pkill -9 -u`.

System and service accounts (`root`, `gdm`, `nobody`, `www-data`, `syslog`, etc.) are explicitly excluded.

### Part 3 — Clean X2Go session database

Kills any previously stuck `x2gocleansessions` process, waits briefly, then runs a fresh `x2gocleansessions` under timeout to purge stale database entries.

---

## Monitoring

Tail the log file to watch cleanup activity in real time:

```bash
tail -f /var/log/x2go-cleanup.log
```

Sample output:

```
===== [Wed Apr 22 10:30:01 PHT 2026] X2Go suspended session cleanup started =====
[Wed Apr 22 10:30:01 PHT 2026] Terminating suspended session: godfrey-52-1745123456 (user: godfrey, PID: 12345, AgentPID: 12350)
 - x2goterminate-session success
 - killed PID 12345
 - killed AgentPID 12350
[Wed Apr 22 10:30:02 PHT 2026] Checking for ghost processes...
[Wed Apr 22 10:30:04 PHT 2026] x2gocleansessions done
===== [Wed Apr 22 10:30:04 PHT 2026] Cleanup finished =====
```

### Log rotation (optional)

Create `/etc/logrotate.d/x2go-cleanup`:

```
/var/log/x2go-cleanup.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
}
```

---

## Requirements

- X2Go Server (`x2goserver` package)
- Bash 4+
- `sudo` access for the user running the script (or run as root via cron)
- Users managed with an `x2gousers` group for ghost detection

---

## Notes

- The script is safe to run while users are actively connected — it will not terminate running sessions.
- If `x2golistsessions_root` times out or returns empty, Part 1 is skipped with a warning rather than failing silently.
- Adjust `TIMEOUT` at the top of the script if your server's X2Go database is very large and commands need more time.

---

## Author

**Godfrey Padua** — IT Administrator
