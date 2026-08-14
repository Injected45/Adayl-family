import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The glass primitives.
///
/// ── Why blur is opt-in and not the default
///
/// `BackdropFilter` is the expensive widget in Flutter. Each one forces the
/// compositor to save the layer beneath it, blur it, and composite the result,
/// and the cost scales with the blurred area. Put one on every row of a
/// scrolling list and the list drops frames — worst on web/CanvasKit, which is
/// a target here.
///
/// So [GlassSurface] does NOT blur unless asked. The rule for this app:
///
///   BLUR  → floating chrome only. App bar, bottom navigation, rail, bottom
///           sheets, dialogs, and at most one hero surface per screen. These are
///           few, fixed in number, and are exactly the places where content
///           moving underneath makes the frost legible.
///
///   NO BLUR → everything that repeats. Cards in a list, table rows, stat tiles,
///             badges. They get the translucent fill and the light hairline, and
///             they read as glass because they sit on the same vibrant field and
///             share the border treatment with the chrome above them. The frost
///             is doing very little visual work on a 64px row anyway.
///
/// [kGlassBlurBudget] is the ceiling, asserted in test/design_system_test.dart
/// by counting BackdropFilter widgets in a rendered screen. Without a test this
/// discipline lasts exactly until the next screen is written.
const int kGlassBlurBudget = 6;

/// CSS `backdrop-filter: blur(20px)` is roughly `sigma: 10` — the guidance range
/// is 10–20px, so this sits at the top of it where the frost is clearly visible
/// without smearing text behind it into mush.
const double kGlassBlurSigma = 10;

/// A translucent pane.
///
/// Provides the fill, the light top-edge stroke and the outer ink hairline that
/// together read as glass. Set [blurred] only for floating chrome — see the
/// budget note above.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.blurred = false,
    this.fill,
    this.radius = AppRadius.pane,
    this.padding,
    this.margin,
    this.lifted = false,
    this.borderColor,
    super.key,
  });

  final Widget child;

  /// Adds a [BackdropFilter]. Costs a compositor layer — chrome only.
  final bool blurred;

  final Color? fill;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  /// One soft ambient shadow, permitted on floating chrome only.
  final bool lifted;

  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final BorderRadius shape = BorderRadius.circular(radius);

    Widget pane = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? GlassColors.surface,
        borderRadius: shape,
        border: Border.all(color: borderColor ?? GlassColors.hairline),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        // The inner light stroke. Drawn inside the pane rather than as a second
        // border so it catches the top edge the way a real bevel would.
        child: CustomPaint(painter: _EdgeLight(shape), child: child),
      ),
    );

    if (blurred) {
      pane = ClipRRect(
        borderRadius: shape,
        // ClipRRect is required: an unbounded BackdropFilter blurs the entire
        // screen behind it, not just the pane.
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: kGlassBlurSigma,
            sigmaY: kGlassBlurSigma,
          ),
          child: pane,
        ),
      );
    }

    if (lifted) {
      pane = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: GlassColors.lift,
              blurRadius: 24,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: pane,
      );
    }

    return margin == null ? pane : Padding(padding: margin!, child: pane);
  }
}

/// Paints the light-catching inner edge along the top of a pane.
class _EdgeLight extends CustomPainter {
  const _EdgeLight(this.shape);

  final BorderRadius shape;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[GlassColors.stroke, Color(0x00FFFFFF)],
        stops: <double>[0, 0.45],
      ).createShader(Offset.zero & size);

    canvas.drawRRect(shape.toRRect(Offset.zero & size).deflate(0.5), paint);
  }

  @override
  bool shouldRepaint(_EdgeLight oldDelegate) => oldDelegate.shape != shape;
}

/// A content card. Never blurred — these repeat.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin,
    this.onTap,
    this.borderColor,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// When set, the whole card becomes a target — with an ink response, so it is
  /// visibly interactive rather than a card that happens to react.
  final VoidCallback? onTap;

  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final Widget surface = GlassSurface(
      radius: AppRadius.pane,
      borderColor: borderColor,
      padding: onTap == null ? padding : EdgeInsets.zero,
      child: onTap == null
          ? child
          : Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.pane),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppRadius.pane),
                // Hover and focus both change the surface, never the size — a
                // scale transform on hover shifts everything around it.
                hoverColor: AppColors.brand.withValues(alpha: 0.04),
                focusColor: AppColors.brand.withValues(alpha: 0.08),
                child: Padding(padding: padding, child: child),
              ),
            ),
    );
    return margin == null ? surface : Padding(padding: margin!, child: surface);
  }
}

/// A titled section, the workhorse layout of every screen.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    required this.title,
    required this.child,
    this.trailing,
    this.icon,
    this.margin,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? trailing;
  final IconData? icon;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                // Flat: a solid saturated tile, no gradient, small radius.
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.brandSoft,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, size: 18, color: AppColors.brandDeep),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
        ],
      ),
    );
  }
}

// StatusBadge and LabelledValue are NOT defined here. They already live in
// core/widgets/async_view.dart and are imported by ten screens; they were
// restyled in place instead of duplicated, because two widgets with the same
// name in one app is how a redesign ends up half-applied.

/// A frosted dialog. Mirrors [AlertDialog]'s API.
///
/// Required, not cosmetic: the theme sets `DialogThemeData.backgroundColor` to
/// transparent so this pane can own the surface, which means a plain AlertDialog
/// would render with no background whatsoever. Every dialog in the app uses this.
///
/// A dialog is the one place blur is unambiguously worth its cost — the barrier
/// already dims the content behind it, and frosting that dimmed content is what
/// makes the pane read as floating above the app rather than pasted onto it.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    this.icon,
    this.title,
    this.content,
    this.actions,
    this.destructive = false,
    super.key,
  });

  /// Optional leading icon, centred above the title. Matches AlertDialog's
  /// `icon` slot so call sites did not have to change shape.
  final Widget? icon;

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  /// Tints the top edge in danger red. Colour is never the only signal — the
  /// confirm button is also styled and relabelled — but a destructive dialog
  /// should be recognisable before the text is read.
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(AppSpacing.xl),
      // NOT blurred, and this is a device-level constraint, not a taste call.
      //
      // A BackdropFilter inside an OVERLAY ROUTE renders nothing on Android with
      // Impeller: the pane vanishes completely, leaving only the barrier dimming
      // the screen behind it. Reproduced on the emulator by screenshot, and it is
      // not a layout fault - a widget test shows the same dialog laying out at
      // 752x146 with all its text present, so the tree is right and the composited
      // result is empty.
      //
      // Chrome blur is unaffected and stays: the app bar, the bottom navigation
      // and the rail all frost correctly in the same frame. The difference is the
      // overlay route, not BackdropFilter itself.
      //
      // Little is lost. The barrier already dims and separates the sheet from the
      // content, which is the job the frost would have done here, and there is
      // nothing moving behind a modal to be worth frosting.
      child: GlassSurface(
        lifted: true,
        fill: GlassColors.overlay,
        borderColor: destructive
            ? AppColors.danger.withValues(alpha: 0.35)
            : GlassColors.hairline,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              // Flat: a solid tinted square, not a bare glyph floating in space.
              Center(
                child: Container(
                  width: 60,
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (destructive ? AppColors.danger : AppColors.brand)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.pane),
                  ),
                  child: icon,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            // Falls back through the text theme rather than force-unwrapping
            // dialogTheme. Those slots are null under any theme that does not
            // set them — including the bare MaterialApp that widget tests use —
            // and a `!` here crashed every dialog test with "Null check operator
            // used on a null value".
            if (title != null) ...<Widget>[
              DefaultTextStyle(
                style:
                    theme.dialogTheme.titleTextStyle ??
                    theme.textTheme.titleLarge ??
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                child: title!,
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (content != null) ...<Widget>[
              DefaultTextStyle(
                style:
                    theme.dialogTheme.contentTextStyle ??
                    theme.textTheme.bodyMedium ??
                    const TextStyle(fontSize: 14),
                child: content!,
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
            if (actions != null)
              // The local Theme is not decoration. It is the fix for a bug that
              // made every dialog in this app invisible.
              //
              // The global button themes use `minimumSize: Size.fromHeight(52)`,
              // and `Size.fromHeight` sets width to **double.infinity**, not 0.
              // On a page that is exactly right: the Column bounds the width, and
              // the infinite minimum is what makes buttons span it.
              //
              // A Row gives its children UNBOUNDED width, so the infinity
              // propagates instead of being clamped, and layout asserts:
              //
              //     BoxConstraints forces an infinite width.
              //     BoxConstraints(w=Infinity, 52.0<=h<=Infinity)
              //     The relevant error-causing widget was: FilledButton
              //
              // A failed layout paints nothing, so the barrier appeared over a
              // dimmed screen with no dialog on it — which is exactly what was
              // reported. Every dialog with a FilledButton or OutlinedButton in
              // its actions was affected; ordinary page buttons never were,
              // because only a dialog puts them in a Row.
              //
              // Overriding minimumSize here, rather than changing the global
              // theme, keeps full-width page buttons working as designed.
              Theme(
                data: theme.copyWith(
                  filledButtonTheme: FilledButtonThemeData(
                    style:
                        (theme.filledButtonTheme.style ?? const ButtonStyle())
                            .copyWith(
                              minimumSize: const WidgetStatePropertyAll<Size>(
                                Size(88, 48),
                              ),
                            ),
                  ),
                  outlinedButtonTheme: OutlinedButtonThemeData(
                    style:
                        (theme.outlinedButtonTheme.style ?? const ButtonStyle())
                            .copyWith(
                              minimumSize: const WidgetStatePropertyAll<Size>(
                                Size(88, 48),
                              ),
                            ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    for (final Widget action in actions!)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: action,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A frosted bottom sheet body. Same reason as [GlassDialog]: the theme made
/// BottomSheetThemeData transparent.
class GlassSheet extends StatelessWidget {
  const GlassSheet({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // See GlassDialog: a BackdropFilter inside an overlay route paints nothing on
    // Android/Impeller.
    return GlassSurface(
      lifted: true,
      fill: GlassColors.overlay,
      margin: const EdgeInsets.all(AppSpacing.sm),
      child: child,
    );
  }
}

/// Content padding for a scrollable screen body.
///
/// The bottom navigation FLOATS over the content, which is what lets the list
/// slide underneath the frosted pill instead of stopping dead at an opaque bar.
/// The cost is that the last row would sit under the pill and be unreachable, so
/// AppScaffold publishes the pill's height as `MediaQuery.padding.bottom` and
/// this reads it back.
///
/// Wrapping the body in a `Padding` would not do: that shrinks the viewport, so
/// the content would stop above the pill and there would be nothing behind the
/// frost. The inset has to live inside the scroll view's own padding.
EdgeInsetsGeometry screenPadding(BuildContext context) {
  return EdgeInsetsDirectional.fromSTEB(
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.lg,
    AppSpacing.lg + MediaQuery.paddingOf(context).bottom,
  );
}

/// Whether the platform asked for less motion.
///
/// Checked before every entrance animation. `disableAnimations` is what iOS
/// "Reduce Motion" and Android "Remove animations" set, and `accessibleNavigation`
/// covers a screen reader being active, where movement is noise.
bool prefersReducedMotion(BuildContext context) {
  final MediaQueryData mq = MediaQuery.of(context);
  return mq.disableAnimations || mq.accessibleNavigation;
}
