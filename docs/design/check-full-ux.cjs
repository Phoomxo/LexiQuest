const fs = require('node:fs');
const path = require('node:path');

const base = __dirname;
const source = fs.readFileSync(path.join(base, 'lexiquest-full-ux.js'), 'utf8');
const html = fs.readFileSync(path.join(base, 'lexiquest-full-ux-prototype.html'), 'utf8');
const ledger = JSON.parse(fs.readFileSync(path.join(base, '../development/ari/optional-mcp-workflows.json'), 'utf8'));

function assert(condition, message) {
  if (!condition) throw new Error(message);
}
function sameSet(actual, expected, label) {
  const a = [...new Set(actual)].sort();
  const e = [...new Set(expected)].sort();
  assert(JSON.stringify(a) === JSON.stringify(e), `${label} mismatch: actual=${a.join(',')} expected=${e.join(',')}`);
  assert(actual.length === a.length, `${label} has duplicate identifiers`);
}

const workflowRows = [...source.matchAll(/^\s*\{id:'(W\d{2})',label:'[^']+',route:'([^']+)'\}/gm)];
const modeIds = [...source.matchAll(/^\s*\{id:'([a-z][a-z-]+)',label:/gm)].map(match => match[1]);
sameSet(workflowRows.map(match => match[1]), ledger.workflows.map(row => row.id), '14 workflow groups');
sameSet(modeIds, ledger.learningModes.map(row => row.id), '14 learning modes');

const viewMatch = source.match(/const views=\{([^\n]+)\};/);
assert(viewMatch, 'view router not found');
const views = [...viewMatch[1].matchAll(/(?:^|,)(?:'([^']+)'|([a-z-]+)):/g)].map(match => match[1] || match[2]);
for (const [, id, route] of workflowRows) assert(views.includes(route), `${id} has no view: ${route}`);
for (const [, modeId] of source.matchAll(/['"]mode:([a-z-]+)['"]/g)) assert(modeIds.includes(modeId), `unknown mode route: ${modeId}`);

const actionIds = [...new Set([...source.matchAll(/data-action=\\?"([a-z-]+)\\?"/g)].map(match => match[1]))];
const handledActions = [...new Set([...source.matchAll(/action==='([a-z-]+)'/g)].map(match => match[1]))];
for (const action of actionIds) assert(handledActions.includes(action), `button has no action handler: ${action}`);

const staticIds = [...html.matchAll(/\bid="([^"]+)"/g)].map(match => match[1]);
sameSet(staticIds, staticIds, 'static HTML IDs');
for (const file of ['lexiquest-full-ux.css', 'lexiquest-full-ux.js', '../../assets/fonts/NotoSansThai-Variable.ttf']) {
  assert(fs.existsSync(path.resolve(base, file)), `local dependency missing: ${file}`);
}
assert(html.includes('lang="th"'), 'prototype must declare Thai language');
console.log(`Prototype coverage verified: ${workflowRows.length} workflow groups, ${modeIds.length} modes, ${views.length} views, ${actionIds.length} declared actions.`);
