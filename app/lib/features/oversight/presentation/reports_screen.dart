import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/router/destinations.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/stat_card.dart';
import '../../../core/widgets/state_views.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'providers.dart';

String _iso(DateTime date) => date.toIso8601String().substring(0, 10);

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final L l = L.of(context);
    final ReportRange range = ref.watch(reportRangeProvider);
    final AsyncValue<FinancialReport> report = ref.watch(reportProvider(range));

    Future<void> pick({required bool isFrom}) async {
      final DateTime initial =
          DateTime.tryParse(isFrom ? range.from : range.to) ?? DateTime.now();
      final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
      );
      if (picked == null) return;
      ref.read(reportRangeProvider.notifier).state = isFrom
          ? (from: _iso(picked), to: range.to)
          : (from: range.from, to: _iso(picked));
    }

    void preset(ReportRange next) {
      ref.read(reportRangeProvider.notifier).state = next;
    }

    final DateTime now = DateTime.now();

    return AppScaffold(
      title: l.navReports,
      currentRoute: AppRoutes.reports,
      body: AsyncView<FinancialReport>(
        value: report,
        onRetry: () => ref.invalidate(reportProvider(range)),
        builder: (FinancialReport data) => ListView(
          padding: screenPadding(context),
          children: <Widget>[
            Text(
              l.reportsIntro,
              style: const TextStyle(fontSize: 12, color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.md),

            Row(
              children: <Widget>[
                Expanded(
                  child: _DateField(
                    label: l.fromDate,
                    value: range.from,
                    onTap: () => pick(isFrom: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _DateField(
                    label: l.toDate,
                    value: range.to,
                    onTap: () => pick(isFrom: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),

            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  ActionChip(
                    label: Text(l.presetThisMonth),
                    onPressed: () => preset((
                      from: _iso(DateTime(now.year, now.month)),
                      to: _iso(now),
                    )),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ActionChip(
                    label: Text(l.presetLastMonth),
                    onPressed: () => preset((
                      from: _iso(DateTime(now.year, now.month - 1)),
                      to: _iso(DateTime(now.year, now.month, 0)),
                    )),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  ActionChip(
                    label: Text(l.presetThisYear),
                    onPressed: () =>
                        preset((from: '${now.year}-01-01', to: _iso(now))),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            StatCardGrid(
              children: <Widget>[
                _Stat(
                  label: l.issuedTotal,
                  value: formatMoney(data.issued),
                  sub: l.issuedCount(data.issuedCount),
                ),
                _Stat(
                  label: l.collectedTotal,
                  value: formatMoney(data.collected),
                  sub: l.collectedCount(data.collectedCount),
                  tone: AppColors.success,
                ),
                _Stat(
                  label: l.outstandingTotal,
                  value: formatMoney(data.debt),
                  tone: AppColors.danger,
                ),
                _Stat(
                  label: l.partiallyPaidCount,
                  value: '${data.partialCount}',
                  sub: l.openPartially,
                  tone: AppColors.warning,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            Text(
              l.collectionDetail,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (data.payments.isEmpty)
              EmptyStateView(
                icon: Icons.bar_chart_outlined,
                title: l.noReportRows,
              )
            else
              for (final ReportPaymentRow row in data.payments)
                Card(
                  margin: const EdgeInsetsDirectional.only(
                    bottom: AppSpacing.sm,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                row.familyName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${formatDate(row.paidAt)} • ${row.method}'
                                '${row.reference.isEmpty ? '' : ' • ${row.reference}'}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          formatMoney(row.amount),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: AppColors.success,
                          ),
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.control),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today, size: 16),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.sub, this.tone});

  final String label;
  final String value;
  final String? sub;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final Color accent = tone ?? AppColors.brand;
    return GlassCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Flat Design's way of carrying meaning: a solid saturated bar,
              // no gradient, no shadow. It also encodes the tone for anyone who
              // cannot distinguish the value's colour, so hue is not the only
              // signal.
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                fontFamily: AppFonts.display,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: tone ?? AppColors.ink,
              ),
            ),
          ),
          if (sub != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              sub!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}
