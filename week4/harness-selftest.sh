#!/usr/bin/env bash
# ============================================================================
# Week-4 Capstone — BACKPRESSURE HARNESS SELF-TEST (red → green)
# ----------------------------------------------------------------------------
# Proves the standup bot's validation gates provide backpressure:
#   RED   : feed a bad run (STANDUP_FORCE_FAIL=output) → the Output Gate must
#           BLOCK it → execution status=error, Slack alert sent, NOTHING posted.
#   GREEN : clear the flag → a good run posts the standup, status=success.
#
# This script IS the "gate that runs on every change": run it after editing the
# workflow; a non-zero exit means the harness is broken. It asserts on the n8n
# execution record (not on log scraping), so it is CI-able.
#
# Prereqs:  stack built;  `docker exec -it claude-code-runner claude login` done;
#           .env filled (GitHub/Redmine/Slack/session).  Run it from anywhere.
# ============================================================================
set -uo pipefail

N8N=${N8N:-http://localhost:5678}
OWNER_EMAIL=${N8N_OWNER_EMAIL:-phongnt1@zigexn.vn}
OWNER_PASS=${N8N_OWNER_PASS:-Standup2026x}
WF1_NAME="Daily Standup Bot — Direction 1 (N8N → Claude)"
CK=/tmp/n8n.selftest.cookies
TMP=/tmp/standup-selftest; mkdir -p "$TMP"

# locate the docker-compose dir (works from repo root or from week4/)
SD="$(cd "$(dirname "$0")" && pwd)"
for c in \
  "$SD/n8n-nodes-claude-code-cli/docker/production/n8n-with-claude-code" \
  "$SD/../docker/production/n8n-with-claude-code" \
  "$SD/docker/production/n8n-with-claude-code"; do
  [ -f "$c/docker-compose.yml" ] && COMPOSE_DIR="$c" && break
done
: "${COMPOSE_DIR:?could not find the n8n compose dir; set COMPOSE_DIR=}"
ENV_FILE="$COMPOSE_DIR/.env"

green(){ printf '\033[32m✔ %s\033[0m\n' "$1"; }
red(){   printf '\033[31m✗ %s\033[0m\n' "$1"; }
die(){   red "$1"; exit 1; }

login(){ curl -s -c "$CK" -X POST "$N8N/rest/login" -H 'content-type: application/json' \
           -d "{\"emailOrLdapLoginId\":\"$OWNER_EMAIL\",\"password\":\"$OWNER_PASS\"}" -o /dev/null; }
wait_healthy(){ for i in $(seq 1 40); do [ "$(curl -s -o /dev/null -w '%{http_code}' "$N8N/healthz")" = 200 ] && return 0; sleep 2; done; return 1; }

# ---- flatted-execution parser (n8n stores execution data flattened) ---------
cat > "$TMP/parse.py" <<'PY'
import json, sys
w = json.load(open(sys.argv[1]))['data']
arr = json.loads(w['data'])
dr = lambda v: arr[int(v)] if isinstance(v, str) and v.isdigit() else v
def deep(v):
    v = dr(v)
    if isinstance(v, dict):  return {k: deep(x) for k, x in v.items()}
    if isinstance(v, list):  return [deep(x) for x in v]
    return v
rd = dr(arr[0]['resultData']); run = dr(rd['runData']); ran = list(run.keys())
def vnode(nm):
    if nm not in run: return None
    e = dr(dr(run[nm])[0]); m = dr(e['data']); m0 = dr(dr(m['main'])[0]); return deep(dr(m0[0])['json'])
vo = vnode('Validate Output') or {}
print("STATUS="    + str(w.get('status')))
print("NODES="     + str(len(w.get('workflowData', {}).get('nodes', []))))
print("POST_RAN="  + str('Post Standup' in ran))
print("HANDLE_RAN="+ str('Handle Error (Alert)' in ran))
print("STOP_RAN="  + str('Stop And Error' in ran))
print("VO_VALID="  + str(vo.get('valid')))
print("VO_ERR='"   + (("; ".join(vo.get('errors', [])) or "-").replace("'", "")) + "'")
PY

reload_env(){ # $1 = value for STANDUP_FORCE_FAIL ("" clears)
  ( grep -v '^STANDUP_FORCE_FAIL=' "$ENV_FILE" 2>/dev/null; echo "STANDUP_FORCE_FAIL=$1" ) > "$ENV_FILE.tmp" && mv "$ENV_FILE.tmp" "$ENV_FILE"
  ( cd "$COMPOSE_DIR" && docker compose up -d >/dev/null 2>&1 )
  wait_healthy || die "n8n did not become healthy after env reload"
}

ensure_active(){ # make sure WF1 is active (recreate can leave it off)
  # REST/active-workflows lag behind /healthz after a recreate — retry until
  # the workflow list actually CONTAINS WF1 (a transient empty list is valid JSON).
  WF1_ID=""; ACT=""
  for i in $(seq 1 20); do
    login
    curl -s -b "$CK" "$N8N/rest/workflows" -o "$TMP/wf.json"
    TMP="$TMP" WF1_NAME="$WF1_NAME" python3 - <<'PY' > "$TMP/wf1.meta" 2>/dev/null || true
import json, os
try:    d = json.load(open(os.environ['TMP'] + "/wf.json")).get('data', [])
except Exception: d = []
w = next((x for x in d if x.get('name') == os.environ['WF1_NAME']), None)
print((w or {}).get('id', '')); print((w or {}).get('active', ''))
PY
    WF1_ID=$(sed -n 1p "$TMP/wf1.meta"); ACT=$(sed -n 2p "$TMP/wf1.meta")
    [ -n "$WF1_ID" ] && break
    sleep 2
  done
  [ -n "$WF1_ID" ] || die "WF1 '$WF1_NAME' not found in n8n"
  if [ "$ACT" != "True" ]; then
    curl -s -b "$CK" "$N8N/rest/workflows/$WF1_ID" -o "$TMP/wf1.full.json"
    python3 -c "import json;print(json.load(open('$TMP/wf1.full.json'))['data'].get('versionId'))" > "$TMP/vid"
    curl -s -b "$CK" -X POST "$N8N/rest/workflows/$WF1_ID/activate" -H 'content-type: application/json' \
      -d "{\"versionId\":\"$(cat "$TMP/vid")\"}" -o /dev/null
  fi
}

fire_and_grab(){ # fire webhook, return latest exec id for WF1 in $TMP/eid
  curl -s -m 150 -X POST "$N8N/webhook/standup-run" -H 'content-type: application/json' -d '{}' -o "$TMP/webhook.out" -w '' || true
  sleep 2; login
  curl -s -b "$CK" "$N8N/rest/executions?filter=%7B%22workflowId%22%3A%22$WF1_ID%22%7D&limit=1" -o "$TMP/elist.json"
  python3 -c "import json;r=json.load(open('$TMP/elist.json'))['data'];rows=r if isinstance(r,list) else r.get('results',[]);print(rows[0]['id'] if rows else '')" > "$TMP/eid"
}

phase(){ # $1=label  $2=expected status  -> prints KEY=VALUE, sets PASS/FAIL
  EID=$(cat "$TMP/eid")
  curl -s -b "$CK" "$N8N/rest/executions/$EID?includeData=true" -o "$TMP/exec.json"
  python3 "$TMP/parse.py" "$TMP/exec.json" > "$TMP/res.env"; cat "$TMP/res.env"
  . "$TMP/res.env"
  echo "exec id=$EID"
}

echo "── 0. pre-flight ───────────────────────────────────────────"
AUTH=$(docker exec claude-code-runner claude -p "reply with exactly: AUTH_OK" --output-format text 2>&1 | head -1)
echo "$AUTH" | grep -q AUTH_OK && green "Claude logged in" || die "Claude not logged in — run: docker exec -it claude-code-runner claude login"
login; ensure_active; green "WF1 active (id=$WF1_ID)"

echo "── 1. RED — feed bad input (STANDUP_FORCE_FAIL=output) ─────"
reload_env "output"; ensure_active
fire_and_grab; phase "RED" "error"
RED_OK=1
[ "$STATUS" = "error" ]   || { red "expected status=error, got $STATUS"; RED_OK=0; }
[ "$POST_RAN" = "False" ] || { red "Post Standup ran on a bad run (garbage would post!)"; RED_OK=0; }
[ "$HANDLE_RAN" = "True" ]|| { red "alert branch did not fire"; RED_OK=0; }
[ "$RED_OK" = 1 ] && green "RED proven: gate BLOCKED the post, execution red, alert sent" || die "RED phase failed"
RED_EID=$EID

echo "── 2. GREEN — clear the flag, good run posts ───────────────"
reload_env ""; ensure_active
fire_and_grab; phase "GREEN" "success"
GREEN_OK=1
[ "$STATUS" = "success" ] || { red "expected status=success, got $STATUS"; GREEN_OK=0; }
[ "$POST_RAN" = "True" ]  || { red "Post Standup did not run on a good run"; GREEN_OK=0; }
[ "$HANDLE_RAN" = "False" ]|| { red "alert branch fired on a good run"; GREEN_OK=0; }
[ "$GREEN_OK" = 1 ] && green "GREEN proven: validation passed, standup posted" || die "GREEN phase failed"
GREEN_EID=$EID

echo
green "SELF-TEST PASSED — backpressure works.  RED exec=$RED_EID  GREEN exec=$GREEN_EID"
echo "(.env STANDUP_FORCE_FAIL left blank — normal operation restored.)"
