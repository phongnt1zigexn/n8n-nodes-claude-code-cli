# RUNBOOK — Week 3 N8N ↔ Claude Standup Bot

What's already done by the scaffold vs. what you do by hand is marked **[DONE]** / **[YOU]**.

---

## 0. Status — what's already automated

- **[DONE]** Repo cloned → `n8n-nodes-claude-code-cli/`
- **[DONE]** `Dockerfile.claude-code` edited: `debian:bookworm-slim` → `debian:trixie-slim`
- **[DONE]** `docker-compose.override.yml` added (injects `.env`, enables `$env` in nodes)
- **[DONE]** Stack built & running: `n8n` (:5678) + `claude-code-runner` (healthy)
- **[DONE]** **n8n owner account created** — login `phongnt1@zigexn.vn` / `Standup2026x` (local, change anytime)
- **[DONE]** **Community node `n8n-nodes-claude-code-cli` v1.9.0 installed** (type `n8n-nodes-claude-code-cli.claudeCode`)
- **[DONE]** **Docker credential created** (`claude-code-runner`) and wired into the Claude node
- **[DONE]** **Both workflows imported + ACTIVE** (WF1 id `jpiohQsl1uXZWe9Y`, WF2/MCP id `cZor57DfC55Fvj1i`, MCP path `/mcp/standup-mcp`)
- **[DONE]** Workflow JSONs, `.env.template`, merge code generated. All external calls (incl. Slack send via `chat.postMessage`) use `{{$env.*}}` → **no UI credential wiring left**.

### ✅ VERIFIED END-TO-END (both directions)
- `claude login` done; `.env` filled (incl. `REDMINE_BASIC_B64` for the nginx gate).
- n8n persists on volume (`N8N_USER_FOLDER=/home/node/.n8n`) — survives restarts.
- **Direction 1:** webhook → 3 sources → Claude → Slack DM `Done ✅` (execution `success`, all nodes green).
- **Memory:** `--resume` recall returned the prior standup's exact items.
- **Direction 2 (MCP):** `GET /mcp/standup-mcp/sse` live; `tools/call run_standup_workflow` → workflow ran → Slack post (`ok:true`).
- All 3 sources authenticate (GitHub, Redmine via basic-auth+key, Slack). Redmine shows items only when issues are *updated today*.

Remaining is just deliverables: add the MCP server to YOUR Claude client (step 8) for the AC-04-4 live call, screenshot the canvas, fill PR.md name, open the PR.

> **macOS / OrbStack keychain note:** the build needed a shadow credential helper because
> `docker-credential-osxkeychain` auto-denies in a non-interactive shell. Images are now cached,
> so a plain `docker compose up -d` works. If you ever rebuild and hit
> `error getting credentials ... User canceled (-128)`, run the build with:
> `PATH=/tmp/fakecreds:$PATH docker compose up -d --build`
> (or in your own terminal, approve the keychain prompt). Your real `~/.docker/config.json` was left untouched.

The stack dir (run all `docker compose` commands here):
```
cd "n8n-nodes-claude-code-cli/docker/production/n8n-with-claude-code"
```

---

## 1. Fill secrets  **[YOU]**

A placeholder `.env` already sits next to the compose file. Edit it in place:
```
n8n-nodes-claude-code-cli/docker/production/n8n-with-claude-code/.env
```
Fill GitHub / Redmine / Slack values (`STANDUP_SESSION_ID` is pre-filled). Then reload env:
```bash
cd "n8n-nodes-claude-code-cli/docker/production/n8n-with-claude-code"
docker compose up -d        # picks up new env (no rebuild needed)
```
Slack bot needs scopes `channels:history`, `groups:history`, `chat:write`, and must be **invited** into the read + post channels.

---

## 2. Authenticate Claude (one-time)  **[YOU]**

```bash
docker exec -it claude-code-runner claude login
```
Use the **company Claude account**. Session persists in the mounted `./claude-config` volume.

Verify:
```bash
docker exec claude-code-runner claude --version    # should print a version (already passing healthcheck)
```

---

## 3–4. Node + credential + import + activate  **[DONE — automated via n8n API]**

Already done (just verify in the UI at <http://localhost:5678>, login above):
- Community node `n8n-nodes-claude-code-cli` v1.9.0 installed. (AC-01-6/8)
- Docker credential `claude-code-runner` created + wired into **Generate Standup**. (AC-01-7)
- **Daily Standup Bot — Direction 1** imported + **active** (id `jpiohQsl1uXZWe9Y`). (AC-03-2)
- **run_standup_workflow — Direction 2 (MCP)** imported + **active**, tool pointed at WF1 (id `cZor57DfC55Fvj1i`, MCP path `/mcp/standup-mcp`).

No UI credential wiring left — every external call (GitHub, Redmine, Slack read **and** send) reads `{{$env.*}}` from `.env`.

---

## 5. Seed the memory session (one-time)  **[YOU]**

Memory = Claude Code's own session (the node has no Window-Buffer-Memory input — see PR notes).
Create the fixed session that every run resumes:
```bash
docker exec claude-code-runner \
  claude --session-id 7b3e9c2a-1d4f-4a6b-9c8e-2f0a5d7b1e30 -p "standup session init"
```
(`7b3e9c2a-…` is the UUID labeled `standup-phong`, matching the *Generate Standup* node's Session ID.)

---

## 6. Run Direction 1 (N8N → Claude)  **[YOU]**  — AC-02 / AC-08-1

1. Open the Direction-1 workflow → click **Execute Workflow** (Manual Trigger).
2. Watch the canvas: all nodes turn **green**. (AC-02-10)
3. Check Slack: the standup (📋 Yesterday / Today / Blockers) is posted to `SLACK_POST_CHANNEL_ID`. (AC-02-9)
4. Open the execution → confirm the Code node merged real GitHub/Redmine/Slack rows (`counts.total > 0`, no hardcoding). (AC-08-3)

---

## 7. Verify memory (run twice)  **[YOU]**  — AC-05 / AC-08-4

1. Run the workflow again (different day / after new commits/issues) → second standup posts.
2. Temporarily edit **Generate Standup** → `Prompt` = `What did I report yesterday?` → **Execute**.
3. Claude's `output` should reference the **previous** standup's content (because Resume Session shares the session). Screenshot it.
4. Restore the original prompt.

---

## 8. Direction 2 (Claude → N8N via MCP)  **[YOU]**  — AC-04 / AC-08-2

1. In the **MCP Server Trigger** node, copy the **MCP URL** shown (e.g. `http://localhost:5678/mcp/standup-mcp`). Confirm whether it lists an SSE or Streamable-HTTP endpoint.
2. Register it with Claude CLI (host) — **verified live endpoint is SSE**:
   ```bash
   claude mcp add --transport sse n8n-standup http://localhost:5678/mcp/standup-mcp/sse
   ```
   (Or add it as a custom connector in claude.ai.)
3. In Claude, say: **"Run my standup for today"**.
4. Expect: Claude auto-calls `run_standup_workflow` → Direction-1 workflow executes → Slack post → Claude replies *"Done. Standup posted to Slack ✅"*. (AC-04-4..7)

---

## 9. Deliverables  **[YOU]**

- Screenshot the Direction-1 canvas (all nodes) → attach to PR. (AC-07-14)
- Fill remaining placeholders in `PR.md` (your name, exec results, MCP reply) and open the PR. (AC-07)
- Push `workflows/*.json` to the branch. (AC-07-15)

---

## 10. Harness / backpressure — red→green demo  **[YOU]**  — Step 3

The workflow has a built-in backpressure harness: **Validate Input** + **Validate Output** Code nodes each feed a boolean `valid` to an **IF gate**; on `valid=false` the run goes to **Handle Error (Alert)** (posts a Slack `⚠️ BLOCKED` alert) → **Stop And Error** (reds the execution). The `Post Standup` node is never reached, so bad data is caught instead of posted.

> If you ran the workflow before this harness was added, re-import `workflows/standup-direction1.json` in the n8n UI (Workflow → ⋯ → Import from File) so the new nodes load.

**Show the gate catches a failure (RED):**
```bash
cd "n8n-nodes-claude-code-cli/docker/production/n8n-with-claude-code"
# force gate #2 to fail (use "input" to force gate #1 instead)
( grep -v '^STANDUP_FORCE_FAIL=' .env; echo 'STANDUP_FORCE_FAIL=output' ) > .env.tmp && mv .env.tmp .env
docker compose up -d                       # reload env
curl -s -X POST http://localhost:5678/webhook/standup-run -d '{}'; echo
docker compose logs --tail=20 n8n | grep '\[standup\]'   # observability line
```
Expect: execution status **error** (red), `Output Gate` false branch, `Post Standup` **not executed**, Slack gets the `⚠️ … BLOCKED at output validation` alert. **Screenshot the red execution log + the alert.** (Step 3 #2)

**Fix it and show green:**
```bash
( grep -v '^STANDUP_FORCE_FAIL=' .env; echo 'STANDUP_FORCE_FAIL=' ) > .env.tmp && mv .env.tmp .env
docker compose up -d
curl -s -X POST http://localhost:5678/webhook/standup-run -d '{}'; echo
```
Expect: status **success** (all nodes green), both gates true, real standup posts to Slack. **Screenshot it.** (Step 3 #3)

The red → green pair is the backpressure proof. **Bonus (observability):** both validators log `[standup][input] valid=… errors=…` to the execution console every run (`docker compose logs -f n8n`).

---

## Phased-workflow log (AC-06)

| Phase | What was done | Tool |
|-------|---------------|------|
| Explore | Deep-read `n8n-nodes-claude-code-cli` source (node params, transport, output shape) to map required nodes; confirmed the node is not a LangChain agent. | Claude Code CLI |
| Plan | Wrote the plan (`~/.claude/plans/…`), defined node graph + memory approach, resolved 4 open questions. | Claude Code CLI Plan Mode |
| Build | Edited Docker stack, generated both workflow JSONs + Code node + prompts + `.env`. | Claude Code CLI (generate JSON) |
| Test | `docker compose ps` (2 UP/healthy), `claude --version`, n8n HTTP 200; remaining UI execution = steps 6–8 above. | N8N execution log |
