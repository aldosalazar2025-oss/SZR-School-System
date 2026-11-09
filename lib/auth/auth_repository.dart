import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';

/// Apartados que el administrador puede habilitar o quitar al personal.
/// ("Panel principal" y "Contactos y políticas" los ve todo el mundo; "Personal" es solo del administrador.)
const List<String> kModulosPersonal = [
  'Estudiantes',
  'Escanear QR',
  'Registro manual',
  'Reportes',
  'Horarios',
  'Personalización',
];

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.username,
    required this.role,
    this.permissions = const {},
  });
  final int id;
  final String name;
  final String username;
  final String role;
  /// Apartados habilitados (solo aplica al personal de asistencia).
  final Set<String> permissions;
  bool get isAdmin => role == 'admin';
  /// El administrador ve todo; el personal solo el Panel principal y lo habilitado.
  bool can(String module) =>
      isAdmin || module == 'Panel principal' || module == 'Contactos y políticas' || permissions.contains(module);
}

class CreatedAccount {
  const CreatedAccount(this.user, this.recoveryCode);
  final AuthUser user;
  final String recoveryCode;
}

class AuthRepository {
  AuthRepository(this._database);
  final AppDatabase _database;

  Future<bool> hasAdministrator() => _database.hasAdministrator();

  /// Permisos que recibe el personal nuevo si no se elige otra cosa.
  static const Set<String> defaultPermisos = {'Escanear QR', 'Registro manual'};

  /// null = permisos por defecto; texto vacío = ningún apartado extra.
  static Set<String> parsePermisos(String? raw) {
    if (raw == null) return {...defaultPermisos};
    return raw.split(',').map((e) => e.trim()).where(kModulosPersonal.contains).toSet();
  }

  static String _serializePermisos(Set<String> p) =>
      kModulosPersonal.where(p.contains).join(',');

  Future<void> setPermissions({
    required AuthUser admin,
    required int userId,
    required Set<String> permissions,
  }) async {
    if (!admin.isAdmin) throw StateError('Solo un administrador puede cambiar permisos.');
    final db = await _database.database;
    await db.update('usuarios', {'permisos': _serializePermisos(permissions)},
        where: "id = ? AND rol = 'personal'", whereArgs: [userId]);
  }

  /// Edita los datos de una cuenta. [newPassword] y [permissions] son opcionales.
  Future<void> updateAccount({
    required AuthUser admin,
    required int userId,
    required String name,
    required String username,
    String? newPassword,
    Set<String>? permissions,
  }) async {
    if (!admin.isAdmin) throw StateError('Solo un administrador puede editar cuentas.');
    if (name.trim().isEmpty || username.trim().isEmpty) {
      throw ArgumentError('El nombre y el usuario no pueden estar vacíos.');
    }
    if (newPassword != null && newPassword.isNotEmpty && newPassword.length < 8) {
      throw ArgumentError('La contraseña debe tener al menos 8 caracteres.');
    }
    final db = await _database.database;
    final values = <String, Object?>{'nombre': name.trim(), 'username': username.trim()};
    if (newPassword != null && newPassword.isNotEmpty) values['password_hash'] = _hash(newPassword);
    await db.transaction((txn) async {
      await txn.update('usuarios', values, where: 'id = ?', whereArgs: [userId]);
      if (permissions != null) {
        await txn.update('usuarios', {'permisos': _serializePermisos(permissions)},
            where: "id = ? AND rol = 'personal'", whereArgs: [userId]);
      }
    });
  }

  String _hash(String value) => BCrypt.hashpw(value, BCrypt.gensalt());
  bool _verify(String value, String hash) => BCrypt.checkpw(value, hash);

  String _newRecoveryCode() {
    final number = Random.secure().nextInt(10000);
    return number.toString().padLeft(4, '0');
  }

  Future<CreatedAccount> createFirstAdministrator({
    required String name,
    required String dni,
    required String username,
    required String password,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final existing = await txn.rawQuery(
        "SELECT COUNT(*) AS total FROM usuarios WHERE rol = 'admin'",
      );
      if ((existing.first['total'] as int) != 0) {
        throw StateError('El administrador principal ya fue configurado.');
      }
      return _insertAccount(
        txn, name: name, dni: dni, username: username,
        password: password, role: 'admin',
      );
    });
  }

  Future<CreatedAccount> createAccount({
    required AuthUser creator,
    required String name,
    required String dni,
    required String username,
    required String password,
    required String role,
    Set<String>? permissions,
  }) async {
    if (!creator.isAdmin) throw StateError('Solo un administrador puede crear cuentas.');
    if (role != 'admin' && role != 'personal') throw ArgumentError('Rol no válido.');
    final db = await _database.database;
    return db.transaction((txn) => _insertAccount(
      txn, name: name, dni: dni, username: username,
      password: password, role: role, permissions: permissions,
    ));
  }

  Future<CreatedAccount> _insertAccount(
    Transaction txn, {
    required String name,
    required String dni,
    required String username,
    required String password,
    required String role,
    Set<String>? permissions,
  }) async {
    final cleanUsername = username.trim();
    if (name.trim().isEmpty || cleanUsername.isEmpty || password.length < 8) {
      throw ArgumentError('Completa los datos y utiliza una contraseña de al menos 8 caracteres.');
    }
    final code = _newRecoveryCode();
    final perms = role == 'personal' ? (permissions ?? {...defaultPermisos}) : <String>{};
    final id = await txn.insert('usuarios', {
      'nombre': name.trim(),
      'dni': dni.trim(),
      'username': cleanUsername,
      'password_hash': _hash(password),
      'rol': role,
      'recovery_hash': _hash(code),
      'activo': 1,
      'permisos': role == 'personal' ? _serializePermisos(perms) : null,
      'fecha_registro': DateTime.now().toIso8601String(),
    });
    return CreatedAccount(
      AuthUser(id: id, name: name.trim(), username: cleanUsername, role: role, permissions: perms),
      code,
    );
  }

  Future<AuthUser?> signIn({required String username, required String password, required String expectedRole}) async {
    final db = await _database.database;
    final rows = await db.query('usuarios', where: 'username = ? AND activo = 1', whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['rol'] != expectedRole || !_verify(password, row['password_hash'] as String)) return null;
    final role = row['rol'] as String;
    return AuthUser(id: row['id'] as int, name: row['nombre'] as String,
      username: row['username'] as String, role: role,
      permissions: role == 'personal' ? parsePermisos(row['permisos'] as String?) : const {});
  }

  Future<void> resetPassword({required String username, required String recoveryCode, required String newPassword}) async {
    if (newPassword.length < 8) throw ArgumentError('La contraseña debe tener al menos 8 caracteres.');
    final db = await _database.database;
    await db.transaction((txn) async {
      final rows = await txn.query('usuarios', where: 'username = ? AND activo = 1', whereArgs: [username.trim()], limit: 1);
      if (rows.isEmpty) throw StateError('No se pudo verificar la cuenta o el código.');
      final row = rows.first;
      final lockedUntil = row['recovery_locked_until'] as String?;
      if (lockedUntil != null && DateTime.parse(lockedUntil).isAfter(DateTime.now())) {
        throw StateError('Demasiados intentos. Intenta nuevamente más tarde.');
      }
      final valid = _verify(recoveryCode.trim(), row['recovery_hash'] as String);
      if (!valid) {
        final attempts = (row['recovery_failed_attempts'] as int) + 1;
        await txn.update('usuarios', {
          'recovery_failed_attempts': attempts >= 5 ? 0 : attempts,
          'recovery_locked_until': attempts >= 5 ? DateTime.now().add(const Duration(minutes: 15)).toIso8601String() : null,
        }, where: 'id = ?', whereArgs: [row['id']]);
        throw StateError('No se pudo verificar la cuenta o el código.');
      }
      await txn.update('usuarios', {
        'password_hash': _hash(newPassword),
        'recovery_failed_attempts': 0,
        'recovery_locked_until': null,
      }, where: 'id = ?', whereArgs: [row['id']]);
    });
  }
}
