/// Why a request failed, at a level the UI can act on.
enum ApiFailureKind {
  /// The server could not be reached at all.
  network,

  /// The server was reached but took too long.
  timeout,

  /// The server answered with an error envelope.
  server,

  /// The database does not have the table or function this build calls.
  ///
  /// Its own kind because it is the ONE failure that will never fix itself:
  /// network and timeout say "try again", and this one means the project is
  /// running a different schema from the app. Reporting it as a generic error
  /// sends someone to wait for something that is never going to change — which
  /// is exactly what happened when the register was rewritten around the عديل
  /// and a project still holding the family/member schema answered every save
  /// with "حدث خطأ غير متوقع".
  schemaMismatch,

  /// Something unforeseen.
  unknown,
}

/// A failed API call.
///
/// The server sends a display-ready Arabic `message` with every error, so for
/// [ApiFailureKind.server] the UI shows that text verbatim rather than mapping
/// a status code to a guess. For transport failures there is no server message,
/// and the UI substitutes a localised string.
class ApiException implements Exception {
  const ApiException({
    required this.kind,
    this.code,
    this.serverMessage,
    this.statusCode,
    this.details,
  });

  final ApiFailureKind kind;

  /// The server's machine-readable code, e.g. `ACCOUNT_PENDING`.
  final String? code;

  /// The server's Arabic message, ready to display.
  final String? serverMessage;

  final int? statusCode;
  final Object? details;

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;

  /// Built by SupabaseFailures, which maps PostgrestException and AuthException
  /// onto this type. The `fromDio` factory that used to live here went with the
  /// HTTP layer — there is no Dio, and no REST API for it to talk to.
  @override
  String toString() =>
      'ApiException(${kind.name}, code: $code, status: $statusCode)';
}
