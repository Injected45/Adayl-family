import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/supabase/supabase_failures.dart';
import '../domain/models.dart';

/// The money path, on Supabase.
///
/// Reads come from `v_*` views; every WRITE goes through a `SECURITY DEFINER`
/// function. That is the whole architecture in one sentence, and the reason is
/// that a payment is not one row.
///
/// Registering 50.00 inserts a payment, N allocations, N receivable updates and a
/// cash movement, and either all of it lands or none of it does. Split across
/// separate PostgREST calls from a phone on a flaky connection, a dropped socket
/// between call three and call four leaves the treasury disagreeing with the
/// ledger, and no retry logic on the client can repair it afterwards. A function
/// body is one transaction, so `register_payment` cannot half-happen.
class FinanceRepository {
  FinanceRepository(this._db);

  final SupabaseClient _db;

  static Map<String, dynamic> _obj(dynamic value) =>
      (value as Map).cast<String, dynamic>();

  static List<Map<String, dynamic>> _rows(dynamic value) =>
      (value as List<dynamic>).map(_obj).toList();

  Future<List<PaymentView>> payments({int? adeelId}) =>
      SupabaseFailures.guard(() async {
        final PostgrestFilterBuilder<dynamic> base = _db
            .from('v_payments')
            .select();
        final dynamic rows = adeelId == null
            ? await base.order('paidAt', ascending: false)
            : await base
                  .eq('adeelId', adeelId)
                  .order('paidAt', ascending: false);
        return _rows(rows).map(PaymentView.fromJson).toList();
      });

  /// Reads back the full row a write produced.
  ///
  /// The write functions return a compact summary, not the whole PaymentView, so
  /// this fetches the committed row through the view — which means the amounts
  /// come back as text like every other read, and the read is governed by RLS
  /// rather than by the definer's rights. The cost is a second round trip; the
  /// alternative was returning the view row from inside the SECURITY DEFINER
  /// function, which would have read it with RLS bypassed.
  Future<PaymentView> _readPayment(int paymentId) async {
    final dynamic row = await _db
        .from('v_payments')
        .select()
        .eq('id', paymentId)
        .single();
    return PaymentView.fromJson(_obj(row));
  }

  /// [bankName], [bankAccountName] and [bankAccountNo] describe the PAYER's
  /// account — the one the عديل transferred FROM — not the association's.
  ///
  /// They are typed with each collection rather than held as a setting, because
  /// a member may use more than one account and more than one bank, and which
  /// he used is a fact about this payment. The server keeps them only when the
  /// method is a transfer; a cash collection has no sending account.
  Future<PaymentView> registerPayment({
    required int adeelId,
    required String amount,
    required String method,
    String? reference,
    String? receiver,
    String? notes,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNo,
  }) => SupabaseFailures.guard(() async {
    final dynamic result = await _db.rpc<dynamic>(
      'register_payment',
      params: <String, dynamic>{
        'p_adeel_id': adeelId,
        // Sent as a STRING and cast by Postgres. Serialising it as a JSON number
        // would route the amount through a double on the way out, which is the
        // same mistake in the other direction.
        'p_amount': amount,
        'p_method': method,
        'p_reference': (reference?.isEmpty ?? true) ? null : reference,
        'p_receiver': (receiver?.isEmpty ?? true) ? null : receiver,
        'p_notes': (notes?.isEmpty ?? true) ? null : notes,
        'p_bank_name': (bankName?.isEmpty ?? true) ? null : bankName,
        'p_bank_account_name': (bankAccountName?.isEmpty ?? true)
            ? null
            : bankAccountName,
        'p_bank_account_no': (bankAccountNo?.isEmpty ?? true)
            ? null
            : bankAccountNo,
      },
    );
    return _readPayment((_obj(result)['paymentId'] as num).toInt());
  });

  Future<PaymentView> cancelPayment({
    required int paymentId,
    required String reason,
  }) => SupabaseFailures.guard(() async {
    await _db.rpc<dynamic>(
      'cancel_payment',
      params: <String, dynamic>{'p_payment_id': paymentId, 'p_reason': reason},
    );
    // The row survives cancellation — rule 9 reverses the money and keeps
    // everything — so it is still there to read back.
    return _readPayment(paymentId);
  });

  Future<CashSummaryView> cashSummary() => SupabaseFailures.guard(() async {
    final dynamic row = await _db.from('v_cash_summary').select().single();
    return CashSummaryView.fromJson(_obj(row));
  });

  Future<List<CashMovementView>> cashMovements() =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_cash_movements')
            .select()
            .order('occurredAt', ascending: false);
        return _rows(rows).map(CashMovementView.fromJson).toList();
      });

  Future<GenerateResultView> generatePeriod(String period) =>
      SupabaseFailures.guard(() async {
        final dynamic result = await _db.rpc<dynamic>(
          'generate_period',
          params: <String, dynamic>{'p_period': period},
        );
        return GenerateResultView.fromJson(_obj(result));
      });

  Future<int> autoClose() => SupabaseFailures.guard(() async {
    final dynamic result = await _db.rpc<dynamic>('auto_close_periods');
    return (_obj(result)['created'] as num).toInt();
  });

  /// Every month the association may close, newest first.
  ///
  /// The range starts at `system_start` — a setting, not a calendar fact — and
  /// stops at LAST month, because the current one is not closed until it ends.
  /// Only the database knows both, which is why this is a call rather than a
  /// date picker built on the client.
  Future<List<ClosablePeriod>> closablePeriods() =>
      SupabaseFailures.guard(() async {
        final dynamic payload = await _db.rpc<dynamic>('api_closable_periods');
        return (payload as List<dynamic>)
            .map((dynamic e) => ClosablePeriod.fromJson(_obj(e)))
            .toList();
      });

  // ── Money OUT ──────────────────────────────────────────────────────────────
  // Reads through views, writes through RPCs, exactly like the collection side.
  // The two RPCs are admin-gated in their own bodies, and register_disbursement
  // additionally refuses to spend past the treasury balance — rule 7 read
  // backwards, and the reason the fund cannot be overdrawn from a phone.

  Future<List<DisbursementView>> disbursements() =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db
            .from('v_disbursements')
            .select()
            .order('spentAt', ascending: false);
        return _rows(rows).map(DisbursementView.fromJson).toList();
      });

  Future<List<ExpenseByCategory>> expenseByCategory() =>
      SupabaseFailures.guard(() async {
        final dynamic rows = await _db.from('v_expense_by_category').select();
        return _rows(rows).map(ExpenseByCategory.fromJson).toList();
      });

  /// Records a voucher and takes the money out of the treasury.
  ///
  /// `amount` is a STRING for the same reason every other amount is: sending it
  /// as a JSON number would route the association's money through a double on
  /// the way out.
  Future<Map<String, dynamic>> registerDisbursement({
    required String amount,
    required String category,
    required String payeeName,
    required String method,
    int? payeeAdeelId,
    String? reference,
    String? bankName,
    String? bankAccountName,
    String? bankAccountNo,
    String? handedBy,
    String? note,
    String? spentAt,
  }) => SupabaseFailures.guard(() async {
    final dynamic payload = await _db.rpc<dynamic>(
      'register_disbursement',
      params: <String, dynamic>{
        'p_amount': amount,
        'p_category': category,
        'p_payee_name': payeeName,
        'p_method': method,
        'p_payee_adeel_id': payeeAdeelId,
        'p_reference': (reference?.isEmpty ?? true) ? null : reference,
        'p_bank_name': (bankName?.isEmpty ?? true) ? null : bankName,
        'p_bank_account_name': (bankAccountName?.isEmpty ?? true)
            ? null
            : bankAccountName,
        'p_bank_account_no': (bankAccountNo?.isEmpty ?? true)
            ? null
            : bankAccountNo,
        'p_handed_by': (handedBy?.isEmpty ?? true) ? null : handedBy,
        'p_note': (note?.isEmpty ?? true) ? null : note,
        'p_spent_at': (spentAt?.isEmpty ?? true) ? null : spentAt,
      },
    );
    return _obj(payload);
  });

  /// Rule 9 in the outgoing direction: the voucher stays, struck through, and
  /// the money returns to the treasury because every total filters on status.
  Future<void> cancelDisbursement(int id, String reason) =>
      SupabaseFailures.guard(() async {
        await _db.rpc<dynamic>(
          'cancel_disbursement',
          params: <String, dynamic>{'p_id': id, 'p_reason': reason},
        );
      });
}
