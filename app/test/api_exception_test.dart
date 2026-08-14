import 'package:family_app/core/network/api_exception.dart';
import 'package:family_app/core/supabase/supabase_failures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Error mapping, moved from Dio to Postgres.
///
/// This file used to test `ApiException.fromDio` against the Node API's
/// `{error: {code, message}}` envelope. There is no API and no Dio, but the thing
/// that test was protecting is unchanged and now MORE load-bearing: the UI decides
/// what to show from `kind`, `statusCode` and `serverMessage`, and those now have
/// to be reconstructed from a raw Postgres error instead of read out of a field
/// the server filled in.
///
/// The mapping that matters most is RUL00 → 403. `require_role()` raises it, and
/// the router's guard plus `describeApiFailure` both branch on `isForbidden`. Map
/// it wrong and every permission refusal in the app renders as an unexplained
/// failure instead of "you do not have permission".
Future<ApiException> _capture(Object error) async {
  try {
    await SupabaseFailures.guard<void>(() async => throw error);
  } on ApiException catch (mapped) {
    return mapped;
  }
  fail('guard did not throw an ApiException for $error');
}

PostgrestException _pg(String code, [String message = 'boom']) =>
    PostgrestException(message: message, code: code);

void main() {
  group('rule violations become the status the UI expects', () {
    test('RUL00 (require_role) is a 403, so isForbidden is true', () async {
      final ApiException e = await _capture(
        _pg('RUL00', 'FORBIDDEN: requires treasurer or higher'),
      );
      expect(e.statusCode, 403);
      expect(e.isForbidden, isTrue);
      expect(e.kind, ApiFailureKind.server);
      expect(e.code, 'RUL00');
    });

    test('RUL07 (payment bounds) is a 422, not a conflict', () async {
      // Paying more than is owed is a bad request the user can correct, not a
      // clash with another writer.
      final ApiException e = await _capture(
        _pg('RUL07', 'Rule 7: amount 80.01 exceeds outstanding balance 80.00'),
      );
      expect(e.statusCode, 422);
      expect(e.isForbidden, isFalse);
    });

    test('RUL05 (immutable snapshot) is a 409', () async {
      final ApiException e = await _capture(_pg('RUL05'));
      expect(e.statusCode, 409);
    });

    test('RUL09 (no hard delete) is a 409', () async {
      expect((await _capture(_pg('RUL09'))).statusCode, 409);
    });

    test('RUL12 (append-only audit) is a 409', () async {
      expect((await _capture(_pg('RUL12'))).statusCode, 409);
    });
  });

  group('the Arabic message reaches the user, the English one does not', () {
    test("a rule's own message is passed through for display", () async {
      const String arabic = 'تاريخ الميلاد لا يمكن أن يكون مستقبلياً';
      final ApiException e = await _capture(_pg('RUL10', arabic));
      expect(e.serverMessage, arabic);
    });

    test('a raw constraint message is withheld', () async {
      // "duplicate key value violates unique constraint
      // uq_members_national_id" must never reach a treasurer's screen; the UI
      // substitutes a localised string when serverMessage is null.
      final ApiException e = await _capture(
        _pg(
          '23505',
          'duplicate key value violates unique constraint '
              '"uq_members_national_id"',
        ),
      );
      expect(e.statusCode, 409);
      expect(
        e.serverMessage,
        isNull,
        reason: 'only RULnn codes carry text meant for a user',
      );
    });
  });

  group("Postgres's own constraint classes", () {
    test('23505 unique_violation is a 409', () async {
      expect((await _capture(_pg('23505'))).statusCode, 409);
    });

    test('23514 check_violation is a 422', () async {
      // ck_recv_paid and ck_pay_amount — the storage-engine backstops.
      expect((await _capture(_pg('23514'))).statusCode, 422);
    });

    test('22003 numeric overflow is a 422', () async {
      expect((await _capture(_pg('22003'))).statusCode, 422);
    });

    test('42501 insufficient_privilege reads as unauthenticated', () async {
      // For a client holding only the anon key this means "not signed in" far
      // more often than "signed in but not allowed", and the router's guard has
      // to send them to sign-in rather than to a permission screen.
      final ApiException e = await _capture(_pg('42501'));
      expect(e.statusCode, 401);
      expect(e.isUnauthorized, isTrue);
    });

    test('an unrecognised code becomes a 500, not a silent success', () async {
      expect((await _capture(_pg('XX000'))).statusCode, 500);
    });
  });

  group('transport and auth', () {
    test('an expired JWT is a 401', () async {
      expect((await _capture(_pg('PGRST301'))).statusCode, 401);
    });

    test('an AuthException maps to a server failure with its code', () async {
      final ApiException e = await _capture(
        const AuthException('Invalid login credentials', statusCode: '400'),
      );
      expect(e.kind, ApiFailureKind.server);
      expect(e.statusCode, 400);
      expect(
        e.serverMessage,
        isNull,
        reason: "GoTrue's messages are English and aimed at developers",
      );
    });

    test('an already-mapped ApiException is not wrapped twice', () async {
      final ApiException e = await _capture(
        const ApiException(
          kind: ApiFailureKind.timeout,
          code: 'ALREADY_MAPPED',
        ),
      );
      expect(e.kind, ApiFailureKind.timeout);
      expect(e.code, 'ALREADY_MAPPED');
    });

    test('an unknown failure is not reported as a server error', () async {
      // A bug in the app is not the database refusing something. Reporting it as
      // ApiFailureKind.server would put a "the server said no" message in front
      // of the user for what is actually a client crash.
      final ApiException e = await _capture(StateError('client bug'));
      expect(e.kind, ApiFailureKind.unknown);
    });
  });
}
