import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';

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

  Widget _glow(Color c, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: P.dark ? .22 : .30), c.withValues(alpha: 0)]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_hasAdmin == null) return Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [P.bg, P.tint])),
        child: Stack(children: [
          Positioned(top: -140, left: -140, child: _glow(P.accent, 460)),
          Positioned(bottom: -160, right: -120, child: _glow(P.accent2, 500)),
          Positioned.fill(child: FuturisticBackground()),
          Positioned(top: 14, right: 18, child: ThemeToggleButton()),
          Center(
            child: SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 850),
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    FadeSlideIn(child: Image.asset('assets/images/logo.png', height: 160, filterQuality: FilterQuality.high)),
                    SizedBox(height: 14),
                    FadeSlideIn(delay: Duration(milliseconds: 150), child: Text('SISTEMA ESCOLAR SZR',
                        style: TextStyle(color: P.text, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 1.2, shadows: [Shadow(color: P.accent.withValues(alpha: .55), blurRadius: 18)]))),
                    SizedBox(height: 6),
                    Text('SISTEMA DE CONTROL DE ASISTENCIA',
                        style: TextStyle(color: P.muted, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 2.2)),
                    SizedBox(height: 14),
                    Container(
                      width: 72,
                      height: 4,
                      decoration: BoxDecoration(gradient: P.brand, borderRadius: BorderRadius.circular(4)),
                    ),
                    SizedBox(height: 34),
                    Wrap(spacing: 22, runSpacing: 22, alignment: WrapAlignment.center, children: [
                      FadeSlideIn(delay: Duration(milliseconds: 300), offset: 30, child: _AccessCard(icon: Icons.admin_panel_settings, title: 'Administrador', description: 'Gestión completa del sistema', color: P.accent, onTap: () => _login('admin'))),
                      FadeSlideIn(delay: Duration(milliseconds: 450), offset: 30, child: _AccessCard(icon: Icons.fact_check, title: 'Personal de asistencia', description: 'Escaneo QR y registro de asistencia', color: P.accent2, onTap: () => _login('personal'))),
                    ]),
                    SizedBox(height: 22),
                    TextButton.icon(onPressed: _adminAuthorization, icon: Icon(Icons.person_add_alt_1, size: 16), label: Text('Crear cuenta de administrador')),
                    SizedBox(height: 24),
                    Text('Aplicación local · Windows · SQLite', style: TextStyle(color: P.subtle, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      ),
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

class _AccessCard extends StatefulWidget {
  const _AccessCard({required this.icon, required this.title, required this.description, required this.color, required this.onTap});
  final IconData icon;
  final String title;
  final String description;
  final Color color;
  final VoidCallback onTap;
  @override
  State<_AccessCard> createState() => _AccessCardState();
}

class _AccessCardState extends State<_AccessCard> {
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 330,
        transform: Matrix4.translationValues(0, hover ? -4 : 0, 0),
        decoration: BoxDecoration(
          color: P.panel,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: hover ? c : P.line, width: hover ? 1.6 : 1),
          boxShadow: [BoxShadow(color: c.withValues(alpha: hover ? .38 : .14), blurRadius: hover ? 30 : 18, offset: Offset(0, 10))],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: widget.onTap,
            child: Padding(
              padding: EdgeInsets.all(28),
              child: Column(children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c.withValues(alpha: .38), c.withValues(alpha: .12)]),
                    border: Border.all(color: c.withValues(alpha: .55)),
                  ),
                  child: Icon(widget.icon, size: 42, color: c),
                ),
                SizedBox(height: 18),
                Text(widget.title, style: TextStyle(color: P.text, fontSize: 20, fontWeight: FontWeight.w800)),
                SizedBox(height: 8),
                Text(widget.description, textAlign: TextAlign.center, style: TextStyle(color: P.muted, fontSize: 13.5)),
                SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: c, foregroundColor: P.on(c)),
                    onPressed: widget.onTap,
                    child: Text('INICIAR SESIÓN'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginDialog extends StatefulWidget {
  const _LoginDialog({required this.role}); final String role;
  @override State<_LoginDialog> createState() => _LoginDialogState();
}
class _LoginDialogState extends State<_LoginDialog> {
  final user = TextEditingController(); final pass = TextEditingController(); String? error; bool busy = false;
  @override void dispose() { user.dispose(); pass.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => AlertDialog(title: Text(widget.role == 'admin' ? 'Acceso de administrador' : 'Acceso de personal'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [TextField(controller: user, autofocus: true, decoration: InputDecoration(labelText: 'Usuario')), TextField(controller: pass, obscureText: true, decoration: InputDecoration(labelText: 'Contraseña'), onSubmitted: (_) => submit()), if (error != null) Padding(padding: EdgeInsets.only(top: 12), child: Text(error!, style: TextStyle(color: P.err)))])), actions: [TextButton(onPressed: () async { await showDialog<void>(context: context, builder: (_) => _RecoveryDialog()); }, child: Text('¿Olvidaste tu contraseña?')), TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')), FilledButton(onPressed: busy ? null : submit, child: Text('Ingresar'))]);
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
    return FScaffold(
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
                      style: TextStyle(color: P.muted),
                    ),
                    SizedBox(height: 20),
                    if (recovery == null) ...[
                      field(name, 'Nombre completo'),
                      field(dni, 'DNI (opcional)'),
                      field(username, 'Nombre de usuario'),
                      field(password, 'Contraseña', secret: true),
                      field(confirm, 'Confirmar contraseña', secret: true),
                      if (error != null)
                        Text(error!, style: TextStyle(color: P.err)),
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
  @override Widget build(BuildContext context) => AlertDialog(title: Text('Crear cuenta'), content: SizedBox(width: 380, child: recovery == null ? Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [TextField(controller: name, decoration: InputDecoration(labelText: 'Nombre completo')), TextField(controller: dni, decoration: InputDecoration(labelText: 'DNI')), TextField(controller: username, decoration: InputDecoration(labelText: 'Usuario')), TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: 'Contraseña (mínimo 8 caracteres)')), SizedBox(height: 12), DropdownButtonFormField<String>(value: role, decoration: InputDecoration(labelText: 'Tipo de cuenta'), items: const [DropdownMenuItem(value: 'personal', child: Text('Personal de asistencia')), DropdownMenuItem(value: 'admin', child: Text('Administrador'))], onChanged: (v) => setState(() => role = v ?? 'personal')), if (error != null) Text(error!, style: TextStyle(color: P.err))]) : Column(mainAxisSize: MainAxisSize.min, children: [Text('Código de recuperación. Entrégalo al titular y guárdalo de forma segura.'), SizedBox(height: 12), SelectableText(recovery!, style: TextStyle(fontSize: 32, letterSpacing: 10, fontWeight: FontWeight.bold))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar')), if (recovery == null) FilledButton(onPressed: create, child: Text('Crear cuenta'))]);
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
  @override Widget build(BuildContext context) => AlertDialog(title: Text('Restablecer contraseña'), content: SizedBox(width: 360, child: Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [TextField(controller: username, decoration: InputDecoration(labelText: 'Nombre de usuario')), TextField(controller: code, maxLength: 4, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Código de recuperación (4 dígitos)')), TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: 'Nueva contraseña')), TextField(controller: confirm, obscureText: true, decoration: InputDecoration(labelText: 'Confirmar contraseña')), if (message != null) Padding(padding: EdgeInsets.only(top: 10), child: Text(message!, style: TextStyle(color: success ? P.ok : P.err)))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar')), FilledButton(onPressed: busy ? null : reset, child: Text('Restablecer'))]);
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
