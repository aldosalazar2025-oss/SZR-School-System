import 'dart:math';

import 'package:bcrypt/bcrypt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../database/app_database.dart';

class AuthUser {
  const AuthUser({required this.id, required this.name, required this.username, required this.role});
  final int id;
  final String name;
  final String username;
  final String role;
  bool get isAdmin => role == 'admin';
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
  }) async {
    if (!creator.isAdmin) throw StateError('Solo un administrador puede crear cuentas.');
    if (role != 'admin' && role != 'personal') throw ArgumentError('Rol no válido.');
    final db = await _database.database;
    return db.transaction((txn) => _insertAccount(
      txn, name: name, dni: dni, username: username,
      password: password, role: role,
    ));
  }

  Future<CreatedAccount> _insertAccount(
    Transaction txn, {
    required String name,
    required String dni,
    required String username,
    required String password,
    required String role,
  }) async {
    final cleanUsername = username.trim();
    if (name.trim().isEmpty || cleanUsername.isEmpty || password.length < 8) {
      throw ArgumentError('Completa los datos y utiliza una contraseña de al menos 8 caracteres.');
    }
    final code = _newRecoveryCode();
    final id = await txn.insert('usuarios', {
      'nombre': name.trim(),
      'dni': dni.trim(),
      'username': cleanUsername,
      'password_hash': _hash(password),
      'rol': role,
      'recovery_hash': _hash(code),
      'activo': 1,
      'fecha_registro': DateTime.now().toIso8601String(),
    });
    return CreatedAccount(
      AuthUser(id: id, name: name.trim(), username: cleanUsername, role: role),
      code,
    );
  }

  Future<AuthUser?> signIn({required String username, required String password, required String expectedRole}) async {
    final db = await _database.database;
    final rows = await db.query('usuarios', where: 'username = ? AND activo = 1', whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    if (row['rol'] != expectedRole || !_verify(password, row['password_hash'] as String)) return null;
    return AuthUser(id: row['id'] as int, name: row['nombre'] as String,
      username: row['username'] as String, role: row['rol'] as String);
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
