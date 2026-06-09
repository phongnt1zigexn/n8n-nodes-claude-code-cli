// n8n Code node — "Merge & Dedup"  (mode: Run Once for All Items)
// Pulls the three source nodes by name, normalizes each row to
// {source, id, text, ts}, dedups by source+id, and builds a single
// `activity` text block for the Claude Code node. No hardcoded data.
//
// This file mirrors the jsCode embedded in workflows/standup-direction1.json.
// Edit here, then keep the JSON in sync (it is the same string).

function rowsFrom(nodeName) {
  // Tolerate both shapes n8n's HTTP Request node can emit:
  //  - array body  -> one item per element
  //  - object body -> a single item wrapping {commits|issues|messages|...}
  let items = [];
  try {
    items = $(nodeName).all();
  } catch (e) {
    return []; // node not executed on this run (e.g. webhook-only path)
  }
  const out = [];
  for (const it of items) {
    const j = it.json ?? {};
    if (Array.isArray(j)) {
      out.push(...j);
    } else if (Array.isArray(j.commits)) {
      out.push(...j.commits);
    } else if (Array.isArray(j.issues)) {
      out.push(...j.issues);
    } else if (Array.isArray(j.messages)) {
      out.push(...j.messages);
    } else if (Object.keys(j).length) {
      out.push(j);
    }
  }
  return out;
}

const todayISO = $now.toISODate(); // yyyy-MM-dd

// --- GitHub commits (last 24h) ---
const github = rowsFrom('GitHub Commits')
  .filter((c) => c && (c.sha || c.commit))
  .map((c) => ({
    source: 'github',
    id: (c.sha || '').slice(0, 7),
    text: ((c.commit && c.commit.message) || '').split('\n')[0],
    ts: (c.commit && c.commit.author && c.commit.author.date) || '',
  }));

// --- Redmine issues (assigned to me, updated today) ---
const redmine = rowsFrom('Redmine Issues')
  .filter((i) => i && i.id)
  .map((i) => ({
    source: 'redmine',
    id: String(i.id),
    text: `#${i.id} ${i.subject || ''}${i.status && i.status.name ? ` [${i.status.name}]` : ''}`,
    ts: i.updated_on || '',
  }));

// --- Slack messages (today, from the watched channel) ---
const slack = rowsFrom('Slack Messages')
  .filter((m) => m && m.ts && m.text && m.subtype !== 'channel_join')
  .map((m) => ({
    source: 'slack',
    id: m.ts,
    text: m.text.replace(/\s+/g, ' ').trim(),
    ts: m.ts,
  }));

// --- merge + dedup by source+id ---
const seen = new Set();
const all = [...github, ...redmine, ...slack].filter((r) => {
  if (!r.text) return false;
  const key = `${r.source}:${r.id}`;
  if (seen.has(key)) return false;
  seen.add(key);
  return true;
});

function block(title, rows) {
  if (!rows.length) return `${title}: (none)`;
  return `${title}:\n` + rows.map((r) => `  • ${r.text}`).join('\n');
}

const activity = [
  `Date: ${todayISO}`,
  block('GitHub commits (last 7 days)', all.filter((r) => r.source === 'github')),
  block('Redmine issues (updated today)', all.filter((r) => r.source === 'redmine')),
  block('Slack messages (today)', all.filter((r) => r.source === 'slack')),
].join('\n\n');

return [
  {
    json: {
      date: todayISO,
      counts: {
        github: github.length,
        redmine: redmine.length,
        slack: slack.length,
        total: all.length,
      },
      items: all,
      activity,
    },
  },
];
