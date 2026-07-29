import {
  type DocumentData,
  type Firestore,
} from "firebase-admin/firestore";

const migrationCollection = "_admin_migrations";
const catalogVersion = "legacy-v1";
const maximumProducts = 100;
const maximumBackupBytes = 750_000;

export type ApplyCatalogMigrationResult = {
  status: "applied" | "already-applied";
  productCount: number;
};

export type RollbackCatalogMigrationResult = {
  status: "rolled-back" | "already-rolled-back";
  productCount: number;
};

type ProductBackup = {
  id: string;
  data: DocumentData;
};

export async function applyProductCatalogMigration(
  firestore: Firestore,
  migrationId: string,
  appliedAt: string,
): Promise<ApplyCatalogMigrationResult> {
  requireMigrationId(migrationId);
  requireUtcInstant(appliedAt);

  return firestore.runTransaction(async (transaction) => {
    const migrationReference = firestore
      .collection(migrationCollection)
      .doc(migrationId);
    const migrationSnapshot = await transaction.get(migrationReference);
    if (migrationSnapshot.exists) {
      const existing = migrationSnapshot.data() ?? {};
      if (existing.status === "applied") {
        return {
          status: "already-applied",
          productCount: requireProductCount(existing.productCount),
        };
      }
      throw new Error(
        `Catalog migration ${migrationId} cannot be applied from status ${String(existing.status)}.`,
      );
    }

    const productsSnapshot = await transaction.get(
      firestore.collection("products").limit(maximumProducts + 1),
    );
    if (productsSnapshot.size > maximumProducts) {
      throw new Error(
        `Catalog migration exceeds the ${maximumProducts}-product safety limit.`,
      );
    }

    const products: ProductBackup[] = productsSnapshot.docs.map((document) => ({
      id: document.id,
      data: document.data(),
    }));
    const backupBytes = Buffer.byteLength(JSON.stringify(products), "utf8");
    if (backupBytes > maximumBackupBytes) {
      throw new Error("Catalog migration backup exceeds the safety limit.");
    }

    transaction.create(migrationReference, {
      schemaVersion: 1,
      status: "applied",
      catalogVersion,
      appliedAt,
      productCount: products.length,
      products,
    });
    for (const product of products) {
      transaction.set(
        firestore.collection("products").doc(product.id),
        {
          active: false,
          catalogVersion,
          migratedAt: appliedAt,
        },
        { merge: true },
      );
    }

    return { status: "applied", productCount: products.length };
  });
}

export async function rollbackProductCatalogMigration(
  firestore: Firestore,
  migrationId: string,
  rolledBackAt: string,
): Promise<RollbackCatalogMigrationResult> {
  requireMigrationId(migrationId);
  requireUtcInstant(rolledBackAt);

  return firestore.runTransaction(async (transaction) => {
    const migrationReference = firestore
      .collection(migrationCollection)
      .doc(migrationId);
    const migrationSnapshot = await transaction.get(migrationReference);
    if (!migrationSnapshot.exists) {
      throw new Error(`Catalog migration ${migrationId} does not exist.`);
    }

    const migration = migrationSnapshot.data() ?? {};
    const products = requireBackups(migration.products);
    if (migration.status === "rolled-back") {
      return {
        status: "already-rolled-back",
        productCount: products.length,
      };
    }
    if (migration.status !== "applied") {
      throw new Error(
        `Catalog migration ${migrationId} cannot roll back from status ${String(migration.status)}.`,
      );
    }

    for (const product of products) {
      transaction.set(
        firestore.collection("products").doc(product.id),
        product.data,
      );
    }
    transaction.update(migrationReference, {
      status: "rolled-back",
      rolledBackAt,
    });

    return { status: "rolled-back", productCount: products.length };
  });
}

function requireMigrationId(value: string): void {
  if (!/^[A-Za-z0-9][A-Za-z0-9_-]{0,79}$/.test(value)) {
    throw new Error("Catalog migration id is invalid.");
  }
}

function requireUtcInstant(value: string): void {
  const parsed = new Date(value);
  if (
    Number.isNaN(parsed.getTime()) ||
    parsed.toISOString() !== value
  ) {
    throw new Error("Catalog migration time must be a canonical UTC instant.");
  }
}

function requireProductCount(value: unknown): number {
  if (
    !Number.isSafeInteger(value) ||
    (value as number) < 0 ||
    (value as number) > maximumProducts
  ) {
    throw new Error("Catalog migration product count is invalid.");
  }
  return value as number;
}

function requireBackups(value: unknown): ProductBackup[] {
  if (!Array.isArray(value) || value.length > maximumProducts) {
    throw new Error("Catalog migration backup is invalid.");
  }
  return value.map((item) => {
    if (
      typeof item !== "object" ||
      item === null ||
      !("id" in item) ||
      !("data" in item) ||
      typeof item.id !== "string" ||
      !/^[^/]{1,500}$/.test(item.id) ||
      typeof item.data !== "object" ||
      item.data === null ||
      Array.isArray(item.data)
    ) {
      throw new Error("Catalog migration backup entry is invalid.");
    }
    return {
      id: item.id,
      data: item.data as DocumentData,
    };
  });
}
