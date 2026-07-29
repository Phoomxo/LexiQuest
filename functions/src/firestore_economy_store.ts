import { createHash } from "node:crypto";

import {
  DocumentData,
  Firestore,
  Transaction,
} from "firebase-admin/firestore";

import {
  EconomyStore,
  EconomyTransaction,
  ProgressSessionRecord,
  ProgressState,
  PurchaseRecord,
  StoreProduct,
} from "./progress_writer.js";

export class FirestoreEconomyStore implements EconomyStore {
  constructor(private readonly firestore: Firestore) {}

  runTransaction<T>(
    operation: (transaction: EconomyTransaction) => Promise<T>,
  ): Promise<T> {
    return this.firestore.runTransaction((transaction) =>
      operation(new FirestoreEconomyTransaction(this.firestore, transaction)),
    );
  }
}

class FirestoreEconomyTransaction implements EconomyTransaction {
  constructor(
    private readonly firestore: Firestore,
    private readonly transaction: Transaction,
  ) {}

  async getState(uid: string): Promise<ProgressState | undefined> {
    const snapshot = await this.transaction.get(
      this.firestore.collection("state").doc(uid),
    );
    if (!snapshot.exists) return undefined;
    const data = snapshot.data() ?? {};
    return {
      totalPoints: numberOrZero(data.totalPoints),
      totalCorrectAnswers: numberOrZero(data.totalCorrectAnswers),
      totalWrongAnswers: numberOrZero(data.totalWrongAnswers),
      gamesPlayed: numberOrZero(data.gamesPlayed),
    };
  }

  async setState(uid: string, state: ProgressState): Promise<void> {
    this.transaction.set(
      this.firestore.collection("state").doc(uid),
      state,
      { merge: true },
    );
  }

  async getProgressSession(
    uid: string,
    sessionId: string,
  ): Promise<ProgressSessionRecord | undefined> {
    const snapshot = await this.transaction.get(
      this.firestore.collection("progress_sessions").doc(documentId(uid, sessionId)),
    );
    if (!snapshot.exists) return undefined;
    const data = snapshot.data() ?? {};
    return progressSessionFromData(data);
  }

  async setProgressSession(
    uid: string,
    sessionId: string,
    record: ProgressSessionRecord,
  ): Promise<void> {
    this.transaction.create(
      this.firestore.collection("progress_sessions").doc(documentId(uid, sessionId)),
      {
        uid,
        ...record,
      },
    );
  }

  async getProduct(productId: string): Promise<StoreProduct | undefined> {
    const snapshot = await this.transaction.get(
      this.firestore.collection("products").doc(productId),
    );
    if (!snapshot.exists) return undefined;
    const data = snapshot.data() ?? {};
    return {
      productId,
      price: data.price as number,
      active: data.active === true,
    };
  }

  async getPurchase(
    uid: string,
    productId: string,
  ): Promise<PurchaseRecord | undefined> {
    const snapshot = await this.transaction.get(
      this.firestore.collection("purchased_items").doc(documentId(uid, productId)),
    );
    if (!snapshot.exists) return undefined;
    const data = snapshot.data() ?? {};
    return {
      userId: data.user_id as string,
      productId: data.product_id as string,
      totalPrice: data.total_price as number,
      purchasedAt: data.purchased_at as string,
    };
  }

  async setPurchase(
    uid: string,
    productId: string,
    record: PurchaseRecord,
  ): Promise<void> {
    this.transaction.create(
      this.firestore.collection("purchased_items").doc(documentId(uid, productId)),
      {
        user_id: record.userId,
        product_id: record.productId,
        total_price: record.totalPrice,
        purchased_at: record.purchasedAt,
      },
    );
  }
}

function documentId(first: string, second: string): string {
  return createHash("sha256").update(first).update("\0").update(second).digest("hex");
}

function numberOrZero(value: unknown): number {
  return value === undefined ? 0 : (value as number);
}

function progressSessionFromData(data: DocumentData): ProgressSessionRecord {
  return {
    sessionId: data.sessionId as string,
    eventIds: data.eventIds as string[],
    correctAnswers: data.correctAnswers as number,
    completedAt: data.completedAt as string,
    recordedAt: data.recordedAt as string,
    fingerprint: data.fingerprint as string,
  };
}
