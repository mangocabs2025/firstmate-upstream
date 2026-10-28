#!/usr/bin/env bash
# Real-herdr end-to-end check: start an isolated lab herdr server through
# fm_backend_herdr_server_ensure from a launcher env polluted like a Claude tool
# shell, then report what the live server process and a fresh pane inherited.
# Usage: real-herdr-env-check.sh <firstmate-tree> <label>
set -u
TREE=$1; LABEL=$2
. "$TREE/bin/fm-herdr-lab.sh"
unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH HERDR_SESSION
S=$(fm_herdr_lab_name "$LABEL")
fm_herdr_lab_prepare "$S" || exit 1
trap 'fm_herdr_lab_teardown "$S" >/dev/null 2>&1 && echo "teardown: lab session $S removed, default-session tripwire unchanged"' EXIT
NAMES='CLAUDE_CODE_CHILD_SESSION|CLAUDE_CODE_SESSION_ID|CLAUDE_CODE_SESSION_ATTENDED|CLAUDE_CODE_BRIDGE_SESSION_ID|CLAUDECODE|FM_CREW_STATE_META_OVERRIDE|FM_CREW_STATE_STATUS_OVERRIDE|CLAUDE_CONFIG_DIR|FM_HERDR_SENTINEL'
echo "tree: $(git -C "$TREE" rev-parse --short HEAD 2>/dev/null || echo "$TREE") adapter sha1: $(sha1sum "$TREE/bin/backends/herdr.sh" | cut -c1-12)"
echo "lab session: $S"
echo "launcher env: CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=parent-session CLAUDE_CODE_SESSION_ATTENDED=1 CLAUDE_CODE_BRIDGE_SESSION_ID=session_parent CLAUDECODE=1 FM_CREW_STATE_META_OVERRIDE=/tmp/other-task.meta FM_CREW_STATE_STATUS_OVERRIDE=/tmp/other-task.status CLAUDE_CONFIG_DIR=/tmp/kept-claude-config FM_HERDR_SENTINEL=kept"
CLAUDE_CODE_CHILD_SESSION=1 CLAUDE_CODE_SESSION_ID=parent-session CLAUDE_CODE_SESSION_ATTENDED=1 \
CLAUDE_CODE_BRIDGE_SESSION_ID=session_parent CLAUDECODE=1 \
FM_CREW_STATE_META_OVERRIDE=/tmp/other-task.meta FM_CREW_STATE_STATUS_OVERRIDE=/tmp/other-task.status \
CLAUDE_CONFIG_DIR=/tmp/kept-claude-config FM_HERDR_SENTINEL=kept \
  bash -c '. "$0/bin/backends/herdr.sh"; fm_backend_herdr_server_ensure "$1"' "$TREE" "$S"
echo "server_ensure rc=$?"
pid=$(pgrep -f -- "herdr server --session $S\$" | head -1)
echo "--- live herdr server process (pid $pid) environment, filtered:"
tr '\0' '\n' < /proc/$pid/environ | grep -E "^($NAMES)=" | sort || true
for n in CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_BRIDGE_SESSION_ID FM_CREW_STATE_META_OVERRIDE FM_CREW_STATE_STATUS_OVERRIDE; do
  tr '\0' '\n' < /proc/$pid/environ | grep -q "^$n=" || echo "$n: <unset>"
done
ws=$(fm_herdr_lab_raw "$S" workspace create --label envcheck --no-focus)
pane=$(printf '%s' "$ws" | jq -r '.. | objects | .pane_id? // empty' | head -1)
fm_herdr_lab_raw "$S" pane wait-output "$pane" --regex '\$ *$' --timeout 10000 >/dev/null 2>&1 || sleep 2
fm_herdr_lab_raw "$S" pane run "$pane" "env | grep -E '^($NAMES)=' | sed 's/^/PANE_ENV /' | sort; echo PANE_ENV_""DONE" >/dev/null
fm_herdr_lab_raw "$S" pane wait-output "$pane" --regex '^PANE_ENV_DONE' --timeout 10000 >/dev/null 2>&1 || sleep 2
echo "--- new pane ($pane) shell environment, filtered:"
fm_herdr_lab_raw "$S" pane read "$pane" --source recent-unwrapped 2>/dev/null | grep '^PANE_ENV' || true
