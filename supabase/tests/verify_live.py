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
# that once the project holds more than the one fixture عديل unless --reset
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

# THIS association's own project. Not the one the app was forked from — this
# suite calls purge_financial_data() before it seeds, so a stale URL here would
# erase somebody else's books rather than merely reading the wrong ones.
URL = 'https://wvryyidbjvvomurvfhpw.supabase.co'
ANON = ('eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6'
        'Ind2cnl5aWRianZ2b211cnZmaHB3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODY3Mjgz'
        'MzgsImV4cCI6MjEwMjMwNDMzOH0.ZvppQmbFK_mU-XWocTFqc9zIUW0CTb9lctD_9yuZ8nk')

if 'YOUR-PROJECT' in URL or not ANON:
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


# ── Seed the starting state ──────────────────────────────────────────────────
# This used to be assumed rather than created, and that made the suite
# single-use: the money path registers a payment and only cancels it at the very
# end, so ANY failure in between left the payment standing. The next run then
# found a smaller balance than it expected and died on a KeyError. A
# verification you can only run once is not a verification — and worse, a
# crashed run silently left a fake receipt on the live project.
#
# Seeding here rather than cleaning up at the end is deliberate: an exit path
# only runs if the script reaches it, and the runs that matter are the ones that
# fail.
print('── seed ' + '─' * 69)
status, adeels = call('/rest/v1/v_adeels?select=id', jwt=JWT)
if status != 200:
    print('cannot read the register:', adeels)
    print('If this says v_adeels does not exist, the project is still on the '
          'OLD family/member schema — apply supabase/APPLY_TO_SUPABASE.sql to a '
          'FRESH project first, then run supabase/VERIFY_INSTALL.sql.')
    sys.exit(1)

# The guard. purge_financial_data() erases every payment, receivable, cash
# movement and audit row in the project. That is harmless while the register is
# still just the fixture, and catastrophic the day the association has real
# figures in here — so the moment the data stops looking like the fixture, this
# refuses and makes the operator say so out loud.
if len(adeels) != 1 and '--reset' not in sys.argv:
    print('REFUSING to seed: this project has %d عدايل, so it is no longer just\n'
          'the test fixture. Seeding runs purge_financial_data(), which erases\n'
          'every payment, receivable, cash movement and audit entry.\n\n'
          'If this project really is disposable, re-run with --reset.'
          % len(adeels))
    sys.exit(1)

ADEEL = adeels[0]['id']

# The fee has to be set, not assumed. It was assumed once, the project's rate had
# since been changed through the app, and the suite reported a debt it did not
# expect. Nothing was broken except the expectation.
#
# ONE rate now. father_fee/son_fee and eligibility_age are gone: every عديل is
# billed the same amount and age decides nothing, so there is no second figure to
# pin and no age to pin it against.
status, body = rpc('update_settings',
                   {'p_patch': {'memberFee': '20.00'}}, JWT)
check('the member fee is pinned to 20.00',
      status == 200 and body.get('memberFee') == '20.00', body)

status, body = rpc('purge_financial_data', {'p_confirm': 'مسح نهائي'}, JWT)
check('financial data cleared', status == 200, body)

for period in ('2026-06', '2026-07'):
    status, body = rpc('generate_period', {'p_period': period}, JWT)
    check('period %s generated' % period, status == 200, body)

status, adeels = call('/rest/v1/v_adeels?select=debt,paid', jwt=JWT)
check('seeded to 40.00 outstanding, nothing paid',
      bool(adeels) and adeels[0]['debt'] == '40.00'
      and adeels[0]['paid'] == '0.00', adeels)
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
      and isinstance(settings['memberFee'], str)
      and settings['memberFee'] == '20.00', settings)
check('nested officials present',
      isinstance(settings.get('treasurer'), dict), settings.get('treasurer'))
# The national ID is gone from the whole project, officials included. Asserted
# rather than assumed: a view that still selected it would be an old view.
check('officials carry a name and a phone, and no national ID',
      set(settings['treasurer']) == {'name', 'phone'}, settings['treasurer'])

status, detail = rpc('api_adeel_detail', {'p_adeel_id': ADEEL}, JWT)
check('api_adeel_detail nests adeel/kpis/receivables/payments',
      status == 200
      and {'adeel', 'kpis', 'receivables'} <= set(detail), list(detail))
check('the record carries no nationalId key at all',
      'nationalId' not in detail['adeel'], list(detail['adeel']))
check('membershipStatus is what gates billing, and it is present',
      detail['adeel'].get('membershipStatus') == 'نشط', detail['adeel'])
check('two periods were raised for him',
      len(detail['receivables']) == 2, len(detail['receivables']))

status, dash = rpc('api_dashboard', {}, JWT)
check('api_dashboard returns stats/topDebtors',
      status == 200 and {'stats', 'topDebtors'} <= set(dash), list(dash))
check('the stat row counts the register by status, not by age',
      {'adeels', 'active', 'suspended', 'deceased'} <= set(dash['stats']),
      list(dash['stats']))
check('closingPeriodLabel is an Arabic month, not a raw period',
      dash['closingPeriodLabel'] != dash['closingPeriod']
      and any('؀' <= c <= 'ۿ' for c in dash['closingPeriodLabel']),
      dash.get('closingPeriodLabel'))

status, recv = rpc('api_receivables', {'p_period': None}, JWT)
check('api_receivables returns items + summary',
      status == 200 and {'items', 'summary'} <= set(recv), list(recv))
check('a receivable carries the snapshotted name and no national ID',
      recv['items'][0].get('adeelName')
      and 'adeelNationalId' not in recv['items'][0],
      list(recv['items'][0]))
check('periodLabel is Arabic',
      any('؀' <= c <= 'ۿ' for c in recv['items'][0]['periodLabel']),
      recv['items'][0].get('periodLabel'))

print('\n── the money path ' + '─' * 59)
status, before = call('/rest/v1/v_adeels?select=debt', jwt=JWT)
owed_before = before[0]['debt']
check('40.00 outstanding across two periods', owed_before == '40.00', owed_before)

status, c0 = call('/rest/v1/v_cash_summary?select=total', jwt=JWT)
cash_before = c0[0]['total']

# Rule 7 no longer caps the amount — the association asked for a wallet, and an
# overpayment is now CREDIT rather than a refusal. This used to send 9999.00 and
# expect RUL07; left as it was it would not merely go red, it would SUCCEED and
# park 9959.00 in the member's wallet, and every FIFO assertion below would then
# be measuring a ledger this check had quietly rewritten.
#
# What survives from rule 7 is the floor, and it is asserted here precisely
# because it refuses — so it cannot disturb the state the rest of the run reads.
status, body = rpc('register_payment', {
    'p_adeel_id': ADEEL, 'p_amount': '0', 'p_method': 'نقداً'}, JWT)
check('rule 7: a payment of zero is still REFUSED with RUL07',
      body.get('code') == 'RUL07', body)
status, body = rpc('register_payment', {
    'p_adeel_id': ADEEL, 'p_amount': '-5.00', 'p_method': 'نقداً'}, JWT)
check('rule 7: and so is a negative one', body.get('code') == 'RUL07', body)

# A 30.00 payment must FIFO: 20 fills the older period, 10 spills into the newer.
status, pay = rpc('register_payment', {
    'p_adeel_id': ADEEL, 'p_amount': '30.00', 'p_method': 'نقداً',
    'p_reference': 'REF-001', 'p_receiver': 'أمين الصندوق'}, JWT)
check('a 30.00 payment is accepted', status == 200 and 'paymentId' in pay, pay)
allocs = pay.get('allocations', [])
check('it split across TWO periods (FIFO)', len(allocs) == 2, allocs)
check('the older period was filled FIRST',
      len(allocs) == 2 and allocs[0]['period'] == '2026-06'
      and allocs[0]['amount'] == '20.00', allocs)
check('the remainder spilled into the newer period',
      len(allocs) == 2 and allocs[1]['period'] == '2026-07'
      and allocs[1]['amount'] == '10.00', allocs)
check('receiptNo was generated', str(pay.get('receiptNo', '')).startswith('PAY-'),
      pay.get('receiptNo'))

status, after = call('/rest/v1/v_adeels?select=debt,paid', jwt=JWT)
check('outstanding fell to 10.00', after[0]['debt'] == '10.00', after)

status, cash = call('/rest/v1/v_cash_summary?select=*', jwt=JWT)
check('rule 8: the treasury rose by exactly 30.00',
      float(cash[0]['total']) - float(cash_before) == 30.0,
      (cash_before, cash[0]['total']))
check('it is all cash, no transfer', cash[0]['transfer'] == '0.00', cash)

print('\n── cancellation reverses and preserves ' + '─' * 39)
pid = pay['paymentId']
status, body = rpc('cancel_payment', {'p_payment_id': pid, 'p_reason': ''}, JWT)
check('cancelling with no reason is refused', body.get('code') == 'RUL09', body)

status, body = rpc('cancel_payment',
                   {'p_payment_id': pid, 'p_reason': 'خطأ في الإدخال'}, JWT)
check('cancelling with a reason succeeds', status == 200, body)

status, after = call('/rest/v1/v_adeels?select=debt,paid', jwt=JWT)
check('the 40.00 debt is back', after[0]['debt'] == '40.00', after)
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

print('\n── money LEAVING the treasury ' + '─' * 47)
# The whole outgoing path over HTTPS. The local suite proves this SQL; only this
# run proves PostgREST resolves the function, that RUL17 survives the hop as a
# code rather than a 500, and that every voucher amount arrives as a STRING.
#
# The treasury is empty at this point — the payment above was cancelled — so it
# has to be funded before anything can be spent.
status, fund = rpc('register_payment', {
    'p_adeel_id': ADEEL, 'p_amount': '30.00', 'p_method': 'نقداً',
    'p_reference': 'FUND-1'}, JWT)
check('a receipt is collected to fund a voucher', status == 200, fund)

status, cash = call('/rest/v1/v_cash_summary?select=total,disbursed,balance',
                    jwt=JWT)
check('the treasury holds 30.00 and has spent nothing yet',
      cash[0]['balance'] == '30.00' and cash[0]['disbursed'] == '0.00', cash)

# ★ The rule that makes it safe, over the wire.
status, body = rpc('register_disbursement', {
    'p_amount': '31.00', 'p_category': 'مصاريف إدارية',
    'p_payee_name': 'مورد', 'p_method': 'نقداً'}, JWT)
check('spending MORE than the fund holds is REFUSED with RUL17',
      body.get('code') == 'RUL17', body)
# The CODE, not the HTTP status. PostgREST has no mapping for a custom SQLSTATE,
# so the status it returns for every RULnn is the same one — which is why
# SupabaseFailures._statusForRule re-maps them on the client. Asserting a status
# here would be asserting PostgREST's default, not this project's rule.
check('...and the refusal carries an Arabic message for the screen',
      'رصيد الصندوق' in str(body.get('message', '')), body)

status, v = rpc('register_disbursement', {
    'p_amount': '12.00', 'p_category': 'إيجار وخدمات',
    'p_payee_name': 'مالك المقر', 'p_method': 'نقداً',
    'p_reference': 'INV-9', 'p_handed_by': 'أمين الصندوق'}, JWT)
check('a voucher within the balance is accepted', status == 200, v)
check('voucherNo was generated', str(v.get('voucherNo', '')).startswith('EXP-'),
      v.get('voucherNo'))
check('the amount came back as a STRING', isinstance(v.get('amount'), str), v)
check('and it states the fund AFTER the voucher',
      v.get('balanceAfter') == '18.00', v)

status, cash = call('/rest/v1/v_cash_summary?select=total,disbursed,balance',
                    jwt=JWT)
# `total` is everything ever COLLECTED and must not move; `balance` is what is
# actually held. Conflating them is what would overstate the fund on the screen
# by every voucher ever written.
check('what was COLLECTED did not move', cash[0]['total'] == '30.00', cash)
check('but the held balance fell to 18.00',
      cash[0]['balance'] == '18.00' and cash[0]['disbursed'] == '12.00', cash)

status, cats = call('/rest/v1/v_expense_by_category?select=*', jwt=JWT)
check('all nine headings are reported, spent on or not', len(cats) == 9, cats)

# ★ THE HOLE THAT WAS CLOSED. register_disbursement refuses to pay out money the
#   association does not hold; without this guard the money could still be taken
#   away AFTER it was spent, and the fund went straight through zero in silence.
status, body = rpc('cancel_payment', {
    'p_payment_id': fund['paymentId'],
    'p_reason': 'محاولة سحب المال المصروف'}, JWT)
check('cancelling the receipt whose money is SPENT is refused',
      body.get('code') == 'RUL09', body)
status, cash = call('/rest/v1/v_cash_summary?select=balance', jwt=JWT)
check('...and the fund never went below zero',
      float(cash[0]['balance']) >= 0, cash)

# Reverse the voucher and the SAME cancellation goes through — a rule, not a wall.
status, body = rpc('cancel_disbursement', {
    'p_id': v['id'], 'p_reason': 'إلغاء لاختبار الترتيب'}, JWT)
check('reversing the voucher releases the money', status == 200, body)
status, body = rpc('cancel_payment', {
    'p_payment_id': fund['paymentId'], 'p_reason': 'إلغاء بعد رد السند'}, JWT)
check('...and NOW the receipt cancels cleanly', status == 200, body)

# Rule 9 outgoing: reversed, never removed.
status, vouchers = call('/rest/v1/v_disbursements?select=voucherNo,status',
                        jwt=JWT)
check('rule 9: the voucher is still LISTED, marked cancelled',
      any(d['status'] == 'ملغي' for d in vouchers), vouchers)

print('\n── the audit trail ' + '─' * 58)
status, audit = call('/rest/v1/v_audit?select=eventType,actorName,detail'
                     '&order=occurredAt.desc', jwt=JWT)
types = [a['eventType'] for a in audit]
check('rule 12: the payment and its cancellation were both logged',
      'payment.register' in types and 'payment.cancel' in types, types)
# Money leaving the treasury is the direction an audit trail exists FOR.
check('rule 12: so were the voucher and its reversal',
      'disbursement.register' in types and 'disbursement.cancel' in types, types)
# The NEWEST entries carry the corrected name. Older ones keep the mangled one on
# purpose — audit_log is append-only, and it snapshots the name as it was.
check('the newest entry snapshotted the actor name in Arabic',
      audit[0]['actorName'] == 'مدير النظام',
      [a['actorName'] for a in audit][:3])

print('\n── the hostile client ' + '─' * 55)
status, body = call('/rest/v1/v_adeels?select=*')            # anon, no session
check('anon cannot read the register view', status == 401 or (
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
    ('v_adeels', '/rest/v1/v_adeels?select=*'),
    ('v_receivables', '/rest/v1/v_receivables?select=*'),
    ('v_payments', '/rest/v1/v_payments?select=*'),
    ('v_cash_movements', '/rest/v1/v_cash_movements?select=*'),
    ('v_cash_summary', '/rest/v1/v_cash_summary?select=*'),
    ('v_settings', '/rest/v1/v_settings?select=*'),
    ('v_disbursements', '/rest/v1/v_disbursements?select=*'),
    ('v_expense_by_category', '/rest/v1/v_expense_by_category?select=*'),
):
    status, body = call(path, jwt=JWT)
    found = doubles(body)
    check('%s has no floating-point value' % label, not found, found)

for label, fn, params in (
    ('api_dashboard', 'api_dashboard', {}),
    ('api_adeel_detail', 'api_adeel_detail', {'p_adeel_id': ADEEL}),
    ('api_adeel_statement', 'api_adeel_statement', {'p_adeel_id': ADEEL}),
    ('api_receivables', 'api_receivables', {'p_period': None}),
    ('api_financial_report', 'api_financial_report',
     {'p_from': '2026-01-01', 'p_to': '2030-12-31'}),
    ('api_settings', 'api_settings', {}),
    # The member-facing totals, which now carry the outgoing side too.
    ('api_association_finance', 'api_association_finance', {}),
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
