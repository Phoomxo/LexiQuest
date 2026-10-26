"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const repoRoot = path.resolve(__dirname, "../..");
const firebase = JSON.parse(
  fs.readFileSync(path.join(repoRoot, "firebase.json"), "utf8"),
);
const sources = ["/privacy/**", "/delete-account/**", "/field-support/**"];
const expected = new Map([
  ["Referrer-Policy", "no-referrer"],
  ["X-Content-Type-Options", "nosniff"],
  ["Permissions-Policy", "camera=(), microphone=(), geolocation=()"],
]);

for (const source of sources) {
  test(`Firebase Hosting protects ${source}`, () => {
    const rule = firebase.hosting.headers.find((entry) => entry.source === source);
    assert.ok(rule, `missing explicit header rule for ${source}`);
    const headers = new Map(rule.headers.map(({ key, value }) => [key, value]));
    assert.match(
      headers.get("Content-Security-Policy") || "",
      /frame-ancestors 'none'/,
    );
    for (const [key, value] of expected) assert.equal(headers.get(key), value);
  });
}

function readLoader(directory) {
  const html = fs.readFileSync(
    path.join(repoRoot, "hosting", "public", directory, "index.html"),
    "utf8",
  );
  const script = html.match(/<script>([\s\S]*?)<\/script>/)?.[1];
  assert.ok(script, `missing runtime config loader in ${directory}`);
  return script;
}

for (const directory of ["privacy", "delete-account", "field-support"]) {
  test(`${directory} inline runtime config loader parses`, () => {
    assert.doesNotThrow(() => new vm.Script(readLoader(directory)));
  });
}

const loaderCases = [
  ["privacy", "private-support-link", "privateSupportUrl"],
  ["delete-account", "deletion-request-link", "deletionRequestUrl"],
  ["field-support", "private-support-link", "privateSupportUrl"],
];

async function runLoader(directory, linkId, configChanges = {}, policyChanges = {}) {
  const elements = new Map();
  const element = (id) => {
    if (!elements.has(id)) {
      elements.set(id, {
        enabled: false,
        href: "",
        textContent: "",
        removeAttribute(name) {
          if (name === "aria-disabled") this.enabled = true;
        },
      });
    }
    return elements.get(id);
  };
  const config = {
    schemaVersion: 1,
    privacyNoticeUrl: "https://vocab-learning-app-219ef.web.app/privacy/",
    privateSupportUrl: "https://support.lexiquest.test/private-request",
    deletionRequestUrl: "https://support.lexiquest.test/delete-account",
    dataControllerName: "Synthetic controller",
    retentionSummary: "Synthetic retention summary",
    ...configChanges,
  };
  const policy = {
    schemaVersion: 1,
    privacyNoticeHosts: ["vocab-learning-app-219ef.web.app"],
    privateSupportHosts: ["support.lexiquest.test"],
    deletionRequestHosts: ["support.lexiquest.test"],
    ...policyChanges,
  };
  const fetch = async (requestPath) => ({
    ok: true,
    json: async () => requestPath.endsWith("policy.json") ? policy : config,
  });
  vm.runInNewContext(readLoader(directory), {
    URL,
    document: { getElementById: element },
    fetch,
    Promise,
    Error,
  });
  await new Promise((resolve) => setImmediate(resolve));
  await new Promise((resolve) => setImmediate(resolve));
  return element(linkId);
}

for (const [directory, linkId, urlProperty] of loaderCases) {
  test(`${directory} rejects a mismatched contact config schema`, async () => {
    const link = await runLoader(directory, linkId, { schemaVersion: 2 });
    assert.equal(link.enabled, false);
  });

  for (const secretPath of ["/%74oken-value", "/%2574oken-value"]) {
    test(`${directory} rejects secret path ${secretPath}`, async () => {
      const link = await runLoader(directory, linkId, {
        [urlProperty]: `https://support.lexiquest.test${secretPath}`,
      });
      assert.equal(link.enabled, false);
    });
  }
}
