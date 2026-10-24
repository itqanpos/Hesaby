// supabase/functions/admin-update-user/index.ts

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

/// يحدد نوع الإجراء الفعلي بناءً على الفرق بين before/after.
function deriveAction(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): string {
  const beforeAdmin = before.is_platform_admin === true;
  const afterAdmin = after.is_platform_admin === true;
  if (!beforeAdmin && afterAdmin) return "user.grant_admin";
  if (beforeAdmin && !afterAdmin) return "user.revoke_admin";
  return "user.update";
}

/// يبني كائن diff يحتوي فقط الحقول التي تغيّرت فعلًا.
function diffFields(
  before: Record<string, unknown>,
  after: Record<string, unknown>,
): { beforeDiff: Record<string, unknown>; afterDiff: Record<string, unknown> } {
  const beforeDiff: Record<string, unknown> = {};
  const afterDiff: Record<string, unknown> = {};
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  for (const key of keys) {
    const b = before[key];
    const a = after[key];
    // مقارنة سطحية آمنة (الحقول هنا بدائية).
    if (JSON.stringify(b) !== JSON.stringify(a)) {
      beforeDiff[key] = b ?? null;
      afterDiff[key] = a ?? null;
    }
  }
  return { beforeDiff, afterDiff };
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

    // التحقق من صلاحية المنفّذ.
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
    const userId = (body.userId ?? "").trim();
    if (!userId) return json({ error: "معرّف المستخدم مطلوب" }, 400);

    if (userId === callerId && body.isPlatformAdmin === false) {
      return json({ error: "لا يمكنك إزالة صلاحية الأدمن عن نفسك" }, 400);
    }

    // ---- اقرأ الحالة الحالية (before) للتدقيق + للتحقق ----
    const { data: targetProfile, error: targetProfileError } = await adminClient
      .from("profiles")
      .select("user_id, full_name, is_platform_admin")
      .eq("user_id", userId)
      .maybeSingle();

    if (targetProfileError) {
      return json({ error: "تعذّر قراءة بيانات المستخدم", details: targetProfileError.message }, 500);
    }
    if (!targetProfile) {
      return json({ error: "المستخدم غير موجود" }, 404);
    }

    // الحالة الابتدائية قبل أي تعديل.
    const beforeState: Record<string, unknown> = {
      full_name: targetProfile.full_name ?? null,
      is_platform_admin: targetProfile.is_platform_admin === true,
    };
    // نضيف email فقط إن كان التعديل عليه (للحفاظ على نظافة الـ diff).
    const wantsEmailChange =
      typeof body.email === "string" && body.email.trim() !== "";

    // ---- بناء تحديثات Auth ----
    const authUpdates: Record<string, unknown> = {};
    let normalizedEmail: string | null = null;
    if (wantsEmailChange) {
      normalizedEmail = body.email.trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(normalizedEmail)) {
        return json({ error: "بريد إلكتروني غير صالح" }, 400);
      }
      authUpdates.email = normalizedEmail;
    }
    const wantsPasswordChange =
      typeof body.password === "string" && body.password.length > 0;
    if (wantsPasswordChange) {
      if (body.password.length < 6) {
        return json({ error: "كلمة المرور يجب أن تكون 6 أحرف على الأقل" }, 400);
      }
      authUpdates.password = body.password;
    }

    // ---- بناء تحديثات Profile ----
    const profileUpdates: Record<string, unknown> = {};
    let nextFullName: string | null | undefined;
    if (body.fullName !== undefined) {
      nextFullName = (body.fullName as string).trim() || null;
      profileUpdates.full_name = nextFullName;
    }
    let nextIsAdmin: boolean | undefined;
    if (body.isPlatformAdmin !== undefined) {
      nextIsAdmin = body.isPlatformAdmin === true;
      profileUpdates.is_platform_admin = nextIsAdmin;
    }

    // ---- تنفيذ تحديث Auth (إن وُجد) ----
    if (Object.keys(authUpdates).length > 0) {
      const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(
        userId,
        authUpdates,
      );
      if (updateAuthError) {
        return json({ error: "تعذّر تحديث بيانات الدخول", details: updateAuthError.message }, 400);
      }
    }

    // ---- تنفيذ تحديث Profile (إن وُجد) ----
    if (Object.keys(profileUpdates).length > 0) {
      const { error: updateProfileError } = await adminClient
        .from("profiles")
        .update(profileUpdates)
        .eq("user_id", userId);
      if (updateProfileError) {
        return json({ error: "تعذّر تحديث الملف الشخصي", details: updateProfileError.message }, 500);
      }
    }

    // ---- بناء الحالة النهائية (after) للتدقيق ----
    const afterState: Record<string, unknown> = {
      full_name: nextFullName !== undefined ? nextFullName : beforeState.full_name,
      is_platform_admin:
        nextIsAdmin !== undefined ? nextIsAdmin : beforeState.is_platform_admin,
    };
    if (normalizedEmail !== null) {
      afterState.email = normalizedEmail;
    }
    if (wantsPasswordChange) {
      // لا نكشف كلمة المرور، فقط نُسجّل حدوث التغيير.
      afterState.password_changed = true;
    }

    // ---- احسب diff + نوع الإجراء + اكتب التدقيق (best-effort) ----
    const action = deriveAction(beforeState, afterState);
    const { beforeDiff, afterDiff } = diffFields(beforeState, afterState);

    await writeAudit(adminClient, {
      actorId: callerId,
      action,
      entityId: userId,
      entityLabel:
        (afterState.email as string | undefined) ??
        (beforeState.full_name as string | null) ??
        null,
      before: beforeDiff,
      after: afterDiff,
    });

    return json({ user_id: userId, message: "تم التحديث بنجاح" });
  } catch (e) {
    console.error("admin-update-user fatal:", e);
    return json({ error: "خطأ داخلي غير متوقع" }, 500);
  }
});
