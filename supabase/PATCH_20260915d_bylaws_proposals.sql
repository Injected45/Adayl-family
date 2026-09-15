-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-15 (d).  قانونُ الجمعية، ومقترحاتُ المشتركين.
--
--  ما الذي يفعله هذا الملف
--
--  ١. قانون الجمعية — صورُ صفحات العقد.
--     • الأدمن وحده يضيف صفحةً (صورة) ويحذفها.
--     • كلُّ مشتركٍ بمفتاحه يعرض الصفحاتِ فقط.
--     • الصورُ تُحفظ في قاعدة البيانات نفسِها (جدول bylaw_pages)، وتُقرأ عبر
--       القناة نفسِها التي تُقرأ بها بقيّةُ بيانات المشترك، فتسري عليها القواعدُ
--       ذاتُها: المفتاح، والجهاز، والدخول.
--
--  ٢. مقترحاتُ المشتركين.
--     • المشتركُ يرسل مقترحًا: عنوانٌ لا يزيد على 20 حرفًا، ونصّ.
--     • يرى مقترحاتِه وحده؛ ولا يرى مقترحَ مشتركٍ آخر.
--     • الأدمن يرى الكلَّ، وله قراران لا ثالث لهما:
--         قبول → يبقى المقترحُ محفوظًا للأبد، لا يُعدَّل ولا يُحذف ولا يُردّ عليه.
--         رفض  → يُحذف المقترحُ نهائيًّا، فيختفي من عند الأدمن ومن عند المشترك.
--
--  ⚠ «للأبد» مكتوبةٌ في قاعدة البيانات لا في الشاشة: محفّزٌ يرفض أيَّ تعديلٍ
--    على مقترحٍ مقبول وأيَّ حذفٍ له — حتى لو جاء الطلبُ من غير التطبيق.
--
--  ⚠ لا يتغيّر أيُّ رقمٍ ماليّ ولا أيُّ دالّةٍ ماليّة. جدولان جديدان منفصلان،
--    ولا مفتاحَ أجنبيّ منهما إلى العدايل (درسُ الإشعارات: المسحُ الكامل يفرّغ
--    العدايل، ومفتاحٌ أجنبيٌّ كان سيُفشله).
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regclass('public.adeels') IS NULL
     OR to_regclass('public.v_cash_summary') IS NULL
     OR to_regprocedure('public.my_adeel_id()') IS NULL
     OR to_regprocedure('public.has_role(app_role)') IS NULL
     OR to_regprocedure('public.require_role(app_role)') IS NULL
     OR to_regprocedure('public.client_callable_functions()') IS NULL THEN
    RAISE EXCEPTION 'هذا ليس مشروع الجمعية — لم يتغيّر شيء.';
  END IF;

  -- صورةُ الأرقام قبل أيّ سطر، تُقارَن بها في آخر الملف. محليّةٌ للمعاملة.
  PERFORM set_config('adayl.fund_before',
                     (SELECT row_to_json(s)::text FROM public.v_cash_summary s),
                     true);
END $prereq$;

-- == 1. صفحاتُ قانون الجمعية ================================================
CREATE TABLE IF NOT EXISTS public.bylaw_pages (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  image       bytea       NOT NULL,
  mime        text        NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid,
  CONSTRAINT ck_bylaw_mime CHECK (mime IN ('image/jpeg', 'image/png', 'image/webp')),
  CONSTRAINT ck_bylaw_size CHECK (octet_length(image) BETWEEN 1 AND 3000000)
);

-- الصورةُ مضغوطةٌ أصلًا؛ محاولةُ ضغطها ثانيةً عملٌ بلا فائدة.
ALTER TABLE public.bylaw_pages ALTER COLUMN image SET STORAGE EXTERNAL;

ALTER TABLE public.bylaw_pages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.bylaw_pages FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.bylaw_pages TO authenticated;

DROP POLICY IF EXISTS read_bylaw_pages_staff ON public.bylaw_pages;
CREATE POLICY read_bylaw_pages_staff ON public.bylaw_pages
  FOR SELECT TO authenticated
  USING (public.has_role('viewer'));

-- ⚠ my_adeel_id() تشترط المفتاحَ والجهازَ والدخول، فهاتفٌ غريبٌ لا يقرأ صفحة.
DROP POLICY IF EXISTS read_bylaw_pages_member ON public.bylaw_pages;
CREATE POLICY read_bylaw_pages_member ON public.bylaw_pages
  FOR SELECT TO authenticated
  USING ((SELECT public.my_adeel_id()) IS NOT NULL);

-- ⚠ "data" نصُّ base64 بلا فواصل أسطر: encode() يقطع السطرَ كلَّ 76 حرفًا،
--   وفكُّ الترميز في التطبيق يرفض الفاصل. والقائمةُ التي لا تطلب "data" لا
--   تحسبه — فتُقرأ الصفحاتُ خفيفةً، ثم كلُّ صورةٍ وحدها.
CREATE OR REPLACE VIEW public.v_bylaw_pages WITH (security_invoker = on) AS
SELECT b.id                                             AS "id",
       b.mime                                           AS "mime",
       octet_length(b.image)                            AS "sizeBytes",
       b.created_at                                     AS "createdAt",
       translate(encode(b.image, 'base64'), E'\n', '')  AS "data"
  FROM public.bylaw_pages b;

REVOKE ALL ON public.v_bylaw_pages FROM PUBLIC, anon;
GRANT SELECT ON public.v_bylaw_pages TO authenticated;

-- == 2. مقترحاتُ المشتركين ==================================================
-- ⚠ اسمُ المشترك وكودُه منسوخان على الصفّ لحظةَ الإرسال، كما في المحادثة:
--   الأدمن يقرأ لمن المقترحُ دون أن يحتاج جدولَ العدايل.
CREATE TABLE IF NOT EXISTS public.proposals (
  id          bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  adeel_id    bigint      NOT NULL,
  adeel_code  text        NOT NULL,
  adeel_name  text        NOT NULL,
  title       text        NOT NULL,
  body        text        NOT NULL,
  status      text        NOT NULL DEFAULT 'pending',
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid,
  decided_at  timestamptz,
  decided_by  uuid,
  CONSTRAINT ck_proposal_title   CHECK (char_length(title) BETWEEN 1 AND 20
                                        AND btrim(title) = title),
  CONSTRAINT ck_proposal_body    CHECK (char_length(btrim(body)) BETWEEN 1 AND 2000),
  CONSTRAINT ck_proposal_status  CHECK (status IN ('pending', 'accepted')),
  CONSTRAINT ck_proposal_decided CHECK ((status = 'accepted') = (decided_at IS NOT NULL))
);

CREATE INDEX IF NOT EXISTS ix_proposals_adeel ON public.proposals (adeel_id, id DESC);

ALTER TABLE public.proposals ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.proposals FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.proposals TO authenticated;

DROP POLICY IF EXISTS read_proposals_staff ON public.proposals;
CREATE POLICY read_proposals_staff ON public.proposals
  FOR SELECT TO authenticated
  USING (public.has_role('viewer'));

-- المشتركُ يرى مقترحاتِه وحده — مما أُرسل بعد إنشاء سجلّه (بعد مسحٍ كامل
-- تُعاد أرقامُ العدايل، فلا يقرأ الجديدُ ما كتبه القديم).
DROP POLICY IF EXISTS read_proposals_member ON public.proposals;
CREATE POLICY read_proposals_member ON public.proposals
  FOR SELECT TO authenticated
  USING (
    (SELECT public.my_adeel_id()) IS NOT NULL
    AND adeel_id = (SELECT public.my_adeel_id())
    AND created_at >= (SELECT a.created_at FROM public.adeels a
                        WHERE a.id = (SELECT public.my_adeel_id()))
  );

CREATE OR REPLACE VIEW public.v_proposals WITH (security_invoker = on) AS
SELECT p.id          AS "id",
       p.adeel_id    AS "adeelId",
       p.adeel_code  AS "adeelCode",
       p.adeel_name  AS "adeelName",
       p.title       AS "title",
       p.body        AS "body",
       p.status      AS "status",
       p.created_at  AS "createdAt",
       p.decided_at  AS "decidedAt"
  FROM public.proposals p;

REVOKE ALL ON public.v_proposals FROM PUBLIC, anon;
GRANT SELECT ON public.v_proposals TO authenticated;

-- == 3. «للأبد»: المقبولُ لا يُعدَّل ولا يُحذف ================================
-- ⚠ التعديلُ الوحيد المسموح: «بانتظار القرار» → «مقبول»، ولا يتحرّك معه غيرُ
--   وقتِ القرار وصاحبِه. والحذفُ لا يقع إلا على ما لم يُقبل (الرفض).
CREATE OR REPLACE FUNCTION public.proposals_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $pg$
BEGIN
  IF TG_OP = 'DELETE' THEN
    IF OLD.status = 'accepted' THEN
      RAISE EXCEPTION 'المقترح المقبول محفوظ ولا يُحذف' USING ERRCODE = 'RUL20';
    END IF;
    RETURN OLD;
  END IF;

  IF OLD.status <> 'pending'
     OR NEW.status <> 'accepted'
     OR NEW.id         IS DISTINCT FROM OLD.id
     OR NEW.adeel_id   IS DISTINCT FROM OLD.adeel_id
     OR NEW.adeel_code IS DISTINCT FROM OLD.adeel_code
     OR NEW.adeel_name IS DISTINCT FROM OLD.adeel_name
     OR NEW.title      IS DISTINCT FROM OLD.title
     OR NEW.body       IS DISTINCT FROM OLD.body
     OR NEW.created_at IS DISTINCT FROM OLD.created_at
     OR NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'المقترح لا يُعدَّل' USING ERRCODE = 'RUL20';
  END IF;
  RETURN NEW;
END $pg$;

DROP TRIGGER IF EXISTS trg_proposals_guard ON public.proposals;
CREATE TRIGGER trg_proposals_guard
  BEFORE UPDATE OR DELETE ON public.proposals
  FOR EACH ROW EXECUTE FUNCTION public.proposals_guard();

-- == 4. الدوالّ ==============================================================

-- ── صفحةٌ جديدة في قانون الجمعية (الأدمن) ─────────────────────────────────
-- ⚠ النوعُ يُطابَق بأوّل بايتات الملف، لا بما يقوله الطلب: ملفٌّ ليس صورةً
--   لا يدخل الجدولَ ولو سُمّي image/jpeg.
CREATE OR REPLACE FUNCTION public.add_bylaw_page(p_image text, p_mime text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $ab$
DECLARE
  v_mime  text := lower(btrim(coalesce(p_mime, '')));
  v_bytes bytea;
  v_id    bigint;
BEGIN
  PERFORM public.require_role('admin');

  IF v_mime NOT IN ('image/jpeg', 'image/png', 'image/webp') THEN
    RAISE EXCEPTION 'نوع الصورة غير مدعوم — استعمل صورة JPG أو PNG'
      USING ERRCODE = 'RUL21';
  END IF;

  BEGIN
    v_bytes := decode(coalesce(p_image, ''), 'base64');
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'تعذّرت قراءة الصورة' USING ERRCODE = 'RUL21';
  END;

  IF octet_length(v_bytes) = 0 THEN
    RAISE EXCEPTION 'الصورة فارغة' USING ERRCODE = 'RUL21';
  END IF;
  IF octet_length(v_bytes) > 3000000 THEN
    RAISE EXCEPTION 'الصورة أكبر من 3 ميغابايت' USING ERRCODE = 'RUL21';
  END IF;

  IF NOT (
       (v_mime = 'image/jpeg'
          AND substring(v_bytes FROM 1 FOR 3) = '\xffd8ff'::bytea)
    OR (v_mime = 'image/png'
          AND substring(v_bytes FROM 1 FOR 8) = '\x89504e470d0a1a0a'::bytea)
    OR (v_mime = 'image/webp'
          AND substring(v_bytes FROM 1 FOR 4) = '\x52494646'::bytea
          AND substring(v_bytes FROM 9 FOR 4) = '\x57454250'::bytea)
  ) THEN
    RAISE EXCEPTION 'الملف ليس صورة' USING ERRCODE = 'RUL21';
  END IF;

  INSERT INTO public.bylaw_pages (image, mime, created_by)
  VALUES (v_bytes, v_mime, auth.uid())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END $ab$;

-- ── حذفُ صفحة (الأدمن) ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_bylaw_page(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $db$
BEGIN
  PERFORM public.require_role('admin');
  DELETE FROM public.bylaw_pages WHERE id = p_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'الصفحة غير موجودة' USING ERRCODE = 'RUL21';
  END IF;
  RETURN jsonb_build_object('id', p_id);
END $db$;

-- ── مقترحٌ جديد (المشترك) ──────────────────────────────────────────────────
-- ⚠ للمشترك بمفتاحه وحده: my_adeel_id() هي السؤالُ نفسُه الذي تسأله كلُّ
--   سياسات المشترك، فالأدمن وغيرُ المربوط لا يرسلان.
CREATE OR REPLACE FUNCTION public.submit_proposal(p_title text, p_body text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $sp$
DECLARE
  v_adeel   bigint := public.my_adeel_id();
  v_title   text   := btrim(coalesce(p_title, ''));
  v_body    text   := btrim(coalesce(p_body, ''));
  v_code    text;
  v_name    text;
  v_pending int;
  v_id      bigint;
BEGIN
  IF v_adeel IS NULL THEN
    RAISE EXCEPTION 'إرسال المقترحات للمشتركين فقط' USING ERRCODE = 'RUL00';
  END IF;

  IF v_title = '' THEN
    RAISE EXCEPTION 'اكتب عنوان المقترح' USING ERRCODE = 'RUL20';
  END IF;
  IF char_length(v_title) > 20 THEN
    RAISE EXCEPTION 'عنوان المقترح لا يزيد على 20 حرفًا' USING ERRCODE = 'RUL20';
  END IF;
  IF v_body = '' THEN
    RAISE EXCEPTION 'اكتب نصَّ المقترح' USING ERRCODE = 'RUL20';
  END IF;
  IF char_length(v_body) > 2000 THEN
    RAISE EXCEPTION 'نصّ المقترح أطول من 2000 حرف' USING ERRCODE = 'RUL20';
  END IF;

  SELECT count(*) INTO v_pending
    FROM public.proposals
   WHERE adeel_id = v_adeel AND status = 'pending';
  IF v_pending >= 20 THEN
    RAISE EXCEPTION 'لديك 20 مقترحًا بانتظار القرار' USING ERRCODE = 'RUL20';
  END IF;

  SELECT a.adeel_code, a.full_name INTO v_code, v_name
    FROM public.adeels a WHERE a.id = v_adeel;

  INSERT INTO public.proposals (adeel_id, adeel_code, adeel_name, title, body, created_by)
  VALUES (v_adeel, v_code, v_name, v_title, v_body, auth.uid())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object('id', v_id);
END $sp$;

-- ── قبول (الأدمن) ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.accept_proposal(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $ap$
BEGIN
  PERFORM public.require_role('admin');

  UPDATE public.proposals
     SET status = 'accepted', decided_at = now(), decided_by = auth.uid()
   WHERE id = p_id AND status = 'pending';

  IF NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM public.proposals WHERE id = p_id) THEN
      RAISE EXCEPTION 'قُبل هذا المقترح من قبل' USING ERRCODE = 'RUL20';
    END IF;
    RAISE EXCEPTION 'المقترح غير موجود' USING ERRCODE = 'RUL20';
  END IF;

  RETURN jsonb_build_object('id', p_id);
END $ap$;

-- ── رفض (الأدمن): حذفٌ نهائيّ ─────────────────────────────────────────────
-- ⚠ «يختفي تمامًا»: الصفُّ يُحذف، فلا يبقى عند الأدمن ولا عند المشترك ولا في
--   أيّ سجلّ. والمقبولُ لا يُرفض — المحفّزُ يرفضه ولو تجاوز أحدٌ هذه الدالّة.
CREATE OR REPLACE FUNCTION public.reject_proposal(p_id bigint)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $rp$
BEGIN
  PERFORM public.require_role('admin');

  DELETE FROM public.proposals WHERE id = p_id AND status = 'pending';

  IF NOT FOUND THEN
    IF EXISTS (SELECT 1 FROM public.proposals WHERE id = p_id) THEN
      RAISE EXCEPTION 'المقترح المقبول محفوظ ولا يُرفض' USING ERRCODE = 'RUL20';
    END IF;
    RAISE EXCEPTION 'المقترح غير موجود' USING ERRCODE = 'RUL20';
  END IF;

  RETURN jsonb_build_object('id', p_id);
END $rp$;

-- == 5. قائمةُ السماح — تُقرأ حيّةً ويُضاف إليها ما نقص =======================
-- ⚠ الدوالُّ الخمس وحدها. محفّزُ الحماية لا يستدعيه عميلٌ أبدًا.
DO $allow$
DECLARE
  v_old  text[] := public.client_callable_functions();
  v_new  text[] := v_old;
  v_sig  text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'add_bylaw_page(text,text)',
    'delete_bylaw_page(bigint)',
    'submit_proposal(text,text)',
    'accept_proposal(bigint)',
    'reject_proposal(bigint)'
  ] LOOP
    IF NOT (v_sig = ANY (SELECT replace(a, ' ', '') FROM unnest(v_new) a)) THEN
      v_new := v_new || v_sig;
    END IF;
  END LOOP;

  EXECUTE format(
    $f$  CREATE OR REPLACE FUNCTION public.client_callable_functions()
         RETURNS text[] LANGUAGE sql IMMUTABLE
         AS $body$ SELECT %L::text[] $body$ $f$, v_new);
END $allow$;

-- == 6. المسحة، بعد آخر CREATE في هذا الملف ================================
-- ⚠ ستُّ دوالّ وُلدت جديدة فأخذت EXECUTE to PUBLIC. المسحةُ تسحبها كلَّها
--   وتمنح الخمسَ التي في القائمة.
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

-- == 7. الحرّاس ============================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == 8. النتيجة: آخرُ جدولٍ يظهر في المحرّر، وكلُّ صفٍّ يجب أن يقول true ======
SELECT 'جدولا القانون والمقترحات وقائمتاهما موجودة' AS "الفحص",
       (to_regclass('public.bylaw_pages') IS NOT NULL
        AND to_regclass('public.v_bylaw_pages') IS NOT NULL
        AND to_regclass('public.proposals') IS NOT NULL
        AND to_regclass('public.v_proposals') IS NOT NULL)::text AS "النتيجة"
UNION ALL SELECT 'الدوالُّ الخمس متاحةٌ للتطبيق',
       (has_function_privilege('authenticated', 'public.add_bylaw_page(text,text)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.delete_bylaw_page(bigint)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.submit_proposal(text,text)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.accept_proposal(bigint)', 'EXECUTE')
        AND has_function_privilege('authenticated', 'public.reject_proposal(bigint)', 'EXECUTE'))::text
UNION ALL SELECT 'ولا يكتب أحدٌ في الجدولين مباشرة',
       (NOT has_table_privilege('authenticated', 'public.bylaw_pages', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.bylaw_pages', 'DELETE')
        AND NOT has_table_privilege('authenticated', 'public.proposals', 'INSERT')
        AND NOT has_table_privilege('authenticated', 'public.proposals', 'UPDATE')
        AND NOT has_table_privilege('authenticated', 'public.proposals', 'DELETE'))::text
UNION ALL SELECT 'والمقترحُ المقبول محميٌّ من التعديل والحذف',
       (SELECT count(*) = 1 FROM pg_trigger
         WHERE tgname = 'trg_proposals_guard' AND NOT tgisinternal)::text
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       ((SELECT row_to_json(s)::text FROM public.v_cash_summary s)
          = current_setting('adayl.fund_before', true))::text
UNION ALL SELECT 'صفحاتُ القانون المرفوعة',
       (SELECT count(*) FROM public.bylaw_pages)::text
UNION ALL SELECT 'المقترحاتُ المحفوظة',
       (SELECT count(*) FROM public.proposals)::text;

COMMIT;
