-- ============================================================================
-- Migration: Platform Overview KPI aggregation
-- File: supabase/migrations/20260102_platform_overview.sql
-- Run in: Supabase SQL Editor (idempotent)
-- ============================================================================
--
-- ما تفعله هذه الهجرة:
--   • تضيف get_platform_overview() RPC واحد يُغذي لوحة المعلومات الرئيسية.
--   • قراءة فقط (SECURITY DEFINER)، محمية بـ is_platform_admin().
--   • تُرجع RETURNS TABLE صريح (typed) — لا jsonb ديناميكي.
--
-- قرارات معمارية (مبنية على فحص DB الفعلي):
--   • companies  = مصدر الشركات (tenants legacy/مهجور — لا نستخدمها).
--   • sales      = مصدر KPIs المبيعات (invoices مرتبط بـ tenants legacy).
--   • subscription_payments = مصدر إيرادات المنصة.
--   • sales_today يُستثنى منها status='voided' (آمن حتى لو القيمة غير موجودة).
--   • "today/month/year" محسوبة بتوقيت Africa/Cairo (المستخدم مصري).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_platform_overview()
RETURNS TABLE (
  -- Companies
  companies_total           int,
  companies_active          int,
  companies_trial           int,
  companies_suspended       int,
  companies_lifetime        int,
  companies_new_today       int,
  companies_new_this_month  int,
  companies_new_this_year   int,
  companies_active_last_7d  int,
  -- Users & structure
  users_total               int,
  branches_total            int,
  -- Business
  sales_total               bigint,
  sales_today               bigint,
  sales_this_month          bigint,
  products_total            bigint,
  customers_total           bigint,
  -- Revenue (platform)
  revenue_total             numeric,
  revenue_this_month        numeric,
  -- Data source timestamps
  computed_at               timestamptz,
  -- Recent activity
  recent_companies          jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  -- نافذة زمنية بتوقيت القاهرة — لتفادي الانحراف حول منتصف الليل.
  v_now          timestamptz := now();
  v_today_start  timestamptz :=
    date_trunc('day',   v_now AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'Africa/Cairo';
  v_month_start  timestamptz :=
    date_trunc('month', v_now AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'Africa/Cairo';
  v_year_start   timestamptz :=
    date_trunc('year',  v_now AT TIME ZONE 'Africa/Cairo') AT TIME ZONE 'Africa/Cairo';
  v_7d_ago       timestamptz := v_now - interval '7 days';
BEGIN
  IF auth.uid() IS NULL OR NOT public.is_platform_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    -- ---------- Companies ----------
    (SELECT COUNT(*)::int FROM public.companies),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE subscription_status = 'active'
        AND NOT is_suspended
        AND NOT is_lifetime),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE subscription_status = 'trial'
        AND NOT is_suspended),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE is_suspended = true),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE is_lifetime = true
        AND NOT is_suspended),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE created_at >= v_today_start),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE created_at >= v_month_start),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE created_at >= v_year_start),
    (SELECT COUNT(*)::int FROM public.companies
      WHERE updated_at >= v_7d_ago),

    -- ---------- Users & structure ----------
    (SELECT COUNT(*)::int FROM public.profiles),
    (SELECT COUNT(*)::int FROM public.branches),

    -- ---------- Sales ----------
    (SELECT COUNT(*)::bigint FROM public.sales
      WHERE status IS DISTINCT FROM 'voided'),
    (SELECT COUNT(*)::bigint FROM public.sales
      WHERE status IS DISTINCT FROM 'voided'
        AND sale_date >= v_today_start),
    (SELECT COUNT(*)::bigint FROM public.sales
      WHERE status IS DISTINCT FROM 'voided'
        AND sale_date >= v_month_start),

    -- ---------- Products & customers ----------
    (SELECT COUNT(*)::bigint FROM public.products),
    (SELECT COUNT(*)::bigint FROM public.customers),

    -- ---------- Revenue ----------
    (SELECT COALESCE(SUM(amount), 0)::numeric FROM public.subscription_payments),
    (SELECT COALESCE(SUM(amount), 0)::numeric FROM public.subscription_payments
      WHERE created_at >= v_month_start),

    -- ---------- Computed at ----------
    v_now,

    -- ---------- Recent companies (last 5) ----------
    (SELECT COALESCE(
              jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC),
              '[]'::jsonb)
       FROM (
         SELECT id,
                name,
                subscription_status,
                is_suspended,
                is_lifetime,
                created_at
           FROM public.companies
          ORDER BY created_at DESC
          LIMIT 5
       ) AS t
    );
END;
$$;

-- المنح: authenticated فقط (التحقق من is_platform_admin داخليًا).
GRANT EXECUTE ON FUNCTION public.get_platform_overview() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_platform_overview() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.get_platform_overview() IS
  'Single-call KPI aggregator for Super Admin Overview tab. Admin-only.';

-- ============================================================================
-- Verification block — شغّل هذا بعد الـ migration وأرسل المخرج
-- ============================================================================
-- (1) توقيع الدالة
SELECT p.proname,
       pg_get_function_result(p.oid) AS returns,
       pg_get_userbyid(p.proowner)   AS owner,
       p.prosecdef                   AS security_definer
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'get_platform_overview';

-- (2) صلاحيات التنفيذ
SELECT grantee, privilege_type
  FROM information_schema.routine_privileges
 WHERE routine_schema='public' AND routine_name='get_platform_overview'
 ORDER BY grantee;

-- (3) اختبار فعلي — يجب أن يعرض الأرقام الحقيقية
SELECT * FROM public.get_platform_overview();
