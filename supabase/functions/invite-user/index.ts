// Edge Function: invite-user
//
// Lets an authenticated admin send a Supabase invite-by-email to a new user
// without exposing the service-role key to the browser.
//
// Implemented with direct fetch calls (no @supabase/supabase-js import) to
// keep the bundle small and the control flow explicit.

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
  // 1. CORS preflight — must return BEFORE any body parsing or JWT handling.
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

  // 2. Caller's JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header" }, 401);
  }

  // 3. Body
  let body: { email?: string; redirectTo?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const email = String(body.email || "").trim().toLowerCase();
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return jsonResponse({ error: "Invalid email" }, 400);
  }
  const redirectTo = typeof body.redirectTo === "string" && body.redirectTo
    ? body.redirectTo
    : null;

  // 4. Verify caller is admin via the REST API, scoped by the caller's JWT.
  // Existing profiles_select policy lets every authenticated user read profiles,
  // so the caller's own row is reachable. We then check is_admin.
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

  // 5. Send the invite using the service-role key against the GoTrue admin API.
  // Pass redirectTo as a query string parameter so the post-acceptance redirect
  // lands on the deployed app URL (not the bare origin Site URL fallback).
  const inviteUrl = redirectTo
    ? `${SUPABASE_URL}/auth/v1/invite?redirect_to=${encodeURIComponent(redirectTo)}`
    : `${SUPABASE_URL}/auth/v1/invite`;
  const inviteRes = await fetch(inviteUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${SERVICE_ROLE_KEY}`,
      "apikey": SERVICE_ROLE_KEY,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email }),
  });
  const inviteData = await inviteRes.json().catch(() => ({}));
  if (!inviteRes.ok) {
    return jsonResponse(
      { error: (inviteData as { msg?: string }).msg || "Invite failed" },
      inviteRes.status,
    );
  }

  return jsonResponse(
    { ok: true, email, user_id: (inviteData as { id?: string }).id ?? null },
    200,
  );
});
