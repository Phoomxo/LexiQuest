import assert from "node:assert/strict";
import { describe, it } from "node:test";

import {
  CallableContractError,
  EconomyStore,
  EconomyTransaction,
  ProgressSessionRecord,
  ProgressState,
  ProgressWriter,
  PurchaseRecord,
  StoreProduct,
  requireCallableIdentity,
} from "./progress_writer.js";

const now = new Date("2026-07-29T10:00:00.000Z");

function progressPayload(overrides: Record<string, unknown> = {}) {
  return {
    sessionId: "session-1",
    eventIds: ["event-1", "event-2"],
    correctAnswers: 2,
    completedAt: "2026-07-29T09:55:00.000Z",
    ...overrides,
  };
}

describe("callable identity", () => {
  it("requires both Firebase authentication and App Check", () => {
    assert.throws(
      () => requireCallableIdentity(undefined, { appId: "app" }),
      (error: unknown) =>
        error instanceof CallableContractError &&
        error.code === "unauthenticated",
    );
    assert.throws(
      () => requireCallableIdentity("owner-a", undefined),
      (error: unknown) =>
        error instanceof CallableContractError &&
        error.code === "failed-precondition",
    );
    assert.deepEqual(
      requireCallableIdentity("owner-a", { appId: "app" }),
      { uid: "owner-a" },
    );
  });
});

describe("recordProgressSession", () => {
  it("rejects unknown fields, oversized payloads, and forged counts", async () => {
    const invalidPayloads = [
      progressPayload({ unexpected: true }),
      progressPayload({ sessionId: "x".repeat(129) }),
      progressPayload({ eventIds: [] }),
      progressPayload({
        eventIds: Array.from({ length: 101 }, (_, index) => `event-${index}`),
      }),
      progressPayload({ eventIds: ["event-1", "event-1"] }),
      progressPayload({ correctAnswers: 3 }),
      progressPayload({ correctAnswers: -1 }),
      progressPayload({ completedAt: "not-a-date" }),
    ];

    for (const payload of invalidPayloads) {
      const writer = new ProgressWriter(new FakeStore(), () => now);
      await assert.rejects(
        writer.recordProgressSession("owner-a", payload),
        (error: unknown) =>
          error instanceof CallableContractError &&
          error.code === "invalid-argument",
      );
    }
  });

  it("increments server-owned counters once and accepts exact replay", async () => {
    const store = new FakeStore();
    const writer = new ProgressWriter(store, () => now);

    const first = await writer.recordProgressSession(
      "owner-a",
      progressPayload(),
    );
    const replay = await writer.recordProgressSession(
      "owner-a",
      progressPayload(),
    );

    assert.deepEqual(first, {
      status: "recorded",
      totalPoints: 2,
      gamesPlayed: 1,
    });
    assert.deepEqual(replay, {
      status: "duplicate",
      totalPoints: 2,
      gamesPlayed: 1,
    });
    assert.deepEqual(store.states.get("owner-a"), {
      totalPoints: 2,
      totalCorrectAnswers: 2,
      totalWrongAnswers: 0,
      gamesPlayed: 1,
    });
    assert.equal(store.sessions.size, 1);
  });

  it("denies reuse of a session id with different evidence", async () => {
    const writer = new ProgressWriter(new FakeStore(), () => now);
    await writer.recordProgressSession("owner-a", progressPayload());

    await assert.rejects(
      writer.recordProgressSession(
        "owner-a",
        progressPayload({
          eventIds: ["event-1"],
          correctAnswers: 1,
        }),
      ),
      (error: unknown) =>
        error instanceof CallableContractError &&
        error.code === "already-exists",
    );
  });
});

describe("purchaseItem", () => {
  it("debits and records a purchase atomically exactly once", async () => {
    const store = new FakeStore();
    store.states.set("owner-a", {
      totalPoints: 100,
      totalCorrectAnswers: 100,
      totalWrongAnswers: 0,
      gamesPlayed: 5,
    });
    store.products.set("wallpaper-neon", {
      productId: "wallpaper-neon",
      price: 40,
      active: true,
    });
    const writer = new ProgressWriter(store, () => now);

    const first = await writer.purchaseItem("owner-a", {
      productId: "wallpaper-neon",
    });
    const duplicate = await writer.purchaseItem("owner-a", {
      productId: "wallpaper-neon",
    });

    assert.deepEqual(first, {
      status: "purchased",
      remainingPoints: 60,
    });
    assert.deepEqual(duplicate, {
      status: "already-owned",
      remainingPoints: 60,
    });
    assert.equal(store.states.get("owner-a")?.totalPoints, 60);
    assert.equal(store.purchases.size, 1);
  });

  it("leaves state unchanged when points are insufficient", async () => {
    const store = new FakeStore();
    store.states.set("owner-a", {
      totalPoints: 10,
      totalCorrectAnswers: 10,
      totalWrongAnswers: 0,
      gamesPlayed: 1,
    });
    store.products.set("wallpaper-neon", {
      productId: "wallpaper-neon",
      price: 40,
      active: true,
    });
    const writer = new ProgressWriter(store, () => now);

    await assert.rejects(
      writer.purchaseItem("owner-a", { productId: "wallpaper-neon" }),
      (error: unknown) =>
        error instanceof CallableContractError &&
        error.code === "failed-precondition",
    );
    assert.equal(store.states.get("owner-a")?.totalPoints, 10);
    assert.equal(store.purchases.size, 0);
  });
});

class FakeStore implements EconomyStore {
  states = new Map<string, ProgressState>();
  sessions = new Map<string, ProgressSessionRecord>();
  products = new Map<string, StoreProduct>();
  purchases = new Map<string, PurchaseRecord>();

  async runTransaction<T>(
    operation: (transaction: EconomyTransaction) => Promise<T>,
  ): Promise<T> {
    const states = structuredClone(this.states);
    const sessions = structuredClone(this.sessions);
    const products = structuredClone(this.products);
    const purchases = structuredClone(this.purchases);
    const transaction: EconomyTransaction = {
      getState: async (uid) => states.get(uid),
      setState: async (uid, state) => {
        states.set(uid, state);
      },
      getProgressSession: async (uid, sessionId) =>
        sessions.get(`${uid}/${sessionId}`),
      setProgressSession: async (uid, sessionId, record) => {
        sessions.set(`${uid}/${sessionId}`, record);
      },
      getProduct: async (productId) => products.get(productId),
      getPurchase: async (uid, productId) =>
        purchases.get(`${uid}/${productId}`),
      setPurchase: async (uid, productId, record) => {
        purchases.set(`${uid}/${productId}`, record);
      },
    };
    const result = await operation(transaction);
    this.states = states;
    this.sessions = sessions;
    this.products = products;
    this.purchases = purchases;
    return result;
  }
}
