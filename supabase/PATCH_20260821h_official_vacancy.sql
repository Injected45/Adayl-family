-- ============================================================================
--  جمعية العدايل — PATCH 2026-08-21 (h).  منصبٌ فارغ يعني اسماً فارغاً.
--
--  WHAT CHANGES
--    update_settings: vacating a post now CLEARS the name and phone it had
--    snapshotted, instead of keeping whatever the client last sent.
--
--  ⚠ WHAT WAS WRONG, AND IT SURVIVED A FULL PURGE. The two names are a
--    SNAPSHOT of the عديل holding each post — the settings screen has no
--    name field at all, it has a picker. So when a post is cleared, the id
--    goes and the name has nothing left behind it. But the old rule was
--
--        coalesce(p_patch ->> 'financeName', finance_manager_name)
--
--    which keeps the previous value whenever the key is absent — and the app
--    was sending the name it had LOADED WITH, so it was never absent. The
--    name of a man who no longer held the post was written back on every
--    save, and `v_officials` went on offering him on the collection sheet.
--
--  ⚠ AND NEITHER PURGE COULD CLEAR IT. Both deliberately leave
--    association_settings standing — erasing the association’s own name and
--    monthly fee is not what «مسح البيانات» means — so the stale official
--    outlived every reset. The association reported exactly that: «يظهر اسم
--    المدير المالي الذي كان موجوداً قبل المسح».
--
--  ⚠ THE NEW RULE IS ONE SENTENCE: when a post has no عديل, its name and
--    phone are whatever the patch says — and an empty patch means EMPTY. A
--    caller that wants to set a manual name still can, by sending one; what
--    it can no longer do is inherit a name it did not send.
--
--  ⚠ AND THE BODY IS LIFTED FROM supabase/migrations/20260811090600_rpc.sql,
--    not retyped. Two patches in this same session were rolled back by their
--    own guards for having been written from memory.
--
--  HOW TO APPLY
--    SQL Editor → New query → paste → Run. One transaction, safe to run twice.
--    It also CLEARS any name already stranded, which is the reason to run it
--    even though the app-side fix ships in the same APK.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.update_settings(p_patch jsonb)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_old     record;
  v_row     record;
  v_changes text[] := '{}';
  v_t_id    bigint;
  v_f_id    bigint;
  -- Scalars, deliberately. See the note beside the lookups: a `record` that is
  -- never assigned makes the UPDATE below unplannable (55000), even in the arm
  -- that does not read it.
  v_t_name  text;
  v_t_phone text;
  v_f_name  text;
  v_f_phone text;
BEGIN
  PERFORM public.require_role('admin');

  SELECT * INTO v_old FROM public.association_settings WHERE id = 1 FOR UPDATE;

  -- ── Who holds each post ───────────────────────────────────────────────────
  -- Both officials are عدايل, chosen from the register rather than typed. The
  -- id is what is being set; the name and phone are copied from his row below,
  -- so the association can never end up with three spellings of one man across
  -- a year of settings edits.
  --
  -- `p_patch ? key` distinguishes "not mentioned" from "explicitly cleared".
  -- Using ->> alone would make a null indistinguishable from an omission, and
  -- vacating a post would become impossible.
  v_t_id := CASE WHEN p_patch ? 'treasurerAdeelId'
                 THEN nullif(p_patch ->> 'treasurerAdeelId', '')::bigint
                 ELSE v_old.treasurer_adeel_id END;
  v_f_id := CASE WHEN p_patch ? 'financeAdeelId'
                 THEN nullif(p_patch ->> 'financeAdeelId', '')::bigint
                 ELSE v_old.finance_manager_adeel_id END;

  -- The overlap the association asked to make impossible. ck_settings_distinct_
  -- officials enforces it in the storage engine too; this exists so the admin
  -- gets a sentence he can act on instead of a constraint name.
  IF v_t_id IS NOT NULL AND v_t_id = v_f_id THEN
    RAISE EXCEPTION 'لا يمكن أن يكون أمين الصندوق والمدير المالي عديلاً واحداً'
      USING ERRCODE = 'RUL16';
  END IF;

  -- ── FOUR SCALARS, NOT TWO RECORDS. This is the second thing that stopped
  --    an official from ever being saved. ───────────────────────────────────
  --
  -- These were `v_t record` / `v_f record`, filled only inside the IF below.
  -- With no post chosen the record is never assigned, and the UPDATE further
  -- down still MENTIONS `v_t.full_name` inside a CASE arm that would not be
  -- taken. PL/pgSQL has to know the record's tuple structure to plan the
  -- statement at all, so the branch never gets a chance to protect it:
  --
  --   55000  record "v_t" is not assigned yet
  --          The tuple structure of a not-yet-assigned record is indeterminate.
  --
  -- So the two failures covered the whole space between them: choosing an
  -- official raised 22P02 on the audit line below, and leaving one vacant
  -- raised 55000 here. There was no input that saved.
  --
  -- A scalar has no tuple structure to be indeterminate about. Unset it is
  -- simply NULL, the CASE arm is planned without complaint, and `SELECT INTO`
  -- still sets FOUND, so the "not on the register" check below is unchanged.
  IF v_t_id IS NOT NULL THEN
    SELECT full_name, phone INTO v_t_name, v_t_phone
      FROM public.adeels WHERE id = v_t_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'أمين الصندوق المختار ليس في سجل العدايل'
        USING ERRCODE = 'RUL16';
    END IF;
  END IF;
  IF v_f_id IS NOT NULL THEN
    SELECT full_name, phone INTO v_f_name, v_f_phone
      FROM public.adeels WHERE id = v_f_id;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'المدير المالي المختار ليس في سجل العدايل'
        USING ERRCODE = 'RUL16';
    END IF;
  END IF;

  UPDATE public.association_settings SET
    association_name = coalesce(p_patch ->> 'associationName', association_name),
    currency         = coalesce(p_patch ->> 'currency', currency),
    -- nullif BEFORE the cast, and the officials below have always had it while
    -- these two did not. An EMPTY string is not a number and not a date, so
    -- `''::numeric` raises 22P02 — a code with no Arabic text, which the app can
    -- only render as "something went wrong". The whole save fails, including
    -- the two officials the admin was actually trying to set, and nothing on
    -- screen connects the failure to a field he may not even have touched.
    --
    -- An empty box now means "leave it alone", which is the only reading that
    -- makes sense: the fee is NOT NULL, so blank cannot be a value.
    member_fee       = coalesce(nullif(p_patch ->> 'memberFee', '')::numeric,
                                member_fee),
    system_start     = coalesce(nullif(p_patch ->> 'systemStart', '')::date,
                                system_start),
    -- The post, then the snapshot of whoever holds it. When an عديل is chosen
    -- his row IS the name and phone; the free-text keys are still honoured when
    -- no عديل is set, so a project that has not picked anyone yet keeps working
    -- exactly as before.
    treasurer_adeel_id    = v_t_id,
    treasurer_name        = CASE WHEN v_t_id IS NOT NULL THEN v_t_name
                                 ELSE coalesce(p_patch ->> 'treasurerName', '') END,
    treasurer_phone       = CASE WHEN v_t_id IS NOT NULL
                                 THEN coalesce(v_t_phone, '')
                                 ELSE coalesce(p_patch ->> 'treasurerPhone', '') END,
    finance_manager_adeel_id = v_f_id,
    finance_manager_name  = CASE WHEN v_f_id IS NOT NULL THEN v_f_name
                                 ELSE coalesce(p_patch ->> 'financeName', '') END,
    finance_manager_phone = CASE WHEN v_f_id IS NOT NULL
                                 THEN coalesce(v_f_phone, '')
                                 ELSE coalesce(p_patch ->> 'financePhone', '') END,
    bank_name                   = coalesce(p_patch ->> 'bankName', bank_name),
    bank_account_no             = coalesce(p_patch ->> 'bankAccountNo', bank_account_no),
    bank_account_name           = coalesce(p_patch ->> 'bankAccountName', bank_account_name),
    updated_by = auth.uid()
  WHERE id = 1
  RETURNING * INTO v_row;

  -- The two financially load-bearing fields first, then the rest. IS DISTINCT
  -- FROM so a field the patch omitted (coalesce kept it) records nothing.
  IF v_row.member_fee IS DISTINCT FROM v_old.member_fee THEN
    v_changes := v_changes || format('الاشتراك الشهري من %s إلى %s',
                                     v_old.member_fee::text, v_row.member_fee::text);
  END IF;
  IF v_row.system_start IS DISTINCT FROM v_old.system_start THEN
    v_changes := v_changes || format('بداية النظام من %s إلى %s',
                                     to_char(v_old.system_start, 'YYYY-MM-DD'),
                                     to_char(v_row.system_start, 'YYYY-MM-DD'));
  END IF;
  IF v_row.currency IS DISTINCT FROM v_old.currency THEN
    v_changes := v_changes || format('العملة من %s إلى %s',
                                     v_old.currency, v_row.currency);
  END IF;
  IF v_row.association_name IS DISTINCT FROM v_old.association_name THEN
    v_changes := v_changes || format('اسم الجمعية من %s إلى %s',
                                     v_old.association_name, v_row.association_name);
  END IF;
  -- The account number is recorded in full, both before and after. It is the
  -- one setting where a single wrong digit sends the association's collections
  -- to a stranger, and "someone changed the bank account" without saying what
  -- it was is not a trail anyone can act on.
  IF v_row.bank_name IS DISTINCT FROM v_old.bank_name THEN
    v_changes := v_changes || format('المصرف من %s إلى %s',
                                     coalesce(nullif(v_old.bank_name, ''), '—'),
                                     coalesce(nullif(v_row.bank_name, ''), '—'));
  END IF;
  IF v_row.bank_account_no IS DISTINCT FROM v_old.bank_account_no THEN
    v_changes := v_changes || format('رقم الحساب المصرفي من %s إلى %s',
                                     coalesce(nullif(v_old.bank_account_no, ''), '—'),
                                     coalesce(nullif(v_row.bank_account_no, ''), '—'));
  END IF;
  IF v_row.bank_account_name IS DISTINCT FROM v_old.bank_account_name THEN
    v_changes := v_changes || format('اسم صاحب الحساب من %s إلى %s',
                                     coalesce(nullif(v_old.bank_account_name, ''), '—'),
                                     coalesce(nullif(v_row.bank_account_name, ''), '—'));
  END IF;
  -- ── `::text` IS NOT DECORATION. Without it this function cannot save an
  --    official at all. ──────────────────────────────────────────────────────
  --
  -- `v_changes` is text[]. Every append above passes format(), which RETURNS
  -- text, so `text[] || text` resolves to array_append and works. These two
  -- passed a bare quoted literal, which Postgres types as `unknown` — and given
  -- the choice between `anyarray || anyelement` and `anyarray || anyarray` it
  -- picks the array form and casts the literal to text[]:
  --
  --   22P02  malformed array literal: "بيانات أمين الصندوق"
  --          Array value must start with "{" or dimension information.
  --
  -- The branch fires on exactly one condition — the treasurer or the finance
  -- manager CHANGED — so the failure is perfectly targeted at the one action
  -- the admin was performing, and invisible for every other settings save. And
  -- 22P02 carries no Arabic, so the app could only say "حدث خطأ غير متوقع"
  -- about a save that looked, from the screen, like it had simply not worked.
  --
  -- It is not a rule, a permission or a constraint. It is a type resolution,
  -- three lines below the officials it was silently refusing to record.
  IF v_row.treasurer_name  IS DISTINCT FROM v_old.treasurer_name
  OR v_row.treasurer_phone IS DISTINCT FROM v_old.treasurer_phone THEN
    v_changes := v_changes || 'بيانات أمين الصندوق'::text;
  END IF;
  IF v_row.finance_manager_name  IS DISTINCT FROM v_old.finance_manager_name
  OR v_row.finance_manager_phone IS DISTINCT FROM v_old.finance_manager_phone THEN
    v_changes := v_changes || 'بيانات المدير المالي'::text;
  END IF;

  -- A no-op save still writes an entry. "An admin opened settings and saved
  -- without changing anything" is itself worth being able to see, and a silent
  -- write would make the trail's gaps ambiguous.
  PERFORM public.write_audit('settings.update',
    CASE WHEN cardinality(v_changes) = 0
         THEN 'تحديث إعدادات الجمعية: لا تغيير'
         ELSE 'تحديث إعدادات الجمعية: ' || array_to_string(v_changes, '، ')
    END,
    'settings');

  RETURN jsonb_build_object(
    'associationName', v_row.association_name, 'currency', v_row.currency,
    'memberFee', v_row.member_fee::text,
    'systemStart', v_row.system_start);
END $$;


-- ── وتنظيف ما علِق فعلاً ────────────────────────────────────────────────
-- ⚠ THE FIX ALONE DOES NOT UNDO THE PAST. The row still holds the stranded
--   name today, and it would keep being offered until somebody saved
--   settings again. A post with no عديل behind it has no name, so this is
--   the same rule applied once to the data.
UPDATE public.association_settings
   SET treasurer_name  = CASE WHEN treasurer_adeel_id IS NULL THEN ''
                              ELSE treasurer_name END,
       treasurer_phone = CASE WHEN treasurer_adeel_id IS NULL THEN ''
                              ELSE treasurer_phone END,
       finance_manager_name  = CASE WHEN finance_manager_adeel_id IS NULL THEN ''
                                    ELSE finance_manager_name END,
       finance_manager_phone = CASE WHEN finance_manager_adeel_id IS NULL THEN ''
                                    ELSE finance_manager_phone END
 WHERE id = 1;


-- == Confirmation ===========================================================
SELECT 'أمين الصندوق' AS "المنصب",
       treasurer_adeel_id AS "رقم العديل",
       treasurer_name AS "الاسم المعروض"
  FROM public.association_settings WHERE id = 1
UNION ALL SELECT 'المدير المالي',
       finance_manager_adeel_id,
       finance_manager_name
  FROM public.association_settings WHERE id = 1;


SELECT public.assert_signin_intact();
SELECT public.assert_function_grants();
SELECT public.assert_no_public_execute();
SELECT public.assert_views_security_invoker();

COMMIT;
