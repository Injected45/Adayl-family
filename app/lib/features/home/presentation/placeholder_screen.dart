import 'package:flutter/material.dart';

import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';

/// Stands in for a screen whose phase has not landed yet.
///
/// The routes exist from Phase 3 so navigation and the role guard are real and
/// testable — a screen that is merely unbuilt behaves very differently from one
/// that is forbidden, and both need to work correctly.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({required this.destination, super.key});

  final AppDestination destination;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return AppScaffold(
      title: destination.label(l),
      currentRoute: destination.route,
      body: EmptyStateView(
        icon: destination.icon,
        title: l.comingSoon,
        message: l.comingSoonBody,
      ),
    );
  }
}
