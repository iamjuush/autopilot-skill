#!/usr/bin/env zsh
#
# autopilot.sh - Continuous ticket processing loop
#
# Runs Claude Code with /autopilot in a loop. Each session:
#   1. Picks the next ready ticket (review feedback > brainstorm answers > todo)
#   2. Brainstorms / plans / implements / tests
#   3. Moves to In Review and exits
#   4. Script waits, then starts the next cycle
#
# All output is logged to logs/autopilot/<run-timestamp>/ for auditing.
#
# Log structure:
#   logs/autopilot/
#   └── 2026-02-04_00-14-03/       # one dir per run
#       ├── run.log                 # master log (header + cycle summaries)
#       ├── summary.json            # machine-readable metadata
#       ├── cycle-1.log             # raw Claude output per cycle
#       └── cycle-2.log
#
# Usage:
#   ./scripts/autopilot.sh              # auto-select tickets
#   ./scripts/autopilot.sh XXX-58       # target a specific ticket
#   ./scripts/autopilot.sh --pause 60   # wait 60s between cycles (default: 30)
#
# Stop: Ctrl+C (or close terminal)

set -euo pipefail

PAUSE_SECONDS=30
TICKET=""
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LOG_BASE="$PROJECT_DIR/logs/autopilot"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --pause)
      PAUSE_SECONDS="$2"
      shift 2
      ;;
    *-*)
      # Match any ticket pattern like LYN-123, PROJ-45, etc.
      TICKET="$1"
      shift
      ;;
    *)
      echo "Usage: $0 [TICKET-ID] [--pause SECONDS]"
      exit 1
      ;;
  esac
done

# Set up per-run log directory
RUN_TIMESTAMP="$(date '+%Y-%m-%d_%H-%M-%S')"
RUN_DIR="$LOG_BASE/$RUN_TIMESTAMP"
mkdir -p "$RUN_DIR"

MASTER_LOG="$RUN_DIR/run.log"
SUMMARY_JSON="$RUN_DIR/summary.json"

# Log to both file and stdout
log() {
  echo "$@" | tee -a "$MASTER_LOG"
}

# ISO 8601 timestamp
iso_now() {
  date '+%Y-%m-%dT%H:%M:%S'
}

# Epoch seconds for duration calc
epoch_now() {
  date '+%s'
}

# Initialize summary.json
RUN_START_ISO="$(iso_now)"
cat > "$SUMMARY_JSON" <<EOF
{
  "started": "$RUN_START_ISO",
  "ticket_arg": "${TICKET:-auto-select}",
  "pause_seconds": $PAUSE_SECONDS,
  "cycles": []
}
EOF

# Strip terminal junk from a log file (in-place)
# Removes: ANSI escape sequences, carriage returns, BEL chars,
# OSC sequences (title-setting), CSI sequences, and other control chars
clean_log() {
  local logfile="$1"
  local tmp="${logfile}.tmp"
  LC_ALL=C sed \
    -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
    -e 's/\x1b\][^\x07]*\x07//g' \
    -e 's/\x1b[()][0-9A-B]//g' \
    -e 's/\x1b[\>=]//g' \
    -e 's/\r//g' \
    -e 's/\x07//g' \
    -e '/^[[:space:]]*$/d' \
    "$logfile" > "$tmp"
  mv "$tmp" "$logfile"
}

# Extract ticket ID from cycle log output
# Looks for "Selected: XXX-123" pattern in the raw session output
extract_ticket() {
  local logfile="$1"
  local ticket
  ticket=$(grep -oE 'Selected: ([A-Z]+-[0-9]+)' "$logfile" \
    | head -1 \
    | sed 's/Selected: //' || true)
  echo "${ticket:-unknown}"
}

# Append a cycle entry to summary.json
# Usage: append_cycle <cycle_num> <start_iso> <end_iso> <duration_s> <exit_code> <log_file> <ticket>
append_cycle() {
  local num="$1" start="$2" end="$3" dur="$4" code="$5" logfile="$6" ticket="$7"
  local tmp="$SUMMARY_JSON.tmp"

  # Build the new cycle JSON entry
  local entry="{\"cycle\":$num,\"ticket\":\"$ticket\",\"started\":\"$start\",\"ended\":\"$end\",\"duration_s\":$dur,\"exit_code\":$code,\"log\":\"$logfile\"}"

  # Insert into the cycles array using simple sed
  if [[ $num -eq 1 ]]; then
    # First cycle: replace empty array
    sed "s|\"cycles\": \[\]|\"cycles\": [$entry]|" "$SUMMARY_JSON" > "$tmp"
  else
    # Subsequent cycles: append before closing bracket
    sed "s|}\]$|},${entry}]|" "$SUMMARY_JSON" > "$tmp"
  fi
  mv "$tmp" "$SUMMARY_JSON"
}

log "=========================================="
log "  Autopilot"
log "  Project:  $PROJECT_DIR"
log "  Ticket:   ${TICKET:-auto-select}"
log "  Pause:    ${PAUSE_SECONDS}s between cycles"
log "  Run dir:  $RUN_DIR"
log "  Stop:     Ctrl+C"
log "=========================================="

CYCLE=0

while true; do
  CYCLE=$((CYCLE + 1))
  CYCLE_LOG="$RUN_DIR/cycle-${CYCLE}.log"
  CYCLE_START_ISO="$(iso_now)"
  CYCLE_START_EPOCH="$(epoch_now)"

  log ""
  log "--- Cycle $CYCLE | $CYCLE_START_ISO ---"

  PROMPT="/autopilot ${TICKET}"

  # Run Claude Code from the project directory
  # All Claude output goes to cycle log AND stdout
  set +e
  claude --dangerously-skip-permissions -p "$PROMPT" 2>&1 | tee "$CYCLE_LOG"
  EXIT_CODE=${pipestatus[1]}
  set -e

  CYCLE_END_ISO="$(iso_now)"
  CYCLE_END_EPOCH="$(epoch_now)"
  DURATION=$((CYCLE_END_EPOCH - CYCLE_START_EPOCH))

  # Strip terminal control sequences from the log
  clean_log "$CYCLE_LOG"

  # Extract which ticket was worked on (from Claude's output or CLI arg)
  if [[ -n "$TICKET" ]]; then
    CYCLE_TICKET="$TICKET"
  else
    CYCLE_TICKET="$(extract_ticket "$CYCLE_LOG")"
  fi

  # Update summary.json
  append_cycle "$CYCLE" "$CYCLE_START_ISO" "$CYCLE_END_ISO" "$DURATION" "$EXIT_CODE" "cycle-${CYCLE}.log" "$CYCLE_TICKET"

  # Check if this cycle was idle, rate limited, or hit an auth error
  IDLE=false
  RATE_LIMITED=false
  AUTH_EXPIRED=false
  if grep -q 'AUTOPILOT_IDLE' "$CYCLE_LOG" 2>/dev/null; then
    IDLE=true
  fi
  if grep -qiE 'rate.?limit|429|too many requests|overloaded' "$CYCLE_LOG" 2>/dev/null; then
    RATE_LIMITED=true
  fi
  if grep -qiE 'authentication_error|OAuth token has expired|401.*authentication' "$CYCLE_LOG" 2>/dev/null; then
    AUTH_EXPIRED=true
  fi

  if [[ "$AUTH_EXPIRED" == "true" ]]; then
    log "AUTH  | $CYCLE_TICKET | exit=$EXIT_CODE | ${DURATION}s | cycle-${CYCLE}.log"
    log ""
    log "=========================================="
    log "  OAuth token expired. Stopping autopilot."
    log "  Re-authenticate with:  claude login"
    log "  Then restart autopilot."
    log "=========================================="
    exit 1
  elif [[ "$RATE_LIMITED" == "true" ]]; then
    log "RATE  | $CYCLE_TICKET | exit=$EXIT_CODE | ${DURATION}s | cycle-${CYCLE}.log"
  elif [[ $EXIT_CODE -ne 0 ]]; then
    log "FAIL  | $CYCLE_TICKET | exit=$EXIT_CODE | ${DURATION}s | cycle-${CYCLE}.log"
    log "Waiting ${PAUSE_SECONDS}s before retry..."
  elif [[ "$IDLE" == "true" ]]; then
    log "IDLE  | no tickets | exit=0 | ${DURATION}s | cycle-${CYCLE}.log"
  else
    log "OK    | $CYCLE_TICKET | exit=0 | ${DURATION}s | cycle-${CYCLE}.log"
  fi

  # If targeting a specific ticket, only run once (unless rate limited — retry)
  if [[ -n "$TICKET" && "$RATE_LIMITED" != "true" ]]; then
    log ""
    log "Single-ticket mode. Done."
    exit 0
  fi

  # Wait longer when idle or rate limited (1 hour), shorter otherwise (30s)
  if [[ "$IDLE" == "true" || "$RATE_LIMITED" == "true" ]]; then
    LONG_PAUSE=3600
    if [[ "$RATE_LIMITED" == "true" ]]; then
      log "Rate limited. Next cycle in ${LONG_PAUSE}s (1 hour)... (Ctrl+C to stop)"
    else
      log "Nothing to do. Next cycle in ${LONG_PAUSE}s (1 hour)... (Ctrl+C to stop)"
    fi
    sleep "$LONG_PAUSE"
  else
    log "Next cycle in ${PAUSE_SECONDS}s... (Ctrl+C to stop)"
    sleep "$PAUSE_SECONDS"
  fi
done
