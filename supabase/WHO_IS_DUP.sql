-- ============================================================================
--  WHO_IS_DUP.sql — أيّ حسابَي بوّابةٍ يخصّان عديلاً واحداً، وأيّهما الصحيح؟
--
--  READ-ONLY. لا يعدّل شيئاً. الإصلاح نفسه من داخل التطبيق، لا من هنا.
--
--  WHY IT MATTERS, and why it is invisible from the app
--    `profiles.adeel_id` is the whole عديل/staff discriminator, and nothing
--    stops two profile rows carrying the same one — two Google accounts each
--    redeeming a code for the same man. There is no unique index on it and
--    there deliberately never was: a man whose phone is replaced needs a second
--    row for a while, and a constraint would refuse the replacement instead of
--    the duplicate.
--
--  ⚠ AND THE FAILURE IS SILENT. my_adeel_id() answers for whichever row the
--    SESSION belongs to and additionally requires device_id to match the
--    x-device-id header. So one account is bound and works; the other signs in
--    successfully, matches no policy, and shows an EMPTY portal with nothing on
--    screen saying why. The man reports «التطبيق فاضي» and every schema check
--    ever written says the database is correct — because it is.
--
--  HOW TO READ IT
--    «مربوط بجهاز» = نعم  →  هذا هو الحساب العامل. اتركه.
--    «مربوط بجهاز» = لا   →  هذا هو الزائد.
--
--    If BOTH say نعم, two handsets are genuinely bound and you must choose:
--    the older row is almost always the one to retire.
--    If BOTH say لا, neither has claimed a device; keep the one whose email the
--    man actually uses and retire the other.
--
--  ⚠ HOW TO FIX — من التطبيق، ولا تلمس القاعدة
--    الإدارة → المستخدمون → الحساب الزائد → اجعله «موقوف».
--
--    و«موقوف» لا «حذف الارتباط»، وهذا ليس تفضيلاً. my_role() تعود NULL ما دام
--    adeel_id مضبوطاً — فمسحُ adeel_id وحده يهبط بالرجل إلى viewer معتمد،
--    وهذا يقرأ الجمعية كلها. أمّا «موقوف» فتُبطل my_adeel_id() و my_role()
--    معاً، لأنّ كلتيهما تشترط status = 'approved'.
-- ============================================================================

SELECT
  p.adeel_id                                   AS "رقم العديل",
  a.full_name                                  AS "الاسم",
  p.email                                      AS "البريد",
  p.status::text                               AS "الحالة",
  p.role::text                                 AS "الدور",
  CASE WHEN p.device_id IS NULL THEN 'لا' ELSE 'نعم' END
                                               AS "مربوط بجهاز",
  to_char(p.created_at AT TIME ZONE 'Africa/Tripoli', 'YYYY-MM-DD HH24:MI')
                                               AS "أُنشئ",
  -- ⚠ THE MOST USEFUL COLUMN HERE, and the one that settles a tie the device
  --   binding cannot: an account nobody has ever opened is the duplicate,
  --   whatever its dates say. api_touch_login() writes this on every launch.
  coalesce(to_char(p.last_login_at AT TIME ZONE 'Africa/Tripoli',
                   'YYYY-MM-DD HH24:MI'), 'لم يدخل قط')
                                               AS "آخر دخول",
  CASE WHEN p.device_id IS NOT NULL
         THEN 'اتركه — هذا هو العامل'
       ELSE 'هذا هو الزائد — اجعله موقوفاً من الإدارة → المستخدمون'
  END                                          AS "ماذا تفعل"
FROM public.profiles p
LEFT JOIN public.adeels a ON a.id = p.adeel_id
WHERE p.adeel_id IN (
  SELECT adeel_id FROM public.profiles
   WHERE adeel_id IS NOT NULL
   GROUP BY adeel_id HAVING count(*) > 1
)
-- Device-bound first, then oldest: the row to keep sits at the top.
ORDER BY p.adeel_id, (p.device_id IS NOT NULL) DESC, p.created_at;
