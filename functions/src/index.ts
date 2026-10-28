import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { FirestoreEconomyStore } from "./firestore_economy_store.js";
import {
  CallableContractError,
  ProgressWriter,
  requireCallableIdentity,
} from "./progress_writer.js";

initializeApp();

const writer = new ProgressWriter(new FirestoreEconomyStore(getFirestore()));
const callableOptions = {
  region: "asia-southeast1",
  enforceAppCheck: true,
  memory: "256MiB" as const,
  timeoutSeconds: 30,
};

export const recordProgressSession = onCall(callableOptions, async (request) => {
  const identity = requireIdentity(request.auth?.uid, request.app);
  try {
    return await writer.recordProgressSession(identity.uid, request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

export const purchaseItem = onCall(callableOptions, async (request) => {
  const identity = requireIdentity(request.auth?.uid, request.app);
  try {
    return await writer.purchaseItem(identity.uid, request.data);
  } catch (error) {
    throw toHttpsError(error);
  }
});

function requireIdentity(uid: string | undefined, app: unknown): { uid: string } {
  try {
    return requireCallableIdentity(uid, app);
  } catch (error) {
    throw toHttpsError(error);
  }
}

function toHttpsError(error: unknown): HttpsError {
  if (error instanceof CallableContractError) {
    return new HttpsError(error.code, error.message);
  }
  return new HttpsError("internal", "The trusted writer is unavailable.");
}
