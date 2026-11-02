"use strict";

const fs = require("node:fs");
const path = require("node:path");
const { createHash } = require("node:crypto");

const projectId = "vocab-learning-app-219ef";
const projectNumber = "145034183638";
const displayName = "LexiQuest 30-participant field trial";
const monthlyAmountThb = "500";
const monthlyAmounts = { THB: monthlyAmountThb, USD: "15" };
const warning = "A budget sends alerts; it is not a hard spending cap.";
const timeout = 30000;

class BudgetError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function fail(code, message) {
  throw new BudgetError(code, message);
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function onlyKeys(value, keys) {
  return isObject(value) && Object.keys(value).every((key) => keys.includes(key));
}

function desiredBudget(currencyCode) {
  return {
    displayName,
    ownershipScope: "BILLING_ACCOUNT",
    budgetFilter: {
      projects: [`projects/${projectNumber}`],
      calendarPeriod: "MONTH",
    },
    amount: { specifiedAmount: { currencyCode, units: monthlyAmounts[currencyCode] } },
    thresholdRules: [0.5, 0.8, 1.0].map((thresholdPercent) => ({
      thresholdPercent,
      spendBasis: "CURRENT_SPEND",
    })),
    notificationsRule: {
      disableDefaultIamRecipients: false,
      enableProjectLevelRecipients: false,
    },
  };
}

function matchesBudget(budget, desired, billingAccountName) {
  if (!onlyKeys(budget, ["name", "displayName", "budgetFilter", "amount", "thresholdRules", "notificationsRule", "etag", "ownershipScope"])) return false;
  if (typeof budget.name !== "string" || !budget.name.startsWith(`${billingAccountName}/budgets/`)) return false;
  if (!/^[A-Za-z0-9_-]+$/.test(budget.name.slice(`${billingAccountName}/budgets/`.length))) return false;
  if (budget.displayName !== desired.displayName) return false;
  if (budget.ownershipScope !== undefined && !["OWNERSHIP_SCOPE_UNSPECIFIED", "ALL_USERS", "BILLING_ACCOUNT"].includes(budget.ownershipScope)) return false;
  const filter = budget.budgetFilter;
  if (!onlyKeys(filter, ["projects", "calendarPeriod", "creditTypesTreatment", "creditTypes", "services", "subaccounts", "resourceAncestors", "labels"])) return false;
  if (!Array.isArray(filter.projects) || filter.projects.length !== 1 || filter.projects[0] !== `projects/${projectNumber}` || filter.calendarPeriod !== "MONTH") return false;
  if (filter.creditTypesTreatment !== undefined && filter.creditTypesTreatment !== "INCLUDE_ALL_CREDITS") return false;
  for (const field of ["creditTypes", "services", "subaccounts", "resourceAncestors"]) {
    if (filter[field] !== undefined && (!Array.isArray(filter[field]) || filter[field].length !== 0)) return false;
  }
  if (filter.labels !== undefined && (!isObject(filter.labels) || Object.keys(filter.labels).length !== 0)) return false;
  if (!onlyKeys(budget.amount, ["specifiedAmount"])) return false;
  const money = budget.amount.specifiedAmount;
  if (!onlyKeys(money, ["currencyCode", "units", "nanos"])) return false;
  if (money.currencyCode !== desired.amount.specifiedAmount.currencyCode || money.units !== desired.amount.specifiedAmount.units || (money.nanos !== undefined && money.nanos !== 0)) return false;
  if (!Array.isArray(budget.thresholdRules) || budget.thresholdRules.length !== 3) return false;
  const rules = [...budget.thresholdRules].sort((a, b) => a.thresholdPercent - b.thresholdPercent);
  if (!rules.every((rule, index) => onlyKeys(rule, ["thresholdPercent", "spendBasis"]) && rule.thresholdPercent === desired.thresholdRules[index].thresholdPercent && rule.spendBasis === "CURRENT_SPEND")) return false;
  const updates = budget.notificationsRule === undefined ? {} : budget.notificationsRule;
  if (!onlyKeys(updates, ["disableDefaultIamRecipients", "enableProjectLevelRecipients", "monitoringNotificationChannels", "pubsubTopic", "schemaVersion"])) return false;
  if (updates.disableDefaultIamRecipients !== undefined && updates.disableDefaultIamRecipients !== false) return false;
  if (updates.enableProjectLevelRecipients !== undefined && updates.enableProjectLevelRecipients !== false) return false;
  if (updates.monitoringNotificationChannels !== undefined && (!Array.isArray(updates.monitoringNotificationChannels) || updates.monitoringNotificationChannels.length !== 0)) return false;
  if (updates.pubsubTopic !== undefined && updates.pubsubTopic !== "") return false;
  return updates.schemaVersion === undefined || updates.schemaVersion === "";
}

async function listBudgets(client, billingAccountName) {
  const budgets = [];
  const tokens = new Set();
  let pageToken;
  do {
    const response = await client.get(`/${billingAccountName}/budgets`, {
      timeout,
      ...(pageToken ? { queryParams: { pageToken } } : {}),
    });
    const body = response?.body;
    if (!isObject(body) || (body.budgets !== undefined && !Array.isArray(body.budgets))) fail("INVALID_CLOUD_RESPONSE", "Budget listing was invalid.");
    for (const budget of body.budgets || []) {
      if (!isObject(budget) || typeof budget.displayName !== "string") fail("INVALID_CLOUD_RESPONSE", "Budget listing was invalid.");
      budgets.push(budget);
    }
    pageToken = body.nextPageToken;
    if (pageToken !== undefined && typeof pageToken !== "string") fail("INVALID_CLOUD_RESPONSE", "Budget pagination was invalid.");
    if (pageToken) {
      if (tokens.has(pageToken) || tokens.size >= 1000 || pageToken.length > 4096) fail("INVALID_CLOUD_RESPONSE", "Budget pagination did not finish safely.");
      tokens.add(pageToken);
    }
  } while (pageToken);
  return budgets;
}

function findBudget(budgets, desired, billingAccountName) {
  const matches = budgets.filter((budget) => budget.displayName === displayName);
  if (matches.length > 1 || (matches.length === 1 && !matchesBudget(matches[0], desired, billingAccountName))) {
    fail("BUDGET_CONFLICT", "A same-name budget has conflicting configuration; nothing was changed.");
  }
  return matches[0];
}

function readRecord(filename) {
  try {
    return JSON.parse(fs.readFileSync(filename, "utf8"));
  } catch (error) {
    if (error.code === "ENOENT") return undefined;
    fail("EVIDENCE_CONFLICT", "Existing budget evidence could not be safely reconciled.");
  }
}

function stableEvidence(evidence) {
  const { recordedAtUtc, operation, ...stable } = evidence;
  return JSON.stringify(stable);
}

function saveEvidence(filename, evidence, prior) {
  if (prior !== undefined) {
    if (!isObject(prior) || stableEvidence(prior) !== stableEvidence(evidence)) fail("EVIDENCE_CONFLICT", "Existing budget evidence differs; use a new private evidence directory.");
    return;
  }
  fs.mkdirSync(path.dirname(filename), { recursive: true });
  fs.writeFileSync(filename, `${JSON.stringify(evidence, null, 2)}\n`, { encoding: "utf8", flag: "wx", mode: 0o600 });
}

async function runBudget({ billingClient, projectClient, budgetClient, apply = false, evidenceDirectory = path.resolve("field/evidence/cloud") }) {
  try {
    if (typeof apply !== "boolean") fail("INVALID_ARGUMENT", "Apply must be an explicit boolean.");
    const evidenceFile = path.join(evidenceDirectory, "firebase-budget.json");
    const intentFile = path.join(evidenceDirectory, "firebase-budget-create-intent.json");
    const prior = readRecord(evidenceFile);
    const priorIntent = readRecord(intentFile);
    const billingInfo = (await billingClient.get(`/projects/${projectId}/billingInfo`, { timeout }))?.body;
    if (!isObject(billingInfo) || billingInfo.projectId !== projectId || typeof billingInfo.billingEnabled !== "boolean") fail("INVALID_CLOUD_RESPONSE", "Project billing metadata was invalid.");
    if (billingInfo.billingEnabled === false && (billingInfo.billingAccountName === undefined || billingInfo.billingAccountName === "")) {
      if (apply) fail("BILLING_UNAVAILABLE", "Billing is disabled or unlinked; creation is unavailable.");
      const evidence = {
        schemaVersion: 1,
        recordedAtUtc: new Date().toISOString(),
        projectId,
        projectNumber,
        billingEnabled: false,
        budgetAlertsConfigured: false,
        budgetAlertsNotApplicable: true,
        billingMode: "noBillingAccount",
        reason: "The project cannot incur paid Firebase charges while Cloud Billing is disabled.",
      };
      saveEvidence(evidenceFile, evidence, prior);
      return evidence;
    }
    const billingAccountName = billingInfo.billingAccountName;
    if (billingInfo.billingEnabled !== true || typeof billingAccountName !== "string" || !/^billingAccounts\/[A-Z0-9]{6}-[A-Z0-9]{6}-[A-Z0-9]{6}$/.test(billingAccountName)) fail("BILLING_UNAVAILABLE", "Linked billing account metadata was invalid.");
    const account = (await billingClient.get(`/${billingAccountName}`, { timeout }))?.body;
    if (!isObject(account) || account.name !== billingAccountName || account.open !== true || typeof account.currencyCode !== "string" || !Object.hasOwn(monthlyAmounts, account.currencyCode)) fail("BILLING_UNAVAILABLE", "An open billing account using THB or USD is required.");
    const project = (await projectClient.get(`/projects/${projectId}`, { timeout }))?.body;
    if (!isObject(project) || project.projectId !== projectId || project.projectNumber !== projectNumber || project.lifecycleState !== "ACTIVE") fail("INVALID_CLOUD_RESPONSE", "Actual project identity did not match the pinned budget scope.");
    const desired = desiredBudget(account.currencyCode);
    const identity = createHash("sha256").update(JSON.stringify({ billingAccountName, desired })).digest("hex");
    if (priorIntent !== undefined && (!isObject(priorIntent) || priorIntent.schemaVersion !== 1 || priorIntent.identity !== identity)) fail("EVIDENCE_CONFLICT", "A different creation attempt is recorded; nothing was changed.");
    let existing = findBudget(await listBudgets(budgetClient, billingAccountName), desired, billingAccountName);
    let operation = "reused";
    if (!existing) {
      if (priorIntent !== undefined) fail("CREATION_UNCERTAIN", "A prior creation may still exist; no additional POST was sent.");
      if (prior !== undefined) fail("EVIDENCE_CONFLICT", "Prior evidence exists but its budget is missing; nothing was changed.");
      if (!apply) return {
        schemaVersion: 1, recordedAtUtc: new Date().toISOString(), projectId, projectNumber,
        billingEnabled: true, budgetAlertsConfigured: false, budgetAlertsNotApplicable: false,
        billingMode: "unconfigured", operation: "check-only", warning,
      };
      fs.mkdirSync(evidenceDirectory, { recursive: true });
      fs.writeFileSync(intentFile, `${JSON.stringify({ schemaVersion: 1, identity }, null, 2)}\n`, { encoding: "utf8", flag: "wx", mode: 0o600 });
      try {
        const result = (await budgetClient.post(`/${billingAccountName}/budgets`, desired, { timeout, retries: 0 }))?.body;
        if (!matchesBudget(result, desired, billingAccountName)) fail("BUDGET_READBACK_MISMATCH", "Budget creation acknowledgement was not the requested configuration.");
        existing = result;
        operation = "created";
      } catch {
        try {
          existing = findBudget(await listBudgets(budgetClient, billingAccountName), desired, billingAccountName);
        } catch (error) {
          if (error instanceof BudgetError && error.code === "BUDGET_CONFLICT") throw error;
          fail("CREATION_UNCERTAIN", "Creation outcome could not be reconciled; no additional POST was sent.");
        }
        if (!existing) fail("CREATION_UNCERTAIN", "Creation outcome is uncertain; no additional POST was sent.");
        operation = "reconciled";
      }
    }
    const actual = (await budgetClient.get(`/${existing.name}`, { timeout }))?.body;
    if (!matchesBudget(actual, desired, billingAccountName) || actual.name !== existing.name) fail("BUDGET_READBACK_MISMATCH", "Actual budget readback differed from the complete requested configuration.");
    const evidence = {
      schemaVersion: 1,
      recordedAtUtc: new Date().toISOString(),
      projectId,
      projectNumber,
      budgetName: actual.name,
      displayName: actual.displayName,
      budgetFilter: desired.budgetFilter,
      amount: desired.amount,
      thresholdRules: desired.thresholdRules,
      notificationsRule: desired.notificationsRule,
      defaultIamRecipientsEnabled: true,
      billingEnabled: true,
      budgetAlertsConfigured: true,
      budgetAlertsNotApplicable: false,
      billingMode: "budgeted",
      operation,
      warning,
    };
    saveEvidence(evidenceFile, evidence, prior);
    return evidence;
  } catch (error) {
    if (error instanceof BudgetError) throw error;
    fail("CLOUD_OPERATION_FAILED", "Budget operation failed; check permissions and private Cloud state.");
  }
}

async function createClients() {
  const npmRoot = path.join(process.env.APPDATA || "", "npm", "node_modules");
  const { logger } = require(path.join(npmRoot, "firebase-tools", "lib", "logger.js"));
  logger.silent = true;
  const auth = require(path.join(npmRoot, "firebase-tools", "lib", "auth.js"));
  const { requireAuth } = require(path.join(npmRoot, "firebase-tools", "lib", "requireAuth.js"));
  const { Client } = require(path.join(npmRoot, "firebase-tools", "lib", "apiv2.js"));
  const account = auth.getGlobalDefaultAccount();
  if (!account) fail("AUTH_REQUIRED", "Firebase CLI is not authenticated.");
  await requireAuth({ project: projectId, user: account.user, tokens: account.tokens });
  return {
    billingClient: new Client({ urlPrefix: "https://cloudbilling.googleapis.com", apiVersion: "v1" }),
    projectClient: new Client({ urlPrefix: "https://cloudresourcemanager.googleapis.com", apiVersion: "v1" }),
    budgetClient: new Client({ urlPrefix: "https://billingbudgets.googleapis.com", apiVersion: "v1" }),
  };
}

async function runCli(args = process.argv.slice(2), dependencies = {}) {
  const stdout = dependencies.stdout || process.stdout;
  const stderr = dependencies.stderr || process.stderr;
  try {
    let apply = false;
    let mode;
    let evidenceDirectory = path.resolve("field/evidence/cloud");
    for (let index = 0; index < args.length; index++) {
      const argument = args[index];
      if (argument === "--help" && args.length === 1) {
        stdout.write("Usage: node tool/cli/configure-firebase-budget.cjs [--check-only | --apply] [--evidence-directory PATH]\nDefault checks only. --apply can create one missing budget; existing budgets are never edited.\n" + warning + "\n");
        return 0;
      }
      if (argument === "--apply" || argument === "--check-only") {
        if (mode !== undefined) fail("INVALID_ARGUMENT", "Choose one mode, --check-only or --apply.");
        mode = argument;
        apply = argument === "--apply";
      } else if (argument === "--evidence-directory" && args[index + 1] && !args[index + 1].startsWith("--")) {
        evidenceDirectory = path.resolve(args[++index]);
      } else fail("INVALID_ARGUMENT", "Unknown or incomplete budget CLI argument.");
    }
    const clients = await (dependencies.createClients || createClients)();
    const result = await runBudget({ ...clients, apply, evidenceDirectory });
    const status = result.budgetAlertsNotApplicable ? "Billing is disabled; alerts are not applicable."
      : result.budgetAlertsConfigured ? "Budget verified with 50/80/100 actual-spend alerts."
      : "Check complete; budget is missing. Creation requires --apply.";
    stdout.write(`${status}\n${warning}\n`);
    return 0;
  } catch (error) {
    stderr.write(`${error instanceof BudgetError ? error.message : "Budget operation failed; inspect private configuration and permissions."}\n`);
    return 1;
  }
}

module.exports = { runBudget, runCli };

if (require.main === module) {
  runCli().then((code) => { process.exitCode = code; });
}
