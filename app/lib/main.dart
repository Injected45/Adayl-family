import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/supabase/supabase_client_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Before runApp, because the router's redirect guard asks for the current
  // session on the very first frame. Returns false rather than throwing when the
  // --dart-define values are missing: the sign-in screen then says what is wrong,
  // which is more use to whoever built the binary than a startup crash.
  await initialiseSupabase();

  runApp(const ProviderScope(child: FamilyApp()));
}
