<!-- PR title: -->
# [PhongNguyen] Week 4 — Capstone: Build to Level 6

> Upgrades the Week-3 Default-path **N8N Daily Standup Bot** to **Level 6 — Harness Engineering**: an automated input/output-validation feedback loop with an error branch that gates **every** execution, so the bot catches and stops its own bad runs **without a human in the loop**. Proven live with a red→green demo and a re-runnable self-test.

## 1. Path & level (AC-1)
- **Path:** Default — N8N Daily Standup Bot (two-way N8N ↔ Claude).
- **Starting level: 5 / 8.** Already in place from Week 3 (see [`AGENT-NOTES.md`](AGENT-NOTES.md)):
  - **L3 Context** — the standup system prompt + data-source contract.
  - **L4 Compounding** — Claude native session memory (`--resume` on a fixed UUID); recall verified.
  - **L5 MCPs & Skills** — a working MCP tool `run_standup_workflow` + the Claude Code CLI generation skill.
- **Target reached: Level 6 — Harness.** Validation gates + error branch below.
- A 9 AM Schedule Trigger exists (brushes L7) but L7/L8 are **not** claimed — out of scope for this capstone.

## 2. L3/L4 — Context & Compounding exist (AC-2)
Full context/system-prompt doc: **[`AGENT-NOTES.md`](AGENT-NOTES.md)** — verbatim system prompt, user-prompt template, operating rules, the 3-source data contract, and the native-session memory mechanism (fixed UUID `7b3e9c2a-…` + Resume Session on the `./claude-config` volume).

## 3. L5 — MCPs & Skills exist (AC-3)
- **MCP tool `run_standup_workflow`** — exposed by an **MCP Server Trigger** node (`workflows/standup-mcp-tool.json`, SSE at `/mcp/standup-mcp/sse`), wired to run the standup workflow end-to-end. Verified in Week 3 via a real `tools/list` + `tools/call` handshake.
- **Claude Code CLI** — the generation skill; the *Generate Standup* node runs `claude` in the `claude-code-runner` container via a Docker credential (no API key).

## 4. Harness Part 1 — validation nodes (AC-4)
Two **Code** nodes assert the data is well-formed; each emits a boolean `valid` + an `errors[]` list (readable copy: [`code-node-validate.js`](code-node-validate.js)):
- **Validate Input** (after *Merge & Dedup*, before Claude): `activity` is a non-empty string, `counts.total` is numeric, `items` is an array. Stops a malformed merge from wasting a Claude call.
- **Validate Output** (after Claude, before Slack): `success !== false`, the standup text is non-empty, and **all three sections** (`Yesterday` / `Today` / `Blockers`) are present. Stops garbage from being posted.

## 5. Harness Part 2 — error branch is the gate (AC-5)
- Each validator feeds an **IF gate** (`Input Gate`, `Output Gate`). On `valid=false` the item is routed to the **error branch**: **Handle Error (Alert)** posts `⚠️ Standup run BLOCKED at <stage> validation — nothing posted. Errors: …` to Slack, then **Stop And Error** terminates the run ⇒ **the execution log goes red**.
- `Post Standup` is on the *true* branch only, so a failed check **never posts**. This gate runs on **every** execution. Topology: `Merge → Validate Input → Input Gate ─true→ Generate Standup → Validate Output → Output Gate ─true→ Post Standup → Respond Done`; both gates' *false* branch → `Handle Error (Alert) → Stop And Error`.

## 6. Backpressure demo — red → green (AC-6)
Fault is injected with env var `STANDUP_FORCE_FAIL` (`input`|`output`) — no need to corrupt real data. Run live on n8n 2.23.4, workflow id `BHJXTMW0trPlFUoH`, via the production webhook `POST /webhook/standup-run`. Asserted against the n8n **execution record** (not log scraping) by `harness-selftest.sh`.

### 🔴 RED — bad run is caught (execution **error**, nothing posted)
`STANDUP_FORCE_FAIL=output` → **execution #18**:
```
status            = error            ← red execution log
workflowData nodes= 16               ← harness version ran
Validate Output   : valid=false  errors=["forced failure (STANDUP_FORCE_FAIL=output)"]
Post Standup ran? = False            ← garbage NOT posted ✅
Handle Error ran? = True  → Slack chat.postMessage ok=true (⚠️ BLOCKED alert sent to DM D0B8TCDMJ2J)
Stop And Error    = True             ← run terminated red
```
📸 **[ATTACH RED screenshot: n8n execution #18 — red status, false-branch to Handle Error + Stop And Error, `Post Standup` greyed out; + the ⚠️ BLOCKED Slack message]**

### 🟢 GREEN — fix it, good run posts (execution **success**)
Clear `STANDUP_FORCE_FAIL` → **execution #19**:
```
status            = success          ← green
Validate Input    : valid=true   |  Validate Output : valid=true
Post Standup ran? = True  → Slack chat.postMessage ok=true (standup posted to DM D0B8TCDMJ2J) ✅
Handle Error ran? = False
```
📸 **[ATTACH GREEN screenshot: n8n execution #19 — all nodes green through `Post Standup`; + the posted 📋 standup in Slack]**

### Automated self-test (the gate "on every change") — [`harness-selftest.sh`](harness-selftest.sh)
Sets the flag, fires the webhook, and **asserts on the execution record**; non-zero exit = harness broken (CI-able). Idempotent — verified across 3 consecutive runs. Live output:
```
── 1. RED — feed bad input (STANDUP_FORCE_FAIL=output) ─────
STATUS=error  POST_RAN=False  HANDLE_RAN=True  STOP_RAN=True  VO_VALID=False
VO_ERR='forced failure (STANDUP_FORCE_FAIL=output)'   exec id=18
✔ RED proven: gate BLOCKED the post, execution red, alert sent
── 2. GREEN — clear the flag, good run posts ───────────────
STATUS=success  POST_RAN=True  HANDLE_RAN=False   exec id=19
✔ GREEN proven: validation passed, standup posted
✔ SELF-TEST PASSED — backpressure works.  RED exec=18  GREEN exec=19
```

## 7. Bonus — logging / observability (AC-7)
Both validators emit a structured line to the n8n execution console every run — input received, validation result, errors:
```
[standup][input]  valid=true  total=2  errors=[]
[standup][output] valid=false len=0   errors=["forced failure (STANDUP_FORCE_FAIL=output)"]
```
Tail with `docker compose logs -f n8n`.

## 60-second share
1. **What it is:** a two-way daily-standup agent — n8n pulls my GitHub/Redmine/Slack activity, Claude writes the standup and posts it to Slack, and I can also trigger it by asking Claude.
2. **What the harness caught:** a forced bad run was blocked at the Output gate — the execution went red and a Slack alert fired **instead of** posting garbage (RED #18); clearing the fault let a clean standup post (GREEN #19).
3. **One thing I still verify by hand:** that the Slack bot is still in the channel and the tokens haven't expired — empty sources make a thin standup that *passes* validation (the gate checks shape, not richness).

---
### Deliverables in this PR (`week4/`)
- `AGENT-NOTES.md` — L3/L4/L5 context doc.
- `workflows/standup-direction1.json` — standup workflow **with the 6 harness nodes** (16 total).
- `workflows/standup-mcp-tool.json` — the MCP tool workflow (L5).
- `code-node-validate.js` — readable copy of both validators.
- `harness-selftest.sh` — automated red→green self-test (the gate on every change).
- 2 screenshots (red #18 + green #19) — **attached by me in the PR UI** (browser; the agent can't capture canvas images).
