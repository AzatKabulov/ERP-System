import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../widgets/app_icons.dart';

/// The palette of the "Premium Minimalist ERP" design (docs/DESIGN_SYSTEM.md): a warm ivory
/// canvas, ink, cobalt for action and selection, and a small set of accents with one job each
/// (violet, emerald, amber, rose). Widgets use these names, not literal colors.
abstract final class AppColors {
  static const canvas = Color(0xFFF5F2EC);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFFAF8F4);
  static const ink = Color(0xFF0D1311);
  static const muted = Color(0xFF5D6561);
  static const line = Color(0xFFE4DFD5);

  /// Hover border of a secondary button or card.
  static const lineStrong = Color(0xFFCBC4B8);

  /// The outline of an enabled input: darker than [line] so the field stays visible
  /// (at least 3:1 on white), in the same warm gray family.
  static const control = Color(0xFF8E887B);
  static const blue = Color(0xFF1740FF);
  static const blueDark = Color(0xFF1234D6);
  static const tint = Color(0xFFEAEEFF);

  /// The second voice of the palette: every colour has one job, so a screen can be read by colour
  /// as well as by words (never by colour alone: each use also carries a label or an icon).
  ///   blue   action, selection, sales
  ///   violet customers, warranties, profit
  ///   emerald money in, in stock
  ///   amber  attention, low stock
  ///   rose   money out, returns, out of stock
  /// The strong shade is for icons, chart marks and tiles; text uses the darker status colours.
  static const violet = Color(0xFF6A4DFF);
  static const violetTint = Color(0xFFEEEAFF);
  static const violetText = Color(0xFF4A32C9);
  static const emerald = Color(0xFF0FA36B);
  static const emeraldTint = Color(0xFFE0F5EC);
  static const amber = Color(0xFFF5A300);
  static const amberTint = Color(0xFFFFF0CC);
  static const rose = Color(0xFFE5484D);
  static const roseTint = Color(0xFFFFE8E8);

  /// The deep surface of the one figure that matters most, and the end of the brand gradient.
  static const navy = Color(0xFF0A1030);
  static const navyMid = Color(0xFF14226B);

  static const success = Color(0xFF14703B);
  static const successTint = Color(0xFFE8F4EC);
  static const warning = Color(0xFF8C5300);
  static const warningTint = Color(0xFFFFF4E0);
  static const danger = Color(0xFFB3261E);
  static const dangerTint = Color(0xFFFDECEA);
  static const info = blue;
  static const neutral = Color(0xFF4B544F);
  static const surfaceMuted = Color(0xFFEEEBE4);

  /// Text on the ink (inverse) surfaces.
  static const onInverse = Colors.white;
  static const onInverseMuted = Color(0xFFB9C0BC);
}

abstract final class AppRadius {
  static const small = 8.0;
  static const control = 12.0;
  static const card = 14.0;
  static const dialog = 18.0;
}

abstract final class AppShadows {
  /// The two-layer, low-spread surface shadow of every card.
  static const card = [
    BoxShadow(color: Color(0x0A0D1311), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x0D0D1311), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// A card that can be pressed, lifted under the pointer.
  static const cardHover = [
    BoxShadow(color: Color(0x0F0D1311), offset: Offset(0, 2), blurRadius: 4),
    BoxShadow(color: Color(0x1F14226B), offset: Offset(0, 16), blurRadius: 36),
  ];
  static const overlay = [
    BoxShadow(color: Color(0x2E0D1311), offset: Offset(0, 24), blurRadius: 80),
  ];
}

/// Gradients are used on three things only: the brand mark, the primary button and the spotlight.
abstract final class AppGradients {
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B55FF), Color(0xFF5B3DF5)],
  );
  static const button = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF3560FF), Color(0xFF1740FF)],
  );
  static const buttonDeep = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF2A52F0), Color(0xFF1234D6)],
  );
  static const spotlight = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.navy, AppColors.navyMid, Color(0xFF2A2BA8)],
    stops: [0, 0.62, 1],
  );
}

/// One family for the whole interface: Onest reads clearly at small sizes in Russian and
/// Turkmen (checked for the letters ä ç ň ö ş ü ý ž), has figures that line up in columns, and a
/// full range of weights for headings. Titles are set in the same family, heavier and tighter.
abstract final class AppFonts {
  static const ui = 'Onest';
  static const display = ui;

  /// SKUs, barcodes and document numbers: the same family, with aligned figures.
  static const mono = ui;

  /// Aligned digits for money and quantities.
  static const tabular = [FontFeature.tabularFigures()];
}

abstract final class AppTheme {
  static ThemeData get light {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.blue,
      primary: AppColors.blue,
      onPrimary: Colors.white,
      primaryContainer: AppColors.tint,
      onPrimaryContainer: AppColors.blue,
      surface: Colors.white,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: Colors.white,
      surfaceContainerLow: AppColors.surfaceSoft,
      surfaceContainer: AppColors.surfaceMuted,
      surfaceContainerHigh: AppColors.surfaceMuted,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.control,
      outlineVariant: AppColors.line,
      error: AppColors.danger,
      errorContainer: AppColors.dangerTint,
      surfaceTint: Colors.transparent,
    );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: AppFonts.ui,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.canvas,
      visualDensity: VisualDensity.standard,
    );

    TextStyle ui(
      double size,
      FontWeight weight, {
      double height = 1.4,
      double spacing = 0,
      Color color = AppColors.ink,
    }) => TextStyle(
      fontFamily: AppFonts.ui,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color,
      fontFeatures: AppFonts.tabular,
    );
    TextStyle display(double size, {double height = 1.15}) => TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: height,
      letterSpacing: size * -0.022,
      color: AppColors.ink,
      fontFeatures: AppFonts.tabular,
    );

    final text = base.textTheme.copyWith(
      displayLarge: display(52, height: 1.05),
      displayMedium: display(44, height: 1.05),
      displaySmall: display(34, height: 1.1),
      headlineLarge: display(32),
      headlineMedium: display(28),
      headlineSmall: display(24),
      titleLarge: ui(20, FontWeight.w600, height: 1.3, spacing: -0.2),
      titleMedium: ui(16, FontWeight.w600, height: 1.35),
      titleSmall: ui(14, FontWeight.w600, height: 1.4),
      bodyLarge: ui(15, FontWeight.w400, height: 1.4),
      bodyMedium: ui(15, FontWeight.w400, height: 1.45),
      bodySmall: ui(13, FontWeight.w400, height: 1.45, color: AppColors.muted),
      labelLarge: ui(14, FontWeight.w600, height: 1.2),
      labelMedium: ui(13, FontWeight.w600, height: 1.35),
      labelSmall: const TextStyle(
        fontFamily: AppFonts.ui,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: 1.2,
        color: AppColors.muted,
      ),
    );

    final controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );

    // Hover and pressed states are overlays, so a label never loses contrast.
    WidgetStateProperty<Color?> overlay(Color color) =>
        WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.pressed)) {
            return color.withValues(alpha: 0.14);
          }
          if (states.contains(WidgetState.hovered)) {
            return color.withValues(alpha: 0.07);
          }
          if (states.contains(WidgetState.focused)) {
            return color.withValues(alpha: 0.1);
          }
          return null;
        });

    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          borderSide: BorderSide(color: color, width: width),
        );

    return base.copyWith(
      textTheme: text,
      primaryTextTheme: text,
      dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
      iconTheme: const IconThemeData(color: AppColors.ink, size: 20),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      actionIconTheme: ActionIconThemeData(
        backButtonIconBuilder: (_) => const AppIcon(AppIcons.back, size: 22),
        closeButtonIconBuilder: (_) => const AppIcon(AppIcons.close, size: 22),
        drawerButtonIconBuilder: (_) => const AppIcon(AppIcons.menu, size: 22),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.canvas,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: ui(16, FontWeight.w600),
        shape: const Border(bottom: BorderSide(color: AppColors.line)),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        labelStyle: ui(14, FontWeight.w400, color: AppColors.muted),
        floatingLabelStyle: ui(13, FontWeight.w600, color: AppColors.ink),
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        hintStyle: ui(14, FontWeight.w400, color: AppColors.muted),
        helperStyle: ui(12, FontWeight.w400, color: AppColors.muted),
        errorStyle: ui(12, FontWeight.w600, color: AppColors.danger),
        prefixIconColor: WidgetStateColor.resolveWith(
          (states) => states.contains(WidgetState.focused)
              ? AppColors.blue
              : AppColors.muted,
        ),
        border: border(AppColors.line),
        enabledBorder: border(AppColors.line),
        disabledBorder: border(AppColors.line),
        focusedBorder: border(AppColors.blue, 1.5),
        errorBorder: border(AppColors.danger),
        focusedErrorBorder: border(AppColors.danger, 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.blue,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surfaceMuted,
          disabledForegroundColor: AppColors.muted.withValues(alpha: 0.7),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: controlShape,
          textStyle: ui(14, FontWeight.w600, height: 1),
          elevation: 0,
        ).copyWith(overlayColor: overlay(Colors.white)),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: controlShape,
              foregroundColor: AppColors.ink,
              textStyle: ui(14, FontWeight.w600, height: 1),
              side: const BorderSide(color: AppColors.line),
            ).copyWith(
              overlayColor: overlay(AppColors.ink),
              side: WidgetStateProperty.resolveWith(
                (states) => BorderSide(
                  color: states.contains(WidgetState.focused)
                      ? AppColors.blue
                      : states.contains(WidgetState.hovered)
                      ? AppColors.lineStrong
                      : AppColors.line,
                  width: states.contains(WidgetState.focused) ? 2 : 1,
                ),
              ),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: controlShape,
          foregroundColor: AppColors.muted,
          textStyle: ui(14, FontWeight.w600, height: 1),
        ).copyWith(overlayColor: overlay(AppColors.ink)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: AppColors.ink,
          shape: controlShape,
        ).copyWith(overlayColor: overlay(AppColors.ink)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(controlShape),
          minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
          textStyle: WidgetStatePropertyAll(ui(13, FontWeight.w600, height: 1)),
          side: const WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Colors.white
                : AppColors.surfaceSoft,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.ink
                : AppColors.muted,
          ),
          overlayColor: overlay(AppColors.ink),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white,
        selectedColor: AppColors.tint,
        disabledColor: AppColors.surfaceMuted,
        checkmarkColor: AppColors.blue,
        showCheckmark: false,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.line,
          ),
        ),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        labelStyle: ui(13, FontWeight.w600, height: 1.2).copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.neutral,
          ),
        ),
        secondaryLabelStyle: ui(13, FontWeight.w600, height: 1.2),
        iconTheme: const IconThemeData(size: 16),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: const Color(0x2E0D1311),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: const BorderSide(color: AppColors.line),
        ),
        barrierColor: const Color(0x6B0D1311),
        titleTextStyle: display(24, height: 1.25),
        contentTextStyle: ui(
          14,
          FontWeight.w400,
          height: 1.55,
          color: AppColors.muted,
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.dialog),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: const Color(0x2E0D1311),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: const BorderSide(color: AppColors.line),
        ),
        textStyle: ui(14, FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        shape: controlShape,
        iconColor: AppColors.muted,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        textStyle: ui(12, FontWeight.w500, color: Colors.white),
        waitDuration: const Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.white,
        contentTextStyle: ui(14, FontWeight.w600),
        actionTextColor: AppColors.blue,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line),
        ),
        elevation: 6,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.blue,
        linearTrackColor: AppColors.surfaceMuted,
        circularTrackColor: AppColors.surfaceMuted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.blue
              : AppColors.control,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: const BorderSide(color: AppColors.control, width: 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.tint,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        elevation: 0,
        height: 72,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => ui(
            11,
            FontWeight.w600,
            height: 1.2,
            color: states.contains(WidgetState.selected)
                ? AppColors.blue
                : AppColors.muted,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.ink,
        unselectedLabelColor: AppColors.muted,
        indicatorColor: AppColors.blue,
        labelStyle: ui(13, FontWeight.w600),
        unselectedLabelStyle: ui(13, FontWeight.w600),
        dividerColor: AppColors.line,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(
          AppColors.control.withValues(alpha: 0.6),
        ),
        radius: const Radius.circular(8),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.blue,
        selectionColor: AppColors.blue.withValues(alpha: 0.2),
        selectionHandleColor: AppColors.blue,
      ),
    );
  }
}
