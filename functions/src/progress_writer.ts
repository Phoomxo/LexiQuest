export type CallableErrorCode =
  | "unauthenticated"
  | "failed-precondition"
  | "invalid-argument"
  | "already-exists"
  | "not-found";

export class CallableContractError extends Error {
  constructor(
    readonly code: CallableErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "CallableContractError";
  }
}

export interface ProgressState {
  totalPoints: number;
  totalCorrectAnswers: number;
  totalWrongAnswers: number;
  gamesPlayed: number;
}

export interface ProgressSessionRecord {
  sessionId: string;
  eventIds: readonly string[];
  correctAnswers: number;
  completedAt: string;
  recordedAt: string;
  fingerprint: string;
}

export interface StoreProduct {
  productId: string;
  price: number;
  active: boolean;
}

export interface PurchaseRecord {
  userId: string;
  productId: string;
  totalPrice: number;
  purchasedAt: string;
}

export interface EconomyTransaction {
  getState(uid: string): Promise<ProgressState | undefined>;
  setState(uid: string, state: ProgressState): Promise<void>;
  getProgressSession(
    uid: string,
    sessionId: string,
  ): Promise<ProgressSessionRecord | undefined>;
  setProgressSession(
    uid: string,
    sessionId: string,
    record: ProgressSessionRecord,
  ): Promise<void>;
  getProduct(productId: string): Promise<StoreProduct | undefined>;
  getPurchase(
    uid: string,
    productId: string,
  ): Promise<PurchaseRecord | undefined>;
  setPurchase(
    uid: string,
    productId: string,
    record: PurchaseRecord,
  ): Promise<void>;
}

export interface EconomyStore {
  runTransaction<T>(
    operation: (transaction: EconomyTransaction) => Promise<T>,
  ): Promise<T>;
}

interface ProgressInput {
  sessionId: string;
  eventIds: string[];
  correctAnswers: number;
  completedAt: string;
}

interface PurchaseInput {
  productId: string;
}

export function requireCallableIdentity(
  uid: string | undefined,
  app: unknown,
): { uid: string } {
  if (typeof uid !== "string" || uid.length === 0) {
    throw new CallableContractError(
      "unauthenticated",
      "Authentication is required.",
    );
  }
  if (app === undefined || app === null) {
    throw new CallableContractError(
      "failed-precondition",
      "App attestation is required.",
    );
  }
  return { uid };
}

export class ProgressWriter {
  constructor(
    private readonly store: EconomyStore,
    private readonly clock: () => Date = () => new Date(),
  ) {}

  async recordProgressSession(
    uid: string,
    data: unknown,
  ): Promise<{
    status: "recorded" | "duplicate";
    totalPoints: number;
    gamesPlayed: number;
  }> {
    const input = parseProgressInput(data, this.clock());
    const fingerprint = JSON.stringify([
      input.sessionId,
      input.eventIds,
      input.correctAnswers,
      input.completedAt,
    ]);

    return this.store.runTransaction(async (transaction) => {
      const existing = await transaction.getProgressSession(
        uid,
        input.sessionId,
      );
      const current = validateStoredState(await transaction.getState(uid));
      if (existing !== undefined) {
        if (existing.fingerprint !== fingerprint) {
          throw new CallableContractError(
            "already-exists",
            "The session identifier was already used.",
          );
        }
        return {
          status: "duplicate" as const,
          totalPoints: current.totalPoints,
          gamesPlayed: current.gamesPlayed,
        };
      }

      const next: ProgressState = {
        totalPoints: safeAdd(current.totalPoints, input.correctAnswers),
        totalCorrectAnswers: safeAdd(
          current.totalCorrectAnswers,
          input.correctAnswers,
        ),
        totalWrongAnswers: current.totalWrongAnswers,
        gamesPlayed: safeAdd(current.gamesPlayed, 1),
      };
      const recordedAt = this.clock().toISOString();
      await transaction.setState(uid, next);
      await transaction.setProgressSession(uid, input.sessionId, {
        ...input,
        recordedAt,
        fingerprint,
      });
      return {
        status: "recorded" as const,
        totalPoints: next.totalPoints,
        gamesPlayed: next.gamesPlayed,
      };
    });
  }

  async purchaseItem(
    uid: string,
    data: unknown,
  ): Promise<{
    status: "purchased" | "already-owned";
    remainingPoints: number;
  }> {
    const input = parsePurchaseInput(data);
    return this.store.runTransaction(async (transaction) => {
      const current = validateStoredState(await transaction.getState(uid));
      const existing = await transaction.getPurchase(uid, input.productId);
      if (existing !== undefined) {
        return {
          status: "already-owned" as const,
          remainingPoints: current.totalPoints,
        };
      }
      const product = await transaction.getProduct(input.productId);
      if (
        product === undefined ||
        product.productId !== input.productId ||
        product.active !== true ||
        !Number.isSafeInteger(product.price) ||
        product.price <= 0 ||
        product.price > 1_000_000
      ) {
        throw new CallableContractError(
          "not-found",
          "The product is unavailable.",
        );
      }
      if (current.totalPoints < product.price) {
        throw new CallableContractError(
          "failed-precondition",
          "Insufficient points.",
        );
      }
      const next: ProgressState = {
        ...current,
        totalPoints: current.totalPoints - product.price,
      };
      await transaction.setState(uid, next);
      await transaction.setPurchase(uid, input.productId, {
        userId: uid,
        productId: input.productId,
        totalPrice: product.price,
        purchasedAt: this.clock().toISOString(),
      });
      return {
        status: "purchased" as const,
        remainingPoints: next.totalPoints,
      };
    });
  }
}

function parseProgressInput(data: unknown, now: Date): ProgressInput {
  const value = requireRecord(data);
  requireOnlyKeys(value, [
    "sessionId",
    "eventIds",
    "correctAnswers",
    "completedAt",
  ]);
  const sessionId = requireIdentifier(value.sessionId, "sessionId");
  if (!Array.isArray(value.eventIds) || value.eventIds.length < 1) {
    invalid("eventIds must contain at least one identifier.");
  }
  if (value.eventIds.length > 100) {
    invalid("eventIds exceeds the maximum size.");
  }
  const eventIds = value.eventIds.map((entry) =>
    requireIdentifier(entry, "eventIds"),
  );
  if (new Set(eventIds).size !== eventIds.length) {
    invalid("eventIds must be unique.");
  }
  if (
    !Number.isSafeInteger(value.correctAnswers) ||
    (value.correctAnswers as number) < 0 ||
    (value.correctAnswers as number) > eventIds.length
  ) {
    invalid("correctAnswers is outside the accepted bounds.");
  }
  if (typeof value.completedAt !== "string") {
    invalid("completedAt must be an ISO timestamp.");
  }
  const completedAtMs = Date.parse(value.completedAt as string);
  if (!Number.isFinite(completedAtMs)) {
    invalid("completedAt must be an ISO timestamp.");
  }
  const maxFuture = now.getTime() + 5 * 60 * 1000;
  const oldest = now.getTime() - 365 * 24 * 60 * 60 * 1000;
  if (completedAtMs > maxFuture || completedAtMs < oldest) {
    invalid("completedAt is outside the accepted window.");
  }
  return {
    sessionId,
    eventIds,
    correctAnswers: value.correctAnswers as number,
    completedAt: new Date(completedAtMs).toISOString(),
  };
}

function parsePurchaseInput(data: unknown): PurchaseInput {
  const value = requireRecord(data);
  requireOnlyKeys(value, ["productId"]);
  return {
    productId: requireIdentifier(value.productId, "productId"),
  };
}

function requireRecord(data: unknown): Record<string, unknown> {
  if (
    typeof data !== "object" ||
    data === null ||
    Array.isArray(data) ||
    Object.getPrototypeOf(data) !== Object.prototype
  ) {
    invalid("The request payload must be an object.");
  }
  return data as Record<string, unknown>;
}

function requireOnlyKeys(
  data: Record<string, unknown>,
  expected: readonly string[],
): void {
  const keys = Object.keys(data);
  if (
    keys.length !== expected.length ||
    keys.some((key) => !expected.includes(key))
  ) {
    invalid("The request payload contains unknown or missing fields.");
  }
}

function requireIdentifier(value: unknown, field: string): string {
  if (
    typeof value !== "string" ||
    value.length < 1 ||
    value.length > 128 ||
    !/^[A-Za-z0-9_-]+$/.test(value)
  ) {
    invalid(`${field} is invalid.`);
  }
  return value as string;
}

function validateStoredState(state: ProgressState | undefined): ProgressState {
  if (state === undefined) {
    return {
      totalPoints: 0,
      totalCorrectAnswers: 0,
      totalWrongAnswers: 0,
      gamesPlayed: 0,
    };
  }
  for (const value of [
    state.totalPoints,
    state.totalCorrectAnswers,
    state.totalWrongAnswers,
    state.gamesPlayed,
  ]) {
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new CallableContractError(
        "failed-precondition",
        "Stored progress is invalid.",
      );
    }
  }
  return state;
}

function safeAdd(left: number, right: number): number {
  const result = left + right;
  if (!Number.isSafeInteger(result) || result < 0) {
    throw new CallableContractError(
      "failed-precondition",
      "The progress total exceeds accepted bounds.",
    );
  }
  return result;
}

function invalid(message: string): never {
  throw new CallableContractError("invalid-argument", message);
}
