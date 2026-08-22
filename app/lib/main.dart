import 'package:flutter/material.dart';

import 'app.dart';
import 'core/notify/notify_text.dart';
import 'core/state/restart.dart';
import 'core/supabase/supabase_client_provider.dart';
import 'l10n/app_localizations_ar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before runApp, because the router's redirect guard asks for the current
  // session on the very first frame. Returns false rather than throwing when the
  // --dart-define values are missing: the sign-in screen then says what is wrong,
  // which is more use to whoever built the binary than a startup crash.
  await initialiseSupabase();

  // ── كلمات الإشعارات، قبل أول إطار ──────────────────────────────────────
  // ⚠ BEFORE runApp, not from a widget. The foreground service can start
  //   from the auth controller before anything has built, and an Android
  //   notification CHANNEL keeps the name it was created with — re-creating
  //   it with a better one does nothing. An empty channel name in the
  //   phone's settings would be permanent.
  //
  //   LAr directly, because this app forces the `ar` locale — there is no
  //   other answer to ask for, and the strings are still the ARB's.
  NotifyText.fill(LAr());

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
