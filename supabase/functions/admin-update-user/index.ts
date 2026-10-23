// supabase/functions/admin-update-user/index.ts

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.0";

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

    // ⬇️ استخدام user_id بدلاً من id
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

    const authUpdates: Record<string, unknown> = {};
    if (body.email && body.email.trim()) {
      const email = body.email.trim().toLowerCase();
      if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
        return json({ error: "بريد إلكتروني غير صالح" }, 400);
      }
      authUpdates.email = email;
    }
    if (body.password && body.password.length > 0) {
      if (body.password.length < 6) {
        return json({ error: "كلمة المرور يجب أن تكون 6 أحرف على الأقل" }, 400);
      }
      authUpdates.password = body.password;
    }

    if (Object.keys(authUpdates).length > 0) {
      const { error: updateAuthError } = await adminClient.auth.admin.updateUserById(
        userId,
        authUpdates,
      );
      if (updateAuthError) {
        return json({ error: "تعذّر تحديث بيانات الدخول", details: updateAuthError.message }, 400);
      }
    }

    const profileUpdates: Record<string, unknown> = {};
    if (body.fullName !== undefined) {
      profileUpdates.full_name = body.fullName.trim() || null;
    }
    if (body.isPlatformAdmin !== undefined) {
      profileUpdates.is_platform_admin = body.isPlatformAdmin;
    }

    if (Object.keys(profileUpdates).length > 0) {
      // ⬇️ استخدام user_id بدلاً من id
      const { error: updateProfileError } = await adminClient
        .from("profiles")
        .update(profileUpdates)
        .eq("user_id", userId);
      if (updateProfileError) {
        return json({ error: "تعذّر تحديث الملف الشخصي", details: updateProfileError.message }, 500);
      }
    }

    return json({ user_id: userId, message: "تم التحديث بنجاح" });
  } catch (e) {
    console.error("admin-update-user fatal:", e);
    return json({ error: "خطأ داخلي غير متوقع" }, 500);
  }
});
