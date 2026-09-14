-- ============================================================================
--  جمعية العدايل — PATCH 2026-09-14.  «الجدوى»: الحركة سنةً بسنة.
--
--  ما الذي يفعله هذا الملف
--    يضيف إلى api_member_value مفتاحًا واحدًا جديدًا اسمه 'years': ما دفعه
--    المشترك وما استلمه في كل سنة، وتحت كل سنة شهورُها التي فيها حركة.
--    عليه يُرسم الرسم البيانيّ الجديد في شاشة «الجدوى».
--
--  ⚠ للقراءة فقط. لا يُكتب صفّ، ولا يتغيّر رقم، ولا تتغيّر صلاحيّة: الدالّةُ
--    نفسُها بالتوقيع نفسِه (CREATE OR REPLACE يُبقي صلاحيّاتها كما هي)، وكلُّ
--    مفتاحٍ كانت ترجعه يبقى حرفًا بحرف — الجسدُ منقولٌ من القاعدة لا مكتوبٌ
--    من الذاكرة، والجديدُ مُلحقٌ في آخره. التطبيقُ القديم على الهواتف لا يقرأ
--    المفتاح الجديد ولا يتأثّر.
--
--  ⚠ كلُّ ما قبل سنة بداية النظام يُجمع في صفٍّ واحد «حتى 2024»، لأنّ
--    اشتراكاتِ ما قبل 2025 إيصالٌ افتتاحيٌّ واحد بينما الصرفُ موزّعٌ على
--    2015→2024؛ تفريقُها بالسنة كان سيُظهر عضوًا «استلم ولم يدفع» في 2018.
--
--  للتشغيل: SQL Editor ← New query ← الصق ← Run. معاملةٌ واحدة، وتكرارُها آمن.
-- ============================================================================

BEGIN;

DO $prereq$
BEGIN
  IF to_regprocedure('public.api_member_value(bigint)') IS NULL THEN
    RAISE EXCEPTION 'api_member_value غير موجودة — طبّق ترقيعات «الجدوى» أولًا.';
  END IF;
END $prereq$;

CREATE OR REPLACE FUNCTION public.api_member_value(p_adeel_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_me   bigint := public.my_adeel_id();
  v_role app_role := public.my_role();
  v_out  jsonb;
BEGIN
  IF v_role IS NULL AND v_me IS DISTINCT FROM p_adeel_id THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;
  IF v_role IS NULL AND v_me IS NULL THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = 'RUL00';
  END IF;

  SELECT jsonb_build_object(
    -- ── HIS SIDE ────────────────────────────────────────────────────────
    -- What he has actually PAID, not what he was billed: the question is
    -- what left his hand.
    'paid', (SELECT coalesce(sum(p.amount), 0)::numeric(12,2)::text
               FROM public.payments p
              WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'),
    'received', (SELECT coalesce(sum(d.amount), 0)::numeric(12,2)::text
                   FROM public.disbursements d
                  WHERE d.payee_adeel_id = p_adeel_id
                    AND d.status <> 'ملغي'),

    -- ── THE FUND ────────────────────────────────────────────────────────
    'collected', (SELECT coalesce(sum(c.amount), 0)::numeric(12,2)::text
                    FROM public.cash_movements c WHERE c.status <> 'ملغي'),
    -- Everything given to NAMED members. Collective spending (فطور رمضان) is
    -- excluded on purpose: this figure answers «how much of the fund comes
    -- back to a man», and a shared meal comes back to everyone at once.
    'toMembers', (SELECT coalesce(sum(d.amount), 0)::numeric(12,2)::text
                    FROM public.disbursements d
                   WHERE d.payee_adeel_id IS NOT NULL
                     AND d.status <> 'ملغي'),

    -- ── THE STATISTICS THAT ANSWER «ما الجدوى» ──────────────────────────
    -- How many men the fund has actually stood behind, out of how many pay
    -- into it. One ratio, no prose.
    'helped', (SELECT count(DISTINCT d.payee_adeel_id)
                 FROM public.disbursements d
                WHERE d.payee_adeel_id IS NOT NULL AND d.status <> 'ملغي'),
    'members', (SELECT count(*) FROM public.adeels),
    -- ⚠ THE INSURANCE FIGURE, and the most useful number on the screen: the
    --   largest single voucher the association has ever written to one man.
    --   «هذا ما تقف خلفه الجمعية إن نزلت بك نازلة» is what a member is
    --   actually buying, and no average says it.
    'largest', (SELECT coalesce(max(d.amount), 0)::numeric(12,2)::text
                  FROM public.disbursements d
                 WHERE d.payee_adeel_id IS NOT NULL AND d.status <> 'ملغي'),

    -- ── حركته على اثني عشر شهراً ─────────────────────────────────────
    -- What he paid and what he was given, month by month, for the chart at
    -- the foot of «الجدوى».
    --
    -- ⚠ THE SPINE IS GENERATED, NOT DERIVED FROM THE ROWS. Grouping the
    --   payments alone would return only the months he happened to pay in,
    --   and a chart drawn from that has no time axis — it has a list of
    --   events evenly spaced, so three months of silence look identical to
    --   three consecutive payments. generate_series gives every month a
    --   column, and an empty one is the fact worth seeing.
    --
    -- ⚠ AND EVERY FIGURE IS SUMMED HERE, IN TEXT. The client draws bars from
    --   these and never adds them: money is text end to end in this app, and
    --   a Dart loop totalling a year of receipts would put the association’s
    --   figures on binary floating point.
    'months', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'period',        to_char(t.month, 'YYYY-MM'),
               'paid',          t.paid::numeric(12,2)::text,
               'received',      t.received::numeric(12,2)::text,
               'paidTotal',     t.paid_total::numeric(12,2)::text,
               'receivedTotal', t.received_total::numeric(12,2)::text)
             ORDER BY t.month)
        FROM (
          SELECT m.month, m.paid, m.received,
                 sum(m.paid)     OVER (ORDER BY m.month) AS paid_total,
                 sum(m.received) OVER (ORDER BY m.month) AS received_total
            FROM (
              SELECT s.month,
                     coalesce((SELECT sum(p.amount) FROM public.payments p
                                WHERE p.adeel_id = p_adeel_id
                                  AND p.status <> 'ملغي'
                                  AND date_trunc('month',
                                        p.paid_at AT TIME ZONE 'Africa/Tripoli')
                                      = s.month), 0) AS paid,
                     coalesce((SELECT sum(d.amount) FROM public.disbursements d
                                WHERE d.payee_adeel_id = p_adeel_id
                                  AND d.status <> 'ملغي'
                                  AND date_trunc('month',
                                        d.spent_at AT TIME ZONE 'Africa/Tripoli')
                                      = s.month), 0) AS received
                -- ── يناير إلى ديسمبر، لا آخر اثني عشر شهراً ──────────
                -- ⚠ A CALENDAR YEAR, at the association's request. The
                --   rolling window ran سبتمبر→أغسطس, and the two ends of
                --   it read as adjacent months in the wrong order under a
                --   heading that said twelve — «التناقض» was his word.
                --
                --   A calendar year needs no explaining: everybody
                --   already knows where January is and where December is,
                --   and the axis stops being something to decode.
                --
                -- ⚠ AND IT IS TRIPOLI'S YEAR. The whole app renders in
                --   Africa/Tripoli; a series bucketed in UTC would put a
                --   receipt taken at 23:30 on 31 December into the wrong
                --   year, on the one screen built to compare years.
                FROM generate_series(
                       date_trunc('year', now() AT TIME ZONE 'Africa/Tripoli'),
                       date_trunc('year', now() AT TIME ZONE 'Africa/Tripoli')
                         + interval '11 months',
                       interval '1 month') AS s(month)
            ) m
        ) t), '[]'::jsonb),

    -- ── سنةً بسنة (PATCH_20260914) ──────────────────────────────────────
    -- What he paid and what he was given, per YEAR, newest first — the
    -- chart at the foot of «الجدوى» — and inside each year the months (or,
    -- for the opening block, the years) that actually held something.
    --
    -- ⚠ EVERYTHING UP TO THE YEAR OF system_start IS ONE BLOCK, «حتى 2024».
    --   His subscriptions before the app are ONE receipt — the «رصيد
    --   افتتاحي» dated 2024-12-31 — while his aid before it is spread over
    --   2015→2024. Bucketed by calendar year, 2018 would show «استلمتَ 250،
    --   دفعتَ 0», which says he took before he gave — a lie the migration
    --   created, not the ledger. So those years fold into one row, and the
    --   row opens onto the YEARS inside it. `opening` is true only when there
    --   is anything dated before that year, so an association starting fresh
    --   keeps its months.
    --
    -- ⚠ SUMMED HERE, AS TEXT, like every other figure in this function.
    'years', coalesce((
      WITH mv AS (
        SELECT (p.paid_at AT TIME ZONE 'Africa/Tripoli') AS at,
               p.amount AS paid, 0::numeric AS received
          FROM public.payments p
         WHERE p.adeel_id = p_adeel_id AND p.status <> 'ملغي'
        UNION ALL
        SELECT (d.spent_at AT TIME ZONE 'Africa/Tripoli'),
               0::numeric, d.amount
          FROM public.disbursements d
         WHERE d.payee_adeel_id = p_adeel_id AND d.status <> 'ملغي'
      ),
      base AS (
        SELECT coalesce((SELECT extract(year FROM s.system_start)::int
                           FROM public.association_settings s LIMIT 1), 0) AS y0
      ),
      tagged AS (
        SELECT mv.at, mv.paid, mv.received,
               extract(year FROM mv.at)::int AS y,
               greatest(extract(year FROM mv.at)::int, (SELECT y0 FROM base)) AS bucket
          FROM mv
      ),
      early AS (
        SELECT EXISTS (SELECT 1 FROM tagged WHERE y < bucket) AS has_early
      ),
      parts AS (
        SELECT t.bucket,
               CASE WHEN t.bucket = (SELECT y0 FROM base) AND (SELECT has_early FROM early)
                    THEN t.y::text
                    ELSE to_char(t.at, 'YYYY-MM') END AS key,
               sum(t.paid) AS paid,
               sum(t.received) AS received
          FROM tagged t
         GROUP BY 1, 2
      )
      SELECT jsonb_agg(jsonb_build_object(
               'year',     b.bucket::text,
               'opening',  (b.bucket = (SELECT y0 FROM base) AND (SELECT has_early FROM early)),
               'paid',     b.paid::numeric(12,2)::text,
               'received', b.received::numeric(12,2)::text,
               'parts',    b.parts)
             ORDER BY b.bucket DESC)
        FROM (
          SELECT p.bucket,
                 sum(p.paid) AS paid,
                 sum(p.received) AS received,
                 jsonb_agg(jsonb_build_object(
                   'key',      p.key,
                   'paid',     p.paid::numeric(12,2)::text,
                   'received', p.received::numeric(12,2)::text)
                   ORDER BY p.key) AS parts
            FROM parts p
           GROUP BY p.bucket
        ) b
    ), '[]'::jsonb)
  ) INTO v_out;

  RETURN v_out;
END $function$;

-- == الفحص الحقيقيّ: الدالّةُ نفسُها، لكلّ مشترك ================================
-- ⚠ محرّرُ SQL يعمل بلا حساب، والدالّةُ ترفض من لا حساب له. فيُستعار حسابُ
--   الأدمن داخل هذا الفحص وحده ثمّ يُرفع فورًا، ويُستدعى api_member_value
--   لكلّ مشترك: مجموعُ سنواته = ما دفع وما استلم، ومجموعُ شهور كلّ سنة =
--   تلك السنة. إن اختلف قرشٌ واحد تُلغى المعاملة كلُّها ولا يتغيّر شيء.
DO $check$
DECLARE
  v_admin uuid;
  v_bad   text;
BEGIN
  SELECT p.id INTO v_admin FROM public.profiles p
   WHERE p.role = 'admin' AND p.status = 'approved' AND p.adeel_id IS NULL
   LIMIT 1;

  IF v_admin IS NULL THEN
    PERFORM set_config('adayl.years_check', 'لا أدمن — تُخطّي', true);
    RETURN;
  END IF;

  PERFORM set_config('request.jwt.claims',
                     json_build_object('sub', v_admin)::text, true);

  SELECT string_agg(a.adeel_code, '، ') INTO v_bad
    FROM public.adeels a
    CROSS JOIN LATERAL (SELECT public.api_member_value(a.id) AS v) x
   WHERE (x.v ->> 'paid')::numeric
           <> (SELECT coalesce(sum((y ->> 'paid')::numeric), 0)
                 FROM jsonb_array_elements(x.v -> 'years') y)
      OR (x.v ->> 'received')::numeric
           <> (SELECT coalesce(sum((y ->> 'received')::numeric), 0)
                 FROM jsonb_array_elements(x.v -> 'years') y)
      OR EXISTS (
           SELECT 1 FROM jsonb_array_elements(x.v -> 'years') y
            WHERE (y ->> 'paid')::numeric
                    <> (SELECT coalesce(sum((q ->> 'paid')::numeric), 0)
                          FROM jsonb_array_elements(y -> 'parts') q)
               OR (y ->> 'received')::numeric
                    <> (SELECT coalesce(sum((q ->> 'received')::numeric), 0)
                          FROM jsonb_array_elements(y -> 'parts') q));

  PERFORM set_config('request.jwt.claims', '', true);

  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION 'مجموع السنوات لا يطابق الحساب عند: %', v_bad;
  END IF;
  PERFORM set_config('adayl.years_check', 'true', true);
END $check$;

-- == الحرّاس ================================================================
SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();
SELECT public.assert_two_doors_only();

-- == النتيجة: آخرُ جدولٍ يظهر في المحرّر، وكلُّ صفٍّ يجب أن يقول true ==========
SELECT 'الدالّةُ تُرجع المفتاح الجديد وكلَّ القديم' AS "الفحص",
       (SELECT prosrc LIKE '%''years''%' AND prosrc LIKE '%''months''%'
               AND prosrc LIKE '%''largest''%' AND prosrc LIKE '%''toMembers''%'
          FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
         WHERE n.nspname = 'public' AND p.proname = 'api_member_value')::text AS "النتيجة"
UNION ALL SELECT 'وما زالت متاحةً للتطبيق',
       has_function_privilege('authenticated', 'public.api_member_value(bigint)', 'EXECUTE')::text
UNION ALL SELECT 'ومجموعُ السنوات يطابق حسابَ كلّ مشترك',
       current_setting('adayl.years_check', true);

COMMIT;
