#!/usr/bin/env bash
# End-to-end verifier for the Week-3 standup bot.
# Run AFTER:  (1) docker exec -it claude-code-runner claude login
#             (2) filling .env  +  docker compose up -d
# It seeds the memory session, fires the full workflow twice via the webhook,
# checks the n8n execution status, and runs the memory-recall test.
set -uo pipefail

N8N=http://localhost:5678
WF1_ID=A9MgMKopk7IqQY2n
SESSION=7b3e9c2a-1d4f-4a6b-9c8e-2f0a5d7b1e30
OWNER_EMAIL=phongnt1@zigexn.vn
OWNER_PASS=Standup2026x
ENV_FILE="n8n-nodes-claude-code-cli/docker/production/n8n-with-claude-code/.env"
COOKIES=/tmp/n8n.verify.cookies
ok(){ printf '\033[32m✔ %s\033[0m\n' "$1"; }
bad(){ printf '\033[31mx %s\033[0m\n' "$1"; }

echo "── 1. Claude auth ─────────────────────────────"
AUTH=$(docker exec claude-code-runner claude -p "reply with exactly: AUTH_OK" --output-format text 2>&1 | head -1)
if echo "$AUTH" | grep -q AUTH_OK; then ok "Claude logged in"; else bad "Claude NOT logged in: $AUTH"; echo "Run: docker exec -it claude-code-runner claude login"; exit 1; fi

echo "── 2. .env secrets ────────────────────────────"
MISS=0
for k in GITHUB_TOKEN GITHUB_OWNER GITHUB_REPO REDMINE_BASE_URL REDMINE_API_KEY SLACK_BOT_TOKEN SLACK_FETCH_CHANNEL_ID SLACK_POST_CHANNEL_ID; do
  v=$(grep -E "^$k=" "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d ' ')
  if [ -z "$v" ]; then bad "$k empty"; MISS=1; else ok "$k set"; fi
done
[ "$MISS" = 1 ] && { echo "Fill $ENV_FILE then: (cd $(dirname "$ENV_FILE") && docker compose up -d)"; exit 1; }

echo "── 3. Seed memory session ($SESSION) ──────────"
docker exec claude-code-runner claude --session-id "$SESSION" -p "Standup session init. Acknowledge with OK." --output-format text 2>&1 | head -1
ok "session seeded (idempotent)"

echo "── 4. Run 1 — fire workflow via webhook ───────"
R1=$(curl -s -X POST "$N8N/webhook/standup-run" -H 'content-type: application/json' -d '{}')
echo "webhook reply: $R1"

echo "── 5. Check execution status (n8n API) ────────"
curl -s -c "$COOKIES" -X POST "$N8N/rest/login" -H 'content-type: application/json' \
  -d "{\"emailOrLdapLoginId\":\"$OWNER_EMAIL\",\"password\":\"$OWNER_PASS\"}" >/dev/null
EXEC=$(curl -s -b "$COOKIES" "$N8N/rest/executions?filter=%7B%22workflowId%22%3A%22$WF1_ID%22%7D&limit=1")
echo "$EXEC" | python3 - <<'PY' 2>/dev/null || echo "(could not parse execution; check UI)"
import json,sys
d=json.load(sys.stdin).get('data',{})
rows=d.get('results') or d.get('data') or []
if not rows: print("no executions found"); sys.exit()
e=rows[0]
print("execution", e.get('id'), "status=", e.get('status'), "finished=", e.get('finished'))
PY

echo "── 6. Run 2 — fire again (different moment) ────"
sleep 2
R2=$(curl -s -X POST "$N8N/webhook/standup-run" -H 'content-type: application/json' -d '{}')
echo "webhook reply: $R2"

echo "── 7. Memory recall test ──────────────────────"
echo "Asking the SAME session what was reported before:"
docker exec claude-code-runner claude --resume "$SESSION" -p "What did I report in my standup yesterday? Summarize the previous standup you generated." --output-format text 2>&1 | head -30

echo
echo "Done. Check Slack ($(grep ^SLACK_POST_CHANNEL_ID= "$ENV_FILE" | cut -d= -f2)) for the posted standups,"
echo "and confirm the recall above references prior content (AC-05 / AC-08-4)."
