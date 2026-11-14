import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// `.card` - white rounded panel with the site's standard shadow.
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(24)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [AppTheme.shadowMd],
      ),
      child: child,
    );
  }
}

/// `.card-title` - icon chip + bold title, used at the top of every card.
class CardTitleRow extends StatelessWidget {
  final String emoji;
  final String title;
  final Color iconBg;
  final EdgeInsets margin;
  const CardTitleRow({
    super.key,
    required this.emoji,
    required this.title,
    this.iconBg = AppColors.iconBlue,
    this.margin = const EdgeInsets.only(bottom: 20),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Text(emoji, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: guFont(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

/// `.btn-primary` / generic `.btn` - flat colorful action button. Pass
/// [background]+[foreground] for a solid color, or leave both null for
/// the default navy gradient primary style.
class AppButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final Color? background;
  final Color foreground;
  final bool loading;
  final bool expand;
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.background,
    this.foreground = AppColors.white,
    this.loading = false,
    this.expand = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
      decoration: BoxDecoration(
        gradient: background == null
            ? const LinearGradient(colors: [AppColors.navyMid, AppColors.navyLight])
            : null,
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: (background ?? AppColors.navyMid).withValues(alpha: 0.35),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Opacity(
        opacity: disabled ? 0.5 : 1,
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: foreground),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: guFont(fontSize: 14, fontWeight: FontWeight.w800, color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: disabled ? null : onPressed,
        child: child,
      ),
    );
  }
}

/// `.btn-reset` - light gray secondary button.
class AppResetButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  const AppResetButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return AppButton(label: label, onPressed: onPressed, background: AppColors.slateLight, foreground: AppColors.slate);
  }
}

/// `.info-banner` - soft blue/green gradient banner used for hints.
class InfoBanner extends StatelessWidget {
  final String title;
  final String? hint;
  final Widget? child;
  const InfoBanner({super.key, required this.title, this.hint, this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.blueBannerA, AppColors.blueBannerB]),
        border: Border.all(color: AppColors.blueBannerBorder, width: 1.5),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: guFont(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.navyMid)),
          if (child != null) ...[const SizedBox(height: 6), child!],
          if (hint != null) ...[
            const SizedBox(height: 8),
            Text(hint!, style: guFont(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.slate)),
          ],
        ],
      ),
    );
  }
}

/// `.reg-chip` - small pill showing a registered/count number.
class StatChip extends StatelessWidget {
  final String label;
  final int value;
  final bool total;
  const StatChip({super.key, required this.label, required this.value, this.total = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: total ? AppColors.navy : AppColors.white,
        border: Border.all(color: total ? AppColors.navy : AppColors.iconBlue, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: guFont(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: total ? AppColors.white : AppColors.navy,
              ),
            ),
            TextSpan(
              text: '$value',
              style: guFont(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: total ? AppColors.goldLight : AppColors.navyLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.section-title` - bold label with a colored left border rule.
class SectionTitleBar extends StatelessWidget {
  final String text;
  final Color borderColor;
  const SectionTitleBar({super.key, required this.text, this.borderColor = AppColors.navyLight});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(border: Border(left: BorderSide(color: borderColor, width: 4))),
      child: Text(text, style: guFont(fontSize: 14, fontWeight: FontWeight.w800)),
    );
  }
}

/// `.total-row` - label + big highlighted number.
class TotalRow extends StatelessWidget {
  final String label;
  final int value;
  const TotalRow({super.key, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: AppColors.slateLight, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(text: label, style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
            TextSpan(
              text: ' $value',
              style: guFont(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navyLight),
            ),
          ],
        ),
      ),
    );
  }
}

enum AlertKind { error, success, lock, info }

/// `.alert` (+ error/success/lock/info variants).
class AlertBox extends StatelessWidget {
  final String text;
  final AlertKind kind;
  const AlertBox({super.key, required this.text, this.kind = AlertKind.info});

  @override
  Widget build(BuildContext context) {
    late Color bg, fg, border;
    switch (kind) {
      case AlertKind.error:
        bg = AppColors.roseLight;
        fg = const Color(0xFF9F1239);
        border = const Color(0xFFFECDD3);
        break;
      case AlertKind.success:
        bg = AppColors.iconGreen;
        fg = AppColors.greenDeep;
        border = AppColors.greenBorder;
        break;
      case AlertKind.lock:
        bg = AppColors.alertLockBg;
        fg = AppColors.alertLockFg;
        border = AppColors.alertLockBorder;
        break;
      case AlertKind.info:
        bg = const Color(0xFFF0F9FF);
        fg = const Color(0xFF0369A1);
        border = const Color(0xFFBAE6FD);
        break;
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(text, style: guFont(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

/// `.class-lock-note` - "🔐 તમારા વર્ગ: ..." chip.
class ClassLockNote extends StatelessWidget {
  final String text;
  const ClassLockNote({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text, style: guFont(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF1E40AF))),
    );
  }
}

/// Simple centered loading state (`.state-box.loading` equivalent).
class LoadingState extends StatelessWidget {
  final String label;
  const LoadingState({super.key, this.label = 'લોડ થાય છે…'});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(color: AppColors.slateLight, borderRadius: BorderRadius.circular(AppRadius.sm)),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.navyLight),
          ),
          const SizedBox(height: 12),
          Text(label, style: guFont(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.slate)),
        ],
      ),
    );
  }
}

/// Centered empty/error state box (`.state-box`).
class MessageState extends StatelessWidget {
  final String text;
  final Color color;
  const MessageState({super.key, required this.text, this.color = AppColors.slate});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      alignment: Alignment.center,
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: guFont(fontSize: 15, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

/// A labeled text field wrapper matching `.field-label` + input styling.
class LabeledField extends StatelessWidget {
  final String label;
  final Widget child;
  const LabeledField({super.key, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: guFont(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.slate,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
