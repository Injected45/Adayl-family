import 'package:flutter/material.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/format/formatters.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/async_view.dart';
import '../../../core/widgets/idle_auto_close.dart';
import '../../../l10n/app_localizations.dart';
import '../domain/models.dart';
import 'notifications_screen.dart' show NoticeTile;

/// تفاصيل الإشعار — the whole notice, on the whole screen, to be read.
///
/// «عند الضغط عليه يظهر تفاصيل الاشعار ومابداخله ليفتح في شاشة الهاتف ليتم
/// قرائته ويرجع كما كان بعدة فتره 30 ثانية اذا ترك ساكن. او ارجاعه فورا من
/// قبل المشترك ان اراد ذلك».
///
/// Three doors lead here and they open the same page: a row on the tab, the
/// app's own banner, and a tap on the phone's notification.
///
/// ── THE THIRTY SECONDS ──────────────────────────────────────────────────────
/// [idleFor], counted by [IdleAutoClose] from the last touch — the same clock
/// a proposal's page uses. «رجوع» and the close button go back at once.
///
/// ⚠ NOTHING HERE IS A FIGURE. The body is the sentence the database wrote,
///   printed as it came; no amount is parsed out of it or added to anything.
class NoticeDetailScreen extends StatelessWidget {
  const NoticeDetailScreen({
    required this.notice,
    this.staff = false,
    super.key,
  });

  final AppNotice notice;

  /// The admin's copy also says whom it went to.
  final bool staff;

  static const Duration idleFor = Duration(seconds: 30);

  /// A full-screen page — the close button in its bar, not a back arrow.
  static Route<void> route(AppNotice notice, {bool staff = false}) =>
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => NoticeDetailScreen(notice: notice, staff: staff),
      );

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final AppNotice n = notice;
    final (IconData icon, Color tone) = NoticeTile.look(n.kind);

    final String who = n.toEveryone
        ? l.noticeToEveryone
        : <String?>[
            n.adeelCode,
            n.adeelName,
          ].whereType<String>().where((String s) => s.isNotEmpty).join(' · ');

    return IdleAutoClose(
      idleFor: idleFor,
      child: AppBackground(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(title: Text(l.noticeDetailTitle)),
          body: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.xl + bottomInset(context),
            ),
            children: <Widget>[
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: tone.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(
                              AppRadius.control,
                            ),
                          ),
                          child: Icon(icon, size: 24, color: tone),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            n.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Text(
                          formatDateTime(n.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        ),
                        if (staff && who.isNotEmpty)
                          StatusBadge(
                            label: who,
                            tone: n.toEveryone
                                ? AppColors.brand
                                : AppColors.inkMuted,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      n.body,
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.75,
                        color: AppColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // ⚠ ALONE, NEVER IN A ROW: an outlined button is full width in
              //   this theme and asserts inside one. See CLAUDE.md.
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(l.backAction),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
