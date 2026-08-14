import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

class OfficialsScreen extends ConsumerWidget {
  const OfficialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final AsyncValue<List<Official>> officials = ref.watch(officialsProvider);

    return AppScaffold(
      title: l.navOfficials,
      currentRoute: AppRoutes.officials,
      body: AsyncView<List<Official>>(
        value: officials,
        onRetry: () => ref.invalidate(officialsProvider),
        builder: (List<Official> people) => ListView(
          padding: screenPadding(context),
          children: <Widget>[
            Text(
              l.officialsIntro,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final Official official in people)
              Card(
                margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        official.role,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Wrap(
                        spacing: AppSpacing.xl,
                        runSpacing: AppSpacing.md,
                        children: <Widget>[
                          LabelledValue(
                            label: l.navOfficials,
                            value: official.name.isEmpty
                                ? l.notAssigned
                                : official.name,
                          ),
                          LabelledValue(
                            label: l.nationalId,
                            value: official.nationalId,
                          ),
                          LabelledValue(label: l.phone, value: official.phone),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
