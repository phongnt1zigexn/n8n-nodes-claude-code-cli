<!-- PR title (correct the name): -->
# [PhongNguyen] Week 3 — N8N + Claude Code Exercise

> ⚠️ Fill the bracketed placeholders before submitting: **name**, execution screenshots, and the live MCP reply.

## Task path
- [x] **Default — Smart Daily Standup Bot** (two-way N8N ↔ Claude)
- [ ] Path A — team tools + MCP
- [ ] Path B — memory-first + MCP

## Setup
- **N8N URL:** http://localhost:5678
- **Integration method:** Production Docker stack `docker/production/n8n-with-claude-code` (n8n + claude-code-runner), community node `n8n-nodes-claude-code-cli` v1.9.0.
- **Docker auth:** `docker exec -it claude-code-runner claude login` (company account, one-time). No Anthropic API key — the node runs `claude` via `docker exec`.
- **Dockerfile change:** `Dockerfile.claude-code` base image `debian:bookworm-slim` → `debian:trixie-slim`.
- **Containers:** `n8n` (:5678) UP, `claude-code-runner` UP + healthy (HEALTHCHECK `claude --version`); n8n `depends_on: claude-code service_healthy`.
- **n8n owner:** `phongnt1@zigexn.vn` (local account, created during setup).
- **Automated via n8n API:** community node install, Docker credential creation + wiring, both workflows imported + activated.
- **Deviations:** (1) `docker-compose.override.yml` (env_file + `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`) instead of editing the base compose; (2) all external calls — incl. Slack read & send — use HTTP Request nodes keyed on `{{$env.*}}` so every secret lives in one `.env` (no per-node UI credentials except the no-secret Docker one).

## Explore
- **First prompt:** *"Deep-read the n8n-nodes-claude-code-cli repo: what nodes/params does the Claude Code node expose, how does it connect (docker exec), what's its output shape, and can an n8n memory node attach to it?"*
- **Nodes researched:** Schedule/Manual/Webhook triggers, HTTP Request, Code, Claude Code (community), Slack, Respond to Webhook, MCP Server Trigger, Call-n8n-Workflow tool.
- **Data sources connected:**
  - [x] GitHub (commits, last 24h)
  - [x] Redmine (issues assigned to me, updated today)
  - [x] Slack (today's channel messages)
  - [ ] Gmail / Notion (optional, not used)

## Vibe coding log
| # | Prompt | Used as-is / edited |
|---|--------|---------------------|
| 1 | "Deep-read the node repo — params, transport, output shape, memory capability." | as-is (research) |
| 2 | "Generate an importable n8n workflow JSON: Schedule+Manual+Webhook triggers → HTTP GET GitHub commits / Redmine issues / Slack history → Code node merge+dedup → Claude Code node (docker, resume session, replace system prompt, JSON output) → Slack send → Respond to Webhook." | edited — chained HTTP nodes linearly so the Code node can reference each by name; secrets via `{{$env}}`. |
| 3 | "Write the Code-node JS to normalize the 3 sources to {source,id,text,ts}, dedup by source+id, and build a Yesterday/Today/Blockers activity string." | as-is (`code-node-merge.js`). |
| 4 | "Generate the MCP tool workflow: MCP Server Trigger + Call-n8n-Workflow tool named run_standup_workflow → Direction-1 workflow." | edited — set `usableAsTool` tool name exactly to `run_standup_workflow`. |

## Build — Part 1 (Direction 1: N8N → Claude)
- **Workflow name:** Daily Standup Bot — Direction 1 (N8N → Claude)
- **Nodes:** Schedule Trigger 9AM, Manual Trigger, Webhook (MCP entry), GitHub Commits (HTTP), Redmine Issues (HTTP), Slack Messages (HTTP), Merge & Dedup (Code), Generate Standup (Claude Code), Post Standup (HTTP `chat.postMessage`), Respond Done.
- **Claude prompt (user):** activity block + *"Write my daily standup in EXACTLY three sections (Yesterday / Today / Blockers)…"*; **system prompt (replace):** standup assistant, use ONLY provided data, never fabricate, remember prior standups in the session.
- **Execution log result:** ✅ all green (n8n execution status `success`, all 7 nodes ran). Verified live via webhook `POST /webhook/standup-run` → HTTP 200 `Done. Standup posted to Slack ✅`. Real standup generated and posted to Slack DM `D0B8TCDMJ2J`:
  ```
  📋 Daily Standup — 2026-06-07
  **Yesterday:**
  • Merged PR #42: fix login timeout on staging
  • Reviewed design doc #99405, left comments
  **Today:**
  • (nothing)
  **Blockers:**
  • Waiting on infra to whitelist the new webhook IP
  ```
  (Data from live Slack channel `C0B8S2P8FSR`. GitHub = 0 commits in 7 days; Redmine blocked by an nginx basic-auth gate on `dev.zigexn.vn` — see Data sources note. No hardcoded data — AC-08-3.)

## Data sources
- **GitHub repo:** `${GITHUB_OWNER}/${GITHUB_REPO}` — `GET /repos/{owner}/{repo}/commits?since={{$now.minus({days:1}).toISO()}}`
- **Redmine URL:** `${REDMINE_BASE_URL}` (`https://dev.zigexn.vn`) — `GET /issues.json?assigned_to_id=me&updated_on=>={{today}}`. This host sits behind an **nginx HTTP Basic Auth** gate, so the Redmine node sends BOTH `X-Redmine-API-Key` (env) and `Authorization: Basic {{$env.REDMINE_BASIC_B64}}`. ✅ Now authenticates (HTTP 200; 20 issues assigned to me, 0 *updated today* at test time → empty Redmine section, which is correct). Broaden `updated_on` to `>=` last-7-days if you want it to show like GitHub.
- **Slack channel:** `${SLACK_FETCH_CHANNEL_ID}` (read) → posts to `${SLACK_POST_CHANNEL_ID}` — `conversations.history?oldest={{today_midnight_epoch}}`
- **Gmail filter:** n/a

## Build — Part 2 (MCP: Claude → N8N)
- **Tool name:** `run_standup_workflow`
- **MCP connector:** n8n **MCP Server Trigger** node (SSE). Live endpoint `GET http://localhost:5678/mcp/standup-mcp/sse`. Register: `claude mcp add --transport sse n8n-standup http://localhost:5678/mcp/standup-mcp/sse`.
- **Test prompt:** "Run my standup for today"
- **Result:** ✅ Verified via a real MCP handshake. `tools/list` returns `run_standup_workflow`; `tools/call` executed it → WF2 (exec 6 `success`) → WF1 (exec 5 `success`) → Slack DM posted. Tool returned `{"ok":true,"channel":"D0B8TCDMJ2J","ts":"1780848482…", message=the standup}`.
- **Claude's reply:** "Done. Standup posted to Slack ✅" (Respond-to-Webhook body; over MCP the tool returns the Slack post confirmation JSON).
- **Note:** AC-04-4 (call originating from *your* claude.ai/CLI) → just add the MCP server above to your Claude client and say "run my standup for today". The server + tool are proven working.

## Memory verification
- **Session ID:** `standup-phong` → UUID `7b3e9c2a-1d4f-4a6b-9c8e-2f0a5d7b1e30`, via Claude Code **Resume Session** (persisted in `./claude-config`).
- **Mechanism note:** the Claude Code CLI node is **not** a LangChain agent and has no `ai_memory` input, so an n8n *Window Buffer Memory* node cannot attach. Memory is achieved with Claude's native fixed-session persistence (functionally equivalent: last-N-messages context retained across runs). This is the documented deviation from AC-02-8 / AC-05-1's literal wording.
- **Second run result:** ✅ Ran the workflow multiple times (3+ executions); each Resume-Session call accumulates in the fixed session.
- **What Claude said about yesterday:** ✅ Memory verified. `claude --resume 7b3e9c2a…  "What did I report in my last standup?"` returned:
  > From the standup I just generated moments ago — **Yesterday:** Merged PR #42: fix login timeout on staging; Reviewed design doc #99405, left comments. **Blockers:** Waiting on infra to whitelist the new webhook IP.

  Claude referenced the prior standup's exact items (not generic) — AC-05-4 / AC-08-4 ✓.

## Acceptance criteria (Default path — 11)
- [x] 1. Schedule **or** Chat trigger — Schedule 9AM + Manual + Webhook
- [x] 2. GitHub commits (24h) via HTTP GET
- [x] 3. Redmine issues (assigned to me, today) via HTTP GET
- [x] 4. Slack messages (today) fetched
- [x] 5. Code node merges + dedups (no hardcode)
- [x] 6. Claude Code node: system prompt + Yesterday/Today/Blockers user prompt
- [x] 7. Standup generated from real data, 3-section format
- [~] 8. Memory attached — via Claude native session (Window Buffer Memory not applicable to this node; see note)
- [~] 9. Slack send posts the standup — via Slack HTTP API `chat.postMessage` (not the native node; keeps all secrets in `.env`)
- [x] 10. Execution log green — verified (`success`, all nodes; webhook HTTP 200)
- [ ] 11. (optional) Gmail/Notion extra source — not used

## Reflection
1. **What worked well?** [YOUR ANSWER — e.g. generating importable JSON from a deep read of the node source]
2. **What was tricky?** The node isn't a LangChain agent, so n8n memory nodes don't attach — had to use Claude's native session persistence. Also an OrbStack keychain quirk blocked image pulls.
3. **What would you automate next?** [YOUR ANSWER]
4. **One thing to check manually each run?** That the Slack bot is still in the channel and tokens haven't expired (otherwise sources return empty and the standup is thin).

## 60-second share
- **Workflow in one sentence:** A two-way standup agent — n8n pulls my GitHub/Redmine/Slack activity, Claude writes the standup and posts it to Slack, and I can also trigger the whole thing by telling Claude "run my standup".
- **Integration win:** Claude calling `run_standup_workflow` over MCP and the workflow running end-to-end to Slack.
- **Thing to check manually:** Slack bot channel membership + token validity (empty sources = empty standup).

---
### Screenshot
[ATTACH: N8N canvas of the Direction-1 workflow showing all nodes — AC-07-14]
