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

-- Pinned so the arithmetic is deterministic rather than dependent on the day the
-- suite runs.
UPDATE public.association_settings
   SET member_fee = 20.00, system_start = '2026-01-01'
 WHERE id = 1;

-- Four عدايل, chosen so a generated period proves the ONLY billing gate that is
-- left. Two are نشط and get charged 20.00 each; one موقوف and one متوفى are
-- skipped entirely. Dates of birth are spread deliberately wide — a 7-year-old
-- among them — because under the old schema age decided who paid and under this
-- one it must decide nothing at all. If an age gate is ever reintroduced by
-- accident, العديل الصغير starts being skipped and 30_rules notices.
INSERT INTO public.adeels
  (full_name, dob, registered_at, status) VALUES
  ('العديل الأول',  '1975-03-01', '2026-01-01', 'نشط'),
  ('العديل الصغير', '2019-07-01', '2026-01-01', 'نشط'),
  ('العديل الموقوف','1970-11-11', '2026-01-01', 'موقوف'),
  ('العديل المتوفى','1968-02-02', '2026-01-01', 'متوفى');
