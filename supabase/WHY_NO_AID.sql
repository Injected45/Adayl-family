-- ============================================================================
--  WHY_NO_AID.sql — سُند صرف يظهر للإدارة ولا يظهر للمشترك. لماذا؟
--
--  READ-ONLY. لا ينشئ شيئاً ولا يحذف شيئاً ولا يكتب صفاً. آمن على المشروع الحيّ،
--  ويُشغَّل كما هو مهما كانت حالة المشروع.
--
--  ── الحالة التي يفسّرها ─────────────────────────────────────────────────────
--  صُرف 150 لمشترك. الإدارة تراه في الصندوق؛ شاشة «مصروفات للمشترك» عنده فارغة،
--  وتبقى فارغة بعد التحديث.
--
--  ── لماذا لا يكفي أن نقول «طبّق الترقيع مرة أخرى» ───────────────────────────
--  api_adeel_aid دالة SECURITY INVOKER — أي أن Postgres يقرأ جدول disbursements
--  بصلاحيات المشترك نفسه، لا بصلاحيات الدالة. فحتى تُرجع له صفاً واحداً يلزم
--  ثلاثة أشياء معاً، وغياب أيٍّ منها يعطي النتيجة ذاتها بالضبط: جدول فارغ بلا
--  رسالة خطأ.
--
--    1. الدالة موجودة بتوقيعها؛
--    2. سياسة read_own_disbursements قائمة على الجدول — وهي التي تقول
--       payee_adeel_id = my_adeel_id()؛
--    3. للمشترك امتياز SELECT على الجدول أصلاً.
--
--  ⚠ و WHICH_STATE.sql يفحص الأوّل وحده. فحصه لترقيع 18/08 (a) هو
--    to_regprocedure('api_adeel_aid(bigint)')، فمشروعٌ نزلت فيه الدالة وسقطت
--    السياسة يقول «applied» ويكون التطبيق معطوباً — وهو الخطأ نفسه الذي وقع مع
--    غرفة المحادثات: اسمُ كائنٍ ليس رقم نسخة.
--
--  ── والاحتمال الرابع، وهو ليس عيباً في القاعدة ──────────────────────────────
--  السند «جماعي». الصرف الجماعي لا يُنسب إلى أحد عمداً — «فطور رمضان» ينفق على
--  الجميع ولا يظهر تحت اسم أيّ فرد. والصفّ الأخير يميّز هذه الحالة عن العطل،
--  لأن الشاشتين تبدوان واحدة من الهاتف.
--
--  ── تشغيله ──────────────────────────────────────────────────────────────────
--  Supabase → SQL Editor → New query → الصق كل هذا → Run، وأرسل الجدول كاملاً.
-- ============================================================================

WITH probe AS (
  SELECT
    to_regclass('public.disbursements') IS NOT NULL                  AS tbl,
    to_regprocedure('public.api_adeel_aid(bigint)') IS NOT NULL      AS fn,

    -- ── السياسة، وهي المشتبه به الأوّل ──────────────────────────────────────
    -- بالاسم وبالمضمون معاً: سياسةٌ بالاسم نفسه وشرطٍ مختلف تحجب بصمت تماماً
    -- كما يحجب غيابها.
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_own_disbursements')              AS pol,
    EXISTS (SELECT 1 FROM pg_policies
             WHERE schemaname='public' AND tablename='disbursements'
               AND policyname='read_own_disbursements'
               AND qual LIKE '%my_adeel_id%'
               AND qual LIKE '%payee_adeel_id%')                     AS pol_ok,

    -- ── والامتياز على الجدول، الذي تحتاجه دالة SECURITY INVOKER ────────────
    CASE WHEN to_regclass('public.disbursements') IS NULL THEN NULL ELSE
      has_table_privilege('authenticated', 'public.disbursements', 'SELECT')
    END                                                              AS grant_ok,

    -- ── و my_adeel_id نفسها: بدونها لا سياسة عديل تعمل البتة ───────────────
    to_regprocedure('public.my_adeel_id()') IS NOT NULL              AS mine_fn,
    CASE WHEN to_regprocedure('public.my_adeel_id()') IS NULL THEN NULL ELSE
      has_function_privilege('authenticated', 'public.my_adeel_id()', 'EXECUTE')
    END                                                              AS mine_exec,

    -- ── السندات نفسها ──────────────────────────────────────────────────────
    -- query_to_xml لأن الجدول قد لا يكون موجوداً، وعندها يموت الاستعلام على
    -- إحدى الحالات التي كُتب ليسمّيها.
    CASE WHEN to_regclass('public.disbursements') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.disbursements$q$,
        false, true, '')))[1]::text::bigint END                      AS n_all,
    CASE WHEN to_regclass('public.disbursements') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.disbursements
            WHERE payee_adeel_id IS NOT NULL$q$,
        false, true, '')))[1]::text::bigint END                      AS n_named,
    CASE WHEN to_regclass('public.disbursements') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.disbursements
            WHERE payee_adeel_id IS NULL$q$,
        false, true, '')))[1]::text::bigint END                      AS n_collective,

    -- ── والعدايل المرتبطون ببوابة، فسياسة العديل لا تعني شيئاً بدونهم ───────
    CASE WHEN to_regclass('public.profiles') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.profiles
            WHERE adeel_id IS NOT NULL AND device_id IS NOT NULL$q$,
        false, true, '')))[1]::text::bigint END                      AS bound,
    CASE WHEN to_regclass('public.profiles') IS NULL THEN NULL ELSE
      (xpath('/row/c/text()', query_to_xml(
        $q$SELECT count(*) AS c FROM public.profiles
            WHERE adeel_id IS NOT NULL AND device_id IS NULL$q$,
        false, true, '')))[1]::text::bigint END                      AS unclaimed
)
SELECT * FROM (
  SELECT 1 AS ord, 'جدول الصرف موجود' AS "الفحص",
         CASE WHEN tbl THEN 'نعم' ELSE 'لا' END AS "النتيجة" FROM probe
  UNION ALL SELECT 2, 'دالة api_adeel_aid(bigint)',
         CASE WHEN fn THEN 'موجودة' ELSE 'غائبة' END FROM probe
  UNION ALL SELECT 3, '‹‹ سياسة read_own_disbursements ››',
         CASE WHEN NOT pol THEN 'غائبة — وهذا وحده يفرغ الشاشة'
              WHEN NOT pol_ok THEN 'موجودة بشرط غير متوقَّع'
              ELSE 'موجودة وصحيحة' END FROM probe
  UNION ALL SELECT 4, 'امتياز SELECT للمشترك على الجدول',
         CASE WHEN grant_ok IS NULL THEN 'لا جدول'
              WHEN grant_ok THEN 'موجود' ELSE 'غائب — وهذا وحده يفرغ الشاشة'
         END FROM probe
  UNION ALL SELECT 5, 'دالة my_adeel_id وتنفيذها',
         CASE WHEN NOT mine_fn THEN 'الدالة غائبة'
              WHEN mine_exec THEN 'موجودة وقابلة للتنفيذ'
              ELSE 'موجودة ولا يملك المشترك تنفيذها' END FROM probe
  UNION ALL SELECT 6, 'عدد السندات كلها',
         coalesce(n_all::text, 'لا جدول') FROM probe
  UNION ALL SELECT 7, 'منها منسوبة لمشترك بعينه',
         coalesce(n_named::text, '—') FROM probe
  UNION ALL SELECT 8, 'ومنها جماعية (لا تظهر لأحد عمداً)',
         coalesce(n_collective::text, '—') FROM probe
  UNION ALL SELECT 9, 'عدايل ربطوا أجهزتهم',
         coalesce(bound::text, '—') FROM probe
  UNION ALL SELECT 10, 'وعدايل لم يطالبوا جهازاً بعد',
         coalesce(unclaimed::text, '—') FROM probe
  UNION ALL SELECT 99, '‹‹ التشخيص ››',
         CASE
           WHEN NOT tbl
             THEN 'STOP — لا يوجد جدول صرف. طبّق PATCH_20260817_device_lock.sql.'
           WHEN NOT fn
             THEN 'STOP — الدالة غائبة. طبّق PATCH_20260818_adeel_aid.sql.'
           WHEN NOT pol
             THEN 'السبب: السياسة غائبة. الدالة نزلت وحدها — وهذا ما يجعل WHICH_STATE يقول applied. أرسل الجدول.'
           WHEN NOT pol_ok
             THEN 'السبب: السياسة موجودة بشرط مختلف. أرسل الجدول قبل تشغيل أي ملف.'
           WHEN grant_ok IS NOT TRUE
             THEN 'السبب: المشترك لا يملك SELECT على الجدول، ودالة SECURITY INVOKER تقرأ بصلاحياته. أرسل الجدول.'
           WHEN mine_exec IS NOT TRUE
             THEN 'السبب: my_adeel_id غير قابلة للتنفيذ من المشترك، فكل سياسات العديل تفشل. أرسل الجدول.'
           WHEN coalesce(n_named, 0) = 0
             THEN 'القاعدة سليمة ولا يوجد سند منسوب إلى أي مشترك — السند المقصود سُجّل «جماعي»، والجماعي لا يظهر تحت أحد عمداً.'
           ELSE 'القاعدة سليمة والسند منسوب. الباقي في الجهاز: تأكّد أن المشترك ربط جهازه (السطر 9) وأن نسخة التطبيق عنده حديثة.'
         END FROM probe
) t ORDER BY ord;
