-- ترحيلُ بيانات جمعية العدايل من منظومة سطح المكتب — 2026-09-11
-- المصدر: EXCHANGESYS2026 · ASSOCIATIONID = 1 · ثمانيةُ مشتركين
-- استحقاقات 8800.00 · مقبوضات 6900.00 · مصروفات 8295.00

BEGIN;

-- ══ §0. الحارس: السجلُّ ثمانيةٌ بأكواد A-01..A-08 ════════════
-- ⚠ لا جدولَ مؤقّتًا هنا البتّة، ولخطأٍ دفعْتُ ثمنَه: CREATE TEMP TABLE
--   يعيش في جلسةٍ واحدة، ومحرّرُ Supabase لا يضمن جلسةً واحدةً لكلّ
--   جملة، فجاء 42P01. فكلُّ إشارةٍ إلى عديلٍ صارت الآن قراءةً
--   مباشرةً من public.adeels بالكود نفسِه.
DO $guard$
DECLARE v_n int; v_bad text;
BEGIN
  SELECT count(*) INTO v_n FROM public.adeels;
  IF v_n <> 8 THEN
    RAISE EXCEPTION 'السجلّ يحمل % عديلاً لا ثمانية — أوقفتُ الترحيل', v_n;
  END IF;

  SELECT string_agg(c, ', ' ORDER BY c) INTO v_bad
    FROM unnest(ARRAY['A-01','A-02','A-03','A-04','A-05','A-06','A-07','A-08']) c
   WHERE NOT EXISTS (SELECT 1 FROM public.adeels a WHERE a.adeel_code = c);
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'أكوادٌ مفقودةٌ من السجلّ: %', v_bad;
  END IF;

  -- ⚠ وكودٌ مكرّرٌ أخطرُ من مفقود: المفقودُ يُرفَض هنا، والمكرّرُ
  --   يجعل (SELECT id FROM adeels WHERE adeel_code=...) يردُّ صفّين، فينهار
  --   بـ 21000 وسطَ الترحيل بدل أن يُرفَض في أوّلِه.
  SELECT string_agg(adeel_code, ', ') INTO v_bad
    FROM (SELECT adeel_code FROM public.adeels
           GROUP BY adeel_code HAVING count(*) > 1) d;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'كودٌ مكرّرٌ في السجلّ: %', v_bad;
  END IF;
END $guard$;

-- ══ §1. مسحُ البيانات الماليّة وحدها ═══════════════════════════════════
-- ⚠ TRUNCATE لا DELETE: محفّزاتُ «لا يُحذف» لا تُطلق عليه، فلا يُنزع حارسٌ
--   ولا يبقى بابٌ مفتوح. والسجلُّ والإعداداتُ والحساباتُ تبقى كما هي —
--   وهذا بالضبط ما يفعله purge_financial_data.
TRUNCATE TABLE public.payment_allocations, public.cash_movements,
               public.payments, public.receivables,
               public.disbursements, public.closed_periods
  RESTART IDENTITY;

-- ══ §2. الاشتراكُ الشهريّ و«ماعدا» ═════════════════════════════════════
-- الاشتراك 100، وشهرا 01 و06 بـ 200.00 و200.00 كما في المنظومة.
UPDATE public.association_settings SET
  member_fee = 100.00,
  fee_exceptions = '{"01":"200.00","06":"200.00"}'::jsonb,
  -- ⚠ تاريخٌ لا نصُّ شهر: system_start عمودُ date، وأوّلُ شهرٍ في
  --   المنظومة هو 2026-01، فبدايتُه أوّلُ يومٍ فيه.
  system_start = DATE '2026-01-01'
 WHERE id = 1;

-- ══ §3. تعطيلُ محفّزَي التاريخ — ويُعادان قبل COMMIT ════════════════════
-- ⚠ pay_stamp_time و disb_stamp_time يستبدلان التاريخ بـ now() عند الإدخال.
--   بدون تعطيلهما تصير الإيصالاتُ الستّةُ والأربعون وسنداتُ الصرف الأربعة
--   كلُّها بتاريخ اليوم، ويضيع تسعةُ أشهرٍ من التاريخ. يُعادان في §9، داخل
--   المعاملة نفسِها، فلا توجد لحظةٌ يكون فيها الحارسُ مفقودًا بعد الانتهاء.
ALTER TABLE public.payments      DISABLE TRIGGER trg_pay_stamp_time;
ALTER TABLE public.disbursements DISABLE TRIGGER trg_disb_stamp_time;

-- ══ §4. الأسماءُ والهواتف من المنظومة ══════════════════════════════════
UPDATE public.adeels a SET
  full_name = m.full_name,
  phone     = nullif(m.phone, ''),
  status    = 'نشط'
  FROM (VALUES
    ('A-01', 'محمد حمد المانجا', '0944557059'),
    ('A-02', 'المهدي عبدالله محمد بوفراج الشوبكي', '201130572182'),
    ('A-03', 'هيثم مفتاح عبدالعظيم', '0916926362'),
    ('A-04', 'ايمن صالح محمد صالح بلها', '201130572182'),
    ('A-05', 'عبدالعزيز عطية حمد يونس الخشبي', '201130572182'),
    ('A-06', 'سالم صالح الشيخي', '0944557059'),
    ('A-07', 'عمران ونيس صالح ادم بوصخرة', '0944557059'),
    ('A-08', 'رزق المبروك جلجال', '0944557059')
  ) AS m(code, full_name, phone)
 WHERE a.adeel_code = m.code;

-- ══ §5. الاستحقاقات — تسعةُ أشهرٍ × ثمانية ═════════════════════════════
-- ⚠ created_at مذكورٌ صراحةً: بيانُ العديل يقرأ تاريخَ الاستحقاق منه، فلو
--   تُرك للقيمة الافتراضيّة لظهرت تسعةُ أشهرٍ كلُّها بتاريخ اليوم.
-- ⚠ و paid يُكتب مباشرةً، و derive_recv_status يشتقّ الحالةَ منه — فلا
--   تُكتب حالةٌ باليد ولا يمكن أن تخالف المال.
INSERT INTO public.receivables
  (adeel_id, period, period_end, adeel_name, total, paid, created_at, legacy_id)
VALUES
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-01', '2026-01-31', 'محمد حمد المانجا', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-1-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-02', '2026-02-28', 'محمد حمد المانجا', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-1-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-03', '2026-03-31', 'محمد حمد المانجا', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-1-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-04', '2026-04-30', 'محمد حمد المانجا', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-1-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-05', '2026-05-31', 'محمد حمد المانجا', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-1-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-06', '2026-06-30', 'محمد حمد المانجا', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-1-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-07', '2026-07-31', 'محمد حمد المانجا', 100.00, 100.00, '2026-07-05 09:00:00+02', 'EXSYS-RECV-1-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-08', '2026-08-31', 'محمد حمد المانجا', 100.00, 100.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-1-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), '2026-09', '2026-09-30', 'محمد حمد المانجا', 100.00, 100.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-1-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-01', '2026-01-31', 'المهدي عبدالله محمد بوفراج الشوبكي', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-2-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-02', '2026-02-28', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-2-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-03', '2026-03-31', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-2-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-04', '2026-04-30', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-2-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-05', '2026-05-31', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-2-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-06', '2026-06-30', 'المهدي عبدالله محمد بوفراج الشوبكي', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-2-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-07', '2026-07-31', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-07-05 09:00:00+02', 'EXSYS-RECV-2-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-08', '2026-08-31', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-2-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), '2026-09', '2026-09-30', 'المهدي عبدالله محمد بوفراج الشوبكي', 100.00, 100.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-2-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-01', '2026-01-31', 'هيثم مفتاح عبدالعظيم', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-3-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-02', '2026-02-28', 'هيثم مفتاح عبدالعظيم', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-3-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-03', '2026-03-31', 'هيثم مفتاح عبدالعظيم', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-3-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-04', '2026-04-30', 'هيثم مفتاح عبدالعظيم', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-3-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-05', '2026-05-31', 'هيثم مفتاح عبدالعظيم', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-3-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-06', '2026-06-30', 'هيثم مفتاح عبدالعظيم', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-3-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-07', '2026-07-31', 'هيثم مفتاح عبدالعظيم', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-3-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-08', '2026-08-31', 'هيثم مفتاح عبدالعظيم', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-3-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), '2026-09', '2026-09-30', 'هيثم مفتاح عبدالعظيم', 100.00, 0.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-3-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-01', '2026-01-31', 'ايمن صالح محمد صالح بلها', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-4-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-02', '2026-02-28', 'ايمن صالح محمد صالح بلها', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-4-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-03', '2026-03-31', 'ايمن صالح محمد صالح بلها', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-4-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-04', '2026-04-30', 'ايمن صالح محمد صالح بلها', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-4-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-05', '2026-05-31', 'ايمن صالح محمد صالح بلها', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-4-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-06', '2026-06-30', 'ايمن صالح محمد صالح بلها', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-4-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-07', '2026-07-31', 'ايمن صالح محمد صالح بلها', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-4-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-08', '2026-08-31', 'ايمن صالح محمد صالح بلها', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-4-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), '2026-09', '2026-09-30', 'ايمن صالح محمد صالح بلها', 100.00, 0.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-4-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-01', '2026-01-31', 'عبدالعزيز عطية حمد يونس الخشبي', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-5-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-02', '2026-02-28', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-5-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-03', '2026-03-31', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-5-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-04', '2026-04-30', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-5-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-05', '2026-05-31', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-5-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-06', '2026-06-30', 'عبدالعزيز عطية حمد يونس الخشبي', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-5-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-07', '2026-07-31', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-5-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-08', '2026-08-31', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-5-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), '2026-09', '2026-09-30', 'عبدالعزيز عطية حمد يونس الخشبي', 100.00, 0.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-5-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-01', '2026-01-31', 'سالم صالح الشيخي', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-6-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-02', '2026-02-28', 'سالم صالح الشيخي', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-6-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-03', '2026-03-31', 'سالم صالح الشيخي', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-6-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-04', '2026-04-30', 'سالم صالح الشيخي', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-6-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-05', '2026-05-31', 'سالم صالح الشيخي', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-6-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-06', '2026-06-30', 'سالم صالح الشيخي', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-6-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-07', '2026-07-31', 'سالم صالح الشيخي', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-6-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-08', '2026-08-31', 'سالم صالح الشيخي', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-6-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), '2026-09', '2026-09-30', 'سالم صالح الشيخي', 100.00, 0.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-6-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-01', '2026-01-31', 'عمران ونيس صالح ادم بوصخرة', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-7-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-02', '2026-02-28', 'عمران ونيس صالح ادم بوصخرة', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-7-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-03', '2026-03-31', 'عمران ونيس صالح ادم بوصخرة', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-7-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-04', '2026-04-30', 'عمران ونيس صالح ادم بوصخرة', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-7-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-05', '2026-05-31', 'عمران ونيس صالح ادم بوصخرة', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-7-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-06', '2026-06-30', 'عمران ونيس صالح ادم بوصخرة', 200.00, 100.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-7-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-07', '2026-07-31', 'عمران ونيس صالح ادم بوصخرة', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-7-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-08', '2026-08-31', 'عمران ونيس صالح ادم بوصخرة', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-7-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), '2026-09', '2026-09-30', 'عمران ونيس صالح ادم بوصخرة', 100.00, 0.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-7-2026-09'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-01', '2026-01-31', 'رزق المبروك جلجال', 200.00, 200.00, '2026-01-04 09:00:00+02', 'EXSYS-RECV-8-2026-01'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-02', '2026-02-28', 'رزق المبروك جلجال', 100.00, 100.00, '2026-02-01 09:00:00+02', 'EXSYS-RECV-8-2026-02'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-03', '2026-03-31', 'رزق المبروك جلجال', 100.00, 100.00, '2026-03-10 09:00:00+02', 'EXSYS-RECV-8-2026-03'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-04', '2026-04-30', 'رزق المبروك جلجال', 100.00, 100.00, '2026-04-17 09:00:00+02', 'EXSYS-RECV-8-2026-04'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-05', '2026-05-31', 'رزق المبروك جلجال', 100.00, 100.00, '2026-05-08 09:00:00+02', 'EXSYS-RECV-8-2026-05'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-06', '2026-06-30', 'رزق المبروك جلجال', 200.00, 200.00, '2026-06-04 09:00:00+02', 'EXSYS-RECV-8-2026-06'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-07', '2026-07-31', 'رزق المبروك جلجال', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-8-2026-07'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-08', '2026-08-31', 'رزق المبروك جلجال', 100.00, 0.00, '2026-08-02 09:00:00+02', 'EXSYS-RECV-8-2026-08'),
  ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), '2026-09', '2026-09-30', 'رزق المبروك جلجال', 100.00, 0.00, '2026-09-06 09:00:00+02', 'EXSYS-RECV-8-2026-09');
-- ══ §6. الإيصالات، وتخصيصُها، وحركةُ الخزينة ═══════════════════════════
-- ⚠ ثلاثةُ صفوفٍ لكلّ إيصال، كما تفعل register_payment بالضبط: الإيصال،
--   ثمّ تخصيصُه على أقدمِ استحقاقٍ فأحدث (FIFO)، ثمّ مرآتُه في الخزينة.
--   حُسب التخصيصُ هنا بنفس خوارزميّة الدالّة وطُوبق على كلّ رجلٍ على حدة.
-- ⚠ occurred_at في الخزينة يُنسخ من paid_at ولا يُولَّد — القاعدة 8 تقول
--   إنّ الحركة مرآةُ الإيصال، ومرآةٌ بتاريخٍ آخر ليست مرآة.

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-2')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-2'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-3')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-3'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-4')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-4'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-5')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-5'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-6')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-6'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-7')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-7'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-8')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-8'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر يناير-2026م', '2026-01-04 10:00:00+02', 'EXSYS-PAY-9')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-9'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي شهر 1 لتعدل القسط الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-11')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-11'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-12')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-12'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-13')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-13'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-14')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-14'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-15')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-15'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-16')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-16'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-17')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-17'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), 100.00,
          'نقداً', 'المنظومة السابقة', 'باقي قسط شهر1 لتعديلة الى 200د.ل', '2026-02-03 10:00:00+02', 'EXSYS-PAY-18')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-01', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-18'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهرين 2+3', '2026-03-10 10:00:00+02', 'EXSYS-PAY-20')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-20'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهرين 2+3', '2026-03-10 10:00:00+02', 'EXSYS-PAY-21')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-21'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر4', '2026-04-17 10:00:00+02', 'EXSYS-PAY-23')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-04', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-23'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 4', '2026-04-17 10:00:00+02', 'EXSYS-PAY-24')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-04', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-24'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), 300.00,
          'نقداً', 'المنظومة السابقة', 'سداد الاشهر 2+3+4', '2026-04-19 10:00:00+02', 'EXSYS-PAY-25')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint),
      ('2026-04', 100.00::numeric, 3::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-25'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), 300.00,
          'نقداً', 'المنظومة السابقة', 'سداد الاشهر 2+3+4', '2026-04-19 10:00:00+02', 'EXSYS-PAY-26')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint),
      ('2026-04', 100.00::numeric, 3::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-26'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), 300.00,
          'نقداً', 'المنظومة السابقة', 'سداد الاشهر 2+3+4', '2026-04-19 10:00:00+02', 'EXSYS-PAY-27')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint),
      ('2026-04', 100.00::numeric, 3::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-27'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), 300.00,
          'نقداً', 'المنظومة السابقة', 'سداد الاشهر 2+3+4', '2026-04-19 10:00:00+02', 'EXSYS-PAY-28')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint),
      ('2026-04', 100.00::numeric, 3::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-28'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), 200.00,
          'نقداً', 'المنظومة السابقة', 'سداد شهرين 2+3', '2026-04-19 10:00:00+02', 'EXSYS-PAY-29')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-29'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك شهر 5', '2026-05-10 10:00:00+02', 'EXSYS-PAY-31')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-31'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك شهر 5', '2026-05-10 10:00:00+02', 'EXSYS-PAY-32')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-32'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), 200.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك شهرين 4+5', '2026-05-10 10:00:00+02', 'EXSYS-PAY-33')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-04', 100.00::numeric, 1::smallint),
      ('2026-05', 100.00::numeric, 2::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-33'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), 300.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك الاشهر2+3+4', '2026-05-10 10:00:00+02', 'EXSYS-PAY-34')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-02', 100.00::numeric, 1::smallint),
      ('2026-03', 100.00::numeric, 2::smallint),
      ('2026-04', 100.00::numeric, 3::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-34'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), 100.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك شهر 5', '2026-05-10 10:00:00+02', 'EXSYS-PAY-35')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-35'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), 100.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك شهر 5', '2026-05-10 10:00:00+02', 'EXSYS-PAY-36')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-36'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), 100.00,
          'نقداً', 'المنظومة السابقة', 'سداد اشتراك شهر 5', '2026-05-10 10:00:00+02', 'EXSYS-PAY-37')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-37'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6', '2026-06-26 10:00:00+02', 'EXSYS-PAY-38')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-06', 200.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-38'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6', '2026-06-26 10:00:00+02', 'EXSYS-PAY-39')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-06', 200.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-39'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-03'), 300.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر6=200 + شهر 5=100', '2026-06-26 10:00:00+02', 'EXSYS-PAY-40')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint),
      ('2026-06', 200.00::numeric, 2::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-40'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-04'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6', '2026-06-26 10:00:00+02', 'EXSYS-PAY-41')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-06', 200.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-41'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-05'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6', '2026-06-26 10:00:00+02', 'EXSYS-PAY-42')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-06', 200.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-42'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-06'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6- خلص عليك عبدالعزيز يوم مشيتك لطبرق', '2026-06-26 10:00:00+02', 'EXSYS-PAY-43')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-06', 200.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-43'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-07'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6', '2026-06-26 10:00:00+02', 'EXSYS-PAY-44')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-05', 100.00::numeric, 1::smallint),
      ('2026-06', 100.00::numeric, 2::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-44'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-08'), 200.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 6', '2026-06-26 10:00:00+02', 'EXSYS-PAY-45')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-06', 200.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-45'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 08', '2026-08-02 10:00:00+02', 'EXSYS-PAY-46')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-07', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-46'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'اشتراك شهر 08', '2026-08-02 10:00:00+02', 'EXSYS-PAY-47')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-07', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-47'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'شهر 7', '2026-09-06 10:00:00+02', 'EXSYS-PAY-48')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-08', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-48'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'شهر 7', '2026-09-06 10:00:00+02', 'EXSYS-PAY-49')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-08', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-49'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-01'), 100.00,
          'نقداً', 'المنظومة السابقة', 'شهر 9', '2026-09-06 10:00:00+02', 'EXSYS-PAY-50')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-09', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-50'
  FROM pay;

WITH pay AS (
  INSERT INTO public.payments
    (adeel_id, amount, method, receiver, notes, paid_at, legacy_id)
  VALUES ((SELECT id FROM public.adeels WHERE adeel_code='A-02'), 100.00,
          'نقداً', 'المنظومة السابقة', 'شهر 9', '2026-09-06 10:00:00+02', 'EXSYS-PAY-51')
  RETURNING id, adeel_id, amount, method, paid_at
), alloc AS (
  INSERT INTO public.payment_allocations
    (payment_id, receivable_id, period, amount, sequence_no)
  SELECT pay.id, r.id, r.period, v.amt, v.seq
    FROM pay
    CROSS JOIN (VALUES
      ('2026-09', 100.00::numeric, 1::smallint)
    ) AS v(period, amt, seq)
    JOIN public.receivables r
      ON r.adeel_id = pay.adeel_id AND r.period = v.period
  RETURNING 1
)
INSERT INTO public.cash_movements
  (payment_id, adeel_id, amount, method, occurred_at, legacy_id)
SELECT pay.id, pay.adeel_id, pay.amount, pay.method, pay.paid_at, 'EXSYS-PAY-51'
  FROM pay;

-- ══ §7. سنداتُ الصرف الأربعة ═══════════════════════════════════════════
-- ⚠ «فطور رمضان» لا تكون «لمشترك» أبدًا — ck_disb_shape يرفضها، وهو مُحقّ:
--   عشاءٌ للجميع نفقةٌ جماعيّة، والاسمُ في المنظومة هو مَن استلم المبلغ
--   لينفقه، لا مَن صُرف له. فوُضع في handed_by، وهو الحقلُ الموجودُ لذلك.
-- ⚠ و«مصروف عام» في السند الرابع تعني بلا مستفيدٍ بعينه — جماعيّ كذلك.
INSERT INTO public.disbursements
  (amount, kind, payee_adeel_id, payee_name, category, method, handed_by,
   note, spent_at)
VALUES
  (1500.00, 'لمشترك', (SELECT id FROM public.adeels WHERE adeel_code='A-07'), 'عمران ونيس صالح ادم بوصخرة', 'حالات طارئة', 'نقداً',
   NULL, 'بند الطواري- عنبة الحوش الجديد- عمران ونيس', '2026-01-03 11:00:00+02'),
  (3275.00, 'جماعي', NULL, NULL, 'فطور رمضان', 'نقداً',
   'ايمن صالح محمد صالح بلها', 'عشاء رمضان2026م', '2026-03-10 11:00:00+02'),
  (2020.00, 'لمشترك', (SELECT id FROM public.adeels WHERE adeel_code='A-03'), 'هيثم مفتاح عبدالعظيم', 'عزاء', 'نقداً',
   NULL, 'تعزيه للدريبي - وفاة مفتاخ - سقيطة18كجم + 5كجم زيت+ شوال رز', '2026-03-30 11:00:00+02'),
  (1500.00, 'جماعي', NULL, NULL, 'عزاء', 'نقداً',
   NULL, 'تعزية لعيت بلها - في وفاة عازة رحمة الله عليها', '2026-04-19 11:00:00+02');

-- ══ §8. الأشهرُ التسعةُ مُغلقة ══════════════════════════════════════════
-- ⚠ closed_periods جدولٌ لا استنتاج: شهرٌ لم يُحمَّل فيه أحد يرفع صفرَ
--   استحقاقات، فقراءةُ «مغلق» من الاستحقاقات تجعله مفتوحًا للأبد وتمنع
--   كلَّ شهرٍ بعده — وهذه هي القاعدة 15ب.
INSERT INTO public.closed_periods (period, closed_at, created)
SELECT r.period, min(r.created_at), count(*)::int
  FROM public.receivables r GROUP BY r.period;

-- ══ §9. إعادةُ الحارسَين ═══════════════════════════════════════════════
ALTER TABLE public.payments      ENABLE TRIGGER trg_pay_stamp_time;
ALTER TABLE public.disbursements ENABLE TRIGGER trg_disb_stamp_time;
-- ══ §10. لا نصدّقُ ما لم نُطابقه — وإلّا رجع كلُّ شيء ═══════════════════
-- ⚠ كلُّ رقمٍ هنا مأخوذٌ من المنظومة المصدر، لا من هذا الملفّ. لو اختلّ
--   تخصيصٌ واحدٌ أو سقط صفٌّ، تفشل المطابقةُ وترجع المعاملةُ كاملةً — ولا
--   تستقرّ قاعدةُ الجمعية على رقمٍ لم يُثبَت.
DO $verify$
DECLARE
  v_recv numeric; v_paid numeric; v_disb numeric; v_alloc numeric;
  v_n int; v_bad text;
BEGIN
  -- (١) المجاميع
  SELECT coalesce(sum(total),0) INTO v_recv FROM public.receivables WHERE status <> 'ملغي';
  IF v_recv <> 8800.00 THEN RAISE EXCEPTION 'الاستحقاقات % لا 8800.00', v_recv; END IF;

  SELECT coalesce(sum(amount),0) INTO v_paid FROM public.payments WHERE status <> 'ملغي';
  IF v_paid <> 6900.00 THEN RAISE EXCEPTION 'المقبوضات % لا 6900.00', v_paid; END IF;

  SELECT coalesce(sum(amount),0) INTO v_disb FROM public.disbursements WHERE status <> 'ملغي';
  IF v_disb <> 8295.00 THEN RAISE EXCEPTION 'المصروفات % لا 8295.00', v_disb; END IF;

  -- (٢) الأعداد
  SELECT count(*) INTO v_n FROM public.receivables;
  IF v_n <> 72 THEN RAISE EXCEPTION 'عدد الاستحقاقات % لا 72', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.payments;
  IF v_n <> 46 THEN RAISE EXCEPTION 'عدد الإيصالات % لا 46', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.payment_allocations;
  IF v_n <> 62 THEN RAISE EXCEPTION 'عدد التخصيصات % لا 62', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.disbursements;
  IF v_n <> 4 THEN RAISE EXCEPTION 'عدد السندات % لا 4', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.cash_movements;
  IF v_n <> 46 THEN RAISE EXCEPTION 'حركات الخزينة % لا 46', v_n; END IF;
  SELECT count(*) INTO v_n FROM public.closed_periods;
  IF v_n <> 9 THEN RAISE EXCEPTION 'الأشهر المغلقة % لا 9', v_n; END IF;

  -- (٣) التخصيصُ يطابق الإيصال، والاستحقاقُ يطابق تخصيصاته
  SELECT coalesce(sum(amount),0) INTO v_alloc FROM public.payment_allocations;
  IF v_alloc <> v_paid THEN
    RAISE EXCEPTION 'خُصّص % من % — الفرق رصيدٌ مقدَّم لم يكن في المصدر', v_alloc, v_paid;
  END IF;

  SELECT string_agg(t.txt, E'
  ') INTO v_bad FROM (
    SELECT r.id::text || ': paid=' || r.paid::text || ' alloc=' ||
           coalesce(sum(a.amount),0)::text AS txt
      FROM public.receivables r
      LEFT JOIN public.payment_allocations a ON a.receivable_id = r.id
     GROUP BY r.id, r.paid
    HAVING r.paid <> coalesce(sum(a.amount),0)) t;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'استحقاقٌ لا يطابق تخصيصاته:%s', E'
  ' || v_bad;
  END IF;

  -- (٤) كلُّ رجلٍ على حدة — وهذا ما يمنع وقوعَ مالِ رجلٍ على آخر
  SELECT string_agg(t.txt, E'
  ') INTO v_bad FROM (
    SELECT a.adeel_code || ': مستحق=' || sum(r.total)::text || ' مدفوع=' || sum(r.paid)::text AS txt
      FROM public.adeels a JOIN public.receivables r ON r.adeel_id = a.id
     GROUP BY a.adeel_code
    HAVING (a.adeel_code, sum(r.total), sum(r.paid)) NOT IN (
      ('A-01', 1100.00::numeric, 1100.00::numeric),
      ('A-02', 1100.00::numeric, 1100.00::numeric),
      ('A-03', 1100.00::numeric, 800.00::numeric),
      ('A-04', 1100.00::numeric, 800.00::numeric),
      ('A-05', 1100.00::numeric, 800.00::numeric),
      ('A-06', 1100.00::numeric, 800.00::numeric),
      ('A-07', 1100.00::numeric, 700.00::numeric),
      ('A-08', 1100.00::numeric, 800.00::numeric)
    )) t;
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'أرقامُ عديلٍ لا تطابق المنظومة:%s', E'
  ' || v_bad;
  END IF;

  -- (٥) والخزينة
  IF (v_paid - v_disb) <> -1395.00 THEN
    RAISE EXCEPTION 'رصيد الخزينة % لا -1395.00', (v_paid - v_disb);
  END IF;

  RAISE NOTICE 'طابقت المنظومة: استحقاقات % · مقبوضات % · مصروفات % · رصيد %',
    v_recv, v_paid, v_disb, (v_paid - v_disb);
END $verify$;

SELECT public.assert_signin_intact();
SELECT public.assert_two_doors_only();

COMMIT;

-- ══ الحصيلة ════════════════════════════════════════════════════════════
SELECT a.adeel_code AS "الكود", a.full_name AS "الاسم",
       to_char(sum(r.total),'FM999999990.00')          AS "مستحق",
       to_char(sum(r.paid),'FM999999990.00')           AS "مدفوع",
       to_char(sum(r.total - r.paid),'FM999999990.00') AS "متبقٍ"
  FROM public.adeels a JOIN public.receivables r ON r.adeel_id = a.id
 GROUP BY a.adeel_code, a.full_name ORDER BY a.adeel_code;