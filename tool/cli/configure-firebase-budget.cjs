"use strict";

const fs = require("node:fs");
const path = require("node:path");

const projectId = "vocab-learning-app-219ef";
const projectNumber = "145034183638";
const displayName = "LexiQuest 30-participant field trial";
const monthlyAmountThb = "100";
const npmRoot = path.join(process.env.APPDATA || "", "npm", "node_modules");
if (!fs.existsSync(npmRoot)) {
  throw new Error(`Global npm module directory is missing: ${npmRoot}`);
}

const auth = require(path.join(
  npmRoot,
  "firebase-tools",
  "lib",
  "auth.js",
));
const { requireAuth } = require(path.join(
  npmRoot,
  "firebase-tools",
  "lib",
  "requireAuth.js",
));
const { Client } = require(path.join(
  npmRoot,
  "firebase-tools",
  "lib",
  "apiv2.js",
));

async function main() {
  const account = auth.getGlobalDefaultAccount();
  if (!account) {
    throw new Error("Firebase CLI is not authenticated.");
  }
  await requireAuth({
    project: projectId,
    user: account.user,
    tokens: account.tokens,
  });

  const billingClient = new Client({
    urlPrefix: "https://cloudbilling.googleapis.com",
    apiVersion: "v1",
  });
  const billingInfo = (
    await billingClient.get(`/projects/${projectId}/billingInfo`, {
      timeout: 30000,
    })
  ).body;
  const evidenceDirectory = path.resolve("field/evidence/cloud");
  fs.mkdirSync(evidenceDirectory, { recursive: true });
  if (!billingInfo.billingEnabled || !billingInfo.billingAccountName) {
    const evidence = {
      schemaVersion: 1,
      recordedAtUtc: new Date().toISOString(),
      projectId,
      projectNumber,
      billingEnabled: false,
      budgetAlertsConfigured: false,
      budgetAlertsNotApplicable: true,
      billingMode: "noBillingAccount",
      reason:
        "The project cannot incur paid Firebase charges while Cloud Billing is disabled.",
    };
    fs.writeFileSync(
      path.join(evidenceDirectory, "firebase-budget.json"),
      `${JSON.stringify(evidence, null, 2)}\n`,
      "utf8",
    );
    process.stdout.write(
      "Firebase billing is disabled; spend alerts are not applicable.\n",
    );
    return;
  }
  const billingAccountName = billingInfo.billingAccountName;
  const budgetClient = new Client({
    urlPrefix: "https://billingbudgets.googleapis.com",
    apiVersion: "v1",
  });
  const budgets = [];
  const seenTokens = new Set();
  let pageToken;
  do {
    const listed = (await budgetClient.get(`/${billingAccountName}/budgets`, {
      timeout: 30000,
      queryParams: pageToken ? { pageToken } : {},
    })).body;
    if (!listed || (listed.budgets !== undefined && !Array.isArray(listed.budgets))) {
      throw new Error("Invalid budget listing response.");
    }
    budgets.push(...(listed.budgets || []));
    pageToken = listed.nextPageToken;
    if (pageToken) {
      if (typeof pageToken !== "string" || seenTokens.has(pageToken)) {
        throw new Error("Budget pagination did not advance.");
      }
      seenTokens.add(pageToken);
    }
  } while (pageToken);
  const sameName = budgets.filter(budget => budget.displayName === displayName);
  if (sameName.length > 1 || sameName.some(budget =>
    budget.budgetFilter?.projects?.length !== 1 ||
    budget.budgetFilter.projects[0] !== `projects/${projectNumber}`)) {
    throw new Error("Budget identity is ambiguous or belongs to another project.");
  }
  const existing = sameName[0];
  if (existing && (!existing.name?.startsWith(`${billingAccountName}/budgets/`) || !existing.etag)) {
    throw new Error("Existing budget resource identity or concurrency token is missing.");
  }

  const body = {
    displayName,
    budgetFilter: {
      projects: [`projects/${projectNumber}`],
      calendarPeriod: "MONTH",
    },
    amount: {
      specifiedAmount: {
        currencyCode: "THB",
        units: monthlyAmountThb,
      },
    },
    thresholdRules: [0.5, 0.8, 1.0].map((thresholdPercent) => ({
      thresholdPercent,
      spendBasis: "CURRENT_SPEND",
    })),
    allUpdatesRule: {
      disableDefaultIamRecipients: false,
    },
  };

  let result;
  let operation;
  if (existing) {
    result = (
      await budgetClient.patch(`/${existing.name}`, {
        ...body,
        name: existing.name,
        etag: existing.etag,
      }, {
        queryParams: { updateMask: "*" },
        timeout: 30000,
      })
    ).body;
    operation = "updated";
  } else {
    result = (
      await budgetClient.post(`/${billingAccountName}/budgets`, body, {
        timeout: 30000,
      })
    ).body;
    operation = "created";
  }

  const thresholds = (result.thresholdRules || [])
    .map((rule) => Number(rule.thresholdPercent))
    .sort();
  if (JSON.stringify(thresholds) !== JSON.stringify([0.5, 0.8, 1]) ||
      result.thresholdRules.some(rule => rule.spendBasis !== "CURRENT_SPEND") ||
      result.displayName !== displayName ||
      !result.name?.startsWith(`${billingAccountName}/budgets/`) ||
      (existing && result.name !== existing.name) ||
      result.budgetFilter?.projects?.length !== 1 ||
      result.budgetFilter.projects[0] !== `projects/${projectNumber}` ||
      result.budgetFilter.calendarPeriod !== "MONTH" ||
      result.amount?.specifiedAmount?.currencyCode !== "THB" ||
      String(result.amount.specifiedAmount.units) !== monthlyAmountThb ||
      (result.amount.specifiedAmount.nanos || 0) !== 0 ||
      result.allUpdatesRule?.disableDefaultIamRecipients !== false) {
    throw new Error("Budget identity, amount, period or alert policy did not reconcile.");
  }

  const evidence = {
    schemaVersion: 1,
    recordedAtUtc: new Date().toISOString(),
    projectId,
    projectNumber,
    budgetName: result.name,
    displayName: result.displayName,
    amount: result.amount,
    thresholdRules: result.thresholdRules,
    defaultIamRecipientsEnabled:
      result.allUpdatesRule?.disableDefaultIamRecipients !== true,
    billingEnabled: true,
    budgetAlertsConfigured: true,
    budgetAlertsNotApplicable: false,
    billingMode: "budgeted",
    operation,
    warning: "A budget sends alerts; it is not a hard spending cap.",
  };
  fs.writeFileSync(
    path.join(evidenceDirectory, "firebase-budget.json"),
    `${JSON.stringify(evidence, null, 2)}\n`,
    "utf8",
  );
  process.stdout.write(
    `Firebase budget ${operation} with 50/80/100 actual-spend alerts.\n`,
  );
}

main().catch((error) => {
  const original = error.original || {};
  const details = [
    error.message,
    original.message,
    original.status ? `HTTP ${original.status}` : "",
    original.context?.body?.error?.message,
  ].filter(Boolean);
  process.stderr.write(`${[...new Set(details)].join(" | ")}\n`);
  process.exitCode = 1;
});
