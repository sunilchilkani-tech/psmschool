import 'package:flutter/material.dart';

/// Screen-size helpers shared by every screen.
///
///  phone   : width < 600  (most mobiles, portrait)
///  tablet  : 600 – 1023   (tablets, small laptops, mobile landscape)
///  desktop : ≥ 1024       (laptops and desktops)
class Responsive {
  Responsive._();

  static const double phoneMax = 600;
  static const double tabletMax = 1024;

  static double width(BuildContext context) => MediaQuery.sizeOf(context).width;
  static bool isPhone(BuildContext context) => width(context) < phoneMax;
  static bool isTablet(BuildContext context) {
    final w = width(context);
    return w >= phoneMax && w < tabletMax;
  }

  static bool isDesktop(BuildContext context) => width(context) >= tabletMax;

  /// Page padding: tight on phones, roomier on large screens.
  static EdgeInsets pagePadding(BuildContext context) {
    final w = width(context);
    if (w < phoneMax) return const EdgeInsets.all(10);
    if (w < tabletMax) return const EdgeInsets.all(14);
    return const EdgeInsets.all(18);
  }

  /// Width for a dialog's content: [desired] on large screens, the whole
  /// usable width on phones.
  static double dialogWidth(BuildContext context, double desired) {
    final w = width(context);
    return w < phoneMax ? w - 24 : (desired < w - 48 ? desired : w - 48);
  }

  /// Phone-friendly version of the app theme. Desktop and laptop sizes keep
  /// [base] unchanged.
  static ThemeData adapt(ThemeData base, Size size) {
    if (size.width >= phoneMax) return base;
    const buttonPadding = EdgeInsets.symmetric(horizontal: 14, vertical: 11);
    const buttonMin = Size(44, 44);
    ButtonStyle tighten(ButtonStyle? s) =>
        (s ?? const ButtonStyle()).copyWith(
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(buttonPadding),
          minimumSize: const WidgetStatePropertyAll<Size>(buttonMin),
        );
    final ab = base.appBarTheme;
    return base.copyWith(
      dialogTheme: base.dialogTheme.copyWith(
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      ),
      appBarTheme: ab.copyWith(
        toolbarHeight: 56,
        titleSpacing: 8,
        titleTextStyle: (ab.titleTextStyle ?? const TextStyle()).copyWith(fontSize: 16.5),
      ),
      filledButtonTheme: FilledButtonThemeData(style: tighten(base.filledButtonTheme.style)),
      elevatedButtonTheme: ElevatedButtonThemeData(style: tighten(base.elevatedButtonTheme.style)),
      outlinedButtonTheme: OutlinedButtonThemeData(style: tighten(base.outlinedButtonTheme.style)),
      inputDecorationTheme: base.inputDecorationTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      tabBarTheme: base.tabBarTheme.copyWith(
        labelPadding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      listTileTheme: base.listTileTheme.copyWith(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      ),
      dataTableTheme: base.dataTableTheme.copyWith(
        columnSpacing: 18,
        horizontalMargin: 10,
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        insetPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      ),
    );
  }
}

/// Applies [Responsive.adapt] to everything below it (used by MaterialApp's
/// builder, so every route and dialog gets the phone theme on small screens).
class ResponsiveTheme extends StatelessWidget {
  const ResponsiveTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final base = Theme.of(context);
    final adapted = Responsive.adapt(base, size);
    if (identical(adapted, base)) return child;
    return Theme(data: adapted, child: child);
  }
}

/// A title with action buttons. On wide screens it is one line (title
/// fills, actions on the right). Below [breakpoint] the actions move under
/// the title and wrap, so neither the title nor the buttons get squeezed.
class TitleWithActions extends StatelessWidget {
  const TitleWithActions({
    super.key,
    required this.title,
    required this.actions,
    this.leading,
    this.breakpoint = 620,
    this.spacing = 8,
  });

  final Widget title;
  final List<Widget> actions;
  final Widget? leading;
  final double breakpoint;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final head = <Widget>[
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(child: title),
      ];
      if (c.maxWidth >= breakpoint || actions.isEmpty) {
        return Row(children: [
          ...head,
          for (final a in actions) ...[SizedBox(width: spacing), a],
        ]);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: head),
          const SizedBox(height: 8),
          Wrap(spacing: spacing, runSpacing: 8, children: actions),
        ],
      );
    });
  }
}

/// Form fields side by side on wide screens, stacked on narrow ones.
class ResponsiveFields extends StatelessWidget {
  const ResponsiveFields({
    super.key,
    required this.children,
    this.breakpoint = 640,
    this.gap = 10,
  });

  final List<Widget> children;
  final double breakpoint;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= breakpoint) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) SizedBox(width: gap),
              Expanded(child: children[i]),
            ],
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) SizedBox(height: gap),
            children[i],
          ],
        ],
      );
    });
  }
}
