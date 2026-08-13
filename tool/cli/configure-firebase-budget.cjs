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
  const listed = (
    await budgetClient.get(`/${billingAccountName}/budgets`, {
      timeout: 30000,
    })
  ).body;
  const existing = (listed.budgets || []).find(
    (budget) => budget.displayName === displayName,
  );

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
  if (JSON.stringify(thresholds) !== JSON.stringify([0.5, 0.8, 1])) {
    throw new Error("Budget thresholds did not reconcile to 50/80/100.");
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
