import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens ported 1:1 from the original site's `:root` CSS variables.
/// Keeping the same names/values so the Flutter UI matches the web app.
class AppColors {
  AppColors._();

  static const navy = Color(0xFF1A2744);
  static const navyMid = Color(0xFF243560);
  static const navyLight = Color(0xFF2F4580);

  static const gold = Color(0xFFF5A623);
  static const goldLight = Color(0xFFFFD166);
  static const goldPale = Color(0xFFFFF8E7);

  static const teal = Color(0xFF0D9488);
  static const tealLight = Color(0xFFCCFBF1);

  static const rose = Color(0xFFE11D48);
  static const roseLight = Color(0xFFFFE4E6);

  static const slate = Color(0xFF64748B);
  static const slateLight = Color(0xFFF1F5F9);

  static const white = Color(0xFFFFFFFF);

  // Extra utility colors seen inline in the original markup
  static const amberBorder = Color(0xFFFBD38D);
  static const amberDeep = Color(0xFF92400E);
  static const greenBg = Color(0xFFF0FDF4);
  static const greenBorder = Color(0xFFBBF7D0);
  static const greenDeep = Color(0xFF15803D);
  static const greenDeep2 = Color(0xFF16A34A);
  static const blueBannerA = Color(0xFFEFF6FF);
  static const blueBannerB = Color(0xFFF0FDF4);
  static const blueBannerBorder = Color(0xFFBFDBFE);
  static const iconBlue = Color(0xFFDBEAFE);
  static const iconAmber = Color(0xFFFEF3C7);
  static const iconGreen = Color(0xFFDCFCE7);
  static const alertLockBg = Color(0xFFFEF9C5);
  static const alertLockFg = Color(0xFF854D0E);
  static const alertLockBorder = Color(0xFFFDE047);
  static const border = Color(0xFFE2E8F0);
}

class AppRadius {
  AppRadius._();
  static const card = 16.0;
  static const sm = 10.0;
}

/// Nunito is the primary font (matches Latin glyphs) with Noto Sans Gujarati
/// as fallback so Gujarati text renders correctly - mirrors the original
/// CSS: `font-family: Nunito, "Noto Sans Gujarati", sans-serif;`
TextStyle guFont({
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w600,
  Color color = AppColors.navy,
  double? letterSpacing,
  double? height,
}) {
  final fallback = GoogleFonts.notoSansGujarati().fontFamily!;
  return GoogleFonts.nunito(
    fontSize: fontSize,
    fontWeight: fontWeight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  ).copyWith(
    fontFamilyFallback: <String>[
      'NotoSansGujaratiLocal',
      'LohitGujaratiLocal',
      fallback,
      'sans-serif',
    ],
  );
}

class AppTheme {
  AppTheme._();

  static const List<String> _fallback = <String>[
    'NotoSansGujaratiLocal',
    'LohitGujaratiLocal',
    'sans-serif',
  ];

  static ThemeData get theme {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: 'NotoSansGujaratiLocal',
      fontFamilyFallback: _fallback,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.navyLight,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.navyLight,
      onPrimary: Colors.white,
      secondary: AppColors.gold,
      tertiary: AppColors.teal,
      error: AppColors.rose,
      surface: Colors.white,
    );
    final text = base.textTheme
        .copyWith(
          headlineSmall: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          titleLarge: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          titleMedium: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          titleSmall: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          bodyLarge: const TextStyle(fontSize: 16, height: 1.4),
          bodyMedium: const TextStyle(fontSize: 15, height: 1.4),
          bodySmall: const TextStyle(fontSize: 13, height: 1.35),
          labelLarge: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          labelMedium: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        )
        .apply(
          fontFamily: 'NotoSansGujaratiLocal',
          fontFamilyFallback: _fallback,
          bodyColor: AppColors.navy,
          displayColor: AppColors.navy,
        );
    final roundedSm = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    );
    const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
    const buttonMin = Size(64, 48);
    const buttonText = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      fontFamily: 'NotoSansGujaratiLocal',
    );

    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFEEF2F8),
      colorScheme: scheme,
      textTheme: text,
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: 'NotoSansGujaratiLocal',
        fontFamilyFallback: _fallback,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 3,
        centerTitle: false,
        toolbarHeight: 62,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        iconTheme: IconThemeData(color: Colors.white, size: 24),
        actionsIconTheme: IconThemeData(color: Colors.white, size: 24),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonMin,
          padding: buttonPadding,
          shape: roundedSm,
          textStyle: buttonText,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonMin,
          padding: buttonPadding,
          shape: roundedSm,
          textStyle: buttonText,
          elevation: 1,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonMin,
          padding: buttonPadding,
          shape: roundedSm,
          textStyle: buttonText,
          side: const BorderSide(color: AppColors.navyLight, width: 1.3),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          shape: roundedSm,
          textStyle: buttonText,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        secondaryLabelStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        backgroundColor: Colors.white,
        selectedColor: const Color(0xFFD6E2FA),
        checkmarkColor: AppColors.navy,
        iconTheme: const IconThemeData(color: AppColors.navyLight, size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: const BorderSide(color: AppColors.border),
      ),
      tabBarTheme: const TabBarThemeData(
        labelStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        unselectedLabelStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        indicatorSize: TabBarIndicatorSize.label,
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 10,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.navy,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 13.5,
          color: AppColors.slate,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFE8EEF9)),
        headingTextStyle: const TextStyle(
          fontSize: 14.5,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        dataTextStyle: const TextStyle(
          fontSize: 14.5,
          color: AppColors.navy,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 64,
        headingRowHeight: 52,
        dividerThickness: 0.8,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.navy,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.navy,
        contentTextStyle: const TextStyle(
          fontSize: 15,
          color: Colors.white,
          fontFamily: 'NotoSansGujaratiLocal',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      tooltipTheme: TooltipThemeData(
        textStyle: const TextStyle(fontSize: 13.5, color: Colors.white),
        decoration: BoxDecoration(
          color: AppColors.navy.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.navyLight),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.navyLight,
        foregroundColor: Colors.white,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.slateLight,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        labelStyle: const TextStyle(fontSize: 15, color: AppColors.slate),
        floatingLabelStyle: const TextStyle(
          fontSize: 15,
          color: AppColors.navyLight,
          fontWeight: FontWeight.w700,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.navyLight, width: 2),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: WidgetStateProperty.all(8),
        radius: const Radius.circular(8),
      ),
      splashFactory: InkRipple.splashFactory,
      // One quick, modern transition on every platform (web included).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
          TargetPlatform.macOS: ZoomPageTransitionsBuilder(),
          TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static BoxDecoration get backgroundGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE8EDF8), Color(0xFFF5F7FD), Color(0xFFEEF4F2)],
          stops: [0.0, 0.5, 1.0],
        ),
      );

  static BoxDecoration get headerGradient => const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.navy, AppColors.navyMid, AppColors.navyLight],
          stops: [0.0, 0.6, 1.0],
        ),
      );

  static BoxShadow get shadowSm => BoxShadow(
        color: AppColors.navy.withValues(alpha: 0.08),
        blurRadius: 8,
        offset: const Offset(0, 2),
      );

  static BoxShadow get shadowMd => BoxShadow(
        color: AppColors.navy.withValues(alpha: 0.13),
        blurRadius: 20,
        offset: const Offset(0, 4),
      );

  static BoxShadow get shadowLg => BoxShadow(
        color: AppColors.navy.withValues(alpha: 0.18),
        blurRadius: 40,
        offset: const Offset(0, 8),
      );
}
