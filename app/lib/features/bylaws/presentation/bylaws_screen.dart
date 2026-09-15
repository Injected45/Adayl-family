import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/glass.dart';
import '../../../core/config/theme.dart';
import '../../../core/router/destinations.dart';
import '../../../core/state/refresh.dart';
import '../../../core/widgets/app_background.dart';
import '../../../core/widgets/app_scaffold.dart';
import '../../../core/widgets/async_view.dart';
import '../../../l10n/app_localizations.dart';
import '../data/page_picker.dart';
import '../domain/models.dart';
import 'providers.dart';

/// قانون الجمعية — the association's contract, as photographs of its pages.
///
/// ── TWO READERS, ONE LIST ───────────────────────────────────────────────────
/// The ADMIN reaches it at `/bylaws` behind «المزيد»: a camera button, a
/// from-the-phone button, and every page with its number and a way to remove
/// it. A MEMBER reaches it by a push from his «المزيد»: the pages, and nothing
/// else — no number, no button, no sentence about what he may not do.
///
/// ⚠ «للعرض فقط» IS THE DATABASE'S, AND IT SAYS NOTHING. `add_bylaw_page` and
///   `delete_bylaw_page` call `require_role('admin')`; a member holds no write
///   on the table. So the member's screen has no controls to hide — it simply
///   was never given any — and prints no hint that there were.
///
/// ⚠ LAZY, PAGE BY PAGE. A contract can be twenty photographs. The list is a
///   builder, each page's bytes are fetched when its card is built, and each is
///   decoded at the width it is shown at rather than at 2000 pixels — twenty
///   full-size decodes at once is a phone out of memory.
class BylawsScreen extends ConsumerStatefulWidget {
  const BylawsScreen({this.manage = false, super.key});

  /// The admin's copy: the upload panel, page numbers and delete.
  final bool manage;

  @override
  ConsumerState<BylawsScreen> createState() => _BylawsScreenState();
}

class _BylawsScreenState extends ConsumerState<BylawsScreen> {
  /// (page being sent, how many) while an upload runs.
  (int, int)? _progress;

  Future<void> _add(Future<List<Uint8List>> Function(PagePicker) pick) async {
    final L l = L.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    List<Uint8List> picked;
    try {
      picked = await pick(ref.read(pagePickerProvider));
    } on Object {
      messenger.showSnackBar(SnackBar(content: Text(l.bylawsPickFailed)));
      return;
    }
    if (picked.isEmpty || !mounted) return;

    int added = 0;
    int refused = 0;
    String? failure;
    for (int i = 0; i < picked.length; i++) {
      if (mounted) setState(() => _progress = (i + 1, picked.length));
      final Uint8List bytes = picked[i];
      final String? mime = imageMimeOf(bytes);
      if (mime == null || bytes.length > bylawMaxBytes) {
        refused++;
        continue;
      }
      try {
        await ref.read(bylawsRepositoryProvider).add(bytes, mime);
        added++;
      } on Object catch (e) {
        failure = describeApiFailure(l, e);
        break;
      }
    }

    ref.invalidate(bylawPagesProvider);
    if (mounted) setState(() => _progress = null);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          failure ??
              (refused > 0
                  ? l.bylawsAddedSomeRefused(added, refused)
                  : l.bylawsAdded(added)),
        ),
      ),
    );
  }

  Future<void> _delete(BylawPage page, int number) async {
    final L l = L.of(context);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    final bool? sure = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => GlassDialog(
        destructive: true,
        icon: const Icon(Icons.delete_outline),
        title: Text(l.bylawsDeleteTitle(number)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l.bylawsDeleteConfirm),
          ),
        ],
      ),
    );
    if (sure != true) return;

    try {
      await ref.read(bylawsRepositoryProvider).delete(page.id);
      ref.invalidate(bylawPagesProvider);
      ref.invalidate(bylawImageProvider(page.id));
      messenger.showSnackBar(SnackBar(content: Text(l.bylawsDeleted)));
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeApiFailure(l, e))));
    }
  }

  void _open(BylawPage page) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => BylawViewer(pageId: page.id),
        ),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final L l = L.of(context);
    final int lead = widget.manage ? 1 : 0;

    return RefreshIndicator(
      onRefresh: () async => refreshAll(ref),
      child: AsyncView<List<BylawPage>>(
        value: ref.watch(bylawPagesProvider),
        onRetry: () => ref.invalidate(bylawPagesProvider),
        builder: (List<BylawPage> pages) => ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.xl + bottomInset(context),
          ),
          itemCount: lead + (pages.isEmpty ? 1 : pages.length),
          itemBuilder: (BuildContext context, int i) {
            if (widget.manage && i == 0) {
              return _UploadPanel(
                progress: _progress,
                onCamera: () => _add((PagePicker p) => p.camera()),
                onDevice: () => _add((PagePicker p) => p.device()),
              );
            }
            if (pages.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xl),
                child: _Empty(text: l.bylawsEmpty),
              );
            }
            final int index = i - lead;
            final BylawPage page = pages[index];
            return _PageCard(
              key: ValueKey<int>(page.id),
              page: page,
              number: index + 1,
              manage: widget.manage,
              onOpen: () => _open(page),
              onDelete: () => _delete(page, index + 1),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);

    if (widget.manage) {
      return AppScaffold(
        title: l.bylawsTitle,
        currentRoute: AppRoutes.bylaws,
        body: _list,
      );
    }

    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.bylawsTitle)),
        body: Builder(builder: _list),
      ),
    );
  }
}

class _UploadPanel extends StatelessWidget {
  const _UploadPanel({
    required this.progress,
    required this.onCamera,
    required this.onDevice,
  });

  final (int, int)? progress;
  final VoidCallback onCamera;
  final VoidCallback onDevice;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final (int, int)? p = progress;
    final bool busy = p != null;

    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ⚠ STACKED, NEVER SIDE BY SIDE: both buttons are full width in this
          //   theme and assert inside a Row. See CLAUDE.md.
          FilledButton.icon(
            onPressed: busy ? null : onCamera,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(l.bylawsCamera),
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: busy ? null : onDevice,
            icon: const Icon(Icons.photo_library_outlined),
            label: Text(l.bylawsFromDevice),
          ),
          if (p != null) ...<Widget>[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: (p.$1 - 1) / p.$2),
            const SizedBox(height: AppSpacing.xs),
            Text(
              l.bylawsUploading(p.$1, p.$2),
              style: TextStyle(fontSize: 12, color: AppColors.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// One page. For the admin, a heading with its number and a delete; for a
/// member, the image alone.
class _PageCard extends StatelessWidget {
  const _PageCard({
    required this.page,
    required this.number,
    required this.manage,
    required this.onOpen,
    required this.onDelete,
    super.key,
  });

  final BylawPage page;
  final int number;
  final bool manage;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    final BorderRadius corners = BorderRadius.circular(AppRadius.pane);

    return GlassCard(
      margin: const EdgeInsetsDirectional.only(bottom: AppSpacing.md),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (manage)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.xs,
                AppSpacing.xs,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      l.bylawsPageNumber(number),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l.bylawsDelete,
                    onPressed: onDelete,
                    icon: Icon(Icons.delete_outline, color: AppColors.danger),
                  ),
                ],
              ),
            ),
          ClipRRect(
            borderRadius: manage
                ? BorderRadius.only(
                    bottomLeft: corners.bottomLeft,
                    bottomRight: corners.bottomRight,
                  )
                : corners,
            child: BylawPageImage(pageId: page.id, onTap: onOpen),
          ),
        ],
      ),
    );
  }
}

/// A page's image at the width it is shown, or a quiet placeholder of an A4
/// page's shape while it loads.
class BylawPageImage extends ConsumerWidget {
  const BylawPageImage({
    required this.pageId,
    this.onTap,
    this.whole = false,
    super.key,
  });

  final int pageId;
  final VoidCallback? onTap;

  /// The viewer's page: the whole of it inside the box it is given, decoded
  /// sharper so pinching in still reads. Otherwise the list's page: the full
  /// width, as tall as it is.
  final bool whole;

  /// A4, portrait — the shape a page most likely has, so the list does not
  /// jump when the picture lands.
  static const double placeholderAspect = 1 / 1.414;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Uint8List> image = ref.watch(bylawImageProvider(pageId));

    Widget placeholder(Widget child) => AspectRatio(
      aspectRatio: placeholderAspect,
      child: ColoredBox(
        color: GlassColors.well,
        child: Center(child: child),
      ),
    );

    final Widget body = image.when(
      loading: () => placeholder(
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
      error: (Object _, StackTrace _) => placeholder(
        IconButton(
          onPressed: () => ref.invalidate(bylawImageProvider(pageId)),
          icon: Icon(Icons.refresh, color: AppColors.muted),
        ),
      ),
      data: (Uint8List bytes) => bytes.isEmpty
          ? placeholder(
              Icon(Icons.image_not_supported_outlined, color: AppColors.muted),
            )
          : LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                final double dpr = MediaQuery.devicePixelRatioOf(context);
                final int decodeWidth = math.max(
                  1,
                  math.min(
                    whole ? 4000 : 2000,
                    (box.maxWidth * dpr * (whole ? 2.5 : 1)).round(),
                  ),
                );
                return Image.memory(
                  bytes,
                  width: box.maxWidth,
                  height: whole ? box.maxHeight : null,
                  fit: whole ? BoxFit.contain : BoxFit.fitWidth,
                  cacheWidth: decodeWidth,
                  gaplessPlayback: true,
                  // ⚠ THE PLACEHOLDER HOLDS UNTIL THE FIRST FRAME. The bytes
                  //   arrive before the picture is decoded, and an Image with
                  //   no frame yet is zero pixels tall — the card collapsed to
                  //   its heading and then jumped open under the reader.
                  frameBuilder:
                      (
                        BuildContext _,
                        Widget child,
                        int? frame,
                        bool loadedAtOnce,
                      ) => frame == null && !loadedAtOnce
                      ? placeholder(const SizedBox.shrink())
                      : child,
                  errorBuilder: (BuildContext _, Object _, StackTrace? _) =>
                      placeholder(
                        Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.muted,
                        ),
                      ),
                );
              },
            ),
    );

    return onTap == null
        ? body
        : Material(
            color: Colors.transparent,
            child: InkWell(onTap: onTap, child: body),
          );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Column(
    children: <Widget>[
      Container(
        width: 64,
        height: 64,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.brandSoft,
          borderRadius: BorderRadius.circular(AppRadius.pane),
        ),
        child: Icon(Icons.gavel_outlined, size: 30, color: AppColors.brandDeep),
      ),
      const SizedBox(height: AppSpacing.lg),
      Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ],
  );
}

/// One page on the whole screen, to read the small print: pinch to enlarge,
/// drag to move along the line, ✕ to go back.
///
/// ⚠ ONE PAGE, NOT A SWIPE BETWEEN PAGES. The first version sat the zoom inside
///   a PageView, and on the emulator a quick swipe was taken by the zoom as a
///   pan of a page that could not move — the next page never came, and a test
///   reproduced it. Two gestures fighting over one finger is a screen that
///   works for whoever tested it slowly. The list is one tap away.
class BylawViewer extends StatelessWidget {
  const BylawViewer({required this.pageId, super.key});

  final int pageId;

  @override
  Widget build(BuildContext context) {
    final L l = L.of(context);
    return AppBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: Text(l.bylawsTitle)),
        body: SafeArea(
          top: false,
          child: InteractiveViewer(
            minScale: 1,
            maxScale: 5,
            child: BylawPageImage(pageId: pageId, whole: true),
          ),
        ),
      ),
    );
  }
}
