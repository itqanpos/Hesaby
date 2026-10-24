// supabase/functions/admin-create-user/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/// Best-effort audit write. Never fails the request on audit errors.
///
/// The caller runs with the service_role key, which we granted EXECUTE
/// on audit_log_insert() via the A1 migration. If this ever fails, we log
/// to console but the primary operation still succeeds — audit is a
/// secondary concern that should not break user flows.
async function writeAudit(
  adminClient: SupabaseClient,
  params: {
    actorId: string;
    action: string;
    entityId: string;
    entityLabel: string | null;
    before?: Record<string, unknown> | null;
    after?: Record<string, unknown> | null;
  },
): Promise<void> {
  try {
    const { error } = await adminClient.rpc("audit_log_insert", {
      p_actor_user_id: params.actorId,
      p_action: params.action,
      p_entity_type: "user",
      p_entity_id: params.entityId,
      p_entity_label: params.entityLabel,
      p_reason: null,
      p_before: params.before ?? null,
      p_after: params.after ?? null,
      p_metadata: null,
    });
    if (error) {
      console.error(
        `audit_log_insert(${params.action}) returned error:`,
        error.message,
      );
    }
  } catch (e) {
    console.error(`audit_log_insert(${params.action}) threw:`, e);
  }
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

    const userClient = createClient(SUPABASE_URL, ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: userData, error: userError } = await userClient.auth.getUser();
    if (userError || !userData.user) {
      return json({ error: "Invalid session", details: userError?.message }, 401);
    }

    const callerId = userData.user.id;

    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerProfile, error: callerProfileError } = await adminClient
      .from("profiles")
      .select("is_platform_admin")
      .eq("user_id", callerId)
      .maybeSingle();

    if (callerProfileError) {
      return json({ error: "Failed to verify permissions", details: callerProfileError.message }, 500);
    }
    if (!callerProfile?.is_platform_admin) {
      return json({ error: "Forbidden: platform admin only" }, 403);
    }

    const body = await req.json();
    const email = (body.email ?? "").trim().toLowerCase();
    const password = body.password ?? "";
    const fullName = (body.fullName ?? "").trim();

    if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
      return json({ error: "بريد إلكتروني غير صالح" }, 400);
    }
    if (password.length < 6) {
      return json({ error: "كلمة المرور يجب أن تكون 6 أحرف على الأقل" }, 400);
    }

    const { data: created, error: createError } = await adminClient.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: fullName ? { full_name: fullName } : undefined,
    });

    if (createError || !created?.user) {
      return json({ error: "تعذّر إنشاء المستخدم", details: createError?.message }, 400);
    }

    const { error: profileUpsertError } = await adminClient
      .from("profiles")
      .upsert(
        {
          user_id: created.user.id,
          full_name: fullName || null,
          is_platform_admin: false,
        },
        { onConflict: "user_id" },
      );

    if (profileUpsertError) {
      console.error("Profile upsert failed:", profileUpsertError);
    }

    // ---- Audit (best-effort) ----
    await writeAudit(adminClient, {
      actorId: callerId,
      action: "user.create",
      entityId: created.user.id,
      entityLabel: email,
      after: {
        email,
        full_name: fullName || null,
        is_platform_admin: false,
      },
    });

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
