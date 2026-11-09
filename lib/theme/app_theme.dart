import 'package:flutter/material.dart';

import '../database/app_database.dart';

/// Paleta del programa: morado suave + celeste bebé, en modo claro y oscuro.
/// Los colores se leen como getters, así que cambian al alternar el modo.
class P {
  static bool dark = true;
  static Color _c(int d, int l) => Color(dark ? d : l);

  // Fondos y superficies
  static Color get bg => _c(0xFF14111F, 0xFFF5F2FC);
  static Color get panel => _c(0xFF1E1A2E, 0xFFFFFFFF);
  static Color get panel2 => _c(0xFF2A2440, 0xFFF0EBFB);
  static Color get field => _c(0xFF181426, 0xFFF1EDFB);
  static Color get head => _c(0xFF2A2347, 0xFFEAE3FA);
  static Color get line => _c(0xFF332C4A, 0xFFE0D8F2);
  static Color get tint => _c(0xFF1B2342, 0xFFE4F3FC); // degradado de fondo (celeste suave)

  // Barra lateral
  static Color get sidebar => _c(0xFF1B1630, 0xFFEDE6FB);
  static Color get sideLine => _c(0xFF2E2748, 0xFFD9CEF2);
  static Color get sideText => _c(0xFFD9D2EE, 0xFF4A4166);

  // Textos
  static Color get text => _c(0xFFF3F0FB, 0xFF2A2340);
  static Color get muted => _c(0xFFC1BAD9, 0xFF635B80);
  static Color get muted2 => _c(0xFFA79FC4, 0xFF7A7298);
  static Color get subtle => _c(0xFF8A82A8, 0xFF9890B4);

  // Colores principales
  static Color get accent => _c(0xFFB79CF5, 0xFF8F6BE0); // morado suave
  static Color get accent2 => _c(0xFF8FD3F4, 0xFF5DB8E8); // celeste bebé
  static Color get onAccent => _c(0xFF1B1030, 0xFFFFFFFF);
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
    onSecondary: dark ? const Color(0xFF0D2230) : Colors.white,
    surface: P.panel,
    onSurface: P.text,
    onSurfaceVariant: P.muted,
    outline: P.line,
    outlineVariant: P.line,
    surfaceContainerLowest: P.bg,
    surfaceContainerLow: P.panel,
    surfaceContainer: P.panel,
    surfaceContainerHigh: P.panel,
    surfaceContainerHighest: P.panel2,
  );
  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: P.bg,
    dividerColor: P.line,
    textTheme: base.textTheme.apply(bodyColor: P.text, displayColor: P.text),
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
        icon: Icon(P.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
      );
}
