"use strict";

const fs = require("node:fs");
const path = require("node:path");

const mode = process.argv[2] || "status";
if (!["enable", "disable", "status"].includes(mode)) {
  throw new Error(
    "Usage: set-firebase-app-check-enforcement.cjs enable|disable|status",
  );
}

const projectId = "vocab-learning-app-219ef";
const projectNumber = "145034183638";
const serviceId = "firestore.googleapis.com";
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

const resourcePath =
  `/projects/${projectNumber}/services/${serviceId}`;

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
    urlPrefix: "https://firebaseappcheck.googleapis.com",
    apiVersion: "v1",
  });

  let response;
  if (mode === "status") {
    response = await client.get(resourcePath, { timeout: 30000 });
  } else {
    const enforcementMode = mode === "enable" ? "ENFORCED" : "UNENFORCED";
    response = await client.patch(
      resourcePath,
      {
        name: `projects/${projectNumber}/services/${serviceId}`,
        enforcementMode,
      },
      {
        queryParams: { updateMask: "enforcementMode" },
        timeout: 30000,
      },
    );
  }

  const enforcementMode = response.body.enforcementMode || "UNSPECIFIED";
  const expected =
    mode === "enable" ? "ENFORCED" :
    mode === "disable" ? "UNENFORCED" :
    enforcementMode;
  if (enforcementMode !== expected) {
    throw new Error("App Check enforcement state did not reconcile.");
  }

  const evidenceDirectory = path.resolve("field/evidence/cloud");
  fs.mkdirSync(evidenceDirectory, { recursive: true });
  const evidence = {
    schemaVersion: 1,
    recordedAtUtc: new Date().toISOString(),
    projectId,
    projectNumber,
    serviceId,
    operation: mode,
    enforcementMode,
  };
  fs.writeFileSync(
    path.join(
      evidenceDirectory,
      `firebase-app-check-enforcement-${mode}-${Date.now()}.json`,
    ),
    `${JSON.stringify(evidence, null, 2)}\n`,
    "utf8",
  );
  process.stdout.write(
    `Firebase App Check Firestore enforcement: ${enforcementMode}.\n`,
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
