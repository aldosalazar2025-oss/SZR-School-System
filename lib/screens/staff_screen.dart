import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import '../main.dart';
import 'app_sidebar.dart';

/// Gestión de usuarios: crear cuentas (administrador / personal de asistencia)
/// y ver, activar o desactivar los usuarios registrados.
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
  static const green = Color(0xFF20D69A);
  static const red = Color(0xFFFF5275);

  final formKey = GlobalKey<FormState>();
  final name = TextEditingController(), username = TextEditingController(), password = TextEditingController();
  String role = 'personal';
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
        columns: ['id', 'nombre', 'username', 'rol', 'activo'], orderBy: 'nombre COLLATE NOCASE');
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
      );
      name.clear();
      username.clear();
      password.clear();
      setState(() => role = 'personal');
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
                style: TextStyle(color: cyan, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 6)),
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
                child: Text('No hay usuarios registrados.', style: TextStyle(color: P.text.withOpacity(.7))))
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
                        DataCell(Text(active ? 'Activo' : 'Inactivo',
                            style: TextStyle(color: active ? green : Colors.orange, fontWeight: FontWeight.bold))),
                        DataCell(TextButton(
                          onPressed: () => toggleActive(u),
                          child: Text(active ? 'Desactivar' : 'Activar',
                              style: TextStyle(color: active ? red : green, fontWeight: FontWeight.bold)),
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
        ]),
      );

  BoxDecoration _box() =>
      BoxDecoration(color: panel, border: Border.all(color: line), borderRadius: BorderRadius.circular(14));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      body: Row(children: [
        AppSidebar(user: widget.user, selected: 'Personal'),
        Expanded(
          child: SafeArea(
            child: Column(children: [
              Container(
                height: 66,
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  Icon(Icons.manage_accounts, color: cyan, size: 30),
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
                      return Column(children: [_form(), SizedBox(height: 14), _table()]);
                    }
                    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 340, child: _form()),
                      SizedBox(width: 16),
                      Expanded(child: _table()),
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
