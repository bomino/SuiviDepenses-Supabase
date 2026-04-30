// Edge Function: invite-user
//
// Lets an authenticated admin send a Supabase invite-by-email to a new user
// without exposing the service-role key to the browser. The invited user
// receives a magic-link email; clicking it lets them set a password and log in.
//
// Authorization model:
//   1. verify_jwt: true (configured at deploy time) ensures only authenticated
//      callers reach this code.
//   2. We then read the caller's profiles row and reject if is_admin is false.
//   3. Only after both checks do we use the service-role key to invite.
//
// Deploy with the following environment variables (Supabase auto-provides them):
//   - SUPABASE_URL
//   - SUPABASE_ANON_KEY
//   - SUPABASE_SERVICE_ROLE_KEY
//
// Frontend invocation (already wired in index.html):
//   await window.supabase.functions.invoke('invite-user', { body: { email } });

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
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
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  // 1. Parse + validate body
  let body: { email?: string };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }
  const email = String(body.email || "").trim().toLowerCase();
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return jsonResponse({ error: "Invalid email" }, 400);
  }

  // 2. Resolve caller identity from the JWT
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) {
    return jsonResponse({ error: "Missing authorization header" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "Server misconfigured (missing env)" }, 500);
  }

  // Caller-scoped client to look up the caller's profile under their JWT.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: userData, error: userErr } = await callerClient.auth.getUser();
  if (userErr || !userData?.user) {
    return jsonResponse({ error: "Unauthenticated" }, 401);
  }

  // 3. Check admin status. profiles_select policy lets every authenticated
  // user read profiles, so the caller's own row is reachable.
  const { data: profile, error: profErr } = await callerClient
    .from("profiles")
    .select("is_admin")
    .eq("id", userData.user.id)
    .single();
  if (profErr || !profile?.is_admin) {
    return jsonResponse({ error: "Admin role required" }, 403);
  }

  // 4. Send the invite using the service-role key. This is the only place
  // the service-role key touches; it never leaves the function runtime.
  const adminClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: invited, error: inviteErr } = await adminClient.auth.admin
    .inviteUserByEmail(email);
  if (inviteErr) {
    // Common cases: user already exists, rate limit, malformed redirect URL.
    return jsonResponse({ error: inviteErr.message }, 400);
  }

  return jsonResponse(
    { ok: true, email, user_id: invited?.user?.id ?? null },
    200,
  );
});
