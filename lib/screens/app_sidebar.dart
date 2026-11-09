import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../auth/auth_repository.dart';
import 'manual_screen.dart';
import 'reports_screen.dart';
import 'schedules_screen.dart';
import 'contact_screen.dart';
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
  static Color get red => P.err;

  static const List<(IconData, String)> _all = [
    (Icons.home_rounded, 'Panel principal'),
    (Icons.school, 'Estudiantes'),
    (Icons.people, 'Personal'),
    (Icons.qr_code_scanner, 'Escanear QR'),
    (Icons.edit_note, 'Registro manual'),
    (Icons.assessment, 'Reportes'),
    (Icons.schedule, 'Horarios'),
    (Icons.palette, 'Personalización'),
    (Icons.contact_support_rounded, 'Contactos y políticas'),
  ];

  /// El administrador ve todo; el personal solo lo que el administrador habilitó.
  List<(IconData, String)> get _items => [
        for (final item in _all)
          if (user.can(item.$2)) item,
      ];

  static Route<void> _route(Widget page) => PageRouteBuilder<void>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );

  void _tap(BuildContext context, String title) {
    if (!user.can(title)) return;
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
    if (title == 'Contactos y políticas') page = ContactScreen(user: user);
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
  Widget build(BuildContext context) {
    final initial = user.username.isEmpty ? '?' : user.username[0].toUpperCase();
    return Container(
      width: 235,
      decoration: BoxDecoration(
        color: P.sidebar,
        border: Border(right: BorderSide(color: P.sideLine)),
      ),
      child: LayoutBuilder(builder: (context, box) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: box.maxHeight),
          child: IntrinsicHeight(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(height: 18),
            Center(child: Image.asset('assets/images/logo.png', width: 128, height: 128, filterQuality: FilterQuality.high)),
            SizedBox(height: 14),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: P.accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: P.accent.withValues(alpha: .3)),
                ),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(gradient: P.brand, shape: BoxShape.circle),
                    child: Text(initial, style: TextStyle(color: P.onBrand, fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(user.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: P.text, fontWeight: FontWeight.w700, fontSize: 13)),
                      Text(user.isAdmin ? 'Administrador' : 'Personal de asistencia',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: P.muted2, fontSize: 10.5)),
                    ]),
                  ),
                ]),
              ),
            ),
            SizedBox(height: 18),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text('MENÚ', style: TextStyle(color: P.subtle, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
            ),
            SizedBox(height: 6),
            for (final item in _items)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  hoverColor: P.accent.withValues(alpha: .10),
                  onTap: () => _tap(context, item.$2),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: item.$2 == selected
                          ? LinearGradient(colors: [P.accent.withValues(alpha: .30), P.accent2.withValues(alpha: .18)])
                          : null,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: item.$2 == selected ? [BoxShadow(color: P.accent.withValues(alpha: .28), blurRadius: 14)] : null,
                      border: Border.all(
                          color: item.$2 == selected ? P.accent.withValues(alpha: .55) : Colors.transparent),
                    ),
                    child: Row(children: [
                      Icon(item.$1, color: item.$2 == selected ? P.text : P.muted2, size: 20),
                      SizedBox(width: 13),
                      Expanded(
                        child: Text(item.$2,
                            style: TextStyle(
                                color: P.text,
                                fontSize: 12.5,
                                fontWeight: item.$2 == selected ? FontWeight.w800 : FontWeight.w500)),
                      ),
                      if (item.$2 == selected)
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(gradient: P.brand, shape: BoxShape.circle),
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
}
