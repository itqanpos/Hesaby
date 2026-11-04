// supabase/functions/admin-delete-user/index.ts
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

async function writeAudit(
  adminClient: SupabaseClient,
  params: { actorId: string; entityId: string; entityLabel: string | null; },
): Promise<void> {
  try {
    await adminClient.rpc("audit_log_insert", {
      p_actor_user_id: params.actorId,
      p_action: "user.delete",
      p_entity_type: "user",
      p_entity_id: params.entityId,
      p_entity_label: params.entityLabel,
      p_before: null,
      p_after: null,
      p_metadata: null,
    });
  } catch (e) {
    console.error(`audit_log_insert failed:`, e);
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
    if (userError || !userData.user) return json({ error: "Invalid session" }, 401);
    const callerId = userData.user.id;

    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    const { data: callerProfile } = await adminClient
      .from("profiles")
      .select("is_platform_admin")
      .eq("user_id", callerId)
      .maybeSingle();

    if (!callerProfile?.is_platform_admin) return json({ error: "Forbidden" }, 403);

    const body = await req.json();
    const userId = (body.userId ?? "").trim();
    if (!userId) return json({ error: "معرّف المستخدم مطلوب" }, 400);

    if (userId === callerId) {
      return json({ error: "لا يمكنك حذف حسابك أنت!" }, 400);
    }

    // جلب الإيميل للتدقيق قبل الحذف
    const { data: targetUser } = await adminClient.auth.admin.getUserById(userId);
    const targetEmail = targetUser?.user?.email;

    // الحذف النهائي
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(userId);
    
    if (deleteError) {
      return json({ error: "تعذّر حذف المستخدم (قد يكون مرتبطاً ببيانات مالية)", details: deleteError.message }, 400);
    }

    await writeAudit(adminClient, {
      actorId: callerId,
      entityId: userId,
      entityLabel: targetEmail,
    });

    return json({ message: "تم حذف المستخدم نهائياً" });
  } catch (e) {
    console.error("admin-delete-user fatal:", e);
    return json({ error: "خطأ داخلي غير متوقع" }, 500);
  }
});
