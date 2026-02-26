import * as admin from "firebase-admin";
import {onCall, onRequest, HttpsError} from "firebase-functions/v2/https";
import {onMessagePublished} from "firebase-functions/v2/pubsub";
import {defineSecret} from "firebase-functions/params";
import * as https from "https";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

const kicksDbApiKey = defineSecret("KICKS_DB_API_KEY");
const ebayClientId = defineSecret("EBAY_CLIENT_ID");
const ebayClientSecret = defineSecret("EBAY_CLIENT_SECRET");
const stockXApiKey = defineSecret("STOCKX_API_KEY");
const stockXClientId = defineSecret("STOCKX_CLIENT_ID");
const stockXClientSecret = defineSecret("STOCKX_CLIENT_SECRET");
const appleSharedSecret = defineSecret("APPLE_SHARED_SECRET");
const googleServiceAccountJson = defineSecret("GOOGLE_SERVICE_ACCOUNT_JSON");

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

// ---------------------------------------------------------------------------
// validatePurchase — callable, verifies Apple/Google receipts server-side
// and writes subscription status to Firebase.
// ---------------------------------------------------------------------------
export const validatePurchase = onCall(
  {
    secrets: [appleSharedSecret, googleServiceAccountJson],
    region: "us-central1",
    memory: "256MiB",
    maxInstances: 10,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be signed in.");
    }
    const uid = request.auth.uid;
    const {platform, productId, receiptData, purchaseToken, transactionId} =
      request.data as {
        platform: string;
        productId: string;
        receiptData?: string;
        purchaseToken?: string;
        transactionId?: string;
      };

    if (!platform || !productId) {
      throw new HttpsError("invalid-argument", "Missing platform or productId.");
    }

    if (platform === "apple") {
      if (!receiptData) {
        throw new HttpsError("invalid-argument", "Missing receiptData for Apple.");
      }
      const result = await verifyAppleReceipt(
        receiptData,
        appleSharedSecret.value()
      );
      if (!result.valid) {
        throw new HttpsError("failed-precondition", "Apple receipt invalid.");
      }
      await admin.database().ref(`users/${uid}/subscriptions/apple`).update({
        status: "active",
        platform: "apple",
        productId,
        originalTransactionId: result.originalTransactionId ?? transactionId ?? null,
        expiresAt: result.expiresAt ?? null,
        purchaseToken: null,
      });
      return {success: true};
    }

    if (platform === "google") {
      if (!purchaseToken) {
        throw new HttpsError(
          "invalid-argument",
          "Missing purchaseToken for Google."
        );
      }
      const result = await verifyGooglePurchase(
        purchaseToken,
        productId,
        googleServiceAccountJson.value()
      );
      if (!result.valid) {
        throw new HttpsError(
          "failed-precondition",
          "Google purchase invalid."
        );
      }
      await admin.database().ref(`users/${uid}/subscriptions/google`).update({
        status: "active",
        platform: "google",
        productId,
        purchaseToken,
        originalTransactionId: null,
        expiresAt: result.expiresAt ?? null,
      });
      return {success: true};
    }

    throw new HttpsError("invalid-argument", `Unknown platform: ${platform}`);
  }
);

// ---------------------------------------------------------------------------
// appleNotifications — Apple App Store Server Notifications (S2S)
// Called by Apple when subscription state changes (renewal, cancellation, etc.)
// ---------------------------------------------------------------------------
export const appleNotifications = onRequest(
  {
    secrets: [appleSharedSecret],
    region: "us-central1",
    memory: "256MiB",
    maxInstances: 10,
  },
  async (req, res) => {
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    try {
      const body = req.body as {signedPayload?: string};
      if (!body.signedPayload) {
        res.status(400).send("Missing signedPayload");
        return;
      }

      // Decode the JWS payload (3-part JWT, base64url encoded)
      const parts = body.signedPayload.split(".");
      if (parts.length < 2) {
        res.status(400).send("Invalid signedPayload");
        return;
      }
      const payloadJson = Buffer.from(parts[1], "base64url").toString("utf8");
      const payload = JSON.parse(payloadJson) as {
        notificationType: string;
        subtype?: string;
        data?: {
          signedTransactionInfo?: string;
          signedRenewalInfo?: string;
          appAppleId?: number;
          bundleId?: string;
          environment?: string;
        };
      };

      const notificationType = payload.notificationType;
      const data = payload.data;

      // Decode transaction info
      let originalTransactionId: string | null = null;
      let expiresAt: number | null = null;
      if (data?.signedTransactionInfo) {
        const txParts = data.signedTransactionInfo.split(".");
        if (txParts.length >= 2) {
          const txJson = Buffer.from(txParts[1], "base64url").toString("utf8");
          const tx = JSON.parse(txJson) as {
            originalTransactionId?: string;
            expiresDate?: number;
            productId?: string;
          };
          originalTransactionId = tx.originalTransactionId ?? null;
          expiresAt = tx.expiresDate ?? null;
        }
      }

      if (!originalTransactionId) {
        console.log("[appleNotifications] No originalTransactionId, skipping");
        res.status(200).send("OK");
        return;
      }

      // Find the user by originalTransactionId
      const snapshot = await admin
        .database()
        .ref("users")
        .orderByChild("subscriptions/apple/originalTransactionId")
        .equalTo(originalTransactionId)
        .limitToFirst(1)
        .get();

      if (!snapshot.exists()) {
        console.log("[appleNotifications] No user found for tx:", originalTransactionId);
        res.status(200).send("OK");
        return;
      }

      const uid = Object.keys(snapshot.val())[0];
      const subRef = admin.database().ref(`users/${uid}/subscriptions/apple`);

      // Map Apple notification types to our status
      const cancelTypes = ["CANCEL", "REVOKE", "REFUND"];
      const expiredTypes = ["EXPIRED"];
      const renewedTypes = ["DID_RENEW", "SUBSCRIBED", "RESUBSCRIBE"];

      if (cancelTypes.includes(notificationType)) {
        await subRef.update({status: "cancelled"});
      } else if (expiredTypes.includes(notificationType)) {
        await subRef.update({status: "expired", expiresAt});
      } else if (renewedTypes.includes(notificationType)) {
        await subRef.update({status: "active", expiresAt});
      }

      console.log(
        `[appleNotifications] ${notificationType} → uid: ${uid}, status updated`
      );
      res.status(200).send("OK");
    } catch (err) {
      console.error("[appleNotifications] Error:", err);
      res.status(500).send("Internal Server Error");
    }
  }
);

// ---------------------------------------------------------------------------
// googleNotifications — Google Play Real-Time Developer Notifications (RTDN)
// Delivered via Cloud Pub/Sub. Topic must be configured in Google Play Console.
// ---------------------------------------------------------------------------
export const googleNotifications = onMessagePublished(
  {
    topic: "sneakerscanner-rtdn",
    secrets: [googleServiceAccountJson],
    region: "us-central1",
    memory: "256MiB",
    maxInstances: 10,
  },
  async (event) => {
    try {
      const messageData = event.data.message.data
        ? Buffer.from(event.data.message.data, "base64").toString("utf8")
        : null;

      if (!messageData) {
        console.log("[googleNotifications] Empty message");
        return;
      }

      const notification = JSON.parse(messageData) as {
        subscriptionNotification?: {
          version: string;
          notificationType: number;
          purchaseToken: string;
          subscriptionId: string;
        };
        packageName?: string;
      };

      const subNotif = notification.subscriptionNotification;
      if (!subNotif) {
        console.log("[googleNotifications] Not a subscription notification");
        return;
      }

      const {notificationType, purchaseToken} = subNotif;

      // Find the user by purchaseToken
      const snapshot = await admin
        .database()
        .ref("users")
        .orderByChild("subscriptions/google/purchaseToken")
        .equalTo(purchaseToken)
        .limitToFirst(1)
        .get();

      if (!snapshot.exists()) {
        console.log("[googleNotifications] No user found for token:", purchaseToken);
        return;
      }

      const uid = Object.keys(snapshot.val())[0];
      const subRef = admin.database().ref(`users/${uid}/subscriptions/google`);

      // Google Play subscription notification types:
      // 1=RECOVERED, 2=RENEWED, 3=CANCELED, 4=PURCHASED, 5=ON_HOLD
      // 6=IN_GRACE_PERIOD, 7=RESTARTED, 8=PRICE_CHANGE_CONFIRMED
      // 9=DEFERRED, 10=PAUSED, 11=PAUSE_SCHEDULE_CHANGED, 12=REVOKED, 13=EXPIRED
      if ([3, 12].includes(notificationType)) {
        await subRef.update({status: "cancelled"});
      } else if ([13].includes(notificationType)) {
        await subRef.update({status: "expired"});
      } else if ([1, 2, 4, 7].includes(notificationType)) {
        await subRef.update({status: "active"});
      }

      console.log(
        `[googleNotifications] notificationType: ${notificationType} → uid: ${uid}`
      );
    } catch (err) {
      console.error("[googleNotifications] Error:", err);
    }
  }
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

async function verifyAppleReceipt(
  receiptData: string,
  sharedSecret: string
): Promise<{valid: boolean; originalTransactionId?: string; expiresAt?: number}> {
  const body = JSON.stringify({
    "receipt-data": receiptData,
    password: sharedSecret,
    "exclude-old-transactions": true,
  });

  // Try production first, fall back to sandbox
  for (const host of [
    "buy.itunes.apple.com",
    "sandbox.itunes.apple.com",
  ]) {
    const result = await httpsPost(host, "/verifyReceipt", body);
    const json = JSON.parse(result) as {
      status: number;
      latest_receipt_info?: Array<{
        original_transaction_id: string;
        expires_date_ms: string;
        product_id: string;
      }>;
    };

    if (json.status === 21007) continue; // sandbox receipt sent to production — retry
    if (json.status !== 0) return {valid: false};

    const latest = json.latest_receipt_info?.[0];
    if (!latest) return {valid: false};

    return {
      valid: true,
      originalTransactionId: latest.original_transaction_id,
      expiresAt: parseInt(latest.expires_date_ms, 10),
    };
  }

  return {valid: false};
}

async function verifyGooglePurchase(
  purchaseToken: string,
  productId: string,
  serviceAccountJson: string
): Promise<{valid: boolean; expiresAt?: number}> {
  try {
    const serviceAccount = JSON.parse(serviceAccountJson) as {
      client_email: string;
      private_key: string;
    };

    // Get OAuth2 access token using service account JWT
    const accessToken = await getGoogleAccessToken(
      serviceAccount.client_email,
      serviceAccount.private_key
    );

    const packageName = "com.brycealbertazzi.sneaker_scanner";
    const url =
      `/androidpublisher/v3/applications/${packageName}/purchases/subscriptions/${productId}/tokens/${purchaseToken}`;

    const result = await httpsGet(
      "androidpublisher.googleapis.com",
      url,
      accessToken
    );

    const purchase = JSON.parse(result) as {
      paymentState?: number;
      expiryTimeMillis?: string;
      cancelReason?: number;
    };

    if (purchase.paymentState === undefined) return {valid: false};
    if (purchase.cancelReason !== undefined) return {valid: false};

    return {
      valid: purchase.paymentState === 1,
      expiresAt: purchase.expiryTimeMillis
        ? parseInt(purchase.expiryTimeMillis, 10)
        : undefined,
    };
  } catch (err) {
    console.error("[verifyGooglePurchase] Error:", err);
    return {valid: false};
  }
}

function httpsPost(host: string, path: string, body: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: host,
      path,
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Content-Length": Buffer.byteLength(body),
      },
    };
    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve(data));
    });
    req.on("error", reject);
    req.write(body);
    req.end();
  });
}

function httpsGet(host: string, path: string, token: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: host,
      path,
      method: "GET",
      headers: {Authorization: `Bearer ${token}`},
    };
    const req = https.request(options, (res) => {
      let data = "";
      res.on("data", (chunk) => (data += chunk));
      res.on("end", () => resolve(data));
    });
    req.on("error", reject);
    req.end();
  });
}

async function getGoogleAccessToken(
  clientEmail: string,
  privateKey: string
): Promise<string> {
  // Build JWT for service account
  const header = Buffer.from(JSON.stringify({alg: "RS256", typ: "JWT"})).toString(
    "base64url"
  );
  const now = Math.floor(Date.now() / 1000);
  const claimSet = Buffer.from(
    JSON.stringify({
      iss: clientEmail,
      scope: "https://www.googleapis.com/auth/androidpublisher",
      aud: "https://oauth2.googleapis.com/token",
      exp: now + 3600,
      iat: now,
    })
  ).toString("base64url");

  const {createSign} = await import("crypto");
  const sign = createSign("RSA-SHA256");
  sign.update(`${header}.${claimSet}`);
  const signature = sign.sign(privateKey, "base64url");
  const jwt = `${header}.${claimSet}.${signature}`;

  const body = new URLSearchParams({
    grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
    assertion: jwt,
  }).toString();

  const result = await httpsPost(
    "oauth2.googleapis.com",
    "/token",
    body
  );
  const json = JSON.parse(result) as {access_token: string};
  return json.access_token;
}
