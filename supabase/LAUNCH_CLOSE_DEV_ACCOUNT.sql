-- ============================================================================
--  جمعية العدايل — إغلاقُ حساب التطوير قبل الإطلاق.
--
--  ⚠ لا تُشغّله إلا إذا قال فحصُ CHECK_PATCHES.sql في صفِّ «ولا حسابَ تطويرٍ
--    معتمَدًا بصلاحية أدمن» ❌ وسمّى بريدًا. إن قال ✅ فلا حاجة له.
--
--  لماذا
--    مفتاحُ القراءة (anon) علنيٌّ بالتصميم ويُشحن داخل التطبيق، وكلمةُ حساب
--    التطوير كانت في ملفٍّ داخل مستودعٍ علنيّ. حُذفت من الملفّ، ولا تُحذف من
--    تاريخ المستودع — فمن قرأها استطاع الدخولَ بحسابِ أدمن إلى المشروع الحيّ
--    بلا تطبيقٍ ولا هاتف. حذفُ السطر لا يغلق شيئًا؛ الذي يغلقه هو تعطيلُ
--    الحساب نفسِه، وهذا ما يفعله هذا الملف.
--
--  ما الذي يفعله
--    يجعل كلَّ حسابٍ معتمَدٍ بصلاحية أدمن بريدُه على نطاق .test «موقوفًا».
--    my_role() تشترط approved، فالموقوفُ لا يملك دورًا: تُغلق في وجهه كلُّ
--    سياسةٍ في القاعدة دفعةً واحدة، ولا يحتاج الأمرُ تعديلَ سياسةٍ واحدة.
--
--  ⚠ ويرفض أن يتركك بلا أدمن. إن لم يبقَ بعده حسابُ أدمنٍ معتمَدٍ واحدٌ على
--    الأقلّ بريدُه حقيقيّ، لا يغيّر شيئًا ويقول لك ذلك. لا يمكن أن تُغلق على
--    نفسك البابَ بهذا الملف.
--
--  للتشغيل: SQL Editor ← New query ← الصق هذا كلَّه ← Run. معاملةٌ واحدة، وتكرارُه آمن.
-- ============================================================================

BEGIN;

DO $close$
DECLARE
  v_dev   int;
  v_real  int;
  v_list  text;
BEGIN
  SELECT count(*), string_agg(email, '، ')
    INTO v_dev, v_list
    FROM public.profiles
   WHERE role = 'admin' AND status = 'approved' AND email LIKE '%.test';

  SELECT count(*) INTO v_real
    FROM public.profiles
   WHERE role = 'admin' AND status = 'approved' AND email NOT LIKE '%.test';

  IF v_dev = 0 THEN
    PERFORM set_config('adayl.closed', 'لا حسابَ تطويرٍ مفتوحًا — لم يتغيّر شيء', false);
    RETURN;
  END IF;

  -- ⚠ الحارس: أدمنٌ حقيقيٌّ واحدٌ على الأقلّ يبقى بعد هذا.
  IF v_real = 0 THEN
    RAISE EXCEPTION
      'لن أُعطّل % لأنّه الأدمنُ الوحيد — ادخل بحسابك الحقيقي أوّلًا ثم أعد التشغيل. لم يتغيّر شيء.',
      v_list;
  END IF;

  UPDATE public.profiles
     SET status = 'suspended'
   WHERE role = 'admin' AND status = 'approved' AND email LIKE '%.test';

  PERFORM public.write_audit('user.access',
    format('إغلاق حساب تطوير قبل الإطلاق: %s', v_list), 'launch');

  PERFORM set_config('adayl.closed', 'عُطّل: ' || v_list, false);
END $close$;

-- == الحرّاس ================================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == النتيجة ===============================================================
SELECT 'ما جرى' AS "الفحص",
       coalesce(current_setting('adayl.closed', true), 'لم يُفحص') AS "النتيجة"
UNION ALL SELECT 'ولم يبقَ حسابُ تطويرٍ بصلاحية أدمن',
       (NOT EXISTS (SELECT 1 FROM public.profiles
                     WHERE role = 'admin' AND status = 'approved'
                       AND email LIKE '%.test'))::text
UNION ALL SELECT 'وما زال للجمعية أدمنٌ يدخل',
       (SELECT count(*)::text || ' حساب'
          FROM public.profiles
         WHERE role = 'admin' AND status = 'approved')
UNION ALL SELECT 'ولم يتغيّر أيُّ رقمٍ ماليّ',
       (SELECT balance FROM public.v_cash_summary);

COMMIT;
