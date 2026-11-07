import 'package:flutter/material.dart';

/// Every colour of the interface for one brightness. Widgets never use literal colours: they
/// read [AppColors], which points at the palette in force, so the same screens are drawn in the
/// light or the dark scheme (a deliberate second scheme, not an inversion: surfaces are lifted
/// in steps of lightness, accents are lightened to keep their contrast, shadows are deepened).
///
/// Roles, one job each, never read by colour alone (each use also has a label or an icon):
///   blue    action and selection        violet  customers, warranties, profit
///   emerald money in, in stock          amber   attention, low stock
///   rose    money out, returns          navy    the one figure that matters most
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.canvas,
    required this.canvasEdge,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceMuted,
    required this.ink,
    required this.muted,
    required this.neutral,
    required this.line,
    required this.lineStrong,
    required this.control,
    required this.blue,
    required this.blueDark,
    required this.blueFill,
    required this.blueFillDeep,
    required this.tint,
    required this.violet,
    required this.violetTint,
    required this.violetText,
    required this.emerald,
    required this.emeraldTint,
    required this.amber,
    required this.amberTint,
    required this.rose,
    required this.roseTint,
    required this.success,
    required this.successTint,
    required this.warning,
    required this.warningTint,
    required this.danger,
    required this.dangerTint,
    required this.glass,
    required this.glassStrong,
    required this.glassEdge,
    required this.glassHighlight,
    required this.shadow,
    required this.scrim,
    required this.orbBlue,
    required this.orbViolet,
    required this.orbTeal,
  });

  final Brightness brightness;

  /// The page behind everything, and the colour the field fades to at its edges.
  final Color canvas;
  final Color canvasEdge;

  /// Opaque surfaces: inputs, menus where blur is not wanted, the inside of a card.
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceMuted;

  final Color ink;
  final Color muted;
  final Color neutral;
  final Color line;
  final Color lineStrong;

  /// The outline of an enabled input: at least 3:1 against the surface it sits on.
  final Color control;

  /// Brand cobalt as text, icons and selection, and as the fill of a filled button.
  final Color blue;
  final Color blueDark;
  final Color blueFill;
  final Color blueFillDeep;
  final Color tint;

  final Color violet;
  final Color violetTint;
  final Color violetText;
  final Color emerald;
  final Color emeraldTint;
  final Color amber;
  final Color amberTint;
  final Color rose;
  final Color roseTint;

  /// Status colours for text on their own tints.
  final Color success;
  final Color successTint;
  final Color warning;
  final Color warningTint;
  final Color danger;
  final Color dangerTint;

  /// Frosted glass: the fill of a card and of a bar (translucent), a denser fill for a surface
  /// that must stay readable over busy content, its rim, and the bright top edge of the rim.
  final Color glass;
  final Color glassStrong;
  final Color glassEdge;
  final Color glassHighlight;

  /// The colour shadows are made of, and the veil behind a dialog.
  final Color shadow;
  final Color scrim;

  /// The three soft lights of the ambient field behind the glass.
  final Color orbBlue;
  final Color orbViolet;
  final Color orbTeal;

  bool get isDark => brightness == Brightness.dark;

  /// A cool, luminous light scheme: a pale blue-grey field, white glass, deep navy ink.
  static const light = AppPalette(
    brightness: Brightness.light,
    canvas: Color(0xFFEEF1F8),
    canvasEdge: Color(0xFFE4E9F5),
    surface: Colors.white,
    surfaceSoft: Color(0xFFF6F8FC),
    surfaceMuted: Color(0xFFE7EBF4),
    ink: Color(0xFF0B1020),
    muted: Color(0xFF556079),
    neutral: Color(0xFF3C455C),
    line: Color(0xFFDCE1ED),
    lineStrong: Color(0xFFC3CADB),
    control: Color(0xFF858EA6),
    blue: Color(0xFF1740FF),
    blueDark: Color(0xFF1234D6),
    blueFill: Color(0xFF2F57FF),
    blueFillDeep: Color(0xFF1740FF),
    tint: Color(0xFFE6EBFF),
    violet: Color(0xFF6A4DFF),
    violetTint: Color(0xFFEDE9FF),
    violetText: Color(0xFF4A32C9),
    emerald: Color(0xFF0FA36B),
    emeraldTint: Color(0xFFDFF4EB),
    amber: Color(0xFFF5A300),
    amberTint: Color(0xFFFFF0CC),
    rose: Color(0xFFE5484D),
    roseTint: Color(0xFFFFE7E8),
    success: Color(0xFF14703B),
    successTint: Color(0xFFE5F4EB),
    warning: Color(0xFF8C5300),
    warningTint: Color(0xFFFFF3DB),
    danger: Color(0xFFB3261E),
    dangerTint: Color(0xFFFCEAE8),
    glass: Color(0xB8FFFFFF),
    glassStrong: Color(0xE0FFFFFF),
    glassEdge: Color(0x99FFFFFF),
    glassHighlight: Color(0xFFFFFFFF),
    shadow: Color(0xFF111A3B),
    scrim: Color(0x6B0B1020),
    orbBlue: Color(0x332F57FF),
    orbViolet: Color(0x2B8B6CFF),
    orbTeal: Color(0x2214C9B0),
  );

  /// The dark scheme: ink-blue field lit from the corners, raised surfaces a step lighter,
  /// cobalt lightened so it still reads on dark, status colours lifted to the same contrast.
  static const dark = AppPalette(
    brightness: Brightness.dark,
    canvas: Color(0xFF090C16),
    canvasEdge: Color(0xFF060810),
    surface: Color(0xFF131829),
    surfaceSoft: Color(0xFF0F1322),
    surfaceMuted: Color(0xFF1B2136),
    ink: Color(0xFFEDF0FA),
    muted: Color(0xFF9AA3BC),
    neutral: Color(0xFFC3CADF),
    line: Color(0xFF252C45),
    lineStrong: Color(0xFF353F61),
    control: Color(0xFF6C7794),
    blue: Color(0xFF8197FF),
    blueDark: Color(0xFF6C86FF),
    blueFill: Color(0xFF4765FA),
    blueFillDeep: Color(0xFF3552F0),
    tint: Color(0xFF1B2552),
    violet: Color(0xFF9B86FF),
    violetTint: Color(0xFF262058),
    violetText: Color(0xFFB7A8FF),
    emerald: Color(0xFF2FD39A),
    emeraldTint: Color(0xFF0F2F28),
    amber: Color(0xFFFFB93D),
    amberTint: Color(0xFF3A2E12),
    rose: Color(0xFFFF6E72),
    roseTint: Color(0xFF3A1B20),
    success: Color(0xFF5BDB9B),
    successTint: Color(0xFF11322A),
    warning: Color(0xFFF7B955),
    warningTint: Color(0xFF392C12),
    danger: Color(0xFFFF8A84),
    dangerTint: Color(0xFF3B1C20),
    glass: Color(0x9E161C33),
    glassStrong: Color(0xE0121730),
    glassEdge: Color(0x33FFFFFF),
    glassHighlight: Color(0x66FFFFFF),
    shadow: Color(0xFF000000),
    scrim: Color(0x99050711),
    orbBlue: Color(0x4D3552F0),
    orbViolet: Color(0x407C5CFF),
    orbTeal: Color(0x2614C9B0),
  );
}
