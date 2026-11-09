import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../auth/auth_repository.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';
import 'app_sidebar.dart';

/// Contactos del desarrollador y políticas de privacidad del sistema.
class ContactScreen extends StatelessWidget {
  const ContactScreen({super.key, required this.user});
  final AuthUser user;

  static const developer = 'Grup Salazar';
  static const phone = '900725974';
  static const email = 'aldosalazar2025@gmail.com';

  static const List<(String, String)> _policies = [
    (
      '1. Datos que se registran',
      'El sistema registra datos de estudiantes (DNI, nombres, apellidos, grado, sección, turno, fotografía y código QR), '
          'sus asistencias (fecha, hora de entrada y salida, estado, motivo y observaciones) y las cuentas de los usuarios '
          'del sistema (nombre, usuario y contraseña).'
    ),
    (
      '2. Finalidad',
      'Los datos se usan únicamente para controlar la asistencia, emitir carnets y generar reportes de la institución. '
          'No se utilizan con fines comerciales ni publicitarios.'
    ),
    (
      '3. Almacenamiento',
      'La información se guarda en una base de datos local, en el equipo donde está instalado el sistema. '
          'El sistema no envía los datos a servidores externos ni a terceros.'
    ),
    (
      '4. Seguridad y acceso',
      'El acceso requiere usuario y contraseña. Las contraseñas y los códigos de recuperación se guardan cifrados. '
          'El administrador decide qué apartados puede ver cada persona del personal. '
          'Cada usuario debe mantener su contraseña en reserva y cerrar sesión al terminar.'
    ),
    (
      '5. Datos de menores de edad',
      'Los estudiantes son, en su mayoría, menores de edad. La institución debe contar con la autorización de sus padres '
          'o apoderados para registrar sus datos y su fotografía, y limitar su uso a los fines escolares descritos.'
    ),
    (
      '6. Conservación',
      'Los datos se conservan mientras sean necesarios para la gestión escolar. El administrador puede desactivar '
          'o eliminar registros cuando ya no se requieran.'
    ),
    (
      '7. Derechos de las personas',
      'Los titulares de los datos (o sus apoderados) pueden solicitar a la institución acceder a su información, '
          'corregirla o pedir su eliminación. Estas solicitudes se atienden a través del administrador del sistema.'
    ),
    (
      '8. Reportes y exportaciones',
      'Los archivos exportados (Excel, PDF) contienen datos personales. Quien los genera es responsable de '
          'resguardarlos y no compartirlos con personas no autorizadas.'
    ),
    (
      '9. Cambios en esta política',
      'Esta política puede actualizarse cuando el sistema cambie. La versión vigente es la que se muestra en esta pantalla.'
    ),
  ];

  BoxDecoration _box() => P.card(r: 14);

  void _copy(BuildContext context, String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copiado')));
  }

  Widget _contactRow(BuildContext context, IconData icon, String label, String value) => Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: P.accent.withValues(alpha: .14), shape: BoxShape.circle),
            child: Icon(icon, color: P.accent, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: TextStyle(color: P.muted, fontSize: 11.5)),
              SelectableText(value, style: TextStyle(color: P.text, fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
          ),
          IconButton(
            tooltip: 'Copiar',
            onPressed: () => _copy(context, value, label),
            icon: Icon(Icons.copy_rounded, color: P.muted2, size: 19),
          ),
        ]),
      );

  Widget _contactCard(BuildContext context) => Container(
        padding: EdgeInsets.all(20),
        decoration: _box(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Contacto',
              style: TextStyle(color: P.text, fontSize: 19, fontWeight: FontWeight.bold)),
          SizedBox(height: 4),
          Text('Soporte y consultas sobre el sistema.', style: TextStyle(color: P.muted, fontSize: 12.5)),
          SizedBox(height: 12),
          _contactRow(context, Icons.code_rounded, 'Desarrollado por', developer),
          _contactRow(context, Icons.phone_rounded, 'Teléfono / WhatsApp', phone),
          _contactRow(context, Icons.email_rounded, 'Correo electrónico', email),
        ]),
      );

  Widget _policyCard() => Container(
        padding: EdgeInsets.all(20),
        decoration: _box(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.privacy_tip_rounded, color: P.accent, size: 22),
            SizedBox(width: 10),
            Text('Políticas de privacidad',
                style: TextStyle(color: P.text, fontSize: 19, fontWeight: FontWeight.bold)),
          ]),
          SizedBox(height: 4),
          Text('Sistema de control de asistencia — $developer',
              style: TextStyle(color: P.muted, fontSize: 12.5)),
          SizedBox(height: 14),
          for (final p in _policies) ...[
            Text(p.$1, style: TextStyle(color: P.text, fontSize: 14, fontWeight: FontWeight.w700)),
            SizedBox(height: 4),
            Text(p.$2, style: TextStyle(color: P.muted2, fontSize: 13, height: 1.45)),
            SizedBox(height: 14),
          ],
          Text('Para cualquier consulta sobre estos temas, escribe a $email o llama al $phone.',
              style: TextStyle(color: P.muted, fontSize: 12.5)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      backgroundColor: P.bg,
      body: Row(children: [
        AppSidebar(user: user, selected: 'Contactos y políticas'),
        FContent(
          child: SafeArea(
            child: Column(children: [
              Container(
                height: 66,
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  PageIcon(Icons.contact_support_rounded),
                  SizedBox(width: 12),
                  Text('Contactos y políticas',
                      style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 860),
                      child: Column(children: [
                        FEntrance(delay: Duration(milliseconds: 120), child: _contactCard(context)),
                        SizedBox(height: 14),
                        FEntrance(delay: Duration(milliseconds: 280), child: _policyCard()),
                      ]),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
