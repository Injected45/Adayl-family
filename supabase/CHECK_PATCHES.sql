-- ============================================================================
--  جمعية العدايل — فحصُ الملفات الأحد عشر بعد تشغيلها (للقراءة فقط).
--
--  لا يكتب شيئًا ولا يغيّر شيئًا: استعلامٌ واحد يقرأ ما أضافه كلُّ ملف ويتأكد
--  أنه يعمل، ثم يكتب الخلاصة في أول صف.
--
--    ✅  سليم          ❌  ناقص — الخلاصة تذكر اسم الملف الذي يُعاد تشغيله
--    ℹ️  معلومة للاطلاع فقط
--
--  ⚠ كلُّ ما قد يكون غائبًا يُسأل عنه أولًا قبل قراءته، فلا يتوقف الفحص بخطأ
--    على الحالة نفسها التي جاء ليكشفها.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run.
-- ============================================================================

WITH base(ord, patch, file, label, ok, detail) AS (
  VALUES
  -- ── 1. الإشعارات ─────────────────────────────────────────────────────────
  (11, '1 · الإشعارات', 'PATCH_20260913c_notifications.sql',
   'جدولُ الإشعارات وقائمتُها موجودان',
   to_regclass('public.notifications') IS NOT NULL
     AND to_regclass('public.v_notifications') IS NOT NULL,
   NULL::text),
  (12, '1 · الإشعارات', 'PATCH_20260913c_notifications.sql',
   'التنبيهُ عند الاستحقاق والقبض والصرف (3 محفّزات)',
   (SELECT count(*) FROM pg_trigger
     WHERE tgname IN ('trg_notify_receivable', 'trg_notify_payment',
                      'trg_notify_disbursement')
       AND NOT tgisinternal) = 3,
   NULL),
  (13, '1 · الإشعارات', 'PATCH_20260913c_notifications.sql',
   'رسالةُ الإدارة متاحةٌ للتطبيق',
   CASE WHEN to_regprocedure('public.send_broadcast(text,text)') IS NULL THEN false
        ELSE has_function_privilege('authenticated',
               'public.send_broadcast(text,text)', 'EXECUTE') END,
   NULL),
  (14, '1 · الإشعارات', 'PATCH_20260913c_notifications.sql',
   'ولا يكتب أحدٌ في جدول الإشعارات مباشرة',
   CASE WHEN to_regclass('public.notifications') IS NULL THEN false
        ELSE NOT has_table_privilege('authenticated', 'public.notifications', 'INSERT')
         AND NOT has_table_privilege('authenticated', 'public.notifications', 'UPDATE')
         AND NOT has_table_privilege('authenticated', 'public.notifications', 'DELETE') END,
   NULL),

  -- ── 2. الجدوى سنةً بسنة ─────────────────────────────────────────────────
  (21, '2 · الجدوى', 'PATCH_20260914_member_years.sql',
   '«الجدوى» تُرجع الحركةَ سنةً بسنة',
   coalesce((SELECT prosrc LIKE '%''years''%'
               FROM pg_proc
              WHERE oid = to_regprocedure('public.api_member_value(bigint)')), false),
   NULL),

  -- ── 3. قفل الجلسة ومنطقة الخطر ──────────────────────────────────────────
  (31, '3 · المفتاح والجهاز', 'PATCH_20260914b_session_lock.sql',
   'المفتاحُ يربط الجهازَ والدخول (عمود الجلسة موجود)',
   EXISTS (SELECT 1 FROM information_schema.columns
            WHERE table_schema = 'public' AND table_name = 'profiles'
              AND column_name = 'session_id'),
   NULL),
  (32, '3 · المفتاح والجهاز', 'PATCH_20260914b_session_lock.sql',
   'كلُّ ما يخصّ المشترك يشترط الدخولَ بالمفتاح',
   coalesce((SELECT prosrc LIKE '%my_session_ok()%'
               FROM pg_proc WHERE oid = to_regprocedure('public.my_adeel_id()')), false),
   NULL),
  (33, '3 · المفتاح والجهاز', 'PATCH_20260914b_session_lock.sql',
   'المفتاحُ المستعمل لا يُستعمل ثانية',
   coalesce((SELECT prosrc LIKE '%استُعمل من قبل%'
               FROM pg_proc WHERE oid = to_regprocedure('public.redeem_adeel_code(text,text)')), false),
   NULL),
  (34, '3 · المفتاح والجهاز', 'PATCH_20260914b_session_lock.sql',
   'المشتركون الداخلون يوم التشغيل لم يُطردوا (لحظة البدء مسجّلة)',
   CASE WHEN NOT EXISTS (SELECT 1 FROM information_schema.columns
                          WHERE table_schema = 'public'
                            AND table_name = 'association_settings'
                            AND column_name = 'member_session_since') THEN false
        ELSE (xpath('/row/c/text()', query_to_xml(
               $q$SELECT (count(*) FILTER (WHERE member_session_since IS NOT NULL) > 0)::text AS c
                    FROM public.association_settings$q$,
               false, true, '')))[1]::text = 'true' END,
   NULL),
  (35, '3 · المفتاح والجهاز', 'PATCH_20260914b_session_lock.sql',
   'منطقةُ الخطر مغلقة: التطبيق لا يستطيع مسح البيانات',
   (to_regprocedure('public.purge_financial_data(text)') IS NULL
      OR NOT has_function_privilege('authenticated',
               'public.purge_financial_data(text)', 'EXECUTE'))
   AND (to_regprocedure('public.purge_all_data(text)') IS NULL
      OR NOT has_function_privilege('authenticated',
               'public.purge_all_data(text)', 'EXECUTE')),
   NULL),

  -- ── 4. سبتمبر مُقفل ─────────────────────────────────────────────────────
  (41, '4 · إقفال سبتمبر', 'PATCH_20260915_september_closed.sql',
   'سبتمبر 2026 يظهر «مُقفل» في قائمة الإقفال',
   coalesce((SELECT (e ->> 'closed')::boolean
               FROM jsonb_array_elements(public.api_closable_periods()) e
              WHERE e ->> 'period' = '2026-09'), false),
   NULL),
  (42, '4 · إقفال سبتمبر', 'PATCH_20260915_september_closed.sql',
   'لا شهرَ مفتوح من بداية النظام حتى سبتمبر',
   NOT EXISTS (
     SELECT 1
       FROM public.association_settings s,
            generate_series(date_trunc('month', s.system_start),
                            date '2026-09-01', interval '1 month') d
      WHERE s.id = 1
        AND NOT EXISTS (SELECT 1 FROM public.closed_periods cp
                         WHERE cp.period = to_char(d, 'YYYY-MM'))),
   (SELECT 'الأشهر المُقفلة: ' || count(*) FROM public.closed_periods)),
  (43, '4 · إقفال سبتمبر', 'PATCH_20260915_september_closed.sql',
   'أكتوبر لا يُقفل قبل أن يبدأ',
   coalesce((SELECT prosrc LIKE '%p_period > to_char(current_date%'
               FROM pg_proc WHERE oid = to_regprocedure('public.generate_period(character)')), false),
   NULL),

  -- ── 5. الإلغاء في يوم العملية فقط ───────────────────────────────────────
  (51, '5 · الإلغاء في نفس اليوم', 'PATCH_20260915b_same_day_cancel.sql',
   'إلغاءُ الإيصال يرفض ما ليس من اليوم',
   coalesce((SELECT prosrc LIKE '%إلا في يوم تسجيله%'
               FROM pg_proc WHERE oid = to_regprocedure('public.cancel_payment(bigint,text)')), false),
   NULL),
  (52, '5 · الإلغاء في نفس اليوم', 'PATCH_20260915b_same_day_cancel.sql',
   'وإلغاءُ الصرف كذلك',
   coalesce((SELECT prosrc LIKE '%إلا في يوم تسجيله%'
               FROM pg_proc WHERE oid = to_regprocedure('public.cancel_disbursement(bigint,text)')), false),
   NULL),
  (53, '5 · الإلغاء في نفس اليوم', 'PATCH_20260915b_same_day_cancel.sql',
   'قائمتا التحصيل والصرف تُخبران التطبيقَ متى يظهر زرّ الإلغاء',
   (SELECT count(*) FROM information_schema.columns
     WHERE table_schema = 'public'
       AND table_name IN ('v_payments', 'v_disbursements')
       AND column_name = 'cancellable') = 2,
   NULL),

  -- ── 6. حركة العدايل ─────────────────────────────────────────────────────
  (61, '6 · حركة العدايل', 'PATCH_20260915c_member_net.sql',
   'قائمةُ «حركة العدايل» موجودة',
   to_regclass('public.v_member_net') IS NOT NULL,
   NULL),
  (62, '6 · حركة العدايل', 'PATCH_20260915c_member_net.sql',
   'وتُقرأ بصلاحية القارئ، وللتطبيق فقط',
   CASE WHEN to_regclass('public.v_member_net') IS NULL THEN false
        ELSE coalesce((SELECT array_to_string(reloptions, ',') ~ 'security_invoker=(on|true|1)'
                         FROM pg_class WHERE oid = to_regclass('public.v_member_net')), false)
         AND has_table_privilege('authenticated', 'public.v_member_net', 'SELECT')
         AND NOT has_table_privilege('anon', 'public.v_member_net', 'SELECT') END,
   NULL),
  (63, '6 · حركة العدايل', 'PATCH_20260915c_member_net.sql',
   'وإجماليُّها = المقبوض − المصروف لأشخاص (غير الملغى)',
   CASE WHEN to_regclass('public.v_member_net') IS NULL THEN false
        ELSE (xpath('/row/c/text()', query_to_xml(
               $q$SELECT ((SELECT coalesce(sum(("net")::numeric), 0) FROM public.v_member_net)
                          = (SELECT coalesce(sum(amount), 0) FROM public.payments
                              WHERE status <> 'ملغي')
                          - (SELECT coalesce(sum(amount), 0) FROM public.disbursements
                              WHERE status <> 'ملغي' AND payee_adeel_id IS NOT NULL))::text AS c$q$,
               false, true, '')))[1]::text = 'true' END,
   CASE WHEN to_regclass('public.v_member_net') IS NULL THEN NULL
        ELSE 'إجمالي الفرق: ' || (xpath('/row/c/text()', query_to_xml(
               $q$SELECT coalesce(max("totalNet"), '0') AS c FROM public.v_member_net$q$,
               false, true, '')))[1]::text END),

  -- ── 7. قانون الجمعية ومقترحات المشتركين ────────────────────────────────
  (71, '7 · القانون والمقترحات', 'PATCH_20260915d_bylaws_proposals.sql',
   'جدولا القانون والمقترحات وقائمتاهما موجودة',
   to_regclass('public.bylaw_pages') IS NOT NULL
     AND to_regclass('public.v_bylaw_pages') IS NOT NULL
     AND to_regclass('public.proposals') IS NOT NULL
     AND to_regclass('public.v_proposals') IS NOT NULL,
   NULL),
  (72, '7 · القانون والمقترحات', 'PATCH_20260915d_bylaws_proposals.sql',
   'رفعُ الصفحات وإرسالُ المقترحات والقبولُ والرفض متاحةٌ للتطبيق',
   (SELECT bool_and(to_regprocedure(f) IS NOT NULL
                    AND has_function_privilege('authenticated', f, 'EXECUTE'))
      FROM unnest(ARRAY['public.add_bylaw_page(text,text)',
                        'public.delete_bylaw_page(bigint)',
                        'public.submit_proposal(text,text)',
                        'public.accept_proposal(bigint)',
                        'public.reject_proposal(bigint)']) f),
   NULL),
  (73, '7 · القانون والمقترحات', 'PATCH_20260915d_bylaws_proposals.sql',
   'المقترحُ المقبول محميٌّ من التعديل والحذف',
   EXISTS (SELECT 1 FROM pg_trigger
            WHERE tgname = 'trg_proposals_guard' AND NOT tgisinternal),
   NULL),

  -- ── 8. زرّ مسح الإشعارات ─────────────────────────────────────────────
  (81, '8 · مسح الإشعارات', 'PATCH_20260915e_clear_notifications.sql',
   'زرُّ «مسح كل الإشعارات» متاحٌ للأدمن',
   CASE WHEN to_regprocedure('public.clear_notifications()') IS NULL THEN false
        ELSE has_function_privilege('authenticated',
               'public.clear_notifications()', 'EXECUTE') END,
   NULL),

  -- ── 9. حذف رسائل المحادثات ───────────────────────────────────────────
  (91, '9 · حذف الرسائل', 'PATCH_20260915f_chat_delete_control.sql',
   'الحذفُ الجزئيّ ومسحُ المحادثة ومسحُ الكل متاحةٌ للتطبيق',
   (SELECT bool_and(to_regprocedure(f) IS NOT NULL
                    AND has_function_privilege('authenticated', f, 'EXECUTE'))
      FROM unnest(ARRAY['public.delete_chat_messages(bigint[])',
                        'public.clear_chat_thread(bigint)',
                        'public.clear_all_board_threads()']) f),
   NULL),
  (92, '9 · حذف الرسائل', 'PATCH_20260915f_chat_delete_control.sql',
   'المشترك لا يستطيع حذف رسالة غيره (الثغرة مُغلقة)',
   coalesce((SELECT prosrc LIKE '%coalesce(v_role = ''admin''%'
               FROM pg_proc WHERE oid = to_regprocedure('public.delete_chat_message(bigint)')), false),
   NULL),

  -- ── 10. الرسالة الموجَّهة، والزرّ المُصلَح ──────────────────────────────
  (101, '10 · رسالة لمشترك', 'PATCH_20260916_notices_fix_and_targeted.sql',
   'إرسالُ رسالةٍ إلى مشتركٍ بعينه متاحٌ للأدمن',
   CASE WHEN to_regprocedure('public.send_notice(bigint[],text,text)') IS NULL THEN false
        ELSE has_function_privilege('authenticated',
               'public.send_notice(bigint[],text,text)', 'EXECUTE') END,
   NULL),
  (102, '10 · رسالة لمشترك', 'PATCH_20260916_notices_fix_and_targeted.sql',
   'وزرُّ المسح على النسخة التي تسمّي خطأها بالعربيّة',
   coalesce((SELECT prosrc LIKE '%تعذّر مسحُ الإشعارات%'
               FROM pg_proc WHERE oid = to_regprocedure('public.clear_notifications()')), false),
   NULL),

  -- ── 11. الشرط الذي يطلبه حارسُ سوبابيز ──────────────────────────────────
  -- ⚠ حسابُ التطبيق يرفض أيَّ حذفٍ أو تعديلٍ بلا WHERE، ولا أثرَ للحارس في
  --   المحرّر ولا في نسخة الاختبار — فلا يُكتشف إلا على الهاتف. هذا الصفُّ
  --   يسأل عنه قبل ذلك. التعليقاتُ تُنزع أولًا: فاصلةٌ منقوطة داخل تعليقٍ
  --   تقطع الأمرَ فتجعله يبدو بلا شرط.
  (111, '11 · شرطُ الحذف', 'PATCH_20260916b_where_clause.sql',
   'لا حذفَ ولا تعديلَ بلا شرط في دالّةٍ يناديها التطبيق',
   NOT EXISTS (
     SELECT 1
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
      CROSS JOIN LATERAL (
        SELECT (regexp_matches(regexp_replace(p.prosrc, '--[^\n]*', '', 'g'),
                  '(DELETE\s+FROM\s+[^;]*;|UPDATE\s+[a-zA-Z_."]+\s+SET\s+[^;]*;)',
                  'gi'))[1] AS s
      ) m
      WHERE n.nspname = 'public'
        AND replace(ltrim(replace(p.oid::regprocedure::text, 'public.', ''), ' '), ' ', '')
            = ANY (SELECT replace(a, ' ', '') FROM unnest(public.client_callable_functions()) a)
        AND m.s !~* 'where'),
   NULL),

  -- ── عامّ ────────────────────────────────────────────────────────────────
  (95, 'عامّ', NULL,
   'الأدمن ما زال يدخل',
   EXISTS (SELECT 1 FROM public.profiles WHERE role = 'admin' AND status = 'approved'),
   NULL),
  (96, 'عامّ', NULL,
   'لا أحد في الداخل بلا مفتاح وليس أدمن',
   NOT EXISTS (SELECT 1 FROM public.profiles
                WHERE status = 'approved' AND adeel_id IS NULL AND role <> 'admin'),
   NULL),
  (97, 'عامّ', NULL,
   'رصيدُ الجمعية الآن',
   NULL,
   (SELECT balance FROM public.v_cash_summary)),
  (98, 'عامّ', NULL,
   'عددُ الإشعارات المسجّلة حتى الآن',
   NULL,
   CASE WHEN to_regclass('public.notifications') IS NULL THEN NULL
        ELSE (xpath('/row/c/text()', query_to_xml(
               $q$SELECT count(*) AS c FROM public.notifications$q$,
               false, true, '')))[1]::text END)
),

-- ═══════════════════════════════════════════════════════════════════════════
--  قبل الإطلاق: هل تستطيع هذه القاعدة أن تخدم التطبيق كلَّه؟
--
--  ⚠ الصفّان التاليان يسألان سؤالًا لا يسأله شيءٌ آخر. كلُّ ما سبق يفحص ملفًّا
--    بعينه؛ وهذان يفحصان **التطبيق**: كلُّ نداءٍ يناديه، وكلُّ قائمةٍ يقرؤها.
--    نداءٌ ناقصٌ أو غيرُ مسموح لا يظهر في أيّ اختبار — يظهر على هاتف مشتركٍ
--    بعد الإطلاق، برسالةٍ لا تقول شيئًا. القائمتان مستخرجتان من شيفرة التطبيق
--    نفسِها (dart run tool/rpc_lint.dart يحرس الأسماء في المستودع).
-- ═══════════════════════════════════════════════════════════════════════════
app_fn(f) AS (VALUES
  ('public.accept_proposal(bigint)'), ('public.add_bylaw_page(text,text)'),
  ('public.api_adeel_aid(bigint)'), ('public.api_adeel_detail(bigint)'),
  ('public.api_adeel_statement(bigint,date,date)'), ('public.api_aid_others(bigint)'),
  ('public.api_arrears_board()'), ('public.api_association_finance()'),
  ('public.api_call_directory()'), ('public.api_closable_periods()'),
  ('public.api_dashboard()'), ('public.api_direct_threads()'),
  ('public.api_financial_report(date,date)'), ('public.api_ice_servers()'),
  ('public.api_me()'), ('public.api_member_value(bigint)'),
  ('public.api_receivables(text)'), ('public.api_settings()'),
  ('public.api_touch_login()'), ('public.auto_close_periods()'),
  ('public.cancel_disbursement(bigint,text)'), ('public.cancel_payment(bigint,text)'),
  ('public.clear_all_board_threads()'), ('public.clear_chat_thread(bigint)'),
  ('public.clear_notifications()'), ('public.delete_adeel(bigint)'),
  ('public.delete_bylaw_page(bigint)'), ('public.delete_chat_message(bigint)'),
  ('public.delete_chat_messages(bigint[])'), ('public.end_call(bigint,boolean)'),
  ('public.generate_period(character)'), ('public.heartbeat_call(bigint)'),
  ('public.issue_adeel_code(bigint)'), ('public.join_call(bigint)'),
  ('public.leave_call(bigint)'), ('public.redeem_adeel_code(text,text)'),
  ('public.reject_proposal(bigint)'),
  ('public.register_payment(bigint,numeric,pay_method,text,text,text,text,text,text)'),
  ('public.register_disbursement(numeric,disbursement_kind,pay_method,bigint,expense_category,text,text,text,text,text,text,date)'),
  ('public.save_adeel(bigint,jsonb)'), ('public.send_broadcast(text,text)'),
  ('public.send_chat_message(text,bigint,bigint,text,integer)'),
  ('public.send_notice(bigint[],text,text)'), ('public.send_signal(bigint,text,jsonb,uuid)'),
  ('public.set_user_access(uuid,app_role,app_status)'), ('public.start_call(bigint,bigint)'),
  ('public.submit_proposal(text,text)'), ('public.unbind_adeel(bigint)'),
  ('public.update_settings(jsonb)')
),
app_view(v) AS (VALUES
  ('v_adeels'), ('v_audit'), ('v_bylaw_pages'), ('v_call_participants'),
  ('v_call_signals'), ('v_calls'), ('v_cash_movements'), ('v_cash_summary'),
  ('v_chat_messages'), ('v_chat_threads'), ('v_disbursements'),
  ('v_expense_by_category'), ('v_member_net'), ('v_notifications'),
  ('v_officials'), ('v_payments'), ('v_proposals'), ('v_settings'), ('v_users')
),
launch(ord, patch, file, label, ok, detail) AS (
  SELECT 121, 'قبل الإطلاق'::text, NULL::text,
         'كلُّ نداءٍ يناديه التطبيق موجودٌ ومسموحٌ له'::text,
         NOT EXISTS (SELECT 1 FROM app_fn a
                      WHERE to_regprocedure(a.f) IS NULL
                         OR NOT has_function_privilege('authenticated', a.f, 'EXECUTE')),
         coalesce((SELECT string_agg(a.f, '، ') FROM app_fn a
                    WHERE to_regprocedure(a.f) IS NULL
                       OR NOT has_function_privilege('authenticated', a.f, 'EXECUTE')),
                  (SELECT count(*)::text || ' نداءً، كلُّها متاحة' FROM app_fn))
  UNION ALL
  SELECT 122, 'قبل الإطلاق', NULL,
         'وكلُّ قائمةٍ يقرؤها موجودةٌ ويقرؤها المسجَّل وحدَه',
         NOT EXISTS (SELECT 1 FROM app_view w
                      WHERE to_regclass('public.' || w.v) IS NULL
                         OR NOT has_table_privilege('authenticated', 'public.' || w.v, 'SELECT')
                         OR has_table_privilege('anon', 'public.' || w.v, 'SELECT')),
         coalesce((SELECT string_agg(w.v, '، ') FROM app_view w
                    WHERE to_regclass('public.' || w.v) IS NULL
                       OR NOT has_table_privilege('authenticated', 'public.' || w.v, 'SELECT')
                       OR has_table_privilege('anon', 'public.' || w.v, 'SELECT')),
                  (SELECT count(*)::text || ' قائمة، كلُّها سليمة' FROM app_view))
  UNION ALL
  -- ⚠ حسابُ التطوير admin@fam.test: كلمتُه في تاريخ المستودع العلنيّ، ومفتاحُ
  --   القراءة علنيٌّ بالتصميم — فمن قرأهما دخل بحساب أدمن بلا تطبيق. حذفُ
  --   السطر من الملفّ لا يكفي؛ يلزم تعطيلُ الحساب أو تغييرُ كلمته.
  SELECT 123, 'قبل الإطلاق', NULL,
         'ولا حسابَ تطويرٍ معتمَدًا بصلاحية أدمن',
         -- ⚠ كلُّ بريدٍ ينتهي بـ .test حسابُ تجربة بحكم التعريف (نطاقٌ محجوز لا
         --   يملكه أحد)، فلا يُعقل أن يكون أدمنًا معتمَدًا في مشروعٍ حيّ.
         NOT EXISTS (SELECT 1 FROM public.profiles
                      WHERE role = 'admin' AND status = 'approved'
                        AND email LIKE '%.test'),
         coalesce((SELECT string_agg(email, '، ') FROM public.profiles
                    WHERE role = 'admin' AND status = 'approved'
                      AND email LIKE '%.test'),
                  'لا شيء')
),
c(ord, patch, file, label, ok, detail) AS (
  SELECT * FROM base UNION ALL SELECT * FROM launch
)
SELECT '' AS "الملف",
       'الخلاصة' AS "الفحص",
       CASE WHEN bool_and(ok) FILTER (WHERE ok IS NOT NULL) THEN '✅' ELSE '❌' END AS "النتيجة",
       coalesce(
         (SELECT 'ناقص: ' || x.patch || ' — ' || x.label
                 || ' ← أعد تشغيل ' || x.file
            FROM c x WHERE x.ok IS FALSE AND x.file IS NOT NULL
           ORDER BY x.ord LIMIT 1),
         (SELECT 'ناقص: ' || x.label
            FROM c x WHERE x.ok IS FALSE
           ORDER BY x.ord LIMIT 1),
         'الملفات الأحد عشر مطبّقة وتعمل') AS "التفاصيل",
       0 AS "#"
  FROM c
UNION ALL
SELECT patch,
       label,
       CASE WHEN ok IS NULL THEN 'ℹ️' WHEN ok THEN '✅' ELSE '❌' END,
       coalesce(detail, ''),
       ord
  FROM c
 ORDER BY 5;
