// Edge Function: delete-user
//
// Lets an authenticated admin remove another user. Performs:
//   1. Caller is admin (via JWT + profiles.is_admin).
//   2. Caller is not deleting themselves (self-protection).
//   3. Cleanup of the target's receipt files in Storage (auth.users delete
//      cascades to profiles + expenses via FK, but the storage objects
//      under receipts/<user_id>/* would be orphaned otherwise).
//   4. auth.admin.deleteUser() via the service-role key.
//
// Same auth + CORS skeleton as invite-user; intentionally NOT shared with
// it (one tiny copy beats premature abstraction for two functions).

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, content-type, apikey, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
  const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !SERVICE_ROLE_KEY) {
    return jsonResponse({ error: "Server misconfigured (missing env)" }, 500);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header" }, 401);
  }

  let body: { user_id?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const targetId = String(body.user_id || "").trim();
  if (!targetId || !/^[0-9a-f-]{36}$/i.test(targetId)) {
    return jsonResponse({ error: "Invalid user_id" }, 400);
  }

  // 1. Resolve caller from JWT and confirm admin.
  const userInfoRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "Authorization": authHeader,
      "apikey": SUPABASE_ANON_KEY,
    },
  });
  if (!userInfoRes.ok) {
    return jsonResponse({ error: "Unauthenticated" }, 401);
  }
  const userInfo = await userInfoRes.json() as { id?: string };
  const callerId = userInfo.id;
  if (!callerId) {
    return jsonResponse({ error: "Unauthenticated" }, 401);
  }

  if (callerId === targetId) {
    return jsonResponse({ error: "Cannot delete your own account" }, 400);
  }

  const profileRes = await fetch(
    `${SUPABASE_URL}/rest/v1/profiles?id=eq.${callerId}&select=is_admin`,
    {
      headers: {
        "Authorization": authHeader,
        "apikey": SUPABASE_ANON_KEY,
        "Accept": "application/json",
      },
    },
  );
  if (!profileRes.ok) {
    return jsonResponse({ error: "Could not load profile" }, 500);
  }
  const profileRows = await profileRes.json() as Array<{ is_admin?: boolean }>;
  if (!profileRows[0]?.is_admin) {
    return jsonResponse({ error: "Admin role required" }, 403);
  }

  // 2. List + delete the target's receipts under receipts/<target_id>/.
  // Best-effort: ignore failures (storage might already be empty, or list
  // could be paginated — we drain whatever the first page returns and trust
  // it's enough for typical small expense counts).
  try {
    const listRes = await fetch(
      `${SUPABASE_URL}/storage/v1/object/list/receipts`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
          "apikey": SERVICE_ROLE_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ prefix: targetId, limit: 1000 }),
      },
    );
    if (listRes.ok) {
      const items = await listRes.json() as Array<{ name?: string }>;
      const paths = items
        .map((it) => it.name ? `${targetId}/${it.name}` : null)
        .filter((p): p is string => !!p);
      if (paths.length > 0) {
        await fetch(`${SUPABASE_URL}/storage/v1/object/receipts`, {
          method: "DELETE",
          headers: {
            "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
            "apikey": SERVICE_ROLE_KEY,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ prefixes: paths }),
        });
      }
    }
  } catch (_) { /* ignore — proceed to delete the user even if cleanup partial */ }

  // 3. Delete the auth.users row. FKs cascade to profiles + expenses.
  const delRes = await fetch(
    `${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(targetId)}`,
    {
      method: "DELETE",
      headers: {
        "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
        "apikey": SERVICE_ROLE_KEY,
      },
    },
  );
  if (!delRes.ok) {
    const errText = await delRes.text().catch(() => "");
    return jsonResponse(
      { error: errText || "Delete failed" },
      delRes.status,
    );
  }

  return jsonResponse({ ok: true, user_id: targetId }, 200);
});
