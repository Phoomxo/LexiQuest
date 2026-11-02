"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const vm = require("node:vm");
const { test } = require("node:test");

const cliPath = path.resolve(__dirname, "../configure-firebase-budget.cjs");
const cliModule = { exports: {} };
vm.runInNewContext(fs.readFileSync(cliPath, "utf8"), {
  require(name) {
    assert.ok(name.startsWith("node:"), "Import must not load Firebase SDK or authenticate");
    return require(name);
  },
  module: cliModule,
  exports: cliModule.exports,
  process,
  __dirname: path.dirname(cliPath),
}, { filename: cliPath });
const { runBudget, runCli } = cliModule.exports;

const projectId = "vocab-learning-app-219ef";
const projectNumber = "145034183638";
const accountName = "billingAccounts/AAAAAA-BBBBBB-CCCCCC";
const displayName = "LexiQuest 30-participant field trial";
const clone = (value) => JSON.parse(JSON.stringify(value));

function expectedBudget(currency = "USD") {
  return {
    name: `${accountName}/budgets/synthetic-budget-1`,
    displayName,
    budgetFilter: { projects: [`projects/${projectNumber}`], calendarPeriod: "MONTH" },
    amount: { specifiedAmount: { currencyCode: currency, units: currency === "THB" ? "500" : "15" } },
    thresholdRules: [0.5, 0.8, 1].map((thresholdPercent) => ({ thresholdPercent, spendBasis: "CURRENT_SPEND" })),
    notificationsRule: { disableDefaultIamRecipients: false, enableProjectLevelRecipients: false },
  };
}

function fixture(t, overrides = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "lq-budget-unit-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const state = {
    billingInfo: { projectId, billingEnabled: true, billingAccountName: accountName },
    account: { name: accountName, open: true, currencyCode: "USD" },
    project: { projectId, projectNumber, lifecycleState: "ACTIVE" },
    budgets: [], calls: [], ...overrides,
  };
  const billingClient = {
    async get(resource) {
      state.calls.push(["billingGet", resource]);
      if (state.billingError) throw state.billingError;
      return { body: clone(resource.endsWith("/billingInfo") ? state.billingInfo : state.account) };
    },
  };
  const projectClient = {
    async get(resource) {
      state.calls.push(["projectGet", resource]);
      return { body: clone(state.project) };
    },
  };
  const budgetClient = {
    async get(resource, options) {
      state.calls.push(["budgetGet", resource, options]);
      if (state.get) return state.get(resource, options, state);
      if (resource.endsWith("/budgets")) return { body: { budgets: clone(state.budgets) } };
      return { body: clone(state.readback || state.budgets.find((budget) => `/${budget.name}` === resource)) };
    },
    async post(resource, body, options) {
      state.calls.push(["post", resource, clone(body), options]);
      if (state.post) return state.post(resource, body, state);
      const created = { ...clone(body), name: `${accountName}/budgets/synthetic-budget-1` };
      state.budgets.push(created);
      return { body: clone(created) };
    },
    async patch() { state.calls.push(["patch"]); throw new Error("PATCH is forbidden"); },
  };
  const options = { billingClient, projectClient, budgetClient, evidenceDirectory: directory };
  return { state, options, directory, run: (extra = {}) => runBudget({ ...options, ...extra }) };
}

const writes = (state) => state.calls.filter(([method]) => method === "post" || method === "patch");

test("import is inert and default mode only checks", async (t) => {
  assert.equal(typeof runBudget, "function");
  const f = fixture(t);
  const evidence = await f.run();
  assert.equal(evidence.budgetAlertsConfigured, false);
  assert.equal(evidence.operation, "check-only");
  assert.equal(writes(f.state).length, 0);
});

for (const currency of ["THB", "USD"]) {
  test(`creation uses actual linked-account ${currency} currency and exact readback`, async (t) => {
    const f = fixture(t, { account: { name: accountName, open: true, currencyCode: currency } });
    const evidence = await f.run({ apply: true });
    const post = writes(f.state)[0];
    assert.equal(post[2].amount.specifiedAmount.currencyCode, currency);
    assert.equal(post[2].amount.specifiedAmount.units, currency === "THB" ? "500" : "15");
    assert.equal(evidence.operation, "created");
    assert.equal(evidence.budgetAlertsConfigured, true);
    assert.match(evidence.warning, /not a hard spending cap/);
    assert.equal(f.state.calls.at(-1)[1], `/${accountName}/budgets/synthetic-budget-1`);
    const before = fs.readFileSync(path.join(f.directory, "firebase-budget.json"), "utf8");
    const rerun = await f.run({ apply: true });
    assert.equal(rerun.operation, "reused");
    assert.equal(writes(f.state).length, 1);
    assert.equal(fs.readFileSync(path.join(f.directory, "firebase-budget.json"), "utf8"), before);
  });
}

test("same-name currency mismatch is preserved without PATCH or POST", async (t) => {
  const f = fixture(t, { budgets: [expectedBudget("THB")] });
  await assert.rejects(f.run({ apply: true }), { code: "BUDGET_CONFLICT" });
  assert.equal(writes(f.state).length, 0);
});

for (const change of [
  (f) => { f.state.account.currencyCode = "EUR"; },
  (f) => { delete f.state.account.currencyCode; },
  (f) => { f.state.account.open = false; },
  (f) => { f.state.account.open = "true"; },
  (f) => { f.state.account.name = "billingAccounts/DDDDDD-EEEEEE-FFFFFF"; },
  (f) => { f.state.billingInfo.billingEnabled = "true"; },
  (f) => { f.state.billingInfo.billingEnabled = "false"; },
  (f) => { f.state.billingInfo.billingEnabled = false; },
  (f) => { f.state.billingInfo.billingEnabled = false; f.state.billingInfo.billingAccountName = null; },
  (f) => { f.state.billingInfo.billingEnabled = false; f.state.billingInfo.billingAccountName = 0; },
  (f) => { f.state.billingInfo.billingEnabled = false; f.state.billingInfo.billingAccountName = false; },
  (f) => { delete f.state.billingInfo.billingEnabled; },
  (f) => { f.state.billingInfo.billingAccountName = "billingAccounts/../../other"; },
  (f) => { delete f.state.billingInfo.billingAccountName; },
  (f) => { f.state.billingInfo.projectId = "another-project"; },
  (f) => { f.state.project.projectNumber = "999999999999"; },
  (f) => { f.state.project.projectId = "another-project"; },
  (f) => { f.state.project.lifecycleState = "DELETE_REQUESTED"; },
]) {
  test(`invalid authority blocks all mutations ${change.toString()}`, async (t) => {
    const f = fixture(t); change(f);
    await assert.rejects(f.run({ apply: true }));
    assert.equal(writes(f.state).length, 0);
  });
}

test("unlinked check keeps legacy N/A shape but apply fails", async (t) => {
  const f = fixture(t, { billingInfo: { projectId, billingEnabled: false } });
  const evidence = await f.run();
  assert.equal(evidence.budgetAlertsNotApplicable, true);
  assert.equal(evidence.billingMode, "noBillingAccount");
  assert.equal(evidence.budgetAlertsConfigured, false);
  await assert.rejects(f.run({ apply: true }), { code: "BILLING_UNAVAILABLE" });
  assert.equal(writes(f.state).length, 0);
});

test("permission errors never expose Cloud payloads or credentials", async (t) => {
  const secret = "secret-person@example.test token-super-private AAAAAA-BBBBBB-CCCCCC";
  const f = fixture(t, { billingError: new Error(secret) });
  await assert.rejects(f.run({ apply: true }), (error) => {
    assert.equal(error.code, "CLOUD_OPERATION_FAILED");
    assert.ok(!String(error.stack).includes(secret));
    return true;
  });
  assert.equal(writes(f.state).length, 0);
});

test("all list pages are read before reusing a matching budget", async (t) => {
  const budget = expectedBudget();
  const f = fixture(t, { get: (resource, options) => {
    if (!resource.endsWith("/budgets")) return { body: clone(budget) };
    return options?.queryParams?.pageToken === "synthetic-page-2"
      ? { body: { budgets: [budget] } }
      : { body: { budgets: [{ ...budget, displayName: "Unrelated" }], nextPageToken: "synthetic-page-2" } };
  } });
  const evidence = await f.run({ apply: true });
  assert.equal(evidence.operation, "reused");
  assert.equal(writes(f.state).length, 0);
  assert.ok(f.state.calls.some((call) => call[2]?.queryParams?.pageToken === "synthetic-page-2"));
});

test("same-name collisions across pages block mutation", async (t) => {
  const budget = expectedBudget();
  const f = fixture(t, { get: (_resource, options) => ({ body: options?.queryParams?.pageToken
    ? { budgets: [{ ...budget, name: `${accountName}/budgets/synthetic-budget-2` }] }
    : { budgets: [budget], nextPageToken: "synthetic-page-2" } }) });
  await assert.rejects(f.run({ apply: true }), { code: "BUDGET_CONFLICT" });
  assert.equal(writes(f.state).length, 0);
});

test("repeated page tokens and invalid list responses fail closed", async (t) => {
  for (const body of [{ budgets: [], nextPageToken: "repeat" }, { budgets: "invalid" }]) {
    const f = fixture(t, { get: () => ({ body }) });
    await assert.rejects(f.run({ apply: true }), { code: "INVALID_CLOUD_RESPONSE" });
    assert.equal(writes(f.state).length, 0);
  }
});

for (const drift of [
  (b) => { b.budgetFilter.projects = ["projects/999999999999"]; },
  (b) => { b.budgetFilter.projects.push("projects/999999999999"); },
  (b) => { b.budgetFilter.calendarPeriod = "YEAR"; },
  (b) => { b.budgetFilter.services = ["services/synthetic-service"]; },
  (b) => { b.budgetFilter.labels = { synthetic: ["restricted"] }; },
  (b) => { b.budgetFilter.customPeriod = { startDate: { year: 2026, month: 11, day: 1 } }; },
  (b) => { b.budgetFilter.creditTypesTreatment = "EXCLUDE_ALL_CREDITS"; },
  (b) => { b.amount.specifiedAmount.currencyCode = "THB"; },
  (b) => { b.amount.specifiedAmount.units = "16"; },
  (b) => { b.amount.specifiedAmount.nanos = 1; },
  (b) => { b.amount.specifiedAmount.nanos = "0"; },
  (b) => { b.thresholdRules[0].spendBasis = "FORECASTED_SPEND"; },
  (b) => { b.thresholdRules[0].thresholdPercent = 0.4; },
  (b) => { b.notificationsRule.disableDefaultIamRecipients = true; },
  (b) => { b.notificationsRule.disableDefaultIamRecipients = "false"; },
  (b) => { b.notificationsRule.enableProjectLevelRecipients = true; },
  (b) => { b.notificationsRule.enableProjectLevelRecipients = "false"; },
  (b) => { b.notificationsRule.monitoringNotificationChannels = ["projects/x/notificationChannels/y"]; },
  (b) => { b.notificationsRule.pubsubTopic = "projects/x/topics/y"; },
  (b) => { b.allUpdatesRule = { disableDefaultIamRecipients: false }; },
  (b) => { b.ownershipScope = "PROJECT"; },
  (b) => { b.spendCap = { enforcementType: "ALL_SERVICES" }; },
  (b) => { b.name = "billingAccounts/DDDDDD-EEEEEE-FFFFFF/budgets/other"; },
]) {
  test(`existing conflicting budget remains untouched ${drift.toString()}`, async (t) => {
    const budget = expectedBudget(); drift(budget);
    const f = fixture(t, { budgets: [budget] });
    await assert.rejects(f.run({ apply: true }), { code: "BUDGET_CONFLICT" });
    assert.equal(writes(f.state).length, 0);
  });
  test(`actual readback drift is rejected ${drift.toString()}`, async (t) => {
    const readback = expectedBudget(); drift(readback);
    const f = fixture(t, { budgets: [expectedBudget()], readback });
    await assert.rejects(f.run({ apply: true }), { code: "BUDGET_READBACK_MISMATCH" });
    assert.equal(writes(f.state).length, 0);
    assert.ok(!fs.existsSync(path.join(f.directory, "firebase-budget.json")));
  });
}

test("lost POST acknowledgement reconciles fresh list and reads actual resource", async (t) => {
  const f = fixture(t, { post: (_resource, body, state) => {
    state.budgets.push({ ...clone(body), name: `${accountName}/budgets/synthetic-budget-1` });
    throw new Error("synthetic lost acknowledgement with private payload");
  } });
  const evidence = await f.run({ apply: true });
  assert.equal(evidence.operation, "reconciled");
  assert.equal(writes(f.state)[0][3].retries, 0);
  await f.run({ apply: true });
  assert.equal(writes(f.state).length, 1);
});

test("uncertain POST is never repeated even after a later invocation", async (t) => {
  const f = fixture(t, { post: () => { throw new Error("synthetic timeout secret-token"); } });
  await assert.rejects(f.run({ apply: true }), { code: "CREATION_UNCERTAIN" });
  await assert.rejects(f.run({ apply: true }), { code: "CREATION_UNCERTAIN" });
  assert.equal(writes(f.state).length, 1);
  f.state.budgets.push(expectedBudget());
  assert.equal((await f.run({ apply: true })).operation, "reused");
  assert.equal(writes(f.state).length, 1);
});

test("POST response is never accepted without actual readback", async (t) => {
  const f = fixture(t, { post: () => ({ body: expectedBudget() }) });
  await assert.rejects(f.run({ apply: true }));
  assert.equal(writes(f.state).length, 1);
  assert.ok(!fs.existsSync(path.join(f.directory, "firebase-budget.json")));
});

test("check-only rejects stale success evidence when its budget is missing", async (t) => {
  const f = fixture(t, { budgets: [expectedBudget()] });
  await f.run();
  const filename = path.join(f.directory, "firebase-budget.json");
  const prior = fs.readFileSync(filename, "utf8");
  f.state.budgets = [];
  await assert.rejects(f.run(), { code: "EVIDENCE_CONFLICT" });
  assert.equal(fs.readFileSync(filename, "utf8"), prior);
  assert.equal(writes(f.state).length, 0);
});

test("check-only reports unresolved creation without offering another POST", async (t) => {
  const f = fixture(t, { post: () => { throw new Error("synthetic lost acknowledgement"); } });
  await assert.rejects(f.run({ apply: true }), { code: "CREATION_UNCERTAIN" });
  await assert.rejects(f.run(), { code: "CREATION_UNCERTAIN" });
  assert.equal(writes(f.state).length, 1);
});

test("unrelated prior evidence is preserved before any creation", async (t) => {
  const f = fixture(t);
  const prior = "{\"schemaVersion\":1,\"uncertain\":true}\n";
  fs.writeFileSync(path.join(f.directory, "firebase-budget.json"), prior);
  await assert.rejects(f.run({ apply: true }), { code: "EVIDENCE_CONFLICT" });
  assert.equal(writes(f.state).length, 0);
  assert.equal(fs.readFileSync(path.join(f.directory, "firebase-budget.json"), "utf8"), prior);
});

test("CLI arguments require --apply and keep public output sanitized", async (t) => {
  const f = fixture(t);
  let stdout = ""; let stderr = ""; let clientLoads = 0;
  const dependencies = {
    createClients: async () => { clientLoads++; return f.options; },
    stdout: { write: (text) => { stdout += text; } },
    stderr: { write: (text) => { stderr += text; } },
  };
  assert.equal(await runCli(["--check-only", "--evidence-directory", f.directory], dependencies), 0);
  assert.equal(writes(f.state).length, 0);
  assert.ok(!stdout.includes(accountName));
  assert.ok(!stdout.includes("@"));
  assert.match(stdout, /not a hard spending cap/);
  assert.equal(await runCli(["--apply", "--check-only"], dependencies), 1);
  assert.equal(clientLoads, 1);
  assert.ok(!stderr.includes(accountName));
  assert.equal(await runCli(["--help"], dependencies), 0);
  assert.equal(clientLoads, 1);
});

test("known account ownership and wire defaults are preserved without editing", async (t) => {
  for (const ownershipScope of [undefined, "OWNERSHIP_SCOPE_UNSPECIFIED", "ALL_USERS", "BILLING_ACCOUNT"]) {
    const budget = expectedBudget();
    if (ownershipScope) budget.ownershipScope = ownershipScope;
    budget.amount.specifiedAmount.nanos = 0;
    budget.budgetFilter.creditTypesTreatment = "INCLUDE_ALL_CREDITS";
    budget.budgetFilter.services = [];
    delete budget.notificationsRule;
    const f = fixture(t, { budgets: [budget] });
    assert.equal((await f.run({ apply: true })).operation, "reused");
    assert.equal(writes(f.state).length, 0);
  }
});

test("SDK logging is silenced before authentication and raw failures stay private", async () => {
  const logger = { silent: false };
  const sandboxModule = { exports: {} };
  const sdkCalls = [];
  const source = fs.readFileSync(cliPath, "utf8");
  vm.runInNewContext(source, {
    module: sandboxModule, exports: sandboxModule.exports, process,
    require(name) {
      if (name.startsWith("node:")) return require(name);
      sdkCalls.push(name);
      if (name.endsWith("logger.js")) return { logger };
      assert.equal(logger.silent, true);
      if (name.endsWith("requireAuth.js")) return { requireAuth: async () => { throw new Error("private-token private-user@example.test AAAAAA-BBBBBB-CCCCCC"); } };
      if (name.endsWith("auth.js")) return { getGlobalDefaultAccount: () => ({ user: {}, tokens: {} }) };
      if (name.endsWith("apiv2.js")) return { Client: class {} };
      throw new Error("Unexpected SDK import");
    },
  });
  assert.equal(sdkCalls.length, 0);
  let output = "";
  const stream = { write: (text) => { output += text; } };
  assert.equal(await sandboxModule.exports.runCli([], { stdout: stream, stderr: stream }), 1);
  assert.ok(!/private-token|@|AAAAAA/.test(output));
});
