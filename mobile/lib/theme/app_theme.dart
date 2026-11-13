import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../widgets/app_icons.dart';
import 'app_palette.dart';

/// The colours of the interface. Widgets use these names, never literal colours: each one is read
/// from the palette in force ([AppPalette.light] or [AppPalette.dark]), so the same screens are
/// drawn in either scheme. The two surfaces that are navy in both schemes (the hero figure) keep
/// constant colours.
abstract final class AppColors {
  static AppPalette _p = AppPalette.light;

  /// The palette in force. Changed only by [use], when the scheme changes.
  static AppPalette get palette => _p;
  static Brightness get brightness => _p.brightness;
  static bool get isDark => _p.isDark;
  static void use(AppPalette palette) => _p = palette;

  static Color get canvas => _p.canvas;
  static Color get canvasEdge => _p.canvasEdge;
  static Color get surface => _p.surface;
  static Color get surfaceSoft => _p.surfaceSoft;
  static Color get surfaceMuted => _p.surfaceMuted;
  static Color get ink => _p.ink;
  static Color get muted => _p.muted;
  static Color get neutral => _p.neutral;
  static Color get line => _p.line;

  /// Hover border of a secondary button or card.
  static Color get lineStrong => _p.lineStrong;

  /// The outline of an enabled input: darker than [line] so the field stays visible
  /// (at least 3:1 against its surface).
  static Color get control => _p.control;

  static Color get blue => _p.blue;
  static Color get blueDark => _p.blueDark;
  static Color get tint => _p.tint;

  /// The second voice of the palette: every colour has one job, so a screen can be read by colour
  /// as well as by words (never by colour alone: each use also carries a label or an icon).
  ///   blue   action, selection, sales
  ///   violet customers, warranties, profit
  ///   emerald money in, in stock
  ///   amber  attention, low stock
  ///   rose   money out, returns, out of stock
  /// The strong shade is for icons, chart marks and tiles; text uses the darker status colours.
  static Color get violet => _p.violet;
  static Color get violetTint => _p.violetTint;
  static Color get violetText => _p.violetText;
  static Color get emerald => _p.emerald;
  static Color get emeraldTint => _p.emeraldTint;
  static Color get amber => _p.amber;
  static Color get amberTint => _p.amberTint;
  static Color get rose => _p.rose;
  static Color get roseTint => _p.roseTint;

  static Color get success => _p.success;
  static Color get successTint => _p.successTint;
  static Color get warning => _p.warning;
  static Color get warningTint => _p.warningTint;
  static Color get danger => _p.danger;
  static Color get dangerTint => _p.dangerTint;
  static Color get info => _p.blue;

  /// Frosted glass (see GlassSurface): the translucent fill, a denser fill for readable surfaces,
  /// the rim, and the bright top edge of the rim.
  static Color get glass => _p.glass;
  static Color get glassStrong => _p.glassStrong;
  static Color get glassEdge => _p.glassEdge;
  static Color get glassHighlight => _p.glassHighlight;
  static Color get shadow => _p.shadow;
  static Color get scrim => _p.scrim;
  static Color get orbBlue => _p.orbBlue;
  static Color get orbViolet => _p.orbViolet;
  static Color get orbTeal => _p.orbTeal;

  /// The deep surface of the one figure that matters most, and the end of the brand gradient.
  /// Navy in both schemes.
  static const navy = Color(0xFF0A1030);
  static const navyMid = Color(0xFF14226B);

  /// Text on the navy surface.
  static const onInverse = Colors.white;
  static const onInverseMuted = Color(0xFFB9C0BC);
}

abstract final class AppRadius {
  static const small = 8.0;
  static const control = 14.0;
  static const card = 16.0;
  static const dialog = 22.0;
}

/// Soft, offset, low-spread shadows tinted with the palette's shadow colour (navy in the light
/// scheme, black in the dark one). Elevation is declared once per surface: a shadow or a rim,
/// not both.
abstract final class AppShadows {
  static List<BoxShadow> _layers(double a1, double a2, double y, double blur) =>
      [
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: a1),
          offset: const Offset(0, 1),
          blurRadius: 2,
        ),
        BoxShadow(
          color: AppColors.shadow.withValues(alpha: a2),
          offset: Offset(0, y),
          blurRadius: blur,
        ),
      ];

  /// The two-layer surface shadow of a raised card.
  static List<BoxShadow> get card => AppColors.isDark
      ? _layers(0.30, 0.38, 10, 28)
      : _layers(0.05, 0.08, 10, 28);

  /// A card that can be pressed, lifted under the pointer.
  static List<BoxShadow> get cardHover => AppColors.isDark
      ? _layers(0.35, 0.5, 18, 40)
      : _layers(0.06, 0.14, 18, 40);

  /// A floating bar or sheet.
  static List<BoxShadow> get float => AppColors.isDark
      ? _layers(0.4, 0.55, 14, 36)
      : _layers(0.06, 0.16, 14, 36);

  static List<BoxShadow> get overlay => [
    BoxShadow(
      color: AppColors.shadow.withValues(alpha: AppColors.isDark ? 0.6 : 0.22),
      offset: const Offset(0, 24),
      blurRadius: 80,
    ),
  ];
}

/// Gradients are used on three things only: the brand mark, the primary button and the spotlight.
abstract final class AppGradients {
  static const brand = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B55FF), Color(0xFF5B3DF5)],
  );
  static LinearGradient get button => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [AppColors.palette.blueFill, AppColors.palette.blueFillDeep],
  );
  static LinearGradient get buttonDeep => LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      AppColors.palette.blueFillDeep,
      Color.lerp(AppColors.palette.blueFillDeep, Colors.black, 0.18)!,
    ],
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
  static ThemeData get light => _build(AppPalette.light);
  static ThemeData get dark => _build(AppPalette.dark);

  /// Builds the theme with [palette] in force, then puts the palette that was in force back: a
  /// theme holds resolved colours, so building both schemes never disturbs the one on screen.
  static ThemeData _build(AppPalette palette) {
    final previous = AppColors.palette;
    AppColors.use(palette);
    try {
      return _make(palette);
    } finally {
      AppColors.use(previous);
    }
  }

  static ThemeData _make(AppPalette p) {
    final scheme = ColorScheme.fromSeed(
      brightness: p.brightness,
      seedColor: AppColors.blue,
      primary: AppColors.blue,
      onPrimary: Colors.white,
      primaryContainer: AppColors.tint,
      onPrimaryContainer: AppColors.blue,
      surface: AppColors.surface,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.muted,
      surfaceContainerLowest: AppColors.surface,
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
      brightness: p.brightness,
      fontFamily: AppFonts.ui,
      colorScheme: scheme,
      // pages are transparent: the ambient field behind them is the page colour
      scaffoldBackgroundColor: Colors.transparent,
      visualDensity: VisualDensity.standard,
    );

    TextStyle ui(
      double size,
      FontWeight weight, {
      double height = 1.4,
      double spacing = 0,
      Color? color,
    }) => TextStyle(
      fontFamily: AppFonts.ui,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color ?? AppColors.ink,
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
      labelSmall: TextStyle(
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
      dividerTheme: DividerThemeData(color: AppColors.line, space: 1),
      iconTheme: IconThemeData(color: AppColors.ink, size: 20),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
          TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
          TargetPlatform.fuchsia: FadeForwardsPageTransitionsBuilder(
            backgroundColor: Colors.transparent,
          ),
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
        shape: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.line),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        constraints: const BoxConstraints(minHeight: 52),
        alignLabelWithHint: true,
        errorMaxLines: 3,
        helperMaxLines: 3,
        filled: true,
        // a field is a little more solid than the glass it sits on, in both schemes
        fillColor: AppColors.isDark
            ? AppColors.surface.withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.9),
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
          backgroundColor: AppColors.palette.blueFill,
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
              backgroundColor: AppColors.surface.withValues(
                alpha: AppColors.isDark ? 0.5 : 0.72,
              ),
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              shape: controlShape,
              foregroundColor: AppColors.ink,
              textStyle: ui(14, FontWeight.w600, height: 1),
              side: BorderSide(color: AppColors.line),
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
          side: WidgetStatePropertyAll(BorderSide(color: AppColors.line)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.surface
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
        backgroundColor: AppColors.surface,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
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
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shadowColor: AppColors.shadow.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.dialog),
          side: BorderSide(color: AppColors.line),
        ),
        barrierColor: AppColors.scrim,
        titleTextStyle: display(24, height: 1.25),
        contentTextStyle: ui(
          14,
          FontWeight.w400,
          height: 1.55,
          color: AppColors.muted,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
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
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: AppColors.shadow.withValues(alpha: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.control),
          side: BorderSide(color: AppColors.line),
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
        textStyle: ui(12, FontWeight.w500, color: AppColors.canvas),
        waitDuration: const Duration(milliseconds: 500),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        // the inverse of the page (dark on light, light on dark), as Material does
        backgroundColor: AppColors.ink,
        contentTextStyle: ui(14, FontWeight.w600, color: AppColors.canvas),
        actionTextColor: AppColors.isDark
            ? AppColors.palette.blueDark
            : const Color(0xFF9DB1FF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.line),
        ),
        elevation: 6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
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
        side: BorderSide(color: AppColors.control, width: 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surface,
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
