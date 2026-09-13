-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-12.  كشفُ الحساب بمدّةٍ ورصيدٍ سابق.
--
--  ما الذي يفعله هذا الملف
--    `api_adeel_statement` كان يعرض عمرَ العديل كلَّه دفعةً واحدة، بلا مدّة
--    ولا رصيدٍ سابق. صار يقبل «من» و«إلى»، ويضع فوق الحركات سطرَ «رصيد سابق»
--    — أي ما كان على الرجل أو له قبل أوّل يومٍ في المدّة — تمامًا كما يفعل
--    إجراءُ المنظومة `ASSMember_Statment`، الذي بُني هذا على شكله عن قصد
--    ليكون الكشفان مقارنَين سطرًا بسطر.
--
--  ⚠ ويصلح خطأً كان في الدالّة: التاريخُ كان يُرسم بتوقيت UTC
--    (`AT TIME ZONE 'UTC'`) لا بتوقيت طرابلس. إيصالٌ يُسجَّل الواحدة صباحًا
--    بتوقيت ليبيا هو الحادية عشرة من مساء اليومِ السابق بتوقيت UTC، فكان
--    يُعرض في اليوم الخطأ. القاعدةُ في هذا المشروع أنّ اليوم يُرسم في
--    Africa/Tripoli دائمًا، وكلُّ دوالّ العرض في دارت تفعل ذلك؛ هذه وحدَها
--    كانت شاذّة. لا يظهر الخطأ في البيانات المرحَّلة لأنّها مختومةٌ التاسعة
--    والعاشرة صباحًا، ويظهر في أوّل إيصالٍ يُسجَّل بعد منتصف الليل.
--
--  ⚠ ومجاميعُ المدّة لا تشمل الرصيدَ السابق، وهذا مقصود. شاشةُ المنظومة
--    (FrmASSMember_Statment) تجمع عمودَي «مدين» و«دائن» من الشبكة كما هي،
--    وصفُّ «رصيد سابق» فيها يحمل الرصيدَ في أحد العمودين — فيُحسب رصيدٌ
--    قديمٌ على أنّه قبضٌ في المدّة. المجموعُ النهائيّ يخرج صحيحًا بالمصادفة
--    (دائن ناقص مدين يساوي الرصيدَ الختاميّ على كلّ حال)، لكنّ «إجمالي
--    المقبوضات» و«إجمالي المستحقّات» المعروضَين خطأ. هنا يُفصل الاثنان:
--    `openingBalance` وحدَه، و`periodDebit`/`periodCredit` للمدّة وحدَها.
--
--  ⚠ والتوقيعُ يتغيّر، فتُحذف الدالّة القديمة ولا تُترك بجانب الجديدة.
--    PostgREST يوزّع على أسماء المعاملات المُرسَلة، فلو بقيت `(bigint)` لظلّ
--    أيُّ عميلٍ يرسل `p_adeel_id` وحدَه يهبط عليها ولا يرى المدّة أبدًا —
--    وهو الفخُّ نفسُه الذي وقع فيه `send_chat_message`. الدالّة الجديدة
--    قِيَمُها الافتراضيّة NULL، فالنداءُ بمعاملٍ واحدٍ يعمل كما كان تمامًا.
--
--  ⚠ وتوقيعٌ جديدٌ يعني صلاحيّاتٍ جديدة: الدالّةُ المحذوفةُ ثمّ المُنشأةُ لا
--    ترث ACL، فتأخذ EXECUTE to PUBLIC الافتراضيّة. لذلك تُحدَّث قائمةُ
--    السماح ثمّ تُمسح الصلاحيّاتُ كلُّها من القائمة نفسِها في آخر الملفّ.
--
--  كيفيّة التطبيق
--    SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.api_adeel_statement(bigint)') IS NULL
     AND to_regprocedure('public.api_adeel_statement(bigint,date,date)') IS NULL THEN
    RAISE EXCEPTION 'لا توجد api_adeel_statement — هذا ليس مشروع الجمعية.';
  END IF;
END $prereq$;

-- == 1. الكشف، بمدّةٍ ورصيدٍ سابق ===========================================
DROP FUNCTION IF EXISTS public.api_adeel_statement(bigint);
DROP FUNCTION IF EXISTS public.api_adeel_statement(bigint, date, date);

CREATE FUNCTION public.api_adeel_statement(
  p_adeel_id bigint,
  p_from     date DEFAULT NULL,
  p_to       date DEFAULT NULL)
RETURNS jsonb
LANGUAGE sql
STABLE
AS $stmt$
  -- الحدّان لحظتان لا يومان: من أوّل لحظةٍ في «من» إلى آخر لحظةٍ في «إلى»،
  -- محسوبتين بتوقيت طرابلس لأنّ اليوم في هذا المشروع يومٌ ليبيّ.
  WITH bounds AS (
    SELECT CASE WHEN p_from IS NULL THEN NULL
                ELSE (p_from::timestamp AT TIME ZONE 'Africa/Tripoli') END AS lo,
           CASE WHEN p_to IS NULL THEN NULL
                ELSE ((p_to + 1)::timestamp AT TIME ZONE 'Africa/Tripoli') END AS hi
  ), movements AS (
    SELECT r.created_at AS at,
           r.period      AS reference,
           'استحقاق'::text AS kind,
           r.total       AS debit,
           NULL::numeric AS credit,
           public.period_label(r.period) AS note
      FROM public.receivables r
     WHERE r.adeel_id = p_adeel_id AND r.status <> 'ملغي'
    UNION ALL
    SELECT p.paid_at,
           p.receipt_no,
           'دفعة'::text,
           NULL::numeric,
           p.amount,
           -- ── The METHOD, in words. Not the transfer reference. ────────────
           -- The reference identifies the transfer to the BANK; it is not what
           -- the movement was. What it was is "تحويل مصرفي" or "نقداً", which is
           -- also the one thing on the line he can check against his own
           -- records. It stays on the payment row and on the collections
           -- screen, where a treasurer reconciling with a bank statement is the
           -- person who actually needs it.
           p.method::text
      FROM public.payments p
     WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'
  ), opening AS (
    -- ما كان قبل أوّل يومٍ في المدّة. مدينٌ موجبٌ يعني «عليه».
    SELECT coalesce(sum(coalesce(m.debit, 0) - coalesce(m.credit, 0)), 0) AS bal
      FROM movements m, bounds b
     WHERE b.lo IS NOT NULL AND m.at < b.lo
  ), windowed AS (
    SELECT m.* FROM movements m, bounds b
     WHERE (b.lo IS NULL OR m.at >= b.lo)
       AND (b.hi IS NULL OR m.at <  b.hi)
  ), ordered AS (
    -- ⚠ الترتيبُ يكسر التعادل بـ reference، ونافذةُ الرصيد تستعمل الترتيبَ
    --   نفسَه الذي يُعرض به الصفّ. لو رُتّب بالتاريخ وحدَه لصار لصفوفِ اليومِ
    --   الواحد ترتيبٌ لا يضمنه شيء، فيظهر عمودُ «الرصيد» وكأنّه يقفز.
    SELECT w.*,
           (SELECT bal FROM opening)
             + sum(coalesce(w.debit, 0) - coalesce(w.credit, 0))
               OVER (ORDER BY w.at, w.reference
                     ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS balance
      FROM windowed w
  )
  SELECT jsonb_build_object(
    'from', to_char(p_from, 'YYYY-MM-DD'),
    'to',   to_char(p_to,   'YYYY-MM-DD'),
    'openingBalance', (SELECT bal::text FROM opening),
    'movements', coalesce(
      (SELECT jsonb_agg(
                jsonb_build_object(
                  -- اليومُ بتوقيت طرابلس، لا UTC.
                  'date', to_char(o.at AT TIME ZONE 'Africa/Tripoli', 'YYYY-MM-DD'),
                  'reference', o.reference,
                  'type', o.kind,
                  'debit', o.debit::text,
                  'credit', o.credit::text,
                  'balance', o.balance::text,
                  'note', o.note)
                ORDER BY o.at, o.reference)
         FROM ordered o),
      '[]'::jsonb),
    -- مجاميعُ المدّة وحدَها — الرصيدُ السابق ليس قبضًا ولا استحقاقًا فيها.
    'periodDebit',  (SELECT coalesce(sum(debit), 0)::text  FROM windowed),
    'periodCredit', (SELECT coalesce(sum(credit), 0)::text FROM windowed),
    'closingBalance',
      coalesce((SELECT o.balance::text FROM ordered o
                 ORDER BY o.at DESC, o.reference DESC LIMIT 1),
               (SELECT bal::text FROM opening)))
$stmt$;

-- == 2. قائمةُ السماح — تُقرأ حيّةً ثمّ تُعاد كتابتُها ======================
-- ⚠ لا تُعاد كتابةُ القائمة من ملفٍّ في المستودع. مشروعُك قد سبق هذا الملفَّ
--   بتوقيعاتٍ لا يعرفها، فإعادةُ كتابتها من الذاكرة تُسقطها. تُقرأ الحيّةُ،
--   ويُبدَّل مُدخلٌ واحد، وتُكتب من تلك.
DO $allow$
DECLARE
  v_old text[] := public.client_callable_functions();
  v_new text[];
BEGIN
  SELECT array_agg(x ORDER BY ord) INTO v_new
    FROM (
      SELECT x, ord FROM unnest(v_old) WITH ORDINALITY AS t(x, ord)
       WHERE replace(x, ' ', '') <> 'api_adeel_statement(bigint)'
      UNION ALL
      SELECT 'api_adeel_statement(bigint,date,date)'::text, 2147483647
    ) s;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 3. المسحة، بعد آخر CREATE في هذا الملف ================================
-- ⚠ الدالّةُ الجديدةُ وُلدت بلا ACL، فأخذت EXECUTE to PUBLIC الافتراضيّة
--   وفوقها anon من ALTER DEFAULT PRIVILEGES التي يضعها سوبابيز. المسحةُ
--   تُعيد حساب كلّ صلاحيّةٍ في المخطّط من قائمة السماح، فتُصلح هذه وما يأتي
--   بعدها — بشرط أن تبقى بعد آخر CREATE.
DO $lockdown$
DECLARE
  r        record;
  v_allow  text[] := public.client_callable_functions();
  v_sig    text;
BEGIN
  FOR r IN
    SELECT p.oid,
           p.oid::regprocedure::text AS full_sig
      FROM pg_proc p
      JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND NOT EXISTS (SELECT 1 FROM pg_depend d
                        WHERE d.objid = p.oid
                          AND d.classid = 'pg_proc'::regclass
                          AND d.deptype = 'e')
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated, service_role',
      r.full_sig);
    v_sig := replace(ltrim(replace(r.full_sig, 'public.', ''), ' '), ' ', '');
    IF v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_allow) a) THEN
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role',
                     r.full_sig);
    END IF;
  END LOOP;
END $lockdown$;

-- == 4. الفحص: للقراءة فقط، وكلُّ صفٍّ يجب أن يقول true ====================
SELECT 'الكشف صار يقبل مدّة' AS "الفحص",
       to_regprocedure('public.api_adeel_statement(bigint,date,date)') IS NOT NULL
         AS "النتيجة"
UNION ALL SELECT 'والقديمةُ ذات المعامل الواحد أُزيلت',
       to_regprocedure('public.api_adeel_statement(bigint)') IS NULL
-- ⚠ يُقرأ الجسدُ لا الاسم: دالّةٌ موجودةٌ بجسدٍ قديمٍ تجتاز كلَّ فحصٍ يسأل
--   «هل هي هناك؟»، وهي بالضبط الحالةُ التي يوجد هذا الملفّ لأجلها.
UNION ALL SELECT 'واليومُ يُرسم بتوقيت طرابلس لا UTC',
       (SELECT prosrc LIKE '%AT TIME ZONE ''Africa/Tripoli'', ''YYYY-MM-DD''%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'api_adeel_statement')
UNION ALL SELECT 'وهي في قائمة السماح بتوقيعها الجديد',
       'api_adeel_statement(bigint,date,date)' = ANY (
         SELECT replace(a, ' ', '') FROM unnest(public.client_callable_functions()) a)
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       (SELECT "total"::numeric = (SELECT coalesce(sum(amount), 0)
                                     FROM public.cash_movements
                                    WHERE status <> 'ملغي')
          FROM public.v_cash_summary);

-- == 5. الحرّاس الأربعة =====================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
