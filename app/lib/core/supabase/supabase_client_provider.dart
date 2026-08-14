import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    realtimeClientOptions: const RealtimeClientOptions(eventsPerSecond: 1),
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
