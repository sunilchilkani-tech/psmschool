import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide display size chosen by the user (saved on the device only, so it
/// costs no Firebase reads or writes).
class DisplayScale {
  DisplayScale._();

  static const String _prefKey = 'psm_display_scale_v1';

  static const List<(double, String)> options = <(double, String)>[
    (1.0, 'સામાન્ય / Normal'),
    (1.12, 'મોટું / Large'),
    (1.25, 'વધુ મોટું / Extra large'),
  ];

  static final ValueNotifier<double> notifier = ValueNotifier<double>(1.0);

  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getDouble(_prefKey);
      if (v != null && v >= 0.9 && v <= 1.4) notifier.value = v;
    } catch (_) {}
  }

  static Future<void> set(double value) async {
    notifier.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_prefKey, value);
    } catch (_) {}
  }

  /// Small menu button for app bars.
  static Widget menuButton({Color? color}) => ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, current, _) => PopupMenuButton<double>(
          tooltip: 'Display size / અક્ષરનું માપ',
          icon: Icon(Icons.format_size_rounded, color: color),
          initialValue: current,
          onSelected: set,
          itemBuilder: (_) => [
            for (final o in options)
              CheckedPopupMenuItem<double>(
                value: o.$1,
                checked: (current - o.$1).abs() < 0.01,
                child: Text(o.$2),
              ),
          ],
        ),
      );
}
