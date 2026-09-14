-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-13 (c).  الإشعارات.
--
--  ما الذي يفعله هذا الملف
--    يُنشئ إشعارًا في قاعدة البيانات عند كلّ إجراءٍ ماليٍّ يُنفَّذ من تطبيق
--    الأدمن، ويضيف رسالةً عامّةً يكتبها الأدمن للجميع:
--
--      احتسابُ شهرٍ (استحقاق)   → للعضو صاحب الاستحقاق وحده
--      تسجيلُ قبض / إلغاؤه       → للعضو صاحب الإيصال وحده
--      صرفٌ جماعيّ / إلغاؤه      → لكلّ الأعضاء
--      صرفٌ لعضوٍ بعينه / إلغاؤه → لذلك العضو وحده
--      رسالةُ الإدارة            → لكلّ الأعضاء
--
--  ⚠ لا يتغيّر أيُّ إجراءٍ ماليّ، ولا أيُّ رقم، ولا أيُّ دالّةٍ ماليّة. الذي يُضاف
--    محفّزاتٌ «بعد» الإدراج، تكتب في جدولٍ منفصل — وكلٌّ منها يبتلع أيَّ خطأٍ
--    فيه ولا يرفعه. فإن تعطّل الإشعار لأيّ سبب، يمضي القبضُ والصرفُ والاحتساب
--    تمامًا كما كانت، ولا يعلم بالعطل إلا سطرُ تحذيرٍ في سجلّ الخادم.
--    الإشعارُ خدمةٌ فوق الدفتر، لا شرطٌ من شروطه.
--
--  ⚠ والصرفُ لعضوٍ بعينه لا يُعلَن للجميع، عن قصد. قرّرت الجمعيةُ من قبل أنّ
--    ما صُرف لرجلٍ في عزاءٍ أو مولودٍ أخصُّ ما في النظام، فأُسقطت سياسةُ
--    `read_all_disbursements_adeel` ولا يرى العضوُ إلا الصرفَ الجماعيّ في
--    «أسلاف للغير». الإشعارُ يتبع القاعدة نفسَها: الجماعيُّ للجميع، والفرديُّ
--    لصاحبه. ولو أُعلن الفرديُّ للجميع لقرأ كلُّ عضوٍ على هاتفه ما حجبته
--    الشاشة عنه.
--
--  ⚠ أوامرُ محرّر SQL والترحيل لا تُنشئ إشعارًا. كلُّ محفّزٍ يشترط auth.uid() —
--    أي أنّ الإجراء جاء من حسابٍ مسجَّلٍ دخولُه في التطبيق. محرّرُ Supabase يعمل
--    باسم postgres بلا auth.uid()، فإعادةُ MIGRATE_FULL_HISTORY مثلًا — مئاتُ
--    الإيصالات والسندات — لا تُغرق هواتف الأعضاء بمئات الإشعارات عن ماضٍ قديم.
--
--  ⚠ ولا مفتاحَ أجنبيّ من الإشعارات إلى أيّ جدول، عن قصد. purge_all_data يفرّغ
--    جدول العدايل بـ TRUNCATE، وPostgres يرفض تفريغ جدولٍ يشير إليه جدولٌ باقٍ
--    — فمفتاحٌ أجنبيٌّ هنا كان سيُفشل المسحَ الكامل (الدرسُ نفسُه في
--    chat_messages). والثمنُ مُعالَج: بعد مسحٍ كامل تُعاد أرقامُ العدايل من
--    ١، فيقرأ العضوُ الجديدُ صاحبُ الرقم ١ إشعاراتِ القديم — لولا أنّ السياسة
--    لا تُريه إلا ما أُنشئ بعد إنشاء سجلّه هو.
--
--  ⚠ «فوريّ» من الخادم نفسِه: كلُّ إشعارٍ يُدرج يقرع جرسَ القناة الخاصّة
--    `association` عبر realtime.send، فتسأل هواتفُ الأعضاء فورًا. الجرسُ لا
--    يحمل نصًّا ولا اسمًا — كلمة «notify» فقط — وتبقى القراءةُ عبر RLS كما هي.
--    وإن لم تكن realtime.send في المشروع، يُتخطّى الجرسُ ويصل الإشعار بالاستطلاع.
--
--  كيفيّة التطبيق
--    SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.payments') IS NULL
     OR to_regclass('public.disbursements') IS NULL
     OR to_regclass('public.receivables') IS NULL THEN
    RAISE EXCEPTION 'جداول الجمعية غير موجودة — هذا ليس مشروع الجمعية.';
  END IF;
  IF to_regprocedure('public.period_label(text)') IS NULL THEN
    RAISE EXCEPTION 'period_label(text) غير موجودة — طبّق ترقيعات الاستحقاقات أولًا.';
  END IF;

  -- ⚠ صورةُ الأرقام قبل أيّ سطرٍ من هذا الملف، تُقارَن بها في آخره. محليّةٌ
  --   للمعاملة (true)، فلا تبقى بعد COMMIT ولا تُكتب في أيّ جدول.
  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
END $prereq$;

-- == 1. الجدول =============================================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- 'member' لعضوٍ بعينه (adeel_id)، و'all' لكلّ الأعضاء
  audience    text        NOT NULL,
  adeel_id    bigint,
  kind        text        NOT NULL,
  title       text        NOT NULL,
  body        text        NOT NULL,
  -- رقمُ الإيصال أو السند أو الشهر — للعرض، لا مفتاحٌ أجنبيّ
  ref         text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid,
  CONSTRAINT ck_notifications_audience CHECK (audience IN ('member', 'all')),
  CONSTRAINT ck_notifications_shape    CHECK ((audience = 'member') = (adeel_id IS NOT NULL)),
  CONSTRAINT ck_notifications_kind     CHECK (kind IN (
    'receivable', 'payment', 'payment_cancelled',
    'disbursement', 'disbursement_cancelled', 'broadcast')),
  CONSTRAINT ck_notifications_title    CHECK (length(title) BETWEEN 1 AND 120),
  CONSTRAINT ck_notifications_body     CHECK (length(body) BETWEEN 1 AND 1000)
);

CREATE INDEX IF NOT EXISTS ix_notifications_member
  ON public.notifications (adeel_id, id) WHERE audience = 'member';
CREATE INDEX IF NOT EXISTS ix_notifications_all
  ON public.notifications (id) WHERE audience = 'all';

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- ⚠ Supabase يمنح anon وauthenticated كلَّ الصلاحيّات على أيّ جدولٍ جديد عبر
--   ALTER DEFAULT PRIVILEGES. الكتابةُ هنا للمحفّزات والدالّة وحدها، فتُسحب
--   الصلاحيّاتُ كلُّها ثمّ تُمنح القراءةُ فقط، وRLS تقرّر أيَّ صفّ.
REVOKE ALL ON public.notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.notifications TO authenticated;

-- الإدارة ترى كلَّ ما أُرسل.
DROP POLICY IF EXISTS read_notifications_staff ON public.notifications;
CREATE POLICY read_notifications_staff ON public.notifications
  FOR SELECT TO authenticated
  USING (public.has_role('viewer'));

-- العضو يرى ما وُجّه له، وما وُجّه للجميع — مما أُنشئ بعد سجلّه.
-- ⚠ my_adeel_id() تشترط الجهاز المربوط، فهاتفٌ غريبٌ لا يقرأ صفًّا.
-- ⚠ (SELECT …) حول كلّ استدعاء: يُحسب مرّةً للاستعلام لا مرّةً لكلّ صفّ.
DROP POLICY IF EXISTS read_notifications_member ON public.notifications;
CREATE POLICY read_notifications_member ON public.notifications
  FOR SELECT TO authenticated
  USING (
    (SELECT public.my_adeel_id()) IS NOT NULL
    AND (audience = 'all' OR adeel_id = (SELECT public.my_adeel_id()))
    AND created_at >= (SELECT a.created_at FROM public.adeels a
                        WHERE a.id = (SELECT public.my_adeel_id()))
  );

-- == 2. العرض ==============================================================
-- ⚠ LEFT JOIN على العدايل: الإدارةُ ترى لمن وُجّه كلُّ إشعار؛ والعضوُ لا يرى من
--   العدايل إلا صفّه، فيظهر كودُه بجانب إشعاراته ولا شيءَ بجانب العامّة.
CREATE OR REPLACE VIEW public.v_notifications WITH (security_invoker = on) AS
SELECT n.id          AS "id",
       n.audience    AS "audience",
       n.kind        AS "kind",
       n.title       AS "title",
       n.body        AS "body",
       n.ref         AS "ref",
       n.created_at  AS "createdAt",
       a.adeel_code  AS "adeelCode",
       a.full_name   AS "adeelName"
  FROM public.notifications n
  LEFT JOIN public.adeels a ON a.id = n.adeel_id;

REVOKE ALL ON public.v_notifications FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.v_notifications TO authenticated;

-- == 3. صياغةُ المبلغ ======================================================
-- ⚠ مبلغٌ مصاغٌ مرّةً واحدة هنا — «5,415.00» — لا في كلّ محفّزٍ بصيغته.
CREATE OR REPLACE FUNCTION public.notify_money(p numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $m$ SELECT to_char(coalesce(p, 0), 'FM999,999,990.00') $m$;

-- == 4. الإدراجُ والجرس ====================================================
-- ⚠ مكانٌ واحدٌ يُدرج الإشعار ويقرع الجرس، تستدعيه المحفّزاتُ الثلاثة ودالّةُ
--   رسالة الإدارة. والجرسُ داخل كتلة استثناءٍ خاصّة به: قناةٌ متعطّلة لا
--   تُسقط إشعارًا، فالإشعارُ يصل بالاستطلاع على كلّ حال.
CREATE OR REPLACE FUNCTION public.notify_insert(
  p_audience text, p_adeel_id bigint, p_kind text,
  p_title text, p_body text, p_ref text)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $ni$
DECLARE v_id bigint;
BEGIN
  INSERT INTO public.notifications (audience, adeel_id, kind, title, body, ref, created_by)
  VALUES (p_audience, p_adeel_id, p_kind,
          left(p_title, 120), left(p_body, 1000), p_ref, auth.uid())
  RETURNING id INTO v_id;

  BEGIN
    IF to_regprocedure('realtime.send(jsonb,text,text,boolean)') IS NOT NULL THEN
      -- ⚠ كلمةٌ واحدة، لا نصَّ ولا اسم: مَن يسمعها يسأل الخادم فتقرّر RLS.
      EXECUTE 'SELECT realtime.send($1, $2, $3, $4)'
        USING jsonb_build_object('kind', 'notify'), 'ring', 'association', true;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify ring: %', SQLERRM;
  END;

  RETURN v_id;
END $ni$;

-- == 5. المحفّزات ==========================================================
-- ⚠ AFTER، وكلُّ واحدٍ داخل كتلة استثناء تبتلع كلَّ خطأ — حتى قراءة auth.uid()
--   نفسِها، لأنّ ترويسةً تالفة ترفع خطأ تحويلٍ إلى uuid. خارج الكتلة كان ذلك
--   الخطأ سيُسقط القبضَ نفسَه. RETURN NULL في محفّز AFTER لا يغيّر شيئًا.

CREATE OR REPLACE FUNCTION public.notify_on_receivable()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $nr$
BEGIN
  BEGIN
    IF auth.uid() IS NULL OR NEW.status = 'ملغي' THEN
      RETURN NULL;
    END IF;
    PERFORM public.notify_insert(
      'member', NEW.adeel_id, 'receivable',
      'استحقاق شهري جديد',
      format('تم احتساب اشتراك %s بقيمة %s د.ل.',
             public.period_label(NEW.period::text), public.notify_money(NEW.total)),
      NEW.period::text);
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_on_receivable: %', SQLERRM;
  END;
  RETURN NULL;
END $nr$;

CREATE OR REPLACE FUNCTION public.notify_on_payment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $np$
BEGIN
  BEGIN
    IF auth.uid() IS NULL THEN
      RETURN NULL;
    END IF;
    IF TG_OP = 'INSERT' AND NEW.status <> 'ملغي' THEN
      PERFORM public.notify_insert(
        'member', NEW.adeel_id, 'payment',
        'تم تسجيل سداد',
        format('استُلم منك %s د.ل — إيصال رقم %s.',
               public.notify_money(NEW.amount), NEW.receipt_no),
        NEW.receipt_no);
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> 'ملغي' AND NEW.status = 'ملغي' THEN
      PERFORM public.notify_insert(
        'member', NEW.adeel_id, 'payment_cancelled',
        'إلغاء إيصال',
        format('أُلغي الإيصال رقم %s بقيمة %s د.ل.',
               NEW.receipt_no, public.notify_money(NEW.amount)),
        NEW.receipt_no);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_on_payment: %', SQLERRM;
  END;
  RETURN NULL;
END $np$;

CREATE OR REPLACE FUNCTION public.notify_on_disbursement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $nd$
DECLARE
  v_all   boolean;
  v_note  text;
BEGIN
  BEGIN
    IF auth.uid() IS NULL THEN
      RETURN NULL;
    END IF;
    -- ⚠ payee_adeel_id IS NULL، لا kind = 'جماعي': القاعدةُ تحرس الاسم، فتُكتب
    --   على العمود الذي يحمل الاسم (كما في read_collective_disbursements).
    v_all  := NEW.payee_adeel_id IS NULL;
    v_note := CASE WHEN nullif(btrim(coalesce(NEW.note, '')), '') IS NULL THEN ''
                   ELSE ' («' || left(btrim(NEW.note), 160) || '»)' END;

    IF TG_OP = 'INSERT' AND NEW.status <> 'ملغي' THEN
      PERFORM public.notify_insert(
        CASE WHEN v_all THEN 'all' ELSE 'member' END,
        NEW.payee_adeel_id, 'disbursement',
        CASE WHEN v_all THEN 'صرف من صندوق الجمعية' ELSE 'صرف لك من الصندوق' END,
        format(CASE WHEN v_all THEN 'صُرف %s د.ل — %s%s. سند رقم %s.'
                               ELSE 'صُرف لك %s د.ل — %s%s. سند رقم %s.' END,
               public.notify_money(NEW.amount), NEW.category::text, v_note,
               NEW.voucher_no),
        NEW.voucher_no);
    ELSIF TG_OP = 'UPDATE' AND OLD.status <> 'ملغي' AND NEW.status = 'ملغي' THEN
      PERFORM public.notify_insert(
        CASE WHEN v_all THEN 'all' ELSE 'member' END,
        NEW.payee_adeel_id, 'disbursement_cancelled',
        'إلغاء سند صرف',
        format('أُلغي سند الصرف رقم %s بقيمة %s د.ل.',
               NEW.voucher_no, public.notify_money(NEW.amount)),
        NEW.voucher_no);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'notify_on_disbursement: %', SQLERRM;
  END;
  RETURN NULL;
END $nd$;

DROP TRIGGER IF EXISTS trg_notify_receivable ON public.receivables;
CREATE TRIGGER trg_notify_receivable
  AFTER INSERT ON public.receivables
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_receivable();

DROP TRIGGER IF EXISTS trg_notify_payment ON public.payments;
CREATE TRIGGER trg_notify_payment
  AFTER INSERT OR UPDATE OF status ON public.payments
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_payment();

DROP TRIGGER IF EXISTS trg_notify_disbursement ON public.disbursements;
CREATE TRIGGER trg_notify_disbursement
  AFTER INSERT OR UPDATE OF status ON public.disbursements
  FOR EACH ROW EXECUTE FUNCTION public.notify_on_disbursement();

-- == 6. رسالةُ الإدارة =====================================================
CREATE OR REPLACE FUNCTION public.send_broadcast(p_title text, p_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $sb$
DECLARE
  v_title text := nullif(btrim(coalesce(p_title, '')), '');
  v_body  text := btrim(coalesce(p_body, ''));
  v_id    bigint;
BEGIN
  PERFORM public.require_role('admin');

  -- RUL18 كرسالة المحادثة: المعنى نفسُه — «فارغة» و«أطول من المسموح».
  IF v_body = '' THEN
    RAISE EXCEPTION 'اكتب نصَّ الرسالة قبل الإرسال' USING ERRCODE = 'RUL18';
  END IF;
  IF length(v_body) > 1000 THEN
    RAISE EXCEPTION 'الرسالة أطول من 1000 حرف' USING ERRCODE = 'RUL18';
  END IF;
  IF v_title IS NOT NULL AND length(v_title) > 120 THEN
    RAISE EXCEPTION 'العنوان أطول من 120 حرفًا' USING ERRCODE = 'RUL18';
  END IF;

  v_id := public.notify_insert('all', NULL, 'broadcast',
                               coalesce(v_title, 'رسالة من الإدارة'), v_body, NULL);
  RETURN jsonb_build_object('id', v_id);
END $sb$;

-- == 7. قائمةُ السماح — تُقرأ حيّةً ويُضاف إليها مُدخلٌ واحد ====================
-- ⚠ send_broadcast وحدها. المحفّزاتُ ودالّةُ الإدراج لا يستدعيها عميلٌ أبدًا —
--   لو كانت notify_insert قابلةً للاستدعاء لكتب أيُّ عضوٍ إشعارًا لمن شاء.
DO $allow$
DECLARE
  v_old text[] := public.client_callable_functions();
  v_new text[];
BEGIN
  IF 'send_broadcast(text,text)' = ANY (SELECT replace(a, ' ', '') FROM unnest(v_old) a) THEN
    v_new := v_old;
  ELSE
    v_new := v_old || 'send_broadcast(text,text)'::text;
  END IF;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 8. المسحة، بعد آخر CREATE في هذا الملف ================================
-- ⚠ ستُّ دوالّ وُلدت جديدة فأخذت EXECUTE to PUBLIC. المسحةُ تسحبها كلَّها
--   وتمنح send_broadcast وحدها لأنّها في القائمة.
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

-- == 9. الفحص: للقراءة فقط، وكلُّ صفٍّ يجب أن يقول true ====================
SELECT 'جدولُ الإشعارات والعرض قائمان' AS "الفحص",
       to_regclass('public.notifications') IS NOT NULL
   AND to_regclass('public.v_notifications') IS NOT NULL AS "النتيجة"
UNION ALL SELECT 'والمحفّزاتُ الثلاثة على الاستحقاق والقبض والصرف',
       (SELECT count(*) FROM pg_trigger
         WHERE tgname IN ('trg_notify_receivable', 'trg_notify_payment',
                          'trg_notify_disbursement') AND NOT tgisinternal) = 3
UNION ALL SELECT 'ولا يكتب العضوُ في الجدول مباشرة',
       NOT has_table_privilege('authenticated', 'public.notifications', 'INSERT')
   AND NOT has_table_privilege('authenticated', 'public.notifications', 'UPDATE')
   AND NOT has_table_privilege('authenticated', 'public.notifications', 'DELETE')
UNION ALL SELECT 'ولا يستدعي دالّةَ الإدراج ولا المحفّزات',
       NOT has_function_privilege('authenticated',
             'public.notify_insert(text,bigint,text,text,text,text)', 'EXECUTE')
   AND NOT has_function_privilege('authenticated',
             'public.notify_on_payment()', 'EXECUTE')
UNION ALL SELECT 'ورسالةُ الإدارة متاحةٌ للاستدعاء (وتفحص الدور في جسدها)',
       has_function_privilege('authenticated', 'public.send_broadcast(text,text)', 'EXECUTE')
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ (المقبوض، المصروف، الرصيد، المتبقّي)',
       (SELECT row_to_json(s)::text FROM public.v_cash_summary s)
         = current_setting('adayl.fund_before', true)
-- ⚠ now() هو وقتُ بدء هذه المعاملة، فكلُّ صفٍّ أُدرج فيها يحمله بالضبط.
UNION ALL SELECT 'ولم يُرسل هذا الملفُّ إشعارًا واحدًا لأحد',
       NOT EXISTS (SELECT 1 FROM public.notifications WHERE created_at = now());

-- == 10. الحرّاس ===========================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

COMMIT;
