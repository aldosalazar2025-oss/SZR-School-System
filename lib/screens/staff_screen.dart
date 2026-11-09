import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import '../main.dart';
import 'app_sidebar.dart';

/// Gestión de usuarios: crear cuentas (administrador / personal de asistencia),
/// elegir qué apartados verá el personal, y activar o desactivar usuarios.
const Map<String, IconData> _modIcons = {
  'Estudiantes': Icons.school,
  'Escanear QR': Icons.qr_code_scanner,
  'Registro manual': Icons.edit_note,
  'Reportes': Icons.assessment,
  'Horarios': Icons.schedule,
  'Personalización': Icons.palette,
};

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key, required this.user});
  final AuthUser user;
  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static Color get green => P.ok;
  static Color get red => P.err;

  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(), username = TextEditingController(), password = TextEditingController();
  String role = 'personal';
  Set<String> perms = {...AuthRepository.defaultPermisos};
  bool busy = false, showPassword = false;
  List<Map<String, Object?>> users = [];

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  void dispose() {
    name.dispose();
    username.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    final db = await AppDatabase.instance.database;
    final data = await db.query('usuarios',
        columns: ['id', 'nombre', 'username', 'rol', 'activo', 'permisos'], orderBy: 'nombre COLLATE NOCASE');
    if (!mounted) return;
    setState(() => users = data);
  }

  void _message(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  Future<void> createUser() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final result = await authRepository.createAccount(
        creator: widget.user,
        name: name.text,
        dni: '',
        username: username.text,
        password: password.text,
        role: role,
        permissions: role == 'personal' ? perms : null,
      );
      name.clear();
      username.clear();
      password.clear();
      setState(() {
        role = 'personal';
        perms = {...AuthRepository.defaultPermisos};
      });
      await refresh();
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (c) => AlertDialog(
          backgroundColor: panel,
          title: Text('Usuario creado'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Se creó la cuenta de ${result.user.name}.'),
            SizedBox(height: 12),
            Text('Código de recuperación (se usa para restablecer la contraseña):'),
            SizedBox(height: 6),
            SelectableText(result.recoveryCode,
                style: TextStyle(color: P.text, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 6)),
            SizedBox(height: 8),
            Text('Anótalo y entrégaselo al usuario: no se volverá a mostrar.',
                style: TextStyle(color: P.muted, fontSize: 12)),
          ]),
          actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text('Entendido'))],
        ),
      );
    } catch (e) {
      final text = e.toString();
      _message(text.contains('UNIQUE') ? 'Ese usuario ya existe. Usa otro correo o nombre de usuario.' : text.replaceFirst(RegExp(r'^[A-Za-z]+: '), ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> toggleActive(Map<String, Object?> u) async {
    final isActive = u['activo'] == 1;
    if (isActive && u['id'] == widget.user.id) {
      _message('No puedes desactivar tu propia cuenta.');
      return;
    }
    final db = await AppDatabase.instance.database;
    if (isActive && u['rol'] == 'admin') {
      final rows = await db.rawQuery("SELECT COUNT(*) AS total FROM usuarios WHERE rol='admin' AND activo=1");
      final admins = (rows.first['total'] as int?) ?? 0;
      if (admins <= 1) {
        _message('Debe quedar al menos un administrador activo.');
        return;
      }
    }
    await db.update('usuarios', {'activo': isActive ? 0 : 1}, where: 'id=?', whereArgs: [u['id']]);
    await refresh();
  }

  Widget _permsPicker(Set<String> selected, void Function(String module, bool on) onChanged) => Container(
        padding: EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          border: Border.all(color: P.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Apartados que podrá ver',
              style: TextStyle(color: P.text, fontWeight: FontWeight.bold, fontSize: 13)),
          SizedBox(height: 2),
          Text('El Panel principal siempre está disponible.',
              style: TextStyle(color: P.muted, fontSize: 11.5)),
          for (final m in kModulosPersonal)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(m),
              onChanged: (v) => onChanged(m, v == true),
              title: Row(children: [
                Icon(_modIcons[m], size: 18, color: P.muted2),
                SizedBox(width: 8),
                Expanded(child: Text(m, style: TextStyle(color: P.text, fontSize: 13))),
              ]),
            ),
        ]),
      );

  Future<void> editUser(Map<String, Object?> u) async {
    final isPersonal = u['rol'] == 'personal';
    final nameC = TextEditingController(text: '${u['nombre']}');
    final userC = TextEditingController(text: '${u['username']}');
    final passC = TextEditingController();
    final sel = Set<String>.from(AuthRepository.parsePermisos(u['permisos'] as String?));
    String? error;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          backgroundColor: panel,
          title: Text('Editar usuario'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: 6),
                TextField(controller: nameC, style: TextStyle(color: P.text), decoration: _dec('Nombre completo')),
                _gap(),
                TextField(controller: userC, style: TextStyle(color: P.text), decoration: _dec('Usuario o correo electrónico')),
                _gap(),
                TextField(
                    controller: passC,
                    obscureText: true,
                    style: TextStyle(color: P.text),
                    decoration: _dec('Nueva contraseña (dejar vacío para no cambiar)')),
                if (isPersonal) ...[
                  _gap(),
                  _permsPicker(sel, (m, on) => setLocal(() {
                        if (on) {
                          sel.add(m);
                        } else {
                          sel.remove(m);
                        }
                      })),
                ],
                if (error != null)
                  Padding(padding: EdgeInsets.only(top: 10), child: Text(error!, style: TextStyle(color: red))),
              ]),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                try {
                  await authRepository.updateAccount(
                    admin: widget.user,
                    userId: u['id'] as int,
                    name: nameC.text,
                    username: userC.text,
                    newPassword: passC.text,
                    permissions: isPersonal ? sel : null,
                  );
                  if (c.mounted) Navigator.pop(c, true);
                } catch (e) {
                  final t = e.toString();
                  setLocal(() => error = t.contains('UNIQUE')
                      ? 'Ese usuario ya existe. Usa otro.'
                      : t.replaceFirst(RegExp(r'^[A-Za-z]+: '), ''));
                }
              },
              child: Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    nameC.dispose();
    userC.dispose();
    passC.dispose();
    if (ok != true) return;
    await refresh();
    _message('Usuario actualizado. Los permisos se aplican cuando inicie sesión de nuevo.');
  }

  String _permsSummary(Map<String, Object?> u) {
    if (u['rol'] == 'admin') return 'Todos';
    final n = AuthRepository.parsePermisos(u['permisos'] as String?).length;
    return n == 0 ? 'Solo Panel principal' : '$n de ${kModulosPersonal.length}';
  }

  InputDecoration _dec(String label, {Widget? suffix}) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: P.muted),
        border: OutlineInputBorder(),
        suffixIcon: suffix,
      );

  Widget _gap() => SizedBox(height: 14);

  Widget _form() => Container(
        padding: EdgeInsets.all(18),
        decoration: _box(),
        child: Form(
          key: formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Nuevo usuario',
                textAlign: TextAlign.center,
                style: TextStyle(color: P.text, fontSize: 19, fontWeight: FontWeight.bold)),
            SizedBox(height: 18),
            TextFormField(
              controller: name,
              style: TextStyle(color: P.text),
              decoration: _dec('Nombre completo'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el nombre completo' : null,
            ),
            _gap(),
            TextFormField(
              controller: username,
              style: TextStyle(color: P.text),
              decoration: _dec('Usuario o correo electrónico'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el usuario' : null,
            ),
            _gap(),
            TextFormField(
              controller: password,
              obscureText: !showPassword,
              style: TextStyle(color: P.text),
              decoration: _dec('Contraseña temporal',
                  suffix: IconButton(
                    tooltip: showPassword ? 'Ocultar' : 'Mostrar',
                    onPressed: () => setState(() => showPassword = !showPassword),
                    icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                  )),
              validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
            ),
            _gap(),
            DropdownButtonFormField<String>(
              value: role,
              dropdownColor: panel,
              style: TextStyle(color: P.text),
              decoration: _dec('Rol'),
              items: const [
                DropdownMenuItem(value: 'personal', child: Text('Personal de asistencia')),
                DropdownMenuItem(value: 'admin', child: Text('Administrador')),
              ],
              onChanged: (v) => setState(() => role = v ?? role),
            ),
            SizedBox(height: 14),
            if (role == 'personal')
              _permsPicker(perms, (m, on) => setState(() {
                    if (on) {
                      perms.add(m);
                    } else {
                      perms.remove(m);
                    }
                  }))
            else
              Text('El administrador tiene acceso a todos los apartados.',
                  style: TextStyle(color: P.muted, fontSize: 12)),
            SizedBox(height: 20),
            SizedBox(
              height: 48,
              child: FilledButton.icon(
                onPressed: busy ? null : createUser,
                icon: Icon(Icons.person_add),
                label: Text(busy ? 'Creando...' : 'Crear usuario'),
              ),
            ),
          ]),
        ),
      );

  Widget _table() => Container(
        padding: EdgeInsets.all(18),
        decoration: _box(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Usuarios registrados',
              textAlign: TextAlign.center,
              style: TextStyle(color: P.text, fontSize: 19, fontWeight: FontWeight.bold)),
          SizedBox(height: 14),
          if (users.isEmpty)
            Padding(
                padding: EdgeInsets.all(18),
                child: Text('No hay usuarios registrados.', style: TextStyle(color: P.muted)))
          else
            LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: c.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(P.head),
                    dataRowMinHeight: 52,
                    dataRowMaxHeight: 56,
                    columns: const [
                      DataColumn(label: Text('NOMBRE')),
                      DataColumn(label: Text('USUARIO / CORREO')),
                      DataColumn(label: Text('ROL')),
                      DataColumn(label: Text('APARTADOS')),
                      DataColumn(label: Text('ESTADO')),
                      DataColumn(label: Text('ACCIÓN')),
                    ],
                    rows: users.map((u) {
                      final active = u['activo'] == 1;
                      return DataRow(cells: [
                        DataCell(Text('${u['nombre']}', style: TextStyle(color: P.text))),
                        DataCell(Text('${u['username']}', style: TextStyle(color: P.text))),
                        DataCell(Text(u['rol'] == 'admin' ? 'Administrador' : 'Personal de asistencia',
                            style: TextStyle(color: P.text))),
                        DataCell(Text(_permsSummary(u), style: TextStyle(color: P.text))),
                        DataCell(Text(active ? 'Activo' : 'Inactivo',
                            style: TextStyle(color: active ? green : Colors.orange, fontWeight: FontWeight.bold))),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          TextButton(
                            onPressed: () => editUser(u),
                            child: Text('Editar', style: TextStyle(color: cyan, fontWeight: FontWeight.bold)),
                          ),
                          TextButton(
                            onPressed: () => toggleActive(u),
                            child: Text(active ? 'Desactivar' : 'Activar',
                                style: TextStyle(color: active ? red : green, fontWeight: FontWeight.bold)),
                          ),
                        ])),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
        ]),
      );

  BoxDecoration _box() =>
      P.card(r: 14);

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      backgroundColor: bg,
      body: Row(children: [
        AppSidebar(user: widget.user, selected: 'Personal'),
        FContent(
          child: SafeArea(
            child: Column(children: [
              Container(
                height: 66,
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  PageIcon(Icons.manage_accounts),
                  SizedBox(width: 12),
                  Text('Gestión de usuarios',
                      style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
                  child: LayoutBuilder(builder: (context, c) {
                    if (c.maxWidth < 850) {
                      return Column(children: [
                        FEntrance(delay: Duration(milliseconds: 120), child: _form()),
                        SizedBox(height: 14),
                        FEntrance(delay: Duration(milliseconds: 280), child: _table()),
                      ]);
                    }
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 340, child: FEntrance(delay: Duration(milliseconds: 120), child: _form())),
                      SizedBox(width: 16),
                      Expanded(child: FEntrance(delay: Duration(milliseconds: 280), child: _table())),
                    ]);
                  }),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
