# AGENT-NOTES — Daily Standup Bot (N8N × Claude Code)

> Context / system-prompt doc for the standup agent (Levels 3–5 of the
> Agentic-Engineering scale). This is the durable "how the agent thinks +
> what it can reach" reference that the Level-6 harness wraps.

- **Path:** Default — N8N Daily Standup Bot (two-way N8N ↔ Claude).
- **Current level: 5.** L3 Context + L4 Compounding (system prompt + native session memory) and L5 MCPs & Skills (a working MCP tool) are all live, documented below.
- **Target: Level 6 — Harness.** Validation gates + error branch provide backpressure (see `PR.md` → *Harness / Backpressure* and `harness-selftest.sh`).

---

## L3 — Context: the agent's prompt

**System prompt** (node *Generate Standup*, `systemPromptMode: replace`) — verbatim:

```
You are a daily-standup assistant. You receive raw activity data (GitHub commits,
Redmine issues, Slack messages) and turn it into a crisp standup with three
sections: Yesterday, Today, Blockers. Rules: use ONLY the provided data, never
fabricate items, infer Today's plan from in-progress Redmine issues, and surface
anything that reads like a blocker. Remember prior standups in this session so you
can answer follow-up questions like 'what did I report yesterday?'.
```

**User prompt** (templated each run with the merged `activity` block):

```
Here is my activity data for today. Use ONLY this data — do not invent anything.

{{ activity }}

Write my daily standup in EXACTLY three sections, each as a bulleted list:
Yesterday:
Today:
Blockers:
Keep it concise. If a section has no data, write "• (nothing)".
Start the message with "📋 Daily Standup — {{ date }}".
```

**Operating rules (the contract the harness enforces):**
- Use ONLY the merged activity data — never fabricate. (Enforced upstream: the *Merge & Dedup* Code node builds `activity` purely from live API responses.)
- Output must contain all three sections: **Yesterday / Today / Blockers**. (Enforced downstream: *Validate Output* rejects any output missing a section → nothing posts.)
- `output` (the standup text) is read from the Claude Code node's `.output` field.

### Data-source contract (normalized to `{source, id, text, ts}` in *Merge & Dedup*)
| Source | Call | Window | Notes |
|--------|------|--------|-------|
| GitHub | `GET /repos/{owner}/{repo}/commits` | last 7 days | `Authorization: Bearer $GITHUB_TOKEN` |
| Redmine | `GET /issues.json?assigned_to_id=me&updated_on=>=today` | updated today | `X-Redmine-API-Key` + nginx Basic-Auth (`$REDMINE_BASIC_B64`) |
| Slack | `GET conversations.history?channel=$FETCH&oldest=midnight` | today | bot token; bot must be in the channel |

---

## L4 — Compounding: memory across runs

The Claude Code CLI node is **not** a LangChain agent (it shells `claude` via
`docker exec`), so it has no `ai_memory` input and an n8n *Window Buffer Memory*
node cannot attach. Memory is achieved with Claude's **native session
persistence**:

- Operation **Resume Session** on a fixed UUID `7b3e9c2a-1d4f-4a6b-9c8e-2f0a5d7b1e30` (label `standup-phong`, `$STANDUP_SESSION_ID`).
- The session lives on the mounted `./claude-config` volume, so every run continues the same conversation — yesterday's standup is in context today.
- Verified: `claude --resume <uuid> "what did I report yesterday?"` returns the prior standup's exact items.

---

## L5 — MCPs & Skills (working tools)

1. **MCP tool `run_standup_workflow`** — exposed by the **MCP Server Trigger**
   node in `workflows/standup-mcp-tool.json` (Direction 2, SSE endpoint
   `http://localhost:5678/mcp/standup-mcp/sse`). A Claude client calls it to run
   the whole standup; the tool is wired to Direction-1 (`run_standup_workflow` →
   the standup workflow → Slack). Register:
   `claude mcp add --transport sse n8n-standup http://localhost:5678/mcp/standup-mcp/sse`.
2. **Claude Code CLI** — the generation "skill": the *Generate Standup* node runs
   `claude` inside the `claude-code-runner` container via a Docker credential
   (no API key; uses the logged-in CLI).

---

## L6 — Harness (this capstone)

Backpressure = two validation Code nodes feeding IF "gates"; on failure the run
is routed to a Slack alert + Stop-And-Error (red log) and the Slack post is
skipped. Fault-injection hook `STANDUP_FORCE_FAIL=input|output`; automated proof
in `harness-selftest.sh`. Full detail + red→green evidence in `PR.md`.
