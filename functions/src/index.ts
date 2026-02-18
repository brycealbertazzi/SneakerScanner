import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const kicksDbApiKey = defineSecret("KICKS_DB_API_KEY");
const ebayClientId = defineSecret("EBAY_CLIENT_ID");
const ebayClientSecret = defineSecret("EBAY_CLIENT_SECRET");
const stockXApiKey = defineSecret("STOCKX_API_KEY");
const stockXClientId = defineSecret("STOCKX_CLIENT_ID");
const stockXClientSecret = defineSecret("STOCKX_CLIENT_SECRET");

export const getApiKeys = onCall(
  {
    secrets: [
      kicksDbApiKey,
      ebayClientId,
      ebayClientSecret,
      stockXApiKey,
      stockXClientId,
      stockXClientSecret,
    ],
    region: "us-central1",
    memory: "256MiB",
    maxInstances: 10,
  },
  (request) => {
    console.log("[getApiKeys] called, auth present:", !!request.auth);
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }

    return {
      kicksDbApiKey: kicksDbApiKey.value(),
      ebayClientId: ebayClientId.value(),
      ebayClientSecret: ebayClientSecret.value(),
      stockXApiKey: stockXApiKey.value(),
      stockXClientId: stockXClientId.value(),
      stockXClientSecret: stockXClientSecret.value(),
    };
  }
);
