import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import '../auth/auth_repository.dart';
import '../main.dart';
import 'dashboard_screen.dart';

class AccessScreen extends StatefulWidget {
  const AccessScreen({super.key});
  @override
  State<AccessScreen> createState() => _AccessScreenState();
}

class _AccessScreenState extends State<AccessScreen> {
  bool? _hasAdmin;
  @override
  void initState() { super.initState(); _checkSetup(); }
  Future<void> _checkSetup() async {
    final ready = await authRepository.hasAdministrator();
    if (mounted) setState(() => _hasAdmin = ready);
  }

  @override
  Widget build(BuildContext context) {
    if (_hasAdmin == null) return Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [P.bg, P.tint])), child: Stack(children: [
        Positioned(top: 14, right: 18, child: ThemeToggleButton()),
        Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 850), child: Padding(
        padding: EdgeInsets.all(32), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Image.asset('assets/images/logo.png', height: 170, filterQuality: FilterQuality.high),
          SizedBox(height: 12), Text('GESTOR DE ASISTENCIAS', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 1)),
          Text('SISTEMA DE CONTROL DE ASISTENCIA', style: TextStyle(color: P.text.withOpacity(.6))),
          SizedBox(height: 36),
          Wrap(spacing: 20, runSpacing: 20, alignment: WrapAlignment.center, children: [
            _AccessCard(icon: Icons.admin_panel_settings, title: 'Administrador', description: 'Gestión completa del sistema', color: P.accent, onTap: () => _login('admin')),
            _AccessCard(icon: Icons.fact_check, title: 'Personal de asistencia', description: 'Escaneo QR y registro de asistencia', color: P.accent2, onTap: () => _login('personal')),
          ]),
          SizedBox(height: 22),
          TextButton.icon(onPressed: _adminAuthorization, icon: Icon(Icons.person_add_alt_1, size: 16), label: Text('Crear cuenta de administrador')),
          SizedBox(height: 28), Text('Aplicación local · Windows · SQLite', style: TextStyle(color: P.text.withOpacity(.38), fontSize: 12)),
        ]),
      ))),
      ])),
    );
  }

  Future<void> _login(String role) async {
    final result = await showDialog<AuthUser>(context: context, builder: (_) => _LoginDialog(role: role));
    if (result == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DashboardScreen(user: result),
    ));
  }

  Future<void> _adminAuthorization() async {
    if (_hasAdmin == false) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => _FirstAdminSetup(onCreated: () {
          Navigator.of(context).pop();
          _checkSetup();
        }),
      ));
      return;
    }
    final admin = await showDialog<AuthUser>(context: context, builder: (_) => _LoginDialog(role: 'admin'));
    if (admin == null || !mounted) return;
    await showDialog<void>(context: context, builder: (_) => _CreateAccountDialog(admin: admin));
  }
}

class _AccessCard extends StatelessWidget {
  const _AccessCard({required this.icon, required this.title, required this.description, required this.color, required this.onTap});
  final IconData icon; final String title; final String description; final Color color; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SizedBox(width: 330, child: Card(child: InkWell(borderRadius: BorderRadius.circular(16), onTap: onTap, child: Padding(padding: EdgeInsets.all(28), child: Column(children: [Icon(icon, size: 48, color: color), SizedBox(height: 16), Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), SizedBox(height: 8), Text(description, textAlign: TextAlign.center, style: TextStyle(color: P.text.withOpacity(.6))), SizedBox(height: 20), SizedBox(width: double.infinity, child: FilledButton(style: FilledButton.styleFrom(backgroundColor: color), onPressed: onTap, child: Text('INICIAR SESIÓN')))])))));
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.role}); final String role;
  @override State<_LoginDialog> createState() => _LoginDialogState();
}
class _LoginDialogState extends State<_LoginDialog> {
  final user = TextEditingController(); final pass = TextEditingController(); String? error; bool busy = false;
  @override void dispose() { user.dispose(); pass.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(widget.role == 'admin' ? 'Acceso de administrador' : 'Acceso de personal'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: user, autofocus: true, decoration: InputDecoration(labelText: 'Usuario')), TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: 'Contraseña'), onSubmitted: (_) => submit()), if (error != null) Padding(padding: EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: Colors.redAccent)))])), actions: [TextButton(onPressed: () async { await showDialog<void>(context: context, builder: (_) => _RecoveryDialog()); }, child: Text('¿Olvidaste tu contraseña?')), TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')), FilledButton(onPressed: busy ? null : submit, child: Text('Ingresar'))]);
  Future<void> submit() async { setState(() { busy = true; error = null; }); try { final found = await authRepository.signIn(username: user.text, password: pass.text, expectedRole: widget.role); if (!mounted) return; if (found == null) { setState(() => error = 'Usuario o contraseña incorrectos, o cuenta inactiva.'); } else { Navigator.pop(context, found); } } catch (_) { if (mounted) setState(() => error = 'No se pudo validar el acceso.'); } finally { if (mounted) setState(() => busy = false); } }
}

class _FirstAdminSetup extends StatefulWidget {
  const _FirstAdminSetup({required this.onCreated}); final VoidCallback onCreated;
  @override State<_FirstAdminSetup> createState() => _FirstAdminSetupState();
}
class _FirstAdminSetupState extends State<_FirstAdminSetup> {
  final name = TextEditingController(), dni = TextEditingController(), username = TextEditingController(), password = TextEditingController(), confirm = TextEditingController();
  String? error; bool busy = false; String? recovery;
  @override void dispose() { name.dispose(); dni.dispose(); username.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          child: SizedBox(
            width: 480,
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield, size: 48, color: P.accent2),
                    SizedBox(height: 12),
                    Text(
                      'CONFIGURACIÓN INICIAL',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Crea el administrador principal del sistema',
                      style: TextStyle(color: P.text.withOpacity(.6)),
                    ),
                    SizedBox(height: 20),
                    if (recovery == null) ...[
                      field(name, 'Nombre completo'),
                      field(dni, 'DNI (opcional)'),
                      field(username, 'Nombre de usuario'),
                      field(password, 'Contraseña', secret: true),
                      field(confirm, 'Confirmar contraseña', secret: true),
                      if (error != null)
                        Text(error!, style: TextStyle(color: Colors.redAccent)),
                      SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: busy ? null : create,
                          child: Text('CREAR ADMINISTRADOR PRINCIPAL'),
                        ),
                      ),
                    ] else ...[
                      Text(
                        'Guarda tu código de recuperación. Se muestra una sola vez.',
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 12),
                      SelectableText(
                        recovery!,
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 12,
                        ),
                      ),
                      SizedBox(height: 16),
                      FilledButton(
                        onPressed: widget.onCreated,
                        child: Text('YA GUARDÉ MI CÓDIGO · CONTINUAR'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  Widget field(TextEditingController c, String label, {bool secret = false}) => Padding(padding: EdgeInsets.only(bottom: 10), child: TextField(controller: c, obscureText: secret, decoration: InputDecoration(labelText: label, border: OutlineInputBorder())));
  Future<void> create() async { if (password.text != confirm.text) { setState(() => error = 'Las contraseñas no coinciden.'); return; } setState(() { busy = true; error = null; }); try { final created = await authRepository.createFirstAdministrator(name: name.text, dni: dni.text, username: username.text, password: password.text); if (mounted) setState(() => recovery = created.recoveryCode); } catch (e) { if (mounted) setState(() => error = e.toString()); } finally { if (mounted) setState(() => busy = false); } }
}

class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({required this.admin}); final AuthUser admin;
  @override State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}
class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final name = TextEditingController(), dni = TextEditingController(), username = TextEditingController(), password = TextEditingController(); String role = 'personal'; String? error, recovery;
  @override void dispose() { name.dispose(); dni.dispose(); username.dispose(); password.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text('Crear cuenta'), content: SizedBox(width: 380, child: recovery == null ? Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: name, decoration: InputDecoration(labelText: 'Nombre completo')), TextField(controller: dni, decoration: InputDecoration(labelText: 'DNI')), TextField(controller: username, decoration: InputDecoration(labelText: 'Usuario')), TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: 'Contraseña (mínimo 8 caracteres)')), SizedBox(height: 12), DropdownButtonFormField<String>(value: role, decoration: InputDecoration(labelText: 'Tipo de cuenta'), items: const [DropdownMenuItem(value: 'personal', child: Text('Personal de asistencia')), DropdownMenuItem(value: 'admin', child: Text('Administrador'))], onChanged: (v) => setState(() => role = v ?? 'personal')), if (error != null) Text(error!, style: TextStyle(color: Colors.redAccent))]) : Column(mainAxisSize: MainAxisSize.min, children: [Text('Código de recuperación. Entrégalo al titular y guárdalo de forma segura.'), SizedBox(height: 12), SelectableText(recovery!, style: TextStyle(fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.bold))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar')), if (recovery == null) FilledButton(onPressed: create, child: Text('Crear cuenta'))]);
  Future<void> create() async { try { final result = await authRepository.createAccount(creator: widget.admin, name: name.text, dni: dni.text, username: username.text, password: password.text, role: role); if (mounted) setState(() => recovery = result.recoveryCode); } catch (e) { if (mounted) setState(() => error = e.toString()); } }
}


class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog();
  @override State<_RecoveryDialog> createState() => _RecoveryDialogState();
}
class _RecoveryDialogState extends State<_RecoveryDialog> {
  final username = TextEditingController(), code = TextEditingController(), password = TextEditingController(), confirm = TextEditingController();
  String? message; bool success = false, busy = false;
  @override void dispose() { username.dispose(); code.dispose(); password.dispose(); confirm.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text('Restablecer contraseña'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: username, decoration: InputDecoration(labelText: 'Nombre de usuario')), TextField(controller: code, maxLength: 4, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Código de recuperación (4 dígitos)')), TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: 'Nueva contraseña')), TextField(controller: confirm, obscureText: true, decoration: InputDecoration(labelText: 'Confirmar contraseña')), if (message != null) Padding(padding: EdgeInsets.only(top: 10), child: Text(message!, style: TextStyle(color: success ? Colors.greenAccent : Colors.redAccent)))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar')), FilledButton(onPressed: busy ? null : reset, child: Text('Restablecer'))]);
  Future<void> reset() async {
    if (password.text != confirm.text) { setState(() { message = 'Las contraseñas no coinciden.'; success = false; }); return; }
    setState(() { busy = true; message = null; });
    try {
      await authRepository.resetPassword(username: username.text, recoveryCode: code.text, newPassword: password.text);
      if (mounted) setState(() { message = 'Contraseña actualizada. Ya puedes iniciar sesión.'; success = true; });
    } catch (e) { if (mounted) setState(() { message = e.toString().replaceFirst('Bad state: ', '').replaceFirst('Invalid argument(s): ', ''); success = false; }); }
    finally { if (mounted) setState(() => busy = false); }
  }
}
