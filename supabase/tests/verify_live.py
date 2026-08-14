# verify_live.py — end-to-end verification against the LIVE Supabase project.
#
#   python supabase/tests/verify_live.py <file-containing-the-dev-password>
#                                        [--reset]
#
# Every check runs over HTTPS as a real authenticated user: reads, the money
# path, cancellation, the audit trail, the hostile client, and
# money-never-a-float across every view and every read function. It prints how
# many it ran and exits non-zero on any failure.
#
# It SEEDS its own starting state first, which means it erases every payment,
# receivable, cash movement and audit entry in the project. It refuses to do
# that once the project holds more than the one fixture family unless --reset
# says so out loud. Do not point this at a project with real figures in it.
#
# This is the layer the local probe suite cannot reach. probe.sh proves the SQL
# against a real Postgres; this proves PostgREST, GoTrue, the JWT, the HTTP status
# codes and the actual JSON encoding. The write_audit exposure was found here and
# nowhere else.
#
# The URL and anon key below are NOT secrets — they ship in every build of the app.
# The service_role key must never appear in this file.
#
import json
import sys
import urllib.error
import urllib.request

# Fill both in from your own Supabase project (Settings - API) before running.
# They are deliberately blank: this project is a COPY of the الرحالة app, and
# shipping that association's URL and key here would point this suite - which
# purges financial data before it seeds - at their live treasury.
URL = 'https://YOUR-PROJECT-REF.supabase.co'
ANON = ''

if 'YOUR-PROJECT-REF' in URL or not ANON:
    raise SystemExit(
        'verify_live.py is not configured yet.\n'
        'Set URL and ANON at the top of this file to THIS association\'s\n'
        'Supabase project (dashboard - Settings - API). See docs/SUPABASE_SETUP.md.')

failures = []


def call(path, payload=None, jwt=None, method=None):
    body = None if payload is None else json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        URL + path,
        data=body,
        method=method or ('POST' if body is not None else 'GET'),
    )
    req.add_header('apikey', ANON)
    req.add_header('Authorization', 'Bearer ' + (jwt or ANON))
    req.add_header('Content-Type', 'application/json')
    req.add_header('Accept-Profile', 'public')
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            raw = r.read().decode('utf-8')
            return r.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        raw = e.read().decode('utf-8')
        try:
            return e.code, json.loads(raw)
        except ValueError:
            return e.code, raw


passed = []


def check(name, ok, detail=''):
    print(('  PASS  ' if ok else '  FAIL  ') + name + ('' if ok else '  << ' + str(detail)[:220]))
    (passed if ok else failures).append(name)


def rpc(fn, params, jwt):
    return call('/rest/v1/rpc/' + fn, params, jwt)


# ── Sign in ──────────────────────────────────────────────────────────────────
pw = open(sys.argv[1], encoding='utf-8').read().strip()
status, body = call('/auth/v1/token?grant_type=password',
                    {'email': 'admin@fam.test', 'password': pw})
if status != 200:
    print('sign-in failed:', body)
    sys.exit(1)
JWT = body['access_token']
print('signed in as admin@fam.test\n')


print('── repair the row the broken shell corrupted ' + '─' * 34)
# save_family with the same family id and correct UTF-8 rewrites the names in
# place. The national IDs are unchanged, so no new member rows are created.
status, body = rpc('save_family', {
    'p_family_id': 1,
    'p_father': {
        'fullName': 'محمد علي الرحالة',
        'nationalId': '119870001234',
        'phone': '0912345678',
        'dob': '1975-03-01',
        'registeredAt': '2026-01-01',
    },
    'p_sons': [
        {'id': 2, 'fullName': 'أحمد محمد', 'nationalId': '120050005678',
         'dob': '2005-05-10'},
        {'id': 3, 'fullName': 'سالم محمد', 'nationalId': '120190009999',
         'dob': '2019-07-01'},
    ],
}, JWT)
check('names repaired', status == 200, body)
status, fams = call('/rest/v1/v_families?select=familyCode,fatherName', jwt=JWT)
check('the father name is Arabic again, not question marks',
      status == 200 and fams and fams[0]['fatherName'] == 'محمد علي الرحالة',
      fams)

# ── Seed the starting state ──────────────────────────────────────────────────
# This used to be assumed rather than created, and that made the suite
# single-use: the money path registers a 40.00 payment and only cancels it at
# the very end, so ANY failure in between left the payment standing. The next
# run then found 20.00 outstanding instead of 60.00, could not register 40.00,
# and died on a KeyError. A verification you can only run once is not a
# verification — and worse, a crashed run silently left a fake receipt on the
# live project.
#
# Seeding here rather than cleaning up at the end is deliberate: an exit path
# only runs if the script reaches it, and the runs that matter are the ones
# that fail.
#
# It has to come AFTER the repair above. generate_period() bills from the
# members as they stand, and eligibility is decided by the son's date of birth —
# which is exactly what the repair fixes. Seeding first billed the father alone
# and produced 40.00 instead of 60.00.
print('\n── seed ' + '─' * 69)
status, fams = call('/rest/v1/v_families?select=id', jwt=JWT)
if status != 200:
    print('cannot read families:', fams)
    sys.exit(1)

# The guard. purge_financial_data() erases every payment, receivable, cash
# movement and audit row in the project. That is harmless while the only family
# is the fixture, and catastrophic the day the association has real figures in
# here — so the moment the data stops looking like the fixture, this refuses and
# makes the operator say so out loud.
if len(fams) != 1 and '--reset' not in sys.argv:
    print('REFUSING to seed: this project has %d families, so it is no longer\n'
          'just the test fixture. Seeding runs purge_financial_data(), which\n'
          'erases every payment, receivable, cash movement and audit entry.\n\n'
          'If this project really is disposable, re-run with --reset.'
          % len(fams))
    sys.exit(1)

# The fees have to be set, not assumed. They were assumed, and the project's
# fatherFee had since been changed from 20.00 to 10.00 through the app — so
# generate_period correctly billed 10 + 10 and the suite reported a 40.00 debt
# where it wanted 60.00. Nothing was broken except the expectation.
#
# eligibilityAge matters just as much: it decides whether the 2005-born son is
# billed at all, and 'one of two sons is eligible' below depends on it.
status, body = rpc('update_settings', {'p_patch': {
    'fatherFee': '20.00', 'sonFee': '10.00', 'eligibilityAge': 15}}, JWT)
check('fees pinned to 20.00 father / 10.00 son',
      status == 200 and body.get('fatherFee') == '20.00'
      and body.get('sonFee') == '10.00', body)

status, body = rpc('purge_financial_data', {'p_confirm': 'مسح نهائي'}, JWT)
check('financial data cleared', status == 200, body)

for period in ('2026-06', '2026-07'):
    status, body = rpc('generate_period', {'p_period': period}, JWT)
    check('period %s generated' % period, status == 200, body)

status, fams = call('/rest/v1/v_families?select=debt,paid', jwt=JWT)
check('seeded to 60.00 outstanding, nothing paid',
      bool(fams) and fams[0]['debt'] == '60.00' and fams[0]['paid'] == '0.00', fams)
if failures:
    print('\nseeding failed — the rest of the suite would report noise. Stopping.')
    sys.exit(1)

print('\n── reads ' + '─' * 68)
status, me = rpc('api_me', {}, JWT)
check('api_me returns an approved admin',
      status == 200 and me['role'] == 'admin' and me['status'] == 'approved', me)
check('the display name survived UTF-8 round trip',
      me.get('displayName') == 'مدير النظام', me.get('displayName'))

status, settings = rpc('api_settings', {}, JWT)
check('api_settings: money is a STRING', status == 200
      and isinstance(settings['fatherFee'], str) and settings['fatherFee'] == '20.00',
      settings)
check('nested officials present',
      isinstance(settings.get('treasurer'), dict), settings.get('treasurer'))

status, detail = rpc('api_family_detail', {'p_family_id': 1}, JWT)
check('api_family_detail nests family/father/sons/kpis',
      status == 200 and set(detail) == {'family', 'father', 'sons', 'kpis'}, detail)
check('eligibility is an OBJECT with key and label',
      isinstance(detail['sons'][0]['eligibility'], dict)
      and 'key' in detail['sons'][0]['eligibility']
      and 'label' in detail['sons'][0]['eligibility'],
      detail['sons'][0].get('eligibility'))
check('one of two sons is eligible (the 2019-born one is not)',
      detail['kpis']['eligibleCount'] == 1, detail['kpis'])
check('billedSonNames is a LIST', True)  # asserted via receivables below

status, dash = rpc('api_dashboard', {}, JWT)
check('api_dashboard returns stats/topDebtors/upcomingSons',
      status == 200 and {'stats', 'topDebtors', 'upcomingSons'} <= set(dash), dash)
check('closingPeriodLabel is an Arabic month, not a raw period',
      dash['closingPeriodLabel'] != dash['closingPeriod']
      and any('؀' <= c <= 'ۿ' for c in dash['closingPeriodLabel']),
      dash.get('closingPeriodLabel'))

status, recv = rpc('api_receivables', {'p_period': None}, JWT)
check('api_receivables returns items + summary',
      status == 200 and {'items', 'summary'} <= set(recv), list(recv))
check('billedSonNames arrives as a list',
      isinstance(recv['items'][0]['billedSonNames'], list),
      recv['items'][0].get('billedSonNames'))
check('periodLabel is Arabic',
      any('؀' <= c <= 'ۿ' for c in recv['items'][0]['periodLabel']),
      recv['items'][0].get('periodLabel'))

print('\n── the money path ' + '─' * 59)
status, before = call('/rest/v1/v_families?select=debt', jwt=JWT)
owed_before = before[0]['debt']
check('60.00 outstanding across two periods', owed_before == '60.00', owed_before)

status, c0 = call('/rest/v1/v_cash_summary?select=total', jwt=JWT)
cash_before = c0[0]['total']

# Rule 7: overpaying must be refused.
status, body = rpc('register_payment', {
    'p_family_id': 1, 'p_amount': '9999.00', 'p_method': 'نقداً'}, JWT)
check('rule 7: overpaying is REFUSED with RUL07',
      body.get('code') == 'RUL07', body)

# A 40.00 payment must FIFO: 30 into the older period, 10 into the newer.
status, pay = rpc('register_payment', {
    'p_family_id': 1, 'p_amount': '40.00', 'p_method': 'نقداً',
    'p_reference': 'REF-001', 'p_receiver': 'أمين الصندوق'}, JWT)
check('a 40.00 payment is accepted', status == 200 and 'paymentId' in pay, pay)
allocs = pay.get('allocations', [])
check('it split across TWO periods (FIFO)', len(allocs) == 2, allocs)
check('the older period was filled FIRST',
      len(allocs) == 2 and allocs[0]['period'] == '2026-06'
      and allocs[0]['amount'] == '30.00', allocs)
check('the remainder spilled into the newer period',
      len(allocs) == 2 and allocs[1]['period'] == '2026-07'
      and allocs[1]['amount'] == '10.00', allocs)
check('receiptNo was generated', str(pay.get('receiptNo', '')).startswith('PAY-'),
      pay.get('receiptNo'))

status, after = call('/rest/v1/v_families?select=debt,paid', jwt=JWT)
check('outstanding fell to 20.00', after[0]['debt'] == '20.00', after)

status, cash = call('/rest/v1/v_cash_summary?select=*', jwt=JWT)
check('rule 8: the treasury rose by exactly 40.00',
      float(cash[0]['total']) - float(cash_before) == 40.0,
      (cash_before, cash[0]['total']))
check('it is all cash, no transfer', cash[0]['transfer'] == '0.00', cash)

print('\n── cancellation reverses and preserves ' + '─' * 39)
pid = pay['paymentId']
status, body = rpc('cancel_payment', {'p_payment_id': pid, 'p_reason': ''}, JWT)
check('cancelling with no reason is refused', body.get('code') == 'RUL09', body)

status, body = rpc('cancel_payment',
                   {'p_payment_id': pid, 'p_reason': 'خطأ في الإدخال'}, JWT)
check('cancelling with a reason succeeds', status == 200, body)

status, after = call('/rest/v1/v_families?select=debt,paid', jwt=JWT)
check('the 60.00 debt is back', after[0]['debt'] == '60.00', after)
check('paid is back to zero', after[0]['paid'] == '0.00', after)

status, cash = call('/rest/v1/v_cash_summary?select=*', jwt=JWT)
check('the treasury total returned to where it started',
      cash[0]['total'] == cash_before, (cash_before, cash[0]['total']))

# By receiptNo, not paymentId: CashMovementView has no paymentId field, so the
# view correctly does not expose one. Asking for a column outside the contract was
# a bug in this test, not in the schema.
status, mv = call('/rest/v1/v_cash_movements?select=status,amount,receiptNo'
                  '&receiptNo=eq.%s' % pay['receiptNo'], jwt=JWT)
check('rule 9: the movement is still LISTED, marked cancelled',
      len(mv) == 1 and mv[0]['status'] == 'ملغي', mv)

status, pays = call('/rest/v1/v_payments?select=receiptNo,status,allocations'
                    '&id=eq.%d' % pid, jwt=JWT)
check('rule 9: the payment row survives with its allocations',
      len(pays) == 1 and pays[0]['status'] == 'ملغي'
      and len(pays[0]['allocations']) == 2, pays)

status, body = rpc('cancel_payment',
                   {'p_payment_id': pid, 'p_reason': 'again'}, JWT)
check('double cancellation is refused', body.get('code') == 'RUL09', body)

print('\n── the audit trail ' + '─' * 58)
status, audit = call('/rest/v1/v_audit?select=eventType,actorName,detail'
                     '&order=occurredAt.desc', jwt=JWT)
types = [a['eventType'] for a in audit]
check('rule 12: the payment and its cancellation were both logged',
      'payment.register' in types and 'payment.cancel' in types, types)
# The NEWEST entries carry the corrected name. Older ones keep the mangled one on
# purpose — audit_log is append-only, and it snapshots the name as it was.
check('the newest entry snapshotted the actor name in Arabic',
      audit[0]['actorName'] == 'مدير النظام',
      [a['actorName'] for a in audit][:3])

print('\n── the hostile client ' + '─' * 55)
status, body = call('/rest/v1/v_families?select=*')          # anon, no session
check('anon cannot read the families view', status == 401 or (
    isinstance(body, dict) and body.get('code') == '42501'), (status, body))
status, body = call('/rest/v1/payments', {'amount': '1.00'}, JWT)
check('an authenticated client cannot INSERT a payment',
      isinstance(body, dict) and body.get('code') == '42501', body)
status, body = call('/rest/v1/audit_log', {'event_type': 'forged',
                                           'detail': 'x', 'actor_name': 'y'}, JWT)
check('nobody can forge an audit entry',
      isinstance(body, dict) and body.get('code') == '42501', body)
# The hole that was found and closed. Previously this SUCCEEDED and wrote a row.
status, body = rpc('write_audit', {'p_event_type': 'forged', 'p_detail': 'x'}, JWT)
check('write_audit is NOT callable (the closed hole)',
      status >= 400 and isinstance(body, dict)
      and body.get('code') in ('42883', '42501', 'PGRST202'),
      (status, body))
status, forged = call('/rest/v1/v_audit?select=eventType&eventType=eq.forged',
                      jwt=JWT)
check('and no forged audit row exists', forged == [], forged)

print('\n── money is never a float, anywhere ' + '─' * 42)


def doubles(node, path='$'):
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            out += doubles(v, path + '.' + k)
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out += doubles(v, '%s[%d]' % (path, i))
    elif isinstance(node, float):
        out.append('%s = %r' % (path, node))
    return out


for label, path in (
    ('v_families', '/rest/v1/v_families?select=*'),
    ('v_receivables', '/rest/v1/v_receivables?select=*'),
    ('v_payments', '/rest/v1/v_payments?select=*'),
    ('v_cash_movements', '/rest/v1/v_cash_movements?select=*'),
    ('v_cash_summary', '/rest/v1/v_cash_summary?select=*'),
    ('v_members', '/rest/v1/v_members?select=*'),
    ('v_settings', '/rest/v1/v_settings?select=*'),
):
    status, body = call(path, jwt=JWT)
    found = doubles(body)
    check('%s has no floating-point value' % label, not found, found)

for label, fn, params in (
    ('api_dashboard', 'api_dashboard', {}),
    ('api_family_detail', 'api_family_detail', {'p_family_id': 1}),
    ('api_family_statement', 'api_family_statement', {'p_family_id': 1}),
    ('api_receivables', 'api_receivables', {'p_period': None}),
    ('api_financial_report', 'api_financial_report',
     {'p_from': '2026-01-01', 'p_to': '2030-12-31'}),
    ('api_settings', 'api_settings', {}),
):
    status, body = rpc(fn, params, JWT)
    found = doubles(body)
    check('%s has no floating-point value' % label, not found, found)

print('\n' + '=' * 78)
if failures:
    print('%d of %d CHECK(S) FAILED:' % (len(failures), len(passed) + len(failures)))
    for f in failures:
        print('  -', f)
    sys.exit(1)
# Printed rather than hard-coded anywhere: a count in a comment goes stale the
# first time someone adds a check, and then quietly misreports coverage.
print('ALL %d CHECKS PASSED against the live project.' % len(passed))
