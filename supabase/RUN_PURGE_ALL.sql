-- ============================================================================
--  ⚠⚠⚠  RUN_PURGE_ALL.sql — هذا يحذف فعلاً. لا تراجع بعده.  ⚠⚠⚠
--
--  ما يحذفه:
--    الاستحقاقات · الإيصالات · التخصيصات · حركات الصندوق · السندات
--    الأشهر المقفلة · سجل التدقيق · المحادثات
--    وكل حسابات المشتركين · وسجل العدايل الثمانية
--
--  ما يبقى:
--    حساب الإدارة (حسابك) · الإعدادات — اسم الجمعية، الاشتراك، «ماعدا»،
--    بيانات المصرف · وحسابات Google نفسها في auth.users
--
--  وما عليك إعادته بعده:
--    ١ — العدايل، بالترتيب الذي تريده. أوّل من تُدخله يأخذ A-01.
--    ٢ — أمين الصندوق والمدير المالي (الحقلان ON DELETE SET NULL، فيُفرَغان).
--    ٣ — رمز دخولٍ لكل عديل.
--
--  ⚠ ولا يبقى في القاعدة أثرٌ يقول إنّ هذا جرى: سجل التدقيق يُمسح معه. ثقبٌ
--    مقصود في القاعدة ١٢، اعرفه قبل أن تضغط.
--
--  ── لماذا من هنا وليس من التطبيق ─────────────────────────────────────────
--    زر «منطقة الخطر» يرفض بالرمز 21000. وثلاثة فحوص أثبتت أنّ القاعدة بريئة:
--    الدالة تنجح عند ندائها مباشرةً، وتنجح بدور authenticated نفسه، وتُبلّغ عن
--    الثمانية والخمسة عشر والستّة والخمسين التي ستحذفها. فالعطل في مسار
--    PostgREST، لا في المسح.
--
--    ⚠ وهذا الملف ينادي نفس الدالة، بنفس العبارة، بنفس هوية المدير. لا شيء
--      فيه «أقوى» من الزرّ — إنّما يتخطّى الطبقة المعطوبة وحدها.
--
--  HOW TO RUN
--    SQL Editor → New query → paste → Run. الجدول الأخير هو التأكيد.
-- ============================================================================

DO $run$
DECLARE
  v_admin uuid;
  v_res   jsonb;
BEGIN
  -- ⚠ THE FUNCTION'S FIRST LINE IS require_role('admin'), which reads
  --   auth.uid(). The SQL editor sends no JWT, so without this the purge is
  --   refused with RUL00 — and refusing is the right default: this is the one
  --   claim in the file, and it is made explicitly rather than by accident.
  SELECT id INTO v_admin FROM public.profiles
   WHERE role = 'admin' AND status = 'approved'
   ORDER BY created_at LIMIT 1;

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'لا مدير معتمد في هذا المشروع — أوقفتُ العملية.';
  END IF;

  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_admin)::text, true);

  v_res := public.purge_all_data('مسح كل البيانات');
  RAISE NOTICE 'تم: %', v_res;
END $run$;

-- ── التأكيد ─────────────────────────────────────────────────────────────────
-- ⚠ THE EDITOR SHOWS ONLY THE LAST RESULT SET, so the NOTICE above is invisible
--   and this table is what you will actually see. Every count must be zero, the
--   admin must still be there, and the next عديل must be A-01.
SELECT 'العدايل' AS "الجدول", count(*)::text AS "الباقي" FROM public.adeels
UNION ALL SELECT 'الاستحقاقات', count(*)::text FROM public.receivables
UNION ALL SELECT 'الإيصالات',   count(*)::text FROM public.payments
UNION ALL SELECT 'حركات الصندوق', count(*)::text FROM public.cash_movements
UNION ALL SELECT 'السندات',     count(*)::text FROM public.disbursements
UNION ALL SELECT 'الأشهر المقفلة', count(*)::text FROM public.closed_periods
UNION ALL SELECT 'المحادثات',   count(*)::text FROM public.chat_messages
UNION ALL SELECT 'حسابات المشتركين', count(*)::text
  FROM public.profiles WHERE adeel_id IS NOT NULL
-- ⚠ THIS ONE MUST NOT BE ZERO. If it is, the association is locked out of its
--   own app and bootstrap_first_admin.sql has to be run again.
UNION ALL SELECT '‹‹ مديرون معتمدون — يجب ألاّ يكون صفراً ››', count(*)::text
  FROM public.profiles WHERE role = 'admin' AND status = 'approved'
-- The register's next number, read off the sequence rather than guessed. NULL
-- last_value means it has never been drawn from since the restart, so the next
-- عديل takes 1 — which is A-01.
UNION ALL SELECT '‹‹ العديل التالي ››',
  coalesce((SELECT CASE WHEN s.last_value IS NULL THEN 'A-01'
                        ELSE 'A-' || lpad((s.last_value + 1)::text, 2, '0') END
              FROM pg_sequences s
             WHERE s.schemaname = 'public'
               AND format('%I.%I', s.schemaname, s.sequencename)
                   = pg_get_serial_sequence('public.adeels', 'id')),
           'تعذّر قراءة التسلسل');
