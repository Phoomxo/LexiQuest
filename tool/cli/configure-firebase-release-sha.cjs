"use strict";

const fs = require("node:fs");
const path = require("node:path");

const projectId = "vocab-learning-app-219ef";
const appId = "1:145034183638:android:2c492244dd68e77dbe5a77";
const manifestPath = path.resolve(
  process.argv[2] || "build/field-release/release-manifest.json",
);
if (!fs.existsSync(manifestPath)) {
  throw new Error(`Release manifest is missing: ${manifestPath}`);
}
const manifest = JSON.parse(
  fs.readFileSync(manifestPath, "utf8").replace(/^\uFEFF/, ""),
);
const shaHash = String(
  manifest.artifact?.signingCertificateSha256 || "",
).toUpperCase();
if (!/^[A-F0-9]{64}$/.test(shaHash)) {
  throw new Error("Release manifest certificate SHA-256 is invalid.");
}

const npmRoot = path.join(process.env.APPDATA || "", "npm", "node_modules");
if (!fs.existsSync(npmRoot)) {
  throw new Error(`Global npm module directory is missing: ${npmRoot}`);
}
const apps = require(path.join(
  npmRoot,
  "firebase-tools",
  "lib",
  "management",
  "apps.js",
));
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
  const existing = await apps.listAppAndroidSha(projectId, appId);
  let certificate = existing.find(
    (candidate) =>
      String(candidate.shaHash || "")
        .replaceAll(":", "")
        .toUpperCase() === shaHash,
  );
  let created = false;
  if (!certificate) {
    certificate = await apps.createAppAndroidSha(projectId, appId, {
      shaHash,
      certType: apps.ShaCertificateType.SHA_256,
    });
    created = true;
  }

  const evidenceDirectory = path.resolve("field/evidence/cloud");
  fs.mkdirSync(evidenceDirectory, { recursive: true });
  const evidence = {
    schemaVersion: 1,
    recordedAtUtc: new Date().toISOString(),
    projectId,
    appId,
    packageName: "com.lexiquest.app",
    certificateName: certificate.name,
    shaHash,
    certType: certificate.certType,
    created,
  };
  fs.writeFileSync(
    path.join(evidenceDirectory, "firebase-release-sha.json"),
    `${JSON.stringify(evidence, null, 2)}\n`,
    "utf8",
  );
  process.stdout.write(
    `Firebase release SHA-256 ${created ? "registered" : "already registered"}.\n`,
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
