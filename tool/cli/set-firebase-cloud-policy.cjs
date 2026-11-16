"use strict";

const fs = require("node:fs");
const path = require("node:path");

const mode = process.argv[2] || "status";
if (!["enable", "disable", "status"].includes(mode)) {
  throw new Error("Usage: set-firebase-cloud-policy.cjs enable|disable|status");
}
const projectId = "vocab-learning-app-219ef";
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

const documentPath =
  `/projects/${projectId}/databases/(default)/documents/app_control/field`;

function decode(document) {
  return {
    schemaVersion: Number(document.fields?.schemaVersion?.integerValue),
    cloudSyncEnabled:
      document.fields?.cloudSyncEnabled?.booleanValue === true,
  };
}

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
  const client = new Client({
    urlPrefix: "https://firestore.googleapis.com",
    apiVersion: "v1",
  });

  let response;
  if (mode === "status") {
    response = await client.get(documentPath, { timeout: 30000 });
  } else {
    const enabled = mode === "enable";
    response = await client.patch(documentPath, {
      fields: {
        schemaVersion: { integerValue: "1" },
        cloudSyncEnabled: { booleanValue: enabled },
      },
    }, {
      timeout: 30000,
    });
  }
  const policy = decode(response.body);
  if (
    policy.schemaVersion !== 1 ||
    (mode === "enable" && policy.cloudSyncEnabled !== true) ||
    (mode === "disable" && policy.cloudSyncEnabled !== false)
  ) {
    throw new Error("Cloud sync policy did not reconcile.");
  }

  const evidenceDirectory = path.resolve("field/evidence/cloud");
  fs.mkdirSync(evidenceDirectory, { recursive: true });
  const record = {
    schemaVersion: 1,
    recordedAtUtc: new Date().toISOString(),
    projectId,
    document: "app_control/field",
    operation: mode,
    cloudSyncEnabled: policy.cloudSyncEnabled,
  };
  fs.writeFileSync(
    path.join(
      evidenceDirectory,
      `cloud-policy-${mode}-${Date.now()}.json`,
    ),
    `${JSON.stringify(record, null, 2)}\n`,
    "utf8",
  );
  process.stdout.write(
    `Firebase cloud sync policy: ${policy.cloudSyncEnabled ? "enabled" : "disabled"}.\n`,
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
