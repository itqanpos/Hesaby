-- ============================================================================
-- Migration: Sync Overview (Phase 5a — partial)
-- File: supabase/migrations/20260103_sync_overview.sql
-- ============================================================================
--
-- ما تفعله:
--   • get_sync_overview() — يُرجع حالة الأجهزة المُستنتَجة من invoices.device_id
--     و invoices.synced_at فقط.
--
-- قيود صريحة (Section 17 — لا ادعاء بما لا نعرفه):
--   • التتبع الحقيقي للمزامنة (العمليات المعلقة، الفاشلة، أسبابها، المحاولات،
--     التعارضات) غير متاح — لا توجد جداول sync_events/device_registrations.
--   • النظام الحديث (sales، purchases، stock_movements) لا يسجّل sync tracking.
--   • invoices.tenant_id قد لا يطابق companies.id (LEFT JOIN آمن → NULL إن لم يطابق).
--   • "آخر مزامنة" = MAX(invoices.synced_at) للفواتير المزامنة فقط.
--
-- الترقية المستقبلية: 20260104_device_sync.sql (Phase 5b) — جداول جديدة +
--   تعديل التطبيق لتسجيل sync_events فعليًا. تحديث هذه الدالة لاحقًا.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_sync_overview()
RETURNS TABLE (
  devices_total         int,
  devices_active_24h    int,
  devices_active_7d     int,
  devices_stale_30d     int,
  devices_never_synced  int,
  invoices_with_device  bigint,
  invoices_synced       bigint,
  invoices_pending      bigint,
  computed_at           timestamptz,
  devices               jsonb
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
  WITH dev_stats AS (
    SELECT
      i.device_id,
      -- LEFT JOIN آمن: NULL إن لم يطابق tenant_id شركة.
      (SELECT c.name
         FROM public.companies c
        WHERE c.id = MAX(i.tenant_id)
        LIMIT 1)                                     AS company_name,
      COUNT(*)::bigint                               AS invoices_count,
      MAX(i.synced_at)                               AS last_sync_at,
      MAX(i.created_at)                              AS last_activity_at
    FROM public.invoices i
    WHERE i.device_id IS NOT NULL
      AND length(trim(i.device_id)) > 0
    GROUP BY i.device_id
  )
  SELECT
    (SELECT COUNT(*)::int FROM dev_stats),
    (SELECT COUNT(*)::int FROM dev_stats
      WHERE last_sync_at >= now() - interval '24 hours'),
    (SELECT COUNT(*)::int FROM dev_stats
      WHERE last_sync_at >= now() - interval '7 days'),
    (SELECT COUNT(*)::int FROM dev_stats
      WHERE last_sync_at < now() - interval '30 days'),
    (SELECT COUNT(*)::int FROM dev_stats
      WHERE last_sync_at IS NULL),
    (SELECT COUNT(*)::bigint FROM public.invoices
      WHERE device_id IS NOT NULL AND length(trim(device_id)) > 0),
    (SELECT COUNT(*)::bigint FROM public.invoices
      WHERE device_id IS NOT NULL AND synced_at IS NOT NULL),
    (SELECT COUNT(*)::bigint FROM public.invoices
      WHERE device_id IS NOT NULL AND synced_at IS NULL),
    now(),
    (SELECT COALESCE(
              jsonb_agg(to_jsonb(d) ORDER BY d.last_sync_at DESC NULLS LAST),
              '[]'::jsonb)
       FROM (
         SELECT
           device_id,
           company_name,
           invoices_count,
           last_sync_at,
           last_activity_at
         FROM dev_stats
         ORDER BY last_sync_at DESC NULLS LAST
         LIMIT 200
       ) AS d
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sync_overview() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_sync_overview() FROM PUBLIC, anon;

COMMENT ON FUNCTION public.get_sync_overview() IS
  'Partial sync overview (devices tracked via invoices only). See Phase 5b for full sync tracking.';

-- ============================================================================
-- Verification — شغّل هذا وأرسل المخرج
-- ============================================================================
SELECT p.proname,
       pg_get_userbyid(p.proowner) AS owner,
       p.prosecdef                 AS security_definer
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname='public' AND p.proname='get_sync_overview';

SELECT grantee, privilege_type
  FROM information_schema.routine_privileges
 WHERE routine_schema='public' AND routine_name='get_sync_overview'
 ORDER BY grantee;
