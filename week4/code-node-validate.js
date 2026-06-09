// ============================================================================
// HARNESS / BACKPRESSURE — readable copies of the two validation Code nodes
// in standup-direction1.json. They are the automated feedback loop required by
// Step 3: each asserts the data is well-formed and feeds a boolean `valid`
// to an IF "gate" node. On false the run is routed to an error branch that
// posts a Slack alert and then a Stop-And-Error node (red execution log) —
// so a bad run is CAUGHT instead of posting garbage to Slack.
//
// Fault-injection hook for the red→green demo: set env STANDUP_FORCE_FAIL to
//   "input"  → forces gate #1 red
//   "output" → forces gate #2 red
// Clear it (unset / empty) to go green again.
// ============================================================================


// ── Node "Validate Input" (runs after Merge & Dedup, before Claude) ─────────
function validateInput($json, $env) {
  const j = $json;
  const errors = [];
  if ($env.STANDUP_FORCE_FAIL === 'input') errors.push('forced failure (STANDUP_FORCE_FAIL=input)');
  if (typeof j.activity !== 'string' || j.activity.trim() === '') errors.push('activity missing/empty');
  if (!j.counts || typeof j.counts.total !== 'number') errors.push('counts.total missing/non-numeric');
  if (!Array.isArray(j.items)) errors.push('items is not an array');
  const valid = errors.length === 0;
  console.log(`[standup][input] valid=${valid} total=${j.counts && j.counts.total} errors=${JSON.stringify(errors)}`);
  return [{ json: { ...j, valid, stage: 'input', errors } }];
}


// ── Node "Validate Output" (runs after Claude, before Post Standup) ─────────
function validateOutput($json, $env) {
  const j = $json;
  const text = typeof j.output === 'string' ? j.output : '';
  const errors = [];
  if ($env.STANDUP_FORCE_FAIL === 'output') errors.push('forced failure (STANDUP_FORCE_FAIL=output)');
  if (j.success === false) errors.push('claude reported success=false');
  if (text.trim() === '') errors.push('empty standup text');
  for (const section of ['Yesterday', 'Today', 'Blockers']) {
    if (!text.includes(section)) errors.push(`missing required section: ${section}`);
  }
  const valid = errors.length === 0;
  console.log(`[standup][output] valid=${valid} len=${text.length} errors=${JSON.stringify(errors)}`);
  return [{ json: { ...j, valid, stage: 'output', errors } }];
}
