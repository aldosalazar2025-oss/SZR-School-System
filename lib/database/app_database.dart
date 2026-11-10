import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final path = await _resolveDbPath();
    _database = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 6,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE usuarios (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              nombre TEXT NOT NULL,
              dni TEXT,
              username TEXT NOT NULL COLLATE NOCASE UNIQUE,
              password_hash TEXT NOT NULL,
              rol TEXT NOT NULL CHECK (rol IN ('admin','personal')),
              recovery_hash TEXT NOT NULL,
              activo INTEGER NOT NULL DEFAULT 1,
              recovery_failed_attempts INTEGER NOT NULL DEFAULT 0,
              recovery_locked_until TEXT,
              permisos TEXT,
              fecha_registro TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE configuracion (
              clave TEXT PRIMARY KEY,
              valor TEXT NOT NULL
            )
          ''');
          await _createSchoolTables(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) await _createSchoolTables(db);
          if (oldVersion < 3) {
            await db.execute('ALTER TABLE alumnos ADD COLUMN foto BLOB');
            await db.execute('ALTER TABLE alumnos ADD COLUMN codigo_qr TEXT');
          }
          if (oldVersion < 4) await _migrateV4(db);
          if (oldVersion < 5) await _migrateV5(db);
          if (oldVersion < 6) await _migrateV6(db);
        },
      ),
    );
    return _database!;
  }

  /// La base de datos va en una carpeta del usuario (%LOCALAPPDATA%\SZR Asistencias),
  /// que siempre tiene permiso de escritura. Si el programa está instalado en
  /// "Program Files", la carpeta del programa es de solo lectura y no sirve.
  /// Si ya existía una base en la ubicación anterior, se copia la primera vez.
  Future<String> _resolveDbPath() async {
    final legacyBase = await databaseFactory.getDatabasesPath();
    final legacy = p.join(legacyBase, 'gestor_asistencias', 'gestor_asistencias.db');
    final root = Platform.environment['LOCALAPPDATA'] ?? Platform.environment['APPDATA'];
    if (root == null || root.isEmpty) {
      await Directory(p.dirname(legacy)).create(recursive: true);
      return legacy;
    }
    final dir = p.join(root, 'SZR Asistencias');
    final path = p.join(dir, 'gestor_asistencias.db');
    await Directory(dir).create(recursive: true);
    if (!await File(path).exists() && await File(legacy).exists()) {
      try {
        await File(legacy).copy(path);
      } catch (_) {}
    }
    return path;
  }

  Future<void> _createSchoolTables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS alumnos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        dni TEXT, nombres TEXT NOT NULL, apellidos TEXT NOT NULL,
        grado TEXT, seccion TEXT, turno TEXT NOT NULL DEFAULT 'Mañana',
        foto BLOB, codigo_qr TEXT,
        activo INTEGER NOT NULL DEFAULT 1, fecha_registro TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS asistencias (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        alumno_id INTEGER NOT NULL, fecha TEXT NOT NULL,
        hora TEXT NOT NULL, estado TEXT NOT NULL CHECK(estado IN ('TEMPRANO','PUNTUAL','TARDE','FALTA')),
        tipo TEXT NOT NULL DEFAULT 'MANUAL', observacion TEXT,
        usuario_id INTEGER, hora_salida TEXT, salida_tipo TEXT, motivo TEXT,
        FOREIGN KEY(alumno_id) REFERENCES alumnos(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS horarios (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        turno TEXT NOT NULL UNIQUE, hora_limite TEXT NOT NULL,
        hora_salida TEXT NOT NULL DEFAULT '13:00',
        hora_temprana TEXT NOT NULL DEFAULT '07:50',
        hora_puntual TEXT NOT NULL DEFAULT '07:51'
      )
    ''');
    await db.insert('horarios', {'turno':'Mañana','hora_temprana':'07:50','hora_puntual':'07:51','hora_limite':'08:00','hora_salida':'13:00'}, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('horarios', {'turno':'Tarde','hora_temprana':'13:50','hora_puntual':'13:51','hora_limite':'14:00','hora_salida':'19:00'}, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> _addColumnIfMissing(DatabaseExecutor db, String table, String column, String type) async {
    final cols = await db.rawQuery('PRAGMA table_info($table)');
    if (cols.any((c) => c['name'] == column)) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  /// v4: salida del estudiante, motivo del registro manual y hora oficial de salida por turno.
  Future<void> _migrateV4(DatabaseExecutor db) async {
    await _addColumnIfMissing(db, 'asistencias', 'hora_salida', 'TEXT');
    await _addColumnIfMissing(db, 'asistencias', 'salida_tipo', 'TEXT');
    await _addColumnIfMissing(db, 'asistencias', 'motivo', 'TEXT');
    await _addColumnIfMissing(db, 'horarios', 'hora_salida', "TEXT NOT NULL DEFAULT '13:00'");
    await db.update('horarios', {'hora_salida': '19:00'}, where: "turno='Tarde' AND hora_salida='13:00'");
  }

  /// v5: horario de 3 tramos por turno (llegada temprana, puntualidad y límite)
  /// y nuevo estado de asistencia PUNTUAL (se reconstruye la tabla por el CHECK).
  Future<void> _migrateV5(DatabaseExecutor db) async {
    await _addColumnIfMissing(db, 'horarios', 'hora_temprana', "TEXT NOT NULL DEFAULT '07:50'");
    await _addColumnIfMissing(db, 'horarios', 'hora_puntual', "TEXT NOT NULL DEFAULT '07:51'");
    final rows = await db.query('horarios');
    for (final r in rows) {
      final lim = _toMin('${r['hora_limite']}');
      await db.update('horarios', {
        'hora_temprana': _fromMin(lim - 10),
        'hora_puntual': _fromMin(lim - 9),
      }, where: 'id = ?', whereArgs: [r['id']]);
    }
    final info = await db.rawQuery("SELECT sql FROM sqlite_master WHERE type='table' AND name='asistencias'");
    final ddl = info.isEmpty ? '' : '${info.first['sql']}';
    if (ddl.isNotEmpty && !ddl.contains("'PUNTUAL'")) {
      await db.execute('ALTER TABLE asistencias RENAME TO asistencias_old');
      await db.execute('''
        CREATE TABLE asistencias (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          alumno_id INTEGER NOT NULL, fecha TEXT NOT NULL,
          hora TEXT NOT NULL, estado TEXT NOT NULL CHECK(estado IN ('TEMPRANO','PUNTUAL','TARDE','FALTA')),
          tipo TEXT NOT NULL DEFAULT 'MANUAL', observacion TEXT,
          usuario_id INTEGER, hora_salida TEXT, salida_tipo TEXT, motivo TEXT,
          FOREIGN KEY(alumno_id) REFERENCES alumnos(id)
        )
      ''');
      await db.execute('INSERT INTO asistencias SELECT id, alumno_id, fecha, hora, estado, tipo, observacion, usuario_id, hora_salida, salida_tipo, motivo FROM asistencias_old');
      await db.execute('DROP TABLE asistencias_old');
    }
  }

  /// v6: permisos por usuario. El personal que ya existía conserva lo que veía
  /// antes (Escanear QR y Registro manual); el administrador puede cambiarlo.
  Future<void> _migrateV6(DatabaseExecutor db) async {
    await _addColumnIfMissing(db, 'usuarios', 'permisos', 'TEXT');
    await db.update('usuarios', {'permisos': 'Escanear QR,Registro manual'},
        where: "rol='personal' AND permisos IS NULL");
  }

  static int _toMin(String s) {
    final p = s.split(':');
    return (int.tryParse(p[0]) ?? 0) * 60 + (p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  static String _fromMin(int m) {
    final v = m.clamp(0, 1439);
    return '${(v ~/ 60).toString().padLeft(2, '0')}:${(v % 60).toString().padLeft(2, '0')}';
  }

  Future<String?> getConfig(String clave) async {
    final db = await database;
    await db.execute('CREATE TABLE IF NOT EXISTS configuracion (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)');
    final r = await db.query('configuracion', where: 'clave=?', whereArgs: [clave], limit: 1);
    return r.isEmpty ? null : '${r.first['valor']}';
  }

  Future<void> setConfig(String clave, String valor) async {
    final db = await database;
    await db.execute('CREATE TABLE IF NOT EXISTS configuracion (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)');
    await db.insert('configuracion', {'clave': clave, 'valor': valor}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Nombres de los turnos configurados (Mañana y Tarde primero, luego los agregados).
  Future<List<String>> listaTurnos() async {
    final db = await database;
    final rows = await db.query('horarios', columns: ['turno'], orderBy: 'id');
    final out = rows.map((r) => '${r['turno']}').toList();
    return out.isEmpty ? ['Mañana', 'Tarde'] : out;
  }

  /// Cierra el día: las entradas sin salida pasan a FALTA y los estudiantes activos
  /// sin ningún registro hoy quedan como FALTA. [turno] null = todos los turnos.
  Future<({int sinSalida, int sinRegistro})> contarCierreDia(String fecha, {String? turno}) async {
    final db = await database;
    final args = <Object?>[fecha, if (turno != null) turno];
    final t = turno == null ? '' : 'AND al.turno=?';
    final a = await db.rawQuery(
        "SELECT COUNT(*) n FROM asistencias a JOIN alumnos al ON al.id=a.alumno_id WHERE a.fecha=? AND a.hora_salida IS NULL AND a.estado IN ('TEMPRANO','PUNTUAL','TARDE') AND al.activo=1 $t",
        args);
    final b = await db.rawQuery(
        "SELECT COUNT(*) n FROM alumnos al WHERE al.activo=1 $t AND NOT EXISTS (SELECT 1 FROM asistencias a WHERE a.alumno_id=al.id AND a.fecha=?)",
        [if (turno != null) turno, fecha]);
    return (sinSalida: (a.first['n'] as int?) ?? 0, sinRegistro: (b.first['n'] as int?) ?? 0);
  }

  Future<({int sinSalida, int sinRegistro})> cerrarDia(String fecha, {String? turno, int? usuarioId}) async {
    final db = await database;
    final cont = await contarCierreDia(fecha, turno: turno);
    final t = turno == null ? '' : 'AND al.turno=?';
    await db.transaction((txn) async {
      await txn.rawUpdate(
          "UPDATE asistencias SET estado='FALTA', motivo='Cierre de día', observacion='Inasistencia: día cerrado sin registrar salida', usuario_id=? WHERE fecha=? AND hora_salida IS NULL AND estado IN ('TEMPRANO','PUNTUAL','TARDE') AND alumno_id IN (SELECT al.id FROM alumnos al WHERE al.activo=1 $t)",
          [usuarioId, fecha, if (turno != null) turno]);
      await txn.rawInsert(
          "INSERT INTO asistencias (alumno_id, fecha, hora, estado, tipo, observacion, usuario_id, motivo) SELECT al.id, ?, '00:00:00', 'FALTA', 'MANUAL', 'Inasistencia: sin registro al cerrar el día', ?, 'Cierre de día' FROM alumnos al WHERE al.activo=1 $t AND NOT EXISTS (SELECT 1 FROM asistencias a WHERE a.alumno_id=al.id AND a.fecha=?)",
          [fecha, usuarioId, if (turno != null) turno, fecha]);
    });
    return cont;
  }

  /// Estado de una entrada según el horario del turno:
  /// antes del inicio de puntualidad = TEMPRANO; hasta la hora límite = PUNTUAL; después = TARDE.
  Future<String> estadoEntrada(String turno, int minutos) async {
    final db = await database;
    final rows = await db.query('horarios', where: 'turno=?', whereArgs: [turno], limit: 1);
    final isTarde = turno == 'Tarde';
    var limite = isTarde ? 14 * 60 : 8 * 60;
    var puntual = limite - 9;
    if (rows.isNotEmpty) {
      limite = _toMin('${rows.first['hora_limite']}');
      puntual = _toMin('${rows.first['hora_puntual']}');
    }
    if (minutos > limite) return 'TARDE';
    if (minutos < puntual) return 'TEMPRANO';
    return 'PUNTUAL';
  }

  /// Todo estudiante con entrada pero sin salida cerrada en un día anterior
  /// pasa a FALTA (inasistencia). Devuelve cuántos registros cambió.
  Future<int> marcarInasistenciasPendientes() async {
    final db = await database;
    final n = DateTime.now();
    final hoy = '${n.year.toString().padLeft(4, '0')}-${n.month.toString().padLeft(2, '0')}-${n.day.toString().padLeft(2, '0')}';
    return db.rawUpdate('''
      UPDATE asistencias
      SET estado='FALTA', observacion='Inasistencia: salida no cerrada al terminar el día'
      WHERE fecha < ? AND hora_salida IS NULL AND estado IN ('TEMPRANO','PUNTUAL','TARDE')
    ''', [hoy]);
  }

  Future<bool> hasAdministrator() async {
    final db = await database;
    final rows = await db.rawQuery(
      "SELECT COUNT(*) AS total FROM usuarios WHERE rol = 'admin'",
    );
    return (rows.first['total'] as int) > 0;
  }
}
