import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../auth/auth_repository.dart';
import 'manual_screen.dart';
import 'reports_screen.dart';
import 'schedules_screen.dart';
import 'customization_screen.dart';
import 'scan_screen.dart';
import 'staff_screen.dart';
import 'students_screen.dart';

/// Barra de navegación lateral compartida por el Panel principal y Estudiantes.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.user,
    required this.selected,
    this.onReload,
  });

  final AuthUser user;
  final String selected;
  /// Se llama al pulsar la sección ya abierta o al volver al panel principal.
  final VoidCallback? onReload;

  static Color get cyan => P.accent;
  static const red = Color(0xFFFF5275);

  List<(IconData, String)> get _items => user.isAdmin
      ? const [
          (Icons.home_rounded, 'Panel principal'),
          (Icons.school, 'Estudiantes'),
          (Icons.people, 'Personal'),
          (Icons.qr_code_scanner, 'Escanear QR'),
          (Icons.edit_note, 'Registro manual'),
          (Icons.assessment, 'Reportes'),
          (Icons.schedule, 'Horarios'),
          (Icons.palette, 'Personalización'),
        ]
      : const [
          (Icons.home_rounded, 'Panel principal'),
          (Icons.qr_code_scanner, 'Escanear QR'),
          (Icons.edit_note, 'Registro manual'),
        ];

  static Route<void> _route(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  void _tap(BuildContext context, String title) {
    if (title == selected) {
      if (title == 'Panel principal') onReload?.call();
      return;
    }
    if (title == 'Panel principal') {
      Navigator.pop(context);
      return;
    }
    Widget? page;
    if (title == 'Estudiantes') page = StudentsScreen(user: user);
    if (title == 'Personal') page = StaffScreen(user: user);
    if (title == 'Escanear QR') page = ScanScreen(user: user);
    if (title == 'Registro manual') page = ManualScreen(user: user);
    if (title == 'Reportes') page = ReportsScreen(user: user);
    if (title == 'Horarios') page = SchedulesScreen(user: user);
    if (title == 'Personalización') page = CustomizationScreen(user: user);
    if (page != null) {
      final route = _route(page);
      if (selected == 'Panel principal') {
        Navigator.push(context, route).then((_) => onReload?.call());
      } else {
        Navigator.pushReplacement(context, route);
      }
      return;
    }
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text('El apartado "$title" está en el menú. Su funcionalidad se desarrollará en la siguiente etapa.'),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        width: 235,
        color: P.sidebar,
        child: LayoutBuilder(builder: (context, box) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: IntrinsicHeight(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: 16),
          Center(child: Image.asset('assets/images/logo.png', width: 150, height: 150, filterQuality: FilterQuality.high)),
          SizedBox(height: 14),
          SizedBox(height: 26),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(user.username.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: P.text, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Text('Sistema de control escolar', style: TextStyle(color: P.muted2, fontSize: 10)),
          ),
          Divider(color: P.sideLine, height: 1),
          SizedBox(height: 10),
          for (final item in _items)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 9, vertical: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _tap(context, item.$2),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 11, vertical: 13),
                  decoration: BoxDecoration(
                    color: item.$2 == selected ? cyan.withOpacity(.14) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(children: [
                    Icon(item.$1, color: item.$2 == selected ? cyan : P.sideText, size: 20),
                    SizedBox(width: 13),
                    Expanded(
                      child: Text(item.$2,
                          style: TextStyle(
                              color: P.text,
                              fontSize: 12,
                              fontWeight: item.$2 == selected ? FontWeight.bold : FontWeight.w500)),
                    ),
                  ]),
                ),
              ),
            ),
          Spacer(),
          ListTile(
            dense: true,
            leading: Icon(P.dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded, color: P.accent2, size: 20),
            title: Text(P.dark ? 'Modo claro' : 'Modo oscuro', style: TextStyle(color: P.text, fontSize: 12)),
            onTap: ThemeController.instance.toggle,
          ),
          Divider(color: P.sideLine, height: 1),
          ListTile(
            leading: Icon(Icons.logout, color: red, size: 20),
            title: Text('Cerrar sesión', style: TextStyle(color: P.text, fontSize: 12)),
            onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
          ),
          SizedBox(height: 12),
        ])),
          ),
        )),
      );
}
