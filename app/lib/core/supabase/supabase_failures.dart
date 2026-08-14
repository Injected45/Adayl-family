import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../network/api_exception.dart';

/// Translates Postgres and GoTrue failures into the app's [ApiException].
///
/// This is where the Node API's error envelope goes. Every route used to answer
/// with `{error: {code, message}}` where `message` was display-ready Arabic, and
/// the UI showed it verbatim. With no API tier, that envelope has to be
/// reconstructed from what Postgres raises.
///
/// It reconstructs cleanly because the schema was built for it: each business rule
/// raises its own SQLSTATE (`RUL01`…`RUL12`) with an Arabic MESSAGE_TEXT, so
/// PostgrestException.code carries the rule and .message carries the sentence.
/// That was not an accident — it is the reason the rules use custom SQLSTATEs
/// instead of a generic `raise_exception`.
abstract final class SupabaseFailures {
  /// Wraps a call so no repository ever leaks a `PostgrestException`.
  static Future<T> guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      throw _fromPostgrest(error);
    } on AuthException catch (error) {
      throw _fromAuth(error);
    } on SocketException {
      throw const ApiException(kind: ApiFailureKind.network);
    } on TimeoutException {
      throw const ApiException(kind: ApiFailureKind.timeout);
    } on ApiException {
      // Already mapped by a nested guard; do not wrap it twice.
      rethrow;
    } on Object catch (error) {
      // Anything else is a transport failure from the http package underneath —
      // DNS, refused connection, TLS. Catching `ClientException` by name would
      // mean taking a direct dependency on package:http just to name the type.
      final String text = error.toString();
      final bool looksLikeTransport =
          text.contains('ClientException') ||
          text.contains('Failed host lookup') ||
          text.contains('Connection');
      throw ApiException(
        kind: looksLikeTransport
            ? ApiFailureKind.network
            : ApiFailureKind.unknown,
        details: error,
      );
    }
  }

  /// Codes the storage layer raises, mapped to what the UI already understands.
  ///
  /// `RUL00` is the authorisation refusal from `require_role()`. It has to become
  /// a 403, because the router's guard and `describeApiFailure` both branch on
  /// `isForbidden` — a role refusal that arrived as a generic server error would
  /// render as an unexplained failure instead of "you do not have permission".
  static const Map<String, int> _statusForRule = <String, int>{
    'RUL00': 403, // require_role / self-elevation / last-admin guard
    'RUL04': 409, // one live receivable per (family, period)
    'RUL05': 409, // receivable snapshots are immutable
    'RUL07': 422, // payment bounds — a bad request, not a conflict
    'RUL09': 409, // cancellation and no-delete guards
    'RUL10': 422, // national id / date of birth
    'RUL12': 409, // audit log is append-only
    'RUL13': 422, // purge confirmation phrase did not match
  };

  static ApiException _fromPostgrest(PostgrestException error) {
    final String? code = error.code;

    // Postgres's own classes, for the constraints that are not custom-coded.
    final int status = switch (code) {
      final String c when _statusForRule.containsKey(c) => _statusForRule[c]!,
      '23505' =>
        409, // unique_violation — duplicate national id, period, receipt
      '23514' => 422, // check_violation  — paid <= total, amount > 0
      '23503' => 409, // foreign_key_violation
      '22003' => 422, // numeric_value_out_of_range
      // PostgREST's own: 42501 is insufficient_privilege, which for a client
      // holding only the anon key means "not signed in" far more often than it
      // means "signed in but not allowed".
      '42501' => 401,
      'PGRST301' => 401, // JWT expired
      'PGRST302' => 401, // no JWT
      _ => 500,
    };

    return ApiException(
      kind: ApiFailureKind.server,
      code: code,
      // The message is already Arabic for every RULnn, because the trigger and
      // function bodies raise it that way. Postgres's own constraint messages are
      // English, and `describeApiFailure` falls back to a localised string when
      // it does not recognise the code.
      serverMessage: _isDisplayable(code) ? error.message : null,
      statusCode: status,
      details: error.details,
    );
  }

  /// Only the app's own rule violations carry text meant for a user. A raw
  /// `duplicate key value violates unique constraint "uq_members_national_id"`
  /// must never reach a treasurer's screen.
  static bool _isDisplayable(String? code) =>
      code != null && code.startsWith('RUL');

  static ApiException _fromAuth(AuthException error) {
    final int status = switch (error.statusCode) {
      final String s => int.tryParse(s) ?? 401,
      _ => 401,
    };
    return ApiException(
      kind: ApiFailureKind.server,
      code: error.code ?? 'AUTH_ERROR',
      statusCode: status,
      // GoTrue's messages are English and aimed at developers
      // ("Invalid login credentials"), so the UI localises instead.
      details: error.message,
    );
  }
}
