import assert from "node:assert/strict";
import { beforeEach, describe, it } from "node:test";

import { getFirestore } from "firebase-admin/firestore";
import {
  HttpsError,
  type CallableRequest,
} from "firebase-functions/v2/https";

import {
  applyProductCatalogMigration,
  rollbackProductCatalogMigration,
} from "./product_catalog_migration.js";
import { purchaseItem, recordProgressSession } from "./index.js";

const firestore = getFirestore();
const completedAt = "2026-07-29T10:00:00.000Z";

function request(
  uid: string | undefined,
  data: unknown,
  includeAppCheck = true,
): CallableRequest<unknown> {
  return {
    data,
    auth: uid === undefined
      ? undefined
      : {
          uid,
          token: {} as never,
          rawToken: "emulator-token",
        },
    app: includeAppCheck
      ? {
          appId: "1:145034183638:android:device-test",
          token: {} as never,
        }
      : undefined,
    rawRequest: {} as never,
    acceptsStreaming: false,
  };
}

function progressData(overrides: Record<string, unknown> = {}) {
  return {
    sessionId: "session_1",
    eventIds: ["event_1"],
    correctAnswers: 1,
    completedAt,
    ...overrides,
  };
}

async function clearFirestore(): Promise<void> {
  const collections = await firestore.listCollections();
  for (const collection of collections) {
    await firestore.recursiveDelete(collection);
  }
}

beforeEach(clearFirestore);

describe("trusted callable emulator contract", () => {
  it("denies unauthenticated and unattested requests", async () => {
    await assert.rejects(
      recordProgressSession.run(request(undefined, progressData())),
      (error: unknown) =>
        error instanceof HttpsError && error.code === "unauthenticated",
    );
    await assert.rejects(
      recordProgressSession.run(request("alice", progressData(), false)),
      (error: unknown) =>
        error instanceof HttpsError && error.code === "failed-precondition",
    );
  });

  it("denies unknown fields, cross-owner claims, and oversized evidence", async () => {
    for (const payload of [
      progressData({ unexpected: true }),
      progressData({ uid: "bob" }),
      progressData({
        eventIds: Array.from({ length: 101 }, (_, index) => `event_${index}`),
      }),
    ]) {
      await assert.rejects(
        recordProgressSession.run(request("alice", payload)),
        (error: unknown) =>
          error instanceof HttpsError && error.code === "invalid-argument",
      );
    }
  });

  it("records exact replay once and isolates identical ids by owner", async () => {
    const first = await recordProgressSession.run(
      request("alice", progressData()),
    );
    const replay = await recordProgressSession.run(
      request("alice", progressData()),
    );
    const secondOwner = await recordProgressSession.run(
      request("bob", progressData()),
    );

    assert.deepEqual(first, {
      status: "recorded",
      totalPoints: 1,
      gamesPlayed: 1,
    });
    assert.deepEqual(replay, {
      status: "duplicate",
      totalPoints: 1,
      gamesPlayed: 1,
    });
    assert.deepEqual(secondOwner, {
      status: "recorded",
      totalPoints: 1,
      gamesPlayed: 1,
    });
    assert.equal((await firestore.collection("state").doc("alice").get()).data()?.totalPoints, 1);
    assert.equal((await firestore.collection("state").doc("bob").get()).data()?.totalPoints, 1);
    assert.equal((await firestore.collection("progress_sessions").get()).size, 2);
  });

  it("rolls back an insufficient purchase and debits an accepted purchase once", async () => {
    await firestore.collection("products").doc("wallpaper_neon").set({
      price: 5,
      active: true,
    });
    await firestore.collection("state").doc("alice").set({
      totalPoints: 4,
      totalCorrectAnswers: 4,
      totalWrongAnswers: 0,
      gamesPlayed: 1,
    });

    await assert.rejects(
      purchaseItem.run(request("alice", { productId: "wallpaper_neon" })),
      (error: unknown) =>
        error instanceof HttpsError && error.code === "failed-precondition",
    );
    assert.equal(
      (await firestore.collection("state").doc("alice").get()).data()?.totalPoints,
      4,
    );
    assert.equal((await firestore.collection("purchased_items").get()).empty, true);

    await firestore.collection("state").doc("alice").update({ totalPoints: 5 });
    const accepted = await purchaseItem.run(
      request("alice", { productId: "wallpaper_neon" }),
    );
    const replay = await purchaseItem.run(
      request("alice", { productId: "wallpaper_neon" }),
    );

    assert.deepEqual(accepted, {
      status: "purchased",
      remainingPoints: 0,
    });
    assert.deepEqual(replay, {
      status: "already-owned",
      remainingPoints: 0,
    });
    assert.equal((await firestore.collection("purchased_items").get()).size, 1);
  });
});

describe("product catalog migration", () => {
  it("is idempotent and restores the exact legacy catalog on rollback", async () => {
    await firestore.collection("products").doc("legacy-a").set({
      name: "Legacy A",
      image_name: "a.png",
      price: 50,
    });
    await firestore.collection("products").doc("legacy-b").set({
      name: "Legacy B",
      image_name: "b.png",
      price: 100,
      active: true,
    });
    await firestore.collection("purchased_items").doc("purchase-1").set({
      user_id: "alice",
      product_id: "legacy-a",
      total_price: 50,
    });

    const before = new Map(
      (await firestore.collection("products").get()).docs.map((document) => [
        document.id,
        document.data(),
      ]),
    );

    assert.deepEqual(
      await applyProductCatalogMigration(
        firestore,
        "catalog-v1",
        "2026-07-29T13:00:00.000Z",
      ),
      { status: "applied", productCount: 2 },
    );
    assert.deepEqual(
      await applyProductCatalogMigration(
        firestore,
        "catalog-v1",
        "2026-07-29T13:00:01.000Z",
      ),
      { status: "already-applied", productCount: 2 },
    );

    for (const document of (await firestore.collection("products").get()).docs) {
      assert.equal(document.data().active, false);
      assert.equal(document.data().catalogVersion, "legacy-v1");
    }
    assert.equal(
      (await firestore.collection("purchased_items").doc("purchase-1").get())
        .data()?.product_id,
      "legacy-a",
    );

    assert.deepEqual(
      await rollbackProductCatalogMigration(
        firestore,
        "catalog-v1",
        "2026-07-29T13:05:00.000Z",
      ),
      { status: "rolled-back", productCount: 2 },
    );
    assert.deepEqual(
      await rollbackProductCatalogMigration(
        firestore,
        "catalog-v1",
        "2026-07-29T13:05:01.000Z",
      ),
      { status: "already-rolled-back", productCount: 2 },
    );

    for (const document of (await firestore.collection("products").get()).docs) {
      assert.deepEqual(document.data(), before.get(document.id));
    }
  });
});
