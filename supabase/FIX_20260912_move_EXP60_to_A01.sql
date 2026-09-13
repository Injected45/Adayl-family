-- ============================================================================
--  جمعية العدايل — تصحيح 2026-09-12.  سندُ «تعزية للدريبي» ينتقل من هيثم
--  (A-03) إلى محمد حمد المانجا (A-01).
--
--  لماذا كان خطأً
--    المنظومةُ لم تُسجّل للسند حسابًا مقابلًا (AccIDTo = 0)، فحقلُ PaidFor
--    وحدَه هو ما فيه اسم، وهو يحمل «هيثم مفتاح عبدالعظيم». واسمُ الميّت في
--    البيان «مفتاح» يطابق اسمَ والد هيثم، فقرأتُه على أنّه المستفيد. وسي
--    المهدي صحّحه: المستفيدُ محمد حمد المانجا. حقلُ PaidFor في سنداتِ ٢٠٢٥
--    يحمل مَن سلّم المبلغَ لا مَن صُرف له — وهذه حالةٌ منه.
--
--  ⚠ تعديلٌ في مكانه، لا إلغاءٌ وإعادةُ تسجيل، وهذا مقصود. الإلغاءُ وإعادةُ
--    التسجيل هو الطريقُ الصحيح لسندٍ سجّلته الجمعيةُ ثمّ أرادت تغييره —
--    فيبقى الأوّلُ ظاهرًا ملغيًّا ويظهر الثاني. لكنّ `disb_stamp_time` يختم
--    الإدخالَ بساعة الخادم، فالسندُ الجديد كان سيُؤرَّخ اليوم لا 30/03/2026،
--    وتضيع سنةُ الحدث من سجلّ أسلاف محمد. وهذا ليس تصحيحَ قرارٍ للجمعية بل
--    تصحيحُ خطأٍ في قراءتي أنا عند الترحيل، والسندُ نفسُه لم يتغيّر: المبلغُ
--    والتاريخُ والوجهُ والبيانُ كما هي، والاسمُ وحدَه يُصحَّح.
--
--  ⚠ ولا يتحرّك دينارٌ واحد. المبلغُ يخرج من الصندوق كما خرج، ورصيدُ الجمعية
--    يبقى 4,230.00، ولا يمسّ هذا استحقاقًا ولا إيصالًا ولا اشتراكًا: صرفُ
--    الجمعية لا يُخصم من دَين أحد. الذي يتغيّر شاشتان: «أسلافي» عند هيثم
--    تنقص 2,020، وعند محمد تزيد 2,020.
--
--  للتشغيل: SQL Editor ← New query ← الصق ← Run. معاملةٌ واحدة، وتكرارُها آمن
--  (يرفض بوضوحٍ إن كان السندُ قد نُقل بالفعل).
-- ============================================================================

BEGIN;

DO $fix$
DECLARE
  v_id      bigint;
  v_no      text;
  v_from    text;
  v_to_id   bigint;
  v_to_name text;
  v_n       int;
BEGIN
  -- ⚠ لا يُبحث عنه برقم السند وحدَه. رقمُ السند مُولَّدٌ بترتيب الإدخال، فلو
  --   أُعيد الترحيلُ بترتيبٍ مختلفٍ لأشار EXP-60 إلى سندٍ آخر — ونقلُ مالٍ
  --   إلى الرجل الخطأ بناءً على رقمٍ متحرّك هو أسوأ ما يمكن أن يفعله ملفٌّ
  --   كهذا. الهُويّةُ هي المبلغُ والتاريخُ والبيان.
  SELECT count(*) INTO v_n
    FROM public.disbursements
   WHERE amount = 2020.00
     AND (spent_at AT TIME ZONE 'Africa/Tripoli')::date = DATE '2026-03-30'
     AND note LIKE '%دريبي%';

  IF v_n = 0 THEN
    RAISE EXCEPTION 'لم أجد سندَ «تعزية للدريبي» بمبلغ 2020.00 في 30/03/2026 — أوقفتُ التصحيح.';
  ELSIF v_n > 1 THEN
    RAISE EXCEPTION 'وجدتُ % سندًا يطابق الوصف لا سندًا واحدًا — أوقفتُ التصحيح.', v_n;
  END IF;

  SELECT d.id, d.voucher_no, a.adeel_code
    INTO v_id, v_no, v_from
    FROM public.disbursements d
    LEFT JOIN public.adeels a ON a.id = d.payee_adeel_id
   WHERE d.amount = 2020.00
     AND (d.spent_at AT TIME ZONE 'Africa/Tripoli')::date = DATE '2026-03-30'
     AND d.note LIKE '%دريبي%';

  IF v_from = 'A-01' THEN
    RAISE EXCEPTION 'السند % محسوبٌ على A-01 أصلاً — لا شيء لأفعله.', v_no;
  ELSIF v_from IS DISTINCT FROM 'A-03' THEN
    RAISE EXCEPTION 'السند % محسوبٌ على % لا على A-03 — أوقفتُ التصحيح.',
      v_no, coalesce(v_from, '(جماعي)');
  END IF;

  SELECT id, full_name INTO v_to_id, v_to_name
    FROM public.adeels WHERE adeel_code = 'A-01';
  IF v_to_id IS NULL THEN
    RAISE EXCEPTION 'لا يوجد عديلٌ بالكود A-01 — أوقفتُ التصحيح.';
  END IF;

  -- ⚠ الاسمُ يُنسخ مع المُعرّف. `payee_name` لقطةٌ على الصفّ لا ارتباطٌ حيّ،
  --   فترْكُه على «هيثم» مع مُعرّفٍ يشير إلى محمد يصنع سندًا يقول اسمًا
  --   ويعني آخر — وهو أسوأ من الخطأ الذي نصلحه، لأنّه يبدو صحيحًا لمن يقرأ
  --   الاسمَ ولمن يقرأ المُعرّف كليهما.
  UPDATE public.disbursements
     SET payee_adeel_id = v_to_id,
         payee_name     = v_to_name
   WHERE id = v_id;

  -- القاعدة 12: فعلٌ غيّر نسبةَ مالٍ إلى رجل يُسجَّل. الأدمن ليس هو مَن نفّذ
  -- هذا — المحرّرُ يعمل باسم postgres و auth.uid() فيه NULL — فيُسمّى الفاعلُ
  -- بما هو، لا بحسابٍ لم يضغط شيئًا.
  INSERT INTO public.audit_log (event_type, detail, ref, actor_user_id, actor_name)
  VALUES ('disbursement.repoint',
          format('نقل سند %s (%s د.ل، %s) من %s إلى A-01 %s — تصحيح خطأ ترحيل',
                 v_no, '2020.00', 'تعزية للدريبي - وفاة مفتاح', v_from, v_to_name),
          v_no, NULL, 'تصحيح يدوي من محرّر SQL');

  RAISE NOTICE 'نُقل السند % من % إلى A-01 (%)', v_no, v_from, v_to_name;
END $fix$;

-- ولا رقمَ ماليًّا تحرّك: المصروفاتُ والرصيدُ كما كانا.
DO $v$
DECLARE vd numeric; vp numeric;
BEGIN
  SELECT coalesce(sum(amount),0) INTO vd FROM public.disbursements WHERE status <> 'ملغي';
  SELECT coalesce(sum(amount),0) INTO vp FROM public.payments      WHERE status <> 'ملغي';
  IF vd <> 53650.00 THEN RAISE EXCEPTION 'المصروفات % لا 53650.00', vd; END IF;
  IF (vp - vd) <> 4230.00 THEN RAISE EXCEPTION 'رصيد الخزينة % لا 4230.00', (vp - vd); END IF;
  RAISE NOTICE 'لم يتغيّر رقمٌ ماليّ: مصروفات % · رصيد %', vd, (vp - vd);
END $v$;

SELECT public.assert_signin_intact();
SELECT public.assert_two_doors_only();

COMMIT;

-- للقراءة: السندُ بعد التصحيح، وجملةُ أسلاف الرجلين.
SELECT d.voucher_no AS "السند", a.adeel_code AS "الكود", d.payee_name AS "المستفيد",
       to_char(d.amount, 'FM99999990.00') AS "المبلغ",
       (d.spent_at AT TIME ZONE 'Africa/Tripoli')::date AS "التاريخ"
  FROM public.disbursements d JOIN public.adeels a ON a.id = d.payee_adeel_id
 WHERE d.note LIKE '%دريبي%';

SELECT a.adeel_code AS "الكود", a.full_name AS "الاسم",
       count(d.id) AS "عدد أسلافه",
       to_char(coalesce(sum(d.amount), 0), 'FM99999990.00') AS "جملتها"
  FROM public.adeels a
  LEFT JOIN public.disbursements d
         ON d.payee_adeel_id = a.id AND d.status <> 'ملغي'
 WHERE a.adeel_code IN ('A-01', 'A-03')
 GROUP BY a.adeel_code, a.full_name ORDER BY a.adeel_code;
