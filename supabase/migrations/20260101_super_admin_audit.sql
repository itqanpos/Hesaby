-- ============================================================================
-- Migration: Super Admin — Audit Log + Lifetime Subscription
-- File: supabase/migrations/20260101_super_admin_audit.sql
-- Run in: Supabase SQL Editor (idempotent — can re-run safely)
-- ============================================================================
--
-- ما تفعله هذه الهجرة:
--   1. إضافة عمود is_lifetime إلى companies (ترخيص مدى الحياة).
--   2. إنشاء جدول audit_logs (append-only) + RLS (قراءة للأدمن فقط).
--   3. إنشاء audit_log_insert() — دالة SECURITY DEFINER للكتابة من RPC/Edge Functions.
--   4. تحديث admin_suspend_company() — نفس التوقيع + تسجيل تدقيق كامل.
--   5. تحديث admin_update_subscription() — نفس التوقيع + دعم lifetime + تدقيق.
--   6. إنشاء get_audit_logs() — لتبويب سجل التدقيق في لوحة الإدارة.
--
-- ضمانات أمنية:
--   • audit_logs: لا سياسة INSERT/UPDATE/DELETE — الكتابة فقط عبر SECURITY DEFINER.
--   • REVOKE EXECUTE on audit_log_insert من PUBLIC — لا يمكن للمستخدم العادي حقن سجلات.
--   • كل RPC تتحقق من is_platform_admin() + auth.uid() قبل التنفيذ.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1) companies.is_lifetime
-- ---------------------------------------------------------------------------
ALTER TABLE public.companies
  ADD COLUMN IF NOT EXISTS is_lifetime boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.companies.is_lifetime IS
  'True عندما يكون الاشتراك مدى الحياة. عند true يُهمَل subscribed_until.';


-- ---------------------------------------------------------------------------
-- 2) audit_logs
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at     timestamptz NOT NULL DEFAULT now(),
  actor_user_id  uuid        REFERENCES auth.users(id) ON DELETE SET NULL,
  actor_email    text,
  action         text        NOT NULL,          -- e.g. 'company.suspend'
  entity_type    text        NOT NULL,          -- 'company' | 'user' | 'system'
  entity_id      uuid,
  entity_label   text,                          -- اسم الشركة أو بريد المستخدم للعرض السريع
  reason         text,                          -- سبب الإيقاف/منح الصلاحية (إن وُجد)
  before_state   jsonb,
  after_state    jsonb,
  metadata       jsonb
);

CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at
  ON public.audit_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_entity
  ON public.audit_logs (entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_actor
  ON public.audit_logs (actor_user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action
  ON public.audit_logs (action);

COMMENT ON TABLE public.audit_logs IS
  'Append-only audit trail. Writes only via SECURITY DEFINER functions.';

-- RLS: read-only for platform admins; no write policies (defense in depth).
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS audit_logs_select_platform_admin ON public.audit_logs;
CREATE POLICY audit_logs_select_platform_admin
  ON public.audit_logs
  FOR SELECT
  TO authenticated
  USING (public.is_platform_admin());

-- ملاحظة: لا توجد سياسة INSERT/UPDATE/DELETE — حتى لو حاول عميل الكتابة مباشرة
-- (وهو مستحيل بدون سياسة)، لن ينجح. الكتابة حصرًا عبر audit_log_insert().


-- ---------------------------------------------------------------------------
-- 3) audit_log_insert() — SECURITY DEFINER writer
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.audit_log_insert(
  p_actor_user_id uuid,
  p_action        text,
  p_entity_type   text,
  p_entity_id     uuid,
  p_entity_label  text   DEFAULT NULL,
  p_reason        text   DEFAULT NULL,
  p_before        jsonb  DEFAULT NULL,
  p_after         jsonb  DEFAULT NULL,
  p_metadata      jsonb  DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id          uuid;
  v_actor_email text;
BEGIN
  IF p_action IS NULL OR length(trim(p_action)) = 0 THEN
    RAISE EXCEPTION 'audit_log_insert: p_action is required'
      USING ERRCODE = '22023';
  END IF;

  IF p_actor_user_id IS NOT NULL THEN
    SELECT u.email INTO v_actor_email
      FROM auth.users u
     WHERE u.id = p_actor_user_id;
  END IF;

  INSERT INTO public.audit_logs (
    actor_user_id, actor_email, action,
    entity_type, entity_id, entity_label, reason,
    before_state, after_state, metadata
  ) VALUES (
    p_actor_user_id, v_actor_email, p_action,
    p_entity_type, p_entity_id, p_entity_label, p_reason,
    p_before, p_after, p_metadata
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Only service_role (Edge Functions) may call directly.
-- The admin RPCs below run as their owner (postgres) → unaffected by REVOKE.
REVOKE ALL ON FUNCTION public.audit_log_insert(
  uuid, text, text, uuid, text, text, jsonb, jsonb, jsonb
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.audit_log_insert(
  uuid, text, text, uuid, text, text, jsonb, jsonb, jsonb
) TO service_role;


-- ---------------------------------------------------------------------------
-- 4) admin_suspend_company() — same signature + audit + auth hardening
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_suspend_company(
  p_company_id uuid,
  p_suspend    boolean,
  p_reason     text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor        uuid := auth.uid();
  v_before       jsonb;
  v_after        jsonb;
  v_company_name text;
BEGIN
  IF v_actor IS NULL OR NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  IF p_suspend AND (p_reason IS NULL OR length(trim(p_reason)) = 0) THEN
    RAISE EXCEPTION 'suspension reason is required' USING ERRCODE = '22023';
  END IF;

  SELECT to_jsonb(c.*), c.name
    INTO v_before, v_company_name
    FROM public.companies c
   WHERE c.id = p_company_id;

  IF v_before IS NULL THEN
    RAISE EXCEPTION 'company not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.companies
     SET is_suspended      = p_suspend,
         suspension_reason = CASE WHEN p_suspend THEN p_reason ELSE NULL END,
         updated_at        = now()
   WHERE id = p_company_id
  RETURNING to_jsonb(companies.*) INTO v_after;

  PERFORM public.audit_log_insert(
    p_actor_user_id => v_actor,
    p_action        => CASE WHEN p_suspend
                            THEN 'company.suspend'
                            ELSE 'company.unsuspend' END,
    p_entity_type   => 'company',
    p_entity_id     => p_company_id,
    p_entity_label  => v_company_name,
    p_reason        => p_reason,
    p_before        => v_before,
    p_after         => v_after
  );
END;
$$;


-- ---------------------------------------------------------------------------
-- 5) admin_update_subscription() — same signature + lifetime + audit
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_update_subscription(
  p_company_id       uuid,
  p_status           text,
  p_plan_id          text,
  p_billing_cycle    text,
  p_subscribed_until timestamptz
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_actor        uuid := auth.uid();
  v_before       jsonb;
  v_after        jsonb;
  v_company_name text;
  v_is_lifetime  boolean;
  v_until        timestamptz;
BEGIN
  IF v_actor IS NULL OR NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  -- نمط "مدى الحياة" = active + billing_cycle = 'lifetime'.
  -- عند الإلغاء نُطفئ is_lifetime تلقائيًا (يُحفظ في before_state).
  v_is_lifetime := (p_status = 'active' AND p_billing_cycle = 'lifetime');
  v_until       := CASE WHEN v_is_lifetime THEN NULL ELSE p_subscribed_until END;

  SELECT to_jsonb(c.*), c.name
    INTO v_before, v_company_name
    FROM public.companies c
   WHERE c.id = p_company_id;

  IF v_before IS NULL THEN
    RAISE EXCEPTION 'company not found' USING ERRCODE = 'P0002';
  END IF;

  UPDATE public.companies
     SET subscription_status = p_status,
         plan_id             = p_plan_id,
         billing_cycle       = p_billing_cycle,
         subscribed_until    = v_until,
         is_lifetime         = v_is_lifetime,
         updated_at          = now()
   WHERE id = p_company_id
  RETURNING to_jsonb(companies.*) INTO v_after;

  PERFORM public.audit_log_insert(
    p_actor_user_id => v_actor,
    p_action        => 'company.update_subscription',
    p_entity_type   => 'company',
    p_entity_id     => p_company_id,
    p_entity_label  => v_company_name,
    p_reason        => NULL,
    p_before        => v_before,
    p_after         => v_after
  );
END;
$$;


-- ---------------------------------------------------------------------------
-- 6) get_audit_logs() — feed for the Audit Log tab
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_audit_logs(
  p_action_prefix text DEFAULT NULL,
  p_entity_type   text DEFAULT NULL,
  p_search        text DEFAULT NULL,
  p_limit         int  DEFAULT 100,
  p_offset        int  DEFAULT 0
) RETURNS TABLE (
  id            uuid,
  created_at    timestamptz,
  actor_user_id uuid,
  actor_email   text,
  action        text,
  entity_type   text,
  entity_id     uuid,
  entity_label  text,
  reason        text,
  before_state  jsonb,
  after_state   jsonb,
  metadata      jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT al.id, al.created_at, al.actor_user_id, al.actor_email,
         al.action, al.entity_type, al.entity_id, al.entity_label,
         al.reason, al.before_state, al.after_state, al.metadata
    FROM public.audit_logs al
   WHERE (p_action_prefix IS NULL
          OR al.action LIKE p_action_prefix || '%')
     AND (p_entity_type IS NULL
          OR al.entity_type = p_entity_type)
     AND (p_search IS NULL OR length(trim(p_search)) = 0
          OR al.entity_label ILIKE '%' || p_search || '%'
          OR al.actor_email  ILIKE '%' || p_search || '%'
          OR al.reason       ILIKE '%' || p_search || '%')
   ORDER BY al.created_at DESC
   LIMIT  GREATEST(1, LEAST(COALESCE(p_limit, 100), 500))
   OFFSET GREATEST(0, COALESCE(p_offset, 0));
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_audit_logs(
  text, text, text, int, int
) TO authenticated;


-- ============================================================================
-- ✅ Done. Next: run the verification block below and paste the output.
-- ============================================================================


-- ============================================================================
-- Verification block (paste output back)
-- ============================================================================
-- (1) audit_logs structure
SELECT column_name, data_type, is_nullable
  FROM information_schema.columns
 WHERE table_schema='public' AND table_name='audit_logs'
 ORDER BY ordinal_position;

-- (2) audit_logs policies (يجب أن يكون صف واحد SELECT فقط)
SELECT policyname, cmd, qual
  FROM pg_policies
 WHERE schemaname='public' AND tablename='audit_logs';

-- (3) function signatures بعد التعديل
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef                      AS security_definer,
       pg_get_userbyid(p.proowner)      AS owner
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public'
   AND p.proname IN ('audit_log_insert','get_audit_logs',
                     'admin_suspend_company','admin_update_subscription')
 ORDER BY p.proname;

-- (4) is_lifetime column
SELECT column_name, data_type, is_nullable, column_default
  FROM information_schema.columns
 WHERE table_schema='public'
   AND table_name='companies'
   AND column_name='is_lifetime';

-- (5) EXECUTE privileges (يجب أن يظهر service_role فقط على audit_log_insert)
SELECT grantee, privilege_type
  FROM information_schema.routine_privileges
 WHERE routine_schema='public'
   AND routine_name='audit_log_insert';
