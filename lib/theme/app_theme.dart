import 'dart:async';

import 'package:flutter/material.dart';

import '../database/app_database.dart';

/// Paleta del programa: morado suave + celeste bebé.
/// Textos: BLANCOS en modo oscuro y NEGROS en modo claro.
/// Los colores se leen como getters, así que cambian al alternar el modo.
class P {
  static bool dark = true;
  static Color _c(int d, int l) => Color(dark ? d : l);

  // ── Fondos y superficies ──────────────────────────────────────────────
  static Color get bg => _c(0xFF12101C, 0xFFF6F3FD);
  static Color get panel => _c(0xFF1C1829, 0xFFFFFFFF);
  static Color get panel2 => _c(0xFF262038, 0xFFF1ECFC);
  static Color get field => _c(0xFF171424, 0xFFF4F0FD);
  static Color get head => _c(0xFF2B2449, 0xFFECE5FB);
  static Color get line => _c(0xFF352E4D, 0xFFE3DBF4);
  static Color get tint => _c(0xFF172540, 0xFFE3F3FD); // degradado de fondo (celeste suave)

  // ── Barra lateral ─────────────────────────────────────────────────────
  static Color get sidebar => _c(0xFF191427, 0xFFEFE9FC);
  static Color get sideLine => _c(0xFF2E2748, 0xFFDDD3F3);
  static Color get sideText => _c(0xFFFFFFFF, 0xFF0A0A0F);

  // ── Textos: blanco (oscuro) / negro (claro) ───────────────────────────
  static Color get text => _c(0xFFFFFFFF, 0xFF0A0A0F);
  static Color get muted => _c(0xFFD2CEDF, 0xFF34303F);
  static Color get muted2 => _c(0xFFB4AFC6, 0xFF4F4A60);
  static Color get subtle => _c(0xFF9792AD, 0xFF68637C);

  // ── Colores principales ───────────────────────────────────────────────
  static Color get accent => _c(0xFFB79CF5, 0xFF8059D8); // morado suave
  static Color get accent2 => _c(0xFF8FD3F4, 0xFF56B4EA); // celeste bebé
  static Color get onAccent => _c(0xFF0B0B0F, 0xFFFFFFFF); // texto sobre botones morados

  // ── Estados (verde / rojo / ámbar) que se ven bien en ambos modos ────
  static Color get ok => _c(0xFF3DDC97, 0xFF0E9F6E);
  static Color get err => _c(0xFFFF6B88, 0xFFE0314F);
  static Color get warn => _c(0xFFFFC04D, 0xFFD98200);

  /// Degradado de marca (morado → celeste), usado en iconos, barras y selección.
  static LinearGradient get brand => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [_c(0xFFB79CF5, 0xFF9C7BEA), _c(0xFF8FD3F4, 0xFF78C6F0)],
      );
  static const Color onBrand = Color(0xFF0B0B0F);

  /// Sombra suave de las tarjetas.
  static List<BoxShadow> get shadow => [
        BoxShadow(
          color: Color(dark ? 0x4D000000 : 0x1A6B4FC4),
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
      ];

  /// Decoración estándar de tarjeta / panel.
  static BoxDecoration card({double r = 14, Color? color}) => BoxDecoration(
        color: color ?? panel.withValues(alpha: dark ? .88 : .95),
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: dark ? accent.withValues(alpha: .42) : accent.withValues(alpha: .28)),
        boxShadow: [
          ...shadow,
          BoxShadow(color: accent.withValues(alpha: dark ? .20 : .12), blurRadius: 30),
        ],
      );

  /// Texto negro o blanco según el brillo del color de fondo.
  static Color on(Color background) =>
      background.computeLuminance() > .4 ? Color(0xFF0B0B0F) : Color(0xFFFFFFFF);
}

ThemeData buildTheme() {
  final dark = P.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF9B7FE0),
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: P.accent,
    onPrimary: P.onAccent,
    secondary: P.accent2,
    onSecondary: P.on(P.accent2),
    tertiary: P.accent2,
    surface: P.panel,
    onSurface: P.text,
    onSurfaceVariant: P.muted,
    outline: P.line,
    outlineVariant: P.line,
    error: P.err,
    surfaceContainerLowest: P.bg,
    surfaceContainerLow: P.panel,
    surfaceContainer: P.panel,
    surfaceContainerHigh: P.panel,
    surfaceContainerHighest: P.panel2,
  );

  final base = ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Segoe UI',
    fontFamilyFallback: const ['Roboto', 'Arial'],
  );

  RoundedRectangleBorder shape(double r) =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(r));
  OutlineInputBorder outline(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: c, width: w),
      );
  final btnText = TextStyle(fontWeight: FontWeight.w700, letterSpacing: .2);
  final btnPad = EdgeInsets.symmetric(horizontal: 18, vertical: 14);

  return base.copyWith(
    scaffoldBackgroundColor: P.bg,
    canvasColor: P.panel,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeUpwardsPageTransitionsBuilder(),
    }),
    dividerColor: P.line,
    dividerTheme: DividerThemeData(color: P.line, thickness: 1, space: 1),
    textTheme: base.textTheme.apply(bodyColor: P.text, displayColor: P.text),
    iconTheme: IconThemeData(color: P.text),

    // ── Campos de texto ──
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: P.field,
      isDense: false,
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: TextStyle(color: P.muted2),
      floatingLabelStyle: TextStyle(color: P.text, fontWeight: FontWeight.w600),
      hintStyle: TextStyle(color: P.subtle),
      prefixIconColor: P.muted2,
      suffixIconColor: P.muted2,
      helperStyle: TextStyle(color: P.muted2),
      errorStyle: TextStyle(color: P.err),
      border: outline(P.line),
      enabledBorder: outline(P.line),
      disabledBorder: outline(P.line.withValues(alpha: .5)),
      focusedBorder: outline(P.accent, 1.8),
      errorBorder: outline(P.err),
      focusedErrorBorder: outline(P.err, 1.8),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: P.accent,
      selectionColor: P.accent.withValues(alpha: .35),
      selectionHandleColor: P.accent,
    ),

    // ── Botones ──
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: P.accent,
        foregroundColor: P.onAccent,
        disabledBackgroundColor: P.line,
        disabledForegroundColor: P.subtle,
        elevation: 4,
        shadowColor: P.accent.withValues(alpha: .6),
        padding: btnPad,
        textStyle: btnText,
        shape: shape(12),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: P.accent,
        foregroundColor: P.onAccent,
        elevation: 0,
        padding: btnPad,
        textStyle: btnText,
        shape: shape(12),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: P.text,
        side: BorderSide(color: P.accent.withValues(alpha: .55), width: 1.2),
        padding: btnPad,
        textStyle: btnText,
        shape: shape(12),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: P.text,
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        textStyle: TextStyle(fontWeight: FontWeight.w600),
        shape: shape(10),
      ).copyWith(
        overlayColor: WidgetStatePropertyAll(P.accent.withValues(alpha: .14)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: P.text, shape: shape(10)),
    ),

    // ── Tarjetas, diálogos y menús ──
    cardTheme: CardThemeData(
      color: P.panel,
      surfaceTintColor: Colors.transparent,
      shadowColor: Color(dark ? 0xFF000000 : 0xFF6B4FC4),
      elevation: dark ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: P.line),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: P.panel,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: P.line),
      ),
      titleTextStyle: TextStyle(color: P.text, fontSize: 19, fontWeight: FontWeight.w700),
      contentTextStyle: TextStyle(color: P.text, fontSize: 14),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: P.panel,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: P.line),
      ),
      textStyle: TextStyle(color: P.text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: P.head,
      contentTextStyle: TextStyle(color: P.text, fontWeight: FontWeight.w500),
      actionTextColor: P.accent2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: P.line),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: P.head,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: P.line),
      ),
      textStyle: TextStyle(color: P.text, fontSize: 12),
    ),

    // ── Tablas, listas y pestañas ──
    dataTableTheme: DataTableThemeData(
      headingRowColor: WidgetStatePropertyAll(P.head),
      headingTextStyle: TextStyle(
        color: P.text,
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: .6,
      ),
      dataTextStyle: TextStyle(color: P.text, fontSize: 13),
      dividerThickness: .6,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: P.text,
      textColor: P.text,
      shape: shape(12),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: P.text,
      unselectedLabelColor: P.muted2,
      indicatorColor: P.accent,
      dividerColor: P.line,
      labelStyle: TextStyle(fontWeight: FontWeight.w700),
    ),

    // ── Controles ──
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? P.onAccent : P.muted2),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? P.accent : P.line),
      trackOutlineColor: WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? P.accent : Colors.transparent),
      checkColor: WidgetStatePropertyAll(P.onAccent),
      side: BorderSide(color: P.muted2, width: 1.4),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: P.accent,
      inactiveTrackColor: P.line,
      thumbColor: P.accent,
      overlayColor: P.accent.withValues(alpha: .18),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: P.accent,
      linearTrackColor: P.line,
      circularTrackColor: P.line,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(P.accent.withValues(alpha: .45)),
      radius: Radius.circular(8),
      thickness: WidgetStatePropertyAll(7),
    ),
  );
}

void _rebuildAll() {
  void visit(Element e) {
    e.markNeedsBuild();
    e.visitChildren(visit);
  }
  WidgetsBinding.instance.rootElement?.visitChildren(visit);
}

/// Controla el modo claro / oscuro y lo guarda en la base de datos.
class ThemeController extends ChangeNotifier {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  Future<void> load() async {
    try {
      final v = await AppDatabase.instance.getConfig('tema');
      P.dark = v != 'claro';
    } catch (_) {}
  }

  Future<void> toggle() async {
    P.dark = !P.dark;
    notifyListeners();
    _rebuildAll();
    try {
      await AppDatabase.instance.setConfig('tema', P.dark ? 'oscuro' : 'claro');
    } catch (_) {}
  }
}

/// Botón sol / luna para alternar el modo.
class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        tooltip: P.dark ? 'Cambiar a modo claro' : 'Cambiar a modo oscuro',
        onPressed: ThemeController.instance.toggle,
        style: IconButton.styleFrom(
          backgroundColor: P.accent.withValues(alpha: .2),
          foregroundColor: P.text,
          side: BorderSide(color: P.accent.withValues(alpha: .45)),
        ),
        icon: Icon(P.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
      );
}

/// Icono de encabezado de pantalla: cuadrado redondeado con degradado morado → celeste.
class PageIcon extends StatelessWidget {
  const PageIcon(this.icon, {super.key, this.size = 40});
  final IconData icon;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          gradient: P.brand,
          borderRadius: BorderRadius.circular(size * .32),
          boxShadow: [
            BoxShadow(
              color: P.accent.withValues(alpha: .35),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: size * .55, color: P.onBrand),
      );
}

/// Aparece suavemente deslizándose hacia arriba (con retraso opcional).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 18,
    this.duration = const Duration(milliseconds: 550),
  });
  final Widget child;
  final Duration delay;
  final double offset;
  final Duration duration;
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _a.value.clamp(0.0, 1.0).toDouble(),
          child: Transform.translate(offset: Offset(0, (1 - _a.value) * widget.offset), child: child),
        ),
      );
}

/// Se eleva ligeramente al pasar el mouse por encima.
class HoverLift extends StatefulWidget {
  const HoverLift({super.key, required this.child, this.lift = 4});
  final Widget child;
  final double lift;
  @override
  State<HoverLift> createState() => _HoverLiftState();
}

class _HoverLiftState extends State<HoverLift> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: Duration(milliseconds: 170),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hover ? -widget.lift : 0, 0),
          child: widget.child,
        ),
      );
}
