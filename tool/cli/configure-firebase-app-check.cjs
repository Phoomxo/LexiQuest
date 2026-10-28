"use strict";

const fs = require("node:fs");
const path = require("node:path");

const projectId = "vocab-learning-app-219ef";
const projectNumber = "145034183638";
const appId = "1:145034183638:android:2c492244dd68e77dbe5a77";
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

const resourceName =
  `projects/${projectNumber}/apps/${appId}/playIntegrityConfig`;
const desired = {
  name: resourceName,
  tokenTtl: "3600s",
  appIntegrity: {
    // The 30-person APK is distributed directly, outside Google Play.
    allowUnrecognizedVersion: true,
  },
  deviceIntegrity: {
    minDeviceRecognitionLevel: "MEETS_DEVICE_INTEGRITY",
  },
  accountDetails: {
    requireLicensed: false,
  },
};

function normalized(config) {
  return {
    tokenTtl: config.tokenTtl || "3600s",
    allowUnrecognizedVersion:
      config.appIntegrity?.allowUnrecognizedVersion === true,
    minDeviceRecognitionLevel:
      config.deviceIntegrity?.minDeviceRecognitionLevel ||
      "DEVICE_RECOGNITION_LEVEL_UNSPECIFIED",
    requireLicensed: config.accountDetails?.requireLicensed === true,
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
    urlPrefix: "https://firebaseappcheck.googleapis.com",
    apiVersion: "v1",
  });

  const response = await client.patch(`/${resourceName}`, desired, {
    queryParams: {
      updateMask:
        "tokenTtl,appIntegrity,deviceIntegrity,accountDetails",
    },
    timeout: 30000,
  });
  const actual = normalized(response.body);
  const expected = normalized(desired);
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new Error("App Check Play Integrity configuration did not reconcile.");
  }

  const evidenceDirectory = path.resolve("field/evidence/cloud");
  fs.mkdirSync(evidenceDirectory, { recursive: true });
  const evidence = {
    schemaVersion: 1,
    recordedAtUtc: new Date().toISOString(),
    projectId,
    projectNumber,
    appId,
    packageName: "com.lexiquest.app",
    provider: "PLAY_INTEGRITY",
    distribution: "OFF_PLAY",
    ...actual,
    enforcement: "NOT_ENABLED_UNTIL_PHYSICAL_DEVICE_ACCEPTANCE",
  };
  fs.writeFileSync(
    path.join(evidenceDirectory, "firebase-app-check.json"),
    `${JSON.stringify(evidence, null, 2)}\n`,
    "utf8",
  );
  process.stdout.write("Firebase App Check Play Integrity configured.\n");
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
