import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@6";

type FirebaseServiceAccount = {
  project_id: string;
  client_email: string;
  private_key: string;
};

type WebhookEvent = {
  type?: string;
  schema?: string;
  table?: string;
  record?: { id?: string };
  notification_id?: string;
};

type FcmError = {
  error?: {
    message?: string;
    status?: string;
    details?: Array<{ errorCode?: string }>;
  };
};

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
const firebaseServiceAccountJson = Deno.env.get(
  "FIREBASE_SERVICE_ACCOUNT_JSON",
);

let cachedAccessToken: string | null = null;
let accessTokenExpiresAt = 0;

function jsonResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: { "content-type": "application/json" },
  });
}

function secureEqual(first: string, second: string): boolean {
  if (first.length !== second.length) return false;
  let difference = 0;
  for (let index = 0; index < first.length; index += 1) {
    difference |= first.charCodeAt(index) ^ second.charCodeAt(index);
  }
  return difference === 0;
}

async function getFirebaseAccessToken(
  account: FirebaseServiceAccount,
): Promise<string> {
  if (cachedAccessToken && Date.now() < accessTokenExpiresAt - 60_000) {
    return cachedAccessToken;
  }

  const privateKey = await importPKCS8(
    account.private_key.replaceAll("\\n", "\n"),
    "RS256",
  );
  const assertion = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(account.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt()
    .setExpirationTime("1h")
    .sign(privateKey);

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const tokenResult = await response.json();
  if (!response.ok || typeof tokenResult.access_token !== "string") {
    throw new Error(
      `Google OAuth token request failed with HTTP ${response.status}.`,
    );
  }

  cachedAccessToken = tokenResult.access_token;
  accessTokenExpiresAt =
    Date.now() + Number(tokenResult.expires_in ?? 3600) * 1000;
  return cachedAccessToken;
}

function isUnregisteredToken(error: FcmError): boolean {
  return error.error?.details?.some(
    (detail) => detail.errorCode === "UNREGISTERED",
  ) ?? false;
}

Deno.serve(async (request) => {
  let serviceClient: ReturnType<typeof createClient> | null = null;
  let activeNotificationId: string | null = null;
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }
  if (!webhookSecret || !serviceRoleKey || !supabaseUrl) {
    return jsonResponse({ error: "Push service is not configured." }, 500);
  }
  const providedSecret = request.headers.get("x-push-webhook-secret") ?? "";
  if (!secureEqual(providedSecret, webhookSecret)) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  if (!firebaseServiceAccountJson) {
    return jsonResponse({ error: "Firebase credentials are not configured." }, 500);
  }

  try {
    const event = (await request.json()) as WebhookEvent;
    if (
      event.type &&
      (event.type !== "INSERT" ||
        event.schema !== "public" ||
        event.table !== "user_notifications")
    ) {
      return jsonResponse({ ignored: true });
    }

    const notificationId = event.record?.id ?? event.notification_id;
    if (!notificationId) {
      return jsonResponse({ error: "Missing notification_id." }, 400);
    }

    serviceClient = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    activeNotificationId = notificationId;
    const { data: notification, error: notificationError } = await serviceClient
      .from("user_notifications")
      .select(
        "id, recipient_id, event_type, priority, title, body, report_id, schedule_id, push_sent_at",
      )
      .eq("id", notificationId)
      .maybeSingle();
    if (notificationError) throw notificationError;
    if (!notification) {
      return jsonResponse({ error: "Notification not found." }, 404);
    }
    if (notification.push_sent_at) {
      return jsonResponse({ ignored: true, reason: "already sent" });
    }

    const { data: devices, error: deviceError } = await serviceClient
      .from("user_push_tokens")
      .select("token")
      .eq("user_id", notification.recipient_id)
      .eq("platform", "android");
    if (deviceError) throw deviceError;
    if (!devices?.length) {
      const { error } = await serviceClient
        .from("user_notifications")
        .update({ push_error: "No Android device token is registered." })
        .eq("id", notification.id);
      if (error) throw error;
      return jsonResponse({ sent: 0, reason: "no registered Android device" });
    }

    const account = JSON.parse(
      firebaseServiceAccountJson,
    ) as FirebaseServiceAccount;
    if (!account.project_id || !account.client_email || !account.private_key) {
      return jsonResponse({ error: "Firebase service account is invalid." }, 500);
    }
    const accessToken = await getFirebaseAccessToken(account);
    const data: Record<string, string> = {
      notification_id: notification.id,
      event_type: notification.event_type,
    };
    if (notification.report_id) data.report_id = notification.report_id;
    if (notification.schedule_id) data.schedule_id = notification.schedule_id;

    let sent = 0;
    const errors: string[] = [];
    for (const device of devices) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            authorization: `Bearer ${accessToken}`,
            "content-type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: device.token,
              notification: {
                title: notification.title,
                body: notification.body,
              },
              data,
              android: {
                priority:
                  notification.priority === "high" ||
                    notification.priority === "critical"
                    ? "HIGH"
                    : "NORMAL",
                notification: {
                  channel_id: "vigimat_maintenance_alerts",
                  icon: "ic_stat_vigimat",
                },
              },
            },
          }),
        },
      );
      if (response.ok) {
        sent += 1;
        continue;
      }

      const fcmError = (await response.json()) as FcmError;
      if (isUnregisteredToken(fcmError)) {
        const { error } = await serviceClient
          .from("user_push_tokens")
          .delete()
          .eq("user_id", notification.recipient_id)
          .eq("token", device.token);
        if (error) errors.push("Could not remove an expired device token.");
      }
      errors.push(
        `FCM HTTP ${response.status}: ${
          fcmError.error?.status ?? fcmError.error?.message ?? "send failed"
        }`,
      );
    }

    const { error: updateError } = await serviceClient
      .from("user_notifications")
      .update({
        push_sent_at: sent > 0 ? new Date().toISOString() : null,
        push_error: errors.length ? errors.slice(0, 10).join("; ") : null,
      })
      .eq("id", notification.id);
    if (updateError) throw updateError;

    return jsonResponse({ sent, failed: devices.length - sent });
  } catch (error) {
    if (serviceClient && activeNotificationId) {
      const { error: updateError } = await serviceClient
        .from("user_notifications")
        .update({
          push_error: error instanceof Error
            ? error.message.slice(0, 1000)
            : "Push notification delivery failed.",
        })
        .eq("id", activeNotificationId);
      if (updateError) {
        console.error("Could not save push delivery error:", updateError);
      }
    }
    console.error("Push notification delivery failed:", error);
    return jsonResponse({ error: "Push notification delivery failed." }, 500);
  }
});
