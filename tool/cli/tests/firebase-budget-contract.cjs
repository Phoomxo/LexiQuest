const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const source = fs.readFileSync(path.join(__dirname, '../configure-firebase-budget.cjs'), 'utf8');
assert.equal(source.split('main().catch').length, 2);
const account = 'billingAccounts/fixture';
const project = 'projects/145034183638';
const name = 'LexiQuest 30-participant field trial';
const target = { name: `${account}/budgets/target`, displayName: name, budgetFilter: { projects: [project], calendarPeriod: 'MONTH' }, etag: 'fixture-etag' };
async function run(pages, mutate = x => x) {
  const calls = [], writes = [];
  const context = {
    process: { env: { APPDATA: 'fixture' }, stdout: { write() {} }, stderr: { write() {} }, exitCode: 0 },
    require(module) {
      if (module === 'node:path') return path;
      if (module === 'node:fs') return { existsSync: () => true, mkdirSync() {}, writeFileSync: (_, text) => writes.push(JSON.parse(text)) };
      if (module.endsWith('requireAuth.js')) return { requireAuth: async () => {} };
      if (module.endsWith('auth.js')) return { getGlobalDefaultAccount: () => ({ user: {}, tokens: {} }) };
      if (module.endsWith('apiv2.js')) return { Client: class {
        constructor(options) { this.billing = options.urlPrefix.includes('cloudbilling.'); }
        async get(url, options) {
          if (this.billing) return { body: { billingEnabled: true, billingAccountName: account } };
          calls.push({ method: 'get', url, options });
          return { body: pages[options.queryParams?.pageToken || 'first'] };
        }
        async patch(url, body) { calls.push({ method: 'patch', url, body }); return { body: mutate({ ...body }) }; }
        async post(url, body) { calls.push({ method: 'post', url, body }); return { body: mutate({ ...body, name: `${account}/budgets/new` }) }; }
      } };
      throw new Error(`Unexpected dependency ${module}`);
    },
  };
  vm.runInNewContext(source.replace('main().catch', 'globalThis.completion = main().catch'), context);
  await context.completion;
  return { calls, writes, failed: context.process.exitCode !== 0 };
}
async function main() {
  const failures = [];
  async function check(label, body) { try { await body(); } catch (e) { failures.push(`${label}: ${e.message}`); } }
  await check('target on later page', async () => {
    const r = await run({ first: { budgets: [], nextPageToken: 'next' }, next: { budgets: [target] } });
    assert.equal(r.failed, false); assert.equal(r.calls.filter(x => x.method === 'get').length, 2);
    assert.equal(r.calls.at(-1).method, 'patch'); assert.equal(r.calls.at(-1).url, '/' + target.name);
  });
  for (const [label, budgets] of [
    ['foreign name collision', [{ ...target, budgetFilter: { projects: ['projects/foreign'] } }]],
    ['duplicate targets', [target, { ...target, name: `${account}/budgets/duplicate` }]],
  ]) await check(label, async () => {
    const r = await run({ first: { budgets } });
    assert.equal(r.failed, true); assert.equal(r.calls.filter(x => x.method !== 'get').length, 0); assert.equal(r.writes.length, 0);
  });
  await check('create after complete empty listing', async () => {
    const r = await run({ first: { budgets: [], nextPageToken: 'next' }, next: { budgets: [] } });
    assert.equal(r.failed, false); assert.equal(r.calls.at(-1).method, 'post'); assert.equal(r.writes.length, 1);
  });
  for (const [label, mutate] of [
    ['wrong project', x => ({ ...x, budgetFilter: { ...x.budgetFilter, projects: ['projects/foreign'] } })],
    ['wrong currency', x => ({ ...x, amount: { specifiedAmount: { currencyCode: 'USD', units: '100' } } })],
    ['wrong amount', x => ({ ...x, amount: { specifiedAmount: { currencyCode: 'THB', units: '200' } } })],
    ['wrong name', x => ({ ...x, name: `${account}/budgets/wrong` })],
    ['forecast threshold', x => ({ ...x, thresholdRules: x.thresholdRules.map(y => ({ ...y, spendBasis: 'FORECASTED_SPEND' })) })],
  ]) await check(label, async () => {
    const r = await run({ first: { budgets: [target] } }, mutate);
    assert.equal(r.failed, true); assert.equal(r.writes.length, 0);
  });
  if (failures.length) throw new Error(failures.join('\n'));
  console.log('PASS: nine budget reconciliation cases; injected clients only, no auth/network/evidence writes');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
