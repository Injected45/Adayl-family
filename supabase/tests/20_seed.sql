-- 20_seed.sql — fixture. Runs as postgres, so RLS is bypassed here by design;
-- everything after this point runs as a real role.
--
-- Fixed UUIDs so failures are reproducible and greppable.

INSERT INTO auth.users (id, email, raw_user_meta_data) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'admin@fam.test',     '{"full_name":"مدير النظام"}'),
  ('00000000-0000-0000-0000-0000000000a2', 'finance@fam.test',   '{"full_name":"المدير المالي"}'),
  ('00000000-0000-0000-0000-0000000000a3', 'treasurer@fam.test', '{"full_name":"أمين الصندوق"}'),
  ('00000000-0000-0000-0000-0000000000a4', 'viewer@fam.test',    '{"full_name":"مطالع"}'),
  ('00000000-0000-0000-0000-0000000000a5', 'pending@fam.test',   '{"full_name":"قيد الموافقة"}'),
  ('00000000-0000-0000-0000-0000000000a6', 'suspended@fam.test', '{"full_name":"موقوف"}');

-- The trigger on auth.users created six profiles, all viewer/pending. Promote
-- four of them; a5 stays pending and a6 becomes suspended, because "signed in
-- but not allowed" is the case most likely to be got wrong.
UPDATE public.profiles SET role = 'admin',          status = 'approved' WHERE email = 'admin@fam.test';
UPDATE public.profiles SET role = 'financeManager', status = 'approved' WHERE email = 'finance@fam.test';
UPDATE public.profiles SET role = 'treasurer',      status = 'approved' WHERE email = 'treasurer@fam.test';
UPDATE public.profiles SET role = 'viewer',         status = 'approved' WHERE email = 'viewer@fam.test';
UPDATE public.profiles SET role = 'admin',          status = 'suspended' WHERE email = 'suspended@fam.test';

-- Settings pinned so eligibility maths is deterministic rather than dependent on
-- the day the suite runs.
UPDATE public.association_settings
   SET father_fee = 20.00, son_fee = 10.00, eligibility_age = 16,
       warning_months = 3, system_start = '2026-01-01'
 WHERE id = 1;

-- Two families. F-0001: father نشط + two sons over 16 + one under → 20 + 20 = 40.
-- F-0002: father موقوف + one son over 16 → 0 + 10 = 10, which proves the father
-- fee is genuinely conditional rather than always added.
INSERT INTO public.families DEFAULT VALUES;
INSERT INTO public.families DEFAULT VALUES;

INSERT INTO public.members
  (family_id, kind, full_name, national_id, dob, registered_at, status) VALUES
  (1, 'father', 'الأب الأول',  '1000000000001', '1975-03-01', '2026-01-01', 'نشط'),
  (1, 'son',    'ابن بالغ ١',  '1000000000002', '2005-05-10', '2026-01-01', 'نشط'),
  (1, 'son',    'ابن بالغ ٢',  '1000000000003', '2008-01-20', '2026-01-01', 'نشط'),
  (1, 'son',    'ابن صغير',    '1000000000004', '2019-07-01', '2026-01-01', 'نشط'),
  (2, 'father', 'الأب الثاني', '1000000000005', '1970-11-11', '2026-01-01', 'موقوف'),
  (2, 'son',    'ابن الثاني',  '1000000000006', '2004-02-02', '2026-01-01', 'نشط');
