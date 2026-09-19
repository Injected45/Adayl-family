-- ============================================================================
--  جمعية العدايل — نسخةٌ احتياطية من الدفتر كلِّه (للقراءة فقط).
--
--  ما هذا
--    استعلامٌ واحد يُخرج خانةً واحدة فيها الدفترُ كلُّه بصيغة JSON: المشتركون،
--    والاشتراكات، والإيصالات، وتوزيعُها، وحركةُ الصندوق، وسندات الصرف،
--    والأشهرُ المُقفلة، والإعدادات، وسجلُّ العمليات، والحسابات وارتباطُها
--    بالمشتركين، والمقترحات.
--
--  كيف يُحفظ — بزرٍّ واحد، لا بالنسخ باليد
--    SQL Editor ← New query ← الصق هذا ← Run ← فوق جدول النتيجة زرُّ التنزيل
--    (Download CSV / Export) ← يُنزَّل ملفٌّ فيه النسخةُ كلُّها. أعِد تسميته
--    adayl-backup-YYYY-MM-DD.csv واحفظه خارج الحاسوب (بريدك يكفي). مرّةً في
--    الأسبوع تكفي، ومرّةً قبل أيِّ عملٍ كبير واجبة.
--
--    ⚠ لا تنسخ الخانةَ بالماوس: النسخةُ مئتا كيلوبايت تقريبًا، والنسخُ اليدويّ
--      يقطعها من حيث لا تشعر فتصير نسخةً مبتورة تظنُّها سليمة. زرُّ التنزيل
--      يأخذها كاملةً دائمًا.
--
--    ⚠ الملفُّ النازل CSV، والنسخةُ داخله بين علامتَي اقتباس وكلُّ " فيها
--      مضاعفة — هكذا يكتب CSV دائمًا، ولا يضيع منها حرف. لا تُصلحها بيدك.
--
--  ⚠ لماذا يلزم أصلًا: سوبابيز في الخطّة المجانية لا يحفظ نسخًا يوميّة يمكن
--    الرجوع إليها. لو أخطأ أحدٌ في محرّر SQL بأمرٍ واحد، فهذه النسخةُ هي كلُّ
--    ما يبقى. وحجمُ دفتر الجمعية صغيرٌ (مئاتُ الصفوف) فالخانةُ الواحدة تكفيه.
--
--  ⚠ ما لا يحمله هذا الملفّ، عن قصد:
--      • صورُ قانون الجمعية (bylaw_pages) — ثقيلةٌ جدًّا على خانةٍ واحدة،
--        واحتفظ بأصولها في هاتفك.
--      • الرسائلُ والمقاطعُ الصوتية والإشعارات — تمضي بطبيعتها.
--      • الحساباتُ في auth (Google) — تملكها سوبابيز، ولا تُفقد بخطأٍ في SQL.
--
--  ⚠ لا يكتب شيئًا ولا يغيّر شيئًا.
-- ============================================================================

-- ⚠ json_build_object لا jsonb: jsonb يُعيد ترتيب المفاتيح بالطول ثمّ أبجديًّا،
--   فتغرق «الخلاصة» وسطَ آلاف السطور. json يحفظ الترتيبَ كما كُتب، فتقرأ
--   الأرقامَ في أوّل الخانة قبل أن تحفظها.
SELECT json_build_object(
  'نسخة',            'adayl-backup-1',
  'المشروع',         current_database(),
  'لحظة_النسخ',      to_char(now() AT TIME ZONE 'Africa/Tripoli', 'YYYY-MM-DD HH24:MI'),

  -- ── ما يجب أن تُطابقه النسخةُ عند الرجوع إليها ─────────────────────────
  -- ⚠ أرقامٌ تُقرأ بالعين قبل الحفظ: نسخةٌ يقول رأسُها «٨ مشتركين ورصيد
  --   4,230» ويقول جسمُها غير ذلك، نسخةٌ مبتورة.
  'الخلاصة', json_build_object(
    'المشتركون',        (SELECT count(*) FROM public.adeels),
    'الاستحقاقات',      (SELECT count(*) FROM public.receivables),
    'الإيصالات',        (SELECT count(*) FROM public.payments),
    'سندات_الصرف',      (SELECT count(*) FROM public.disbursements),
    'الأشهر_المقفلة',   (SELECT count(*) FROM public.closed_periods),
    'سجل_العمليات',     (SELECT count(*) FROM public.audit_log),
    'رصيد_الجمعية',     (SELECT balance FROM public.v_cash_summary)
  ),

  'adeels',              (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.adeels t),
  'association_settings',(SELECT coalesce(json_agg(to_json(t)), '[]'::json)
                            FROM public.association_settings t),
  'closed_periods',      (SELECT coalesce(json_agg(to_json(t) ORDER BY t.period), '[]'::json)
                            FROM public.closed_periods t),
  'receivables',         (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.receivables t),
  'payments',            (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.payments t),
  'payment_allocations', (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.payment_allocations t),
  'cash_movements',      (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.cash_movements t),
  'disbursements',       (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.disbursements t),
  'audit_log',           (SELECT coalesce(json_agg(to_json(t) ORDER BY t.id), '[]'::json)
                            FROM public.audit_log t),
  -- ⚠ الحسابات: الأدوارُ وارتباطُ كلّ حسابٍ بمشتركه. هذه هي «مَن يدخل وبماذا»،
  --   وإعادةُ بنائها بالتخمين بعد ضياعها تعني إغلاقَ التطبيق في وجه الجميع.
  'profiles',            (SELECT coalesce(json_agg(to_json(t) ORDER BY t.created_at), '[]'::json)
                            FROM public.profiles t),
  'proposals',           CASE WHEN to_regclass('public.proposals') IS NULL THEN '[]'::json
                              ELSE (xpath('/row/c/text()', query_to_xml(
                                     $q$SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY t.id), '[]')::text AS c
                                          FROM public.proposals t$q$,
                                     false, true, '')))[1]::text::json END
)::text AS "النسخة الاحتياطية";
