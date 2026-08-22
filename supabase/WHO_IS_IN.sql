-- ============================================================================
--  WHO_IS_IN.sql — من يستطيع أن يفتح ماذا، الآن.  READ-ONLY.
--
--  ⚠ THIS ANSWERS THE QUESTION NO OTHER FILE IN THIS FOLDER ASKS.
--    VERIFY_INSTALL asks «did the bundle land». WHICH_STATE asks «which patch
--    is next». FINAL_CHECK asks «does the schema WORK». All three are about
--    the schema — and on 2026-08-22 every one of them would have passed while
--    a member sat inside the association app under his own name.
--
--    Six accounts were at role=viewer, status=approved, adeel_id=NULL, and
--    that is DATA. No schema check can see it, because nothing about the
--    schema was wrong.
--
--  ⚠ AND ROW 1 READS THE FUNCTION BODY, NOT ITS NAME. «my_role exists» is true
--    on every project ever built and answers nothing. What matters is whether
--    the admin clause is inside it.
--
--  ⚠ ROW 7 READS auth.users, NOT profiles. An account with no profile row still
--    SIGNS IN SUCCESSFULLY — GoTrue knows nothing about public.profiles — and
--    it appears in no listing built from profiles alone. That is exactly how
--    the exposed admin account stayed invisible while it was the association's
--    only administrator. assert_signin_intact() only RAISE WARNINGs on this,
--    and a warning in a dashboard is read by nobody.
--
--  Paste into the SQL Editor and read. It writes nothing.
-- ============================================================================

SELECT 1 AS n, 'هل my_role مقفلة على الأدمن؟' AS "الفحص",
  CASE WHEN (SELECT pg_get_functiondef(p.oid) FROM pg_proc p
               JOIN pg_namespace nn ON nn.oid = p.pronamespace
              WHERE nn.nspname = 'public' AND p.proname = 'my_role')
            LIKE '%role = ''admin''%'
       THEN 'نعم — مقفلة' ELSE 'لا ⚠ ما زالت مفتوحة' END AS "النتيجة"

UNION ALL SELECT 2, 'من يفتح تطبيق الجمعية؟',
  coalesce((SELECT string_agg(email, ' + ') FROM public.profiles
             WHERE role = 'admin' AND status = 'approved'), 'لا أحد ⚠')

UNION ALL SELECT 3, 'من يفتح بوّابة العديل؟',
  coalesce((SELECT string_agg(coalesce(email, '?'), ' + ') FROM public.profiles
             WHERE adeel_id IS NOT NULL AND device_id IS NOT NULL
               AND status = 'approved'), 'لا أحد')

-- ⚠ THIS IS THE ROW THE INCIDENT WOULD HAVE SHOWN ON. It must read «لا أحد».
UNION ALL SELECT 4, 'حسابات معتمدة ليست أدمن ولا عديل',
  coalesce((SELECT string_agg(email, ' + ') FROM public.profiles
             WHERE status = 'approved' AND adeel_id IS NULL
               AND role <> 'admin'), 'لا أحد')

UNION ALL SELECT 5, 'مفاتيح دخول قائمة',
  (SELECT count(*)::text FROM public.adeel_access_codes)

-- ⚠ IT ASKS auth.users, NOT profiles, AND THAT IS THE CORRECTION THAT
--   MATTERS. The first version read profiles.status and called anything not
--   'suspended' «يعمل» — so it raised an alarm over an account that had been
--   password-scrambled and banned in GoTrue and could not sign in at all,
--   while it would have stayed SILENT about a live account whose profile
--   merely happened to say 'pending'. The profile was never the lock.
--
--   The three locks are independent and any one suffices, so all three are
--   reported: a password that matches nothing, a GoTrue ban, and a profile
--   that reaches nothing.
UNION ALL SELECT 6, 'الحساب المكشوف admin@adayl.test',
  coalesce((SELECT
      CASE WHEN u.banned_until > now()
                 AND u.encrypted_password NOT LIKE '$2%'
             THEN 'مقفول ✔ (محظور + كلمة سرّ لا تطابق)'
           WHEN u.banned_until > now()
             THEN 'محظور ✔ (لكن كلمة السرّ ما زالت صالحة)'
           WHEN u.encrypted_password NOT LIKE '$2%'
             THEN 'كلمة السرّ لا تطابق ✔ (لكنه غير محظور)'
           ELSE 'يفتح ⚠ يسجّل الدخول بكلمة السرّ المنشورة'
      END || ' — الصفحة: ' ||
      coalesce(p.role::text || '/' || p.status::text, 'لا صفحة')
    FROM auth.users u
    LEFT JOIN public.profiles p ON p.id = u.id
   WHERE lower(u.email) = 'admin@adayl.test'), 'غير موجود ✔')

UNION ALL SELECT 7, 'حسابات تسجّل الدخول ولا صفحة لها',
  (SELECT count(*)::text FROM auth.users u
    WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id))

ORDER BY n;
