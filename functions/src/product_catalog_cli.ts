import {
  applicationDefault,
  getApps,
  initializeApp,
} from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";

import {
  applyProductCatalogMigration,
  rollbackProductCatalogMigration,
} from "./product_catalog_migration.js";

const productionProjectId = "vocab-learning-app-219ef";

async function main(): Promise<void> {
  const command = process.argv[2];
  const migrationId = process.argv[3] ?? "product-catalog-legacy-v1";
  if (command !== "apply" && command !== "rollback") {
    throw new Error(
      "Usage: product_catalog_cli.js apply|rollback [migrationId]",
    );
  }

  const projectId =
    process.env.GOOGLE_CLOUD_PROJECT ??
    process.env.GCLOUD_PROJECT ??
    productionProjectId;
  if (projectId !== productionProjectId) {
    throw new Error("The catalog command targets the wrong Firebase project.");
  }
  const requiredConfirmation = `${command}:${migrationId}:${projectId}`;
  if (
    process.env.LEXIQUEST_CATALOG_CONFIRMATION !== requiredConfirmation
  ) {
    throw new Error(
      `Set LEXIQUEST_CATALOG_CONFIRMATION to ${requiredConfirmation}.`,
    );
  }

  if (getApps().length === 0) {
    initializeApp({
      credential: applicationDefault(),
      projectId,
    });
  }
  const firestore = getFirestore();
  const now = new Date().toISOString();
  const result = command === "apply"
    ? await applyProductCatalogMigration(firestore, migrationId, now)
    : await rollbackProductCatalogMigration(firestore, migrationId, now);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

void main().catch((error: unknown) => {
  const message = error instanceof Error
    ? error.message
    : "Catalog migration failed.";
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
});
