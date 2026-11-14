import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'common_widgets.dart';

/// Shared shell used by all 4 popup overlays in the original site
/// (teacher-msg-overlay / zero-reg-overlay / all-zero-overlay /
/// mdm-bf-zero-overlay) - same card, same backdrop, different content.
Future<T?> showEmojiDialog<T>({
  required BuildContext context,
  required String emoji,
  String? title,
  required Widget content,
  required List<Widget> actions,
  bool barrierDismissible = false,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.7),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [AppTheme.shadowLg],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 40)),
            const SizedBox(height: 10),
            if (title != null) ...[
              Text(title,
                  textAlign: TextAlign.center,
                  style: guFont(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
            ],
            content,
            const SizedBox(height: 20),
            for (final a in actions) Padding(padding: const EdgeInsets.only(bottom: 12), child: a),
          ],
        ),
      ),
    ),
  );
}

/// "આચાર્યશ્રીનો સંદેશ" - shown once per day when the principal has left
/// a message for teachers (`getTodayMessage`).
Future<void> showTeacherMessageDialog(BuildContext context, String message) {
  return showEmojiDialog(
    context: context,
    emoji: '📢',
    title: 'આચાર્યશ્રીનો સંદેશ',
    content: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.greenBg,
        border: Border.all(color: AppColors.greenBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: guFont(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.navyMid, height: 1.4),
      ),
    ),
    actions: [
      AppButton(
        label: 'OK, મેં વાંચી લીધું',
        onPressed: () => Navigator.of(context).pop(),
        background: AppColors.navy,
        expand: true,
      ),
    ],
  );
}

/// Generic single-button info/warning popup (used for zero-registered
/// warnings and other one-off notices).
Future<void> showInfoOkDialog(BuildContext context, {String emoji = '⚠️', required String message}) {
  return showEmojiDialog(
    context: context,
    emoji: emoji,
    content: Text(
      message,
      textAlign: TextAlign.center,
      style: guFont(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navyMid, height: 1.4),
    ),
    actions: [
      AppButton(label: 'Ok', onPressed: () => Navigator.of(context).pop(), background: AppColors.navy, expand: true),
    ],
  );
}

/// "શું આજે ખરેખર કોઈ હાજર નથી?" confirmation before saving an all-zero
/// attendance entry. Returns true only if the teacher confirms.
Future<bool> showAllZeroConfirm(BuildContext context) async {
  final res = await showEmojiDialog<bool>(
    context: context,
    emoji: '❓',
    content: Text(
      'આજે બધા વિદ્યાર્થીઓની હાજર સંખ્યા 0 છે. શું આ સાચું છે?',
      textAlign: TextAlign.center,
      style: guFont(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navyMid, height: 1.4),
    ),
    actions: [
      AppButton(
        label: 'હા, આજે કોઈ હાજર નથી.',
        onPressed: () => Navigator.of(context).pop(true),
        background: AppColors.greenDeep,
        expand: true,
      ),
      AppResetButton(label: 'ના, મારે સુધારો કરવાની જરૂર છે.', onPressed: () => Navigator.of(context).pop(false)),
    ],
  );
  return res ?? false;
}

/// "શું ખરેખર PM Poshan/અલ્પાહાર 0 છે?" confirmation.
Future<bool> showMdmBfZeroConfirm(BuildContext context) async {
  final res = await showEmojiDialog<bool>(
    context: context,
    emoji: '❓',
    content: Text(
      'શું ખરેખર આજે પીએમ પોષણ (MDM) અને અલ્પાહાર લેનાર વિદ્યાર્થીઓની સંખ્યા 0 છે?',
      textAlign: TextAlign.center,
      style: guFont(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.navyMid, height: 1.4),
    ),
    actions: [
      AppButton(
        label: 'હા, સબમિટ કરો',
        onPressed: () => Navigator.of(context).pop(true),
        background: AppColors.greenDeep,
        expand: true,
      ),
      AppResetButton(label: 'ના, મારે સુધારો કરવો છે', onPressed: () => Navigator.of(context).pop(false)),
    ],
  );
  return res ?? false;
}

/// Generic Yes/No confirmation (used by holiday delete, message delete).
Future<bool> showConfirmDialog(
  BuildContext context, {
  String emoji = '❓',
  required String message,
  String yesLabel = 'હા',
  String noLabel = 'ના',
}) async {
  final res = await showEmojiDialog<bool>(
    context: context,
    emoji: emoji,
    content: Text(
      message,
      textAlign: TextAlign.center,
      style: guFont(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.navyMid, height: 1.4),
    ),
    actions: [
      AppButton(label: yesLabel, onPressed: () => Navigator.of(context).pop(true), background: AppColors.rose, expand: true),
      AppResetButton(label: noLabel, onPressed: () => Navigator.of(context).pop(false)),
    ],
  );
  return res ?? false;
}

/// Master-password gate used before the admin-only "change server URL"
/// and "change teacher PIN" actions - same behaviour as the original
/// site's `prompt(...)` password checks (`openApiSettings` /
/// `openPasswordSettings`). Returns true only when [expectedPassword]
/// is entered correctly.
Future<bool> promptMasterPassword(
  BuildContext context, {
  required String expectedPassword,
  String title = '🔒 પાસવર્ડ દાખલ કરો',
  String hint = 'માસ્ટર પાસવર્ડ',
}) async {
  final ctrl = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) {
      String? error;
      return StatefulBuilder(builder: (ctx, setD) {
        void verify() {
          if (ctrl.text == expectedPassword) {
            Navigator.of(ctx).pop(true);
          } else {
            setD(() => error = '❌ ખોટો પાસવર્ડ!');
          }
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title, style: guFont(fontWeight: FontWeight.w800, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(hintText: hint),
                onSubmitted: (_) => verify(),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: guFont(fontSize: 12.5, color: AppColors.rose, fontWeight: FontWeight.w700)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('રદ કરો')),
            AppButton(label: 'ખાતરી કરો', background: AppColors.navy, onPressed: verify),
          ],
        );
      });
    },
  );
  ctrl.dispose();
  return ok ?? false;
}

void showBusyDialog(BuildContext context, String message) {
  showDialog(
    context: context,
    barrierDismissible: false,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.navyLight),
            ),
            const SizedBox(width: 16),
            Flexible(child: Text(message, style: guFont(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    ),
  );
}

void hideBusyDialog(BuildContext context) {
  Navigator.of(context, rootNavigator: true).pop();
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message, style: guFont(color: Colors.white, fontWeight: FontWeight.w700)),
      backgroundColor: error ? AppColors.rose : AppColors.navy,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
      margin: const EdgeInsets.only(bottom: 24, left: 40, right: 40),
    ),
  );
}
