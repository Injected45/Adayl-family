import 'package:flutter/material.dart';

import 'app.dart';
import 'core/state/restart.dart';
import 'core/supabase/supabase_client_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before runApp, because the router's redirect guard asks for the current
  // session on the very first frame. Returns false rather than throwing when the
  // --dart-define values are missing: the sign-in screen then says what is wrong,
  // which is more use to whoever built the binary than a startup crash.
  await initialiseSupabase();

  // RestartWidget OWNS the ProviderScope rather than sitting inside one, which
  // is what lets the in-app restart button dispose every provider and mount a
  // fresh set. A scope out here would outlive the restart and hand the rebuilt
  // tree the same cached state it was trying to discard.
  //
  // initialiseSupabase() stays outside it: the Supabase client is a process-wide
  // singleton holding the session, and tearing it down would sign the user out —
  // which is a different act from restarting the app.
  runApp(const RestartWidget(child: FamilyApp()));
}
