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

  Future<List<PaymentView>> payments({int? familyId}) =>
      SupabaseFailures.guard(() async {
        final PostgrestFilterBuilder<dynamic> base = _db
            .from('v_payments')
            .select();
        final dynamic rows = familyId == null
            ? await base.order('paidAt', ascending: false)
            : await base
                  .eq('familyId', familyId)
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

  Future<PaymentView> registerPayment({
    required int familyId,
    required String amount,
    required String method,
    String? reference,
    String? receiver,
    String? notes,
  }) => SupabaseFailures.guard(() async {
    final dynamic result = await _db.rpc<dynamic>(
      'register_payment',
      params: <String, dynamic>{
        'p_family_id': familyId,
        // Sent as a STRING and cast by Postgres. Serialising it as a JSON number
        // would route the amount through a double on the way out, which is the
        // same mistake in the other direction.
        'p_amount': amount,
        'p_method': method,
        'p_reference': (reference?.isEmpty ?? true) ? null : reference,
        'p_receiver': (receiver?.isEmpty ?? true) ? null : receiver,
        'p_notes': (notes?.isEmpty ?? true) ? null : notes,
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
}
