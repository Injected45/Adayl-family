import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../device/device_identity.dart';
import 'secure_local_storage.dart';
import 'supabase_config.dart';

/// Brings up Supabase. Called once, from main(), before runApp.
///
/// Returns false when [SupabaseConfig] is incomplete instead of throwing. A
/// missing --dart-define is a build mistake, and the useful response is an app
/// that starts and explains itself on the sign-in screen rather than a red screen
/// with an initialisation stack trace.
Future<bool> initialiseSupabase() async {
  if (!SupabaseConfig.isConfigured) return false;

  await Supabase.initialize(
    url: SupabaseConfig.url,
    // ── The handset, on EVERY request ────────────────────────────────────────
    // `my_adeel_id()` reads `x-device-id` out of PostgREST's request.headers and
    // refuses to answer when it does not match the device the عديل's access code
    // was redeemed on. Setting it here rather than per call is the point: the
    // rule is enforced by a clause inside an RLS-facing function, so it has to
    // arrive with every read the client makes, including ones nobody remembers
    // to thread it through.
    //
    // Resolved BEFORE initialize because these headers are fixed at client
    // construction. It is a hash, it never throws, and it costs one platform
    // call at startup.
    headers: <String, String>{'x-device-id': await DeviceIdentity.resolve()},
    // `publishableKey`, not the deprecated `anonKey`. Supabase renamed the
    // concept; the parameter accepts either the legacy JWT anon key or a new
    // sb_publishable_… key, so the --dart-define keeps its familiar name.
    publishableKey: SupabaseConfig.anonKey,
    // The refresh token goes to the platform keystore, not SharedPreferences.
    // See SecureLocalStorage for why that matters.
    authOptions: FlutterAuthClientOptions(
      localStorage: SecureLocalStorage(),
      authFlowType: AuthFlowType.pkce,
    ),
    // Realtime is not used. The screens are pull-to-refresh and provider
    // invalidation, and an open websocket per client would be cost and battery
    // for a treasury app that is consulted a few times a day.
    // ── جرس الباب، ولا خانق له ─────────────────────────────────────────────
    // ⚠ `eventsPerSecond: 1` USED TO SIT HERE AND IT WAS REMOVED, NOT RAISED.
    //   It reads like a rate limit and is not one: in this client the field is
    //   declared on the options class and READ BY NOTHING — the analyzer marks
    //   it deprecated with «client side rate limit has been removed, this
    //   option will be ignored», and grepping the package confirms it.
    //
    // ⚠ I RAISED IT TO 10 FIRST, AND WROTE A PARAGRAPH EXPLAINING THAT 1 WOULD
    //   HAVE CAPPED THE DOORBELL AT ONE RING A SECOND. That was wrong, and it
    //   is recorded rather than quietly deleted: an inert setting with a
    //   confident comment beside it is worse than no setting, because the next
    //   person to hunt a dropped ring starts here and loses an evening.
    //
    //   Whatever limits the bell, it is not this. If rings are ever dropped,
    //   look at the SERVER-side Realtime quota on the project, not here.
    debug: SupabaseConfig.verbose,
  );
  return true;
}

/// The client. Every repository takes this rather than reaching for the
/// `Supabase.instance` singleton, so tests can inject one.
final Provider<SupabaseClient> supabaseClientProvider =
    Provider<SupabaseClient>((Ref ref) {
      if (!SupabaseConfig.isConfigured) {
        // Reached only if a screen queries before the sign-in screen has shown
        // the misconfiguration notice. Failing here with the same sentence is
        // better than a null dereference three frames deeper.
        throw StateError(SupabaseConfig.misconfigurationHint);
      }
      return Supabase.instance.client;
    });

/// Whether the build carries usable Supabase credentials. Watched by the sign-in
/// screen so it can say so.
final Provider<bool> supabaseConfiguredProvider = Provider<bool>(
  (Ref ref) => SupabaseConfig.isConfigured,
);
