import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../l10n/app_localizations.dart';
import '../data/ice_probe.dart';
import 'providers.dart';

/// «فحص مسار الاتصال» — يجيب عن سؤال يحتاج عادةً جهازين، بجهاز واحد.
///
/// ⚠ THE QUESTION IT ANSWERS IS «هل تنجح المكالمة بين شبكتين مختلفتين»,
///   and it is not answerable by reading code: it depends on two carriers,
///   their NAT, and whether a borrowed public relay is alive this week.
///
/// ⚠ AND IT SEPARATES FOUR FAILURES THAT OTHERWISE LOOK IDENTICAL. «الاتصال لا
///   يعمل» can be an unapplied patch, a wrong policy, a dead relay or a real
///   bug — and each has a different fix. Three lines on this sheet say which,
///   in ten seconds, without another person's phone.
Future<void> showIceCheck(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext _) => const _IceSheet(),
    );

class _IceSheet extends ConsumerStatefulWidget {
  const _IceSheet();

  @override
  ConsumerState<_IceSheet> createState() => _IceSheetState();
}

class _IceSheetState extends ConsumerState<_IceSheet> {
  IceReport? _report;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _report = null;
    });
    try {
      final List<Map<String, dynamic>> ice = await ref
          .read(callRepositoryProvider)
          .iceServers();
      final IceReport r = await probeIce(ice);
      if (!mounted) return;
      setState(() {
        _report = r;
        _busy = false;
      });
    } on Object {
      if (!mounted) return;
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final IceReport? r = _report;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: GlassCard(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                l.iceCheck,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_busy) ...<Widget>[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: AppSpacing.md),
                Text(
                  l.iceRunning,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                  ),
                ),
              ] else if (r != null) ...<Widget>[
                _Line(label: l.iceHost, ok: r.host),
                _Line(label: l.iceStun, ok: r.srflx),
                // ⚠ THE ONE THAT DECIDES THE HARD CASE. Two subscribers on
                //   Libyan mobile data are both behind carrier-grade NAT and
                //   cannot reach each other whatever STUN says — the audio has
                //   to travel through a relay. No relay here means calls work
                //   on wifi and fail on mobile, which is the exact symptom
                //   that is otherwise impossible to name.
                _Line(label: l.iceRelay, ok: r.relay),
                const SizedBox(height: AppSpacing.lg),

                Text(
                  !r.host
                      ? l.iceNone
                      : r.relay
                      ? l.iceGood
                      : l.iceWifiOnly,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: !r.host
                        ? AppColors.danger
                        : r.relay
                        ? AppColors.success
                        : AppColors.warning,
                  ),
                ),

                // The sentence that makes the amber case actionable rather
                // than merely disappointing.
                if (r.host && !r.relay) ...<Widget>[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    l.iceRelayNote,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.muted,
                      height: 1.5,
                    ),
                  ),
                ],
              ],

              const SizedBox(height: AppSpacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _run,
                      child: Text(l.retry),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l.close),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: <Widget>[
        // ⚠ AN ICON AND A COLOUR, NOT A COLOUR ALONE — the same rule the status
        //   palette follows everywhere else in this app.
        Icon(
          ok ? Icons.check_circle : Icons.cancel,
          size: 18,
          color: ok ? AppColors.success : AppColors.danger,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
      ],
    ),
  );
}
