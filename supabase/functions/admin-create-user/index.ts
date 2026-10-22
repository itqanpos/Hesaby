// supabase/functions/admin-create-user/index.ts
//
// Provisions a new user via the Supabase Admin API.
//
// SECURITY:
// * The caller's JWT is verified by Supabase (verify_jwt = true).
// * We then re-check `profiles.is_platform_admin` using the service role
//   before touching `auth.admin.*`.
// * The service-role key NEVER leaves this function; it is not embedded in
//   the Flutter app.
//
// Request body:
//   { email: string, password: string, fullName?: string }
// Response:
//   200 { user_id, email, message }
//   4xx { error, details? }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

interface CreateUserBody {
  email?: string;
  password?: string;
  fullName?: string;
}

serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

    // --- 1. Verify the caller is a platform admin ---------------------------
    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: "Invalid session", details: userError?.message }, 401);
    }

    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from("profiles")
      .select("is_platform_admin")
      .eq("id", userData.user.id)
      .maybeSingle();

    if (callerProfileError) {
      return json({ error: "Failed to verify permissions", details: callerProfileError.message }, 500);
    }
    if (!callerProfile?.is_platform_admin) {
      return json({ error: "Forbidden: platform admin only" }, 403);
    }

    // --- 2. Validate input --------------------------------------------------
    const body = (await req.json()) as CreateUserBody;
    const email = (body.email ?? "").trim().toLowerCase();
    const password = body.password ?? "";
    const fullName = (body.fullName ?? "").trim();

    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ error: "بريد إلكتروني غير صالح" }, 400);
    }
    if (password.length < 6) {
      return json({ error: "كلمة المرور يجب أن تكون 6 أحرف على الأقل" }, 400);
    }

    // --- 3. Create the user (auto-confirm, admin-provisioned) ---------------
    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: fullName ? { full_name: fullName } : undefined,
    });

    if (createError || !created?.user) {
      return json({ error: "تعذّر إنشاء المستخدم", details: createError?.message }, 400);
    }

    // --- 4. Ensure the profile row exists with the correct full_name --------
    // The handle_new_user trigger normally creates it; we upsert defensively.
    const { error: profileUpsertError } = await adminClient
      .from("profiles")
      .upsert(
        {
          id: created.user.id,
          full_name: fullName || null,
          is_platform_admin: false,
        },
        { onConflict: "id" },
      );

    if (profileUpsertError) {
      // Log but do not fail — user exists, admin can fix the profile later.
      console.error("Profile upsert failed:", profileUpsertError);
    }

    return json({
      user_id: created.user.id,
      email: created.user.email,
      message: "تم إنشاء المستخدم بنجاح",
    });
  } catch (e) {
    console.error("admin-create-user fatal:", e);
    return json({ error: "خطأ داخلي غير متوقع" }, 500);
  }
});
