import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import 'app_sidebar.dart';

enum _Modo { automatico, forzarEntrada, forzarSalida }

class _Alumno {
  _Alumno(this.id, this.nombres, this.apellidos, this.dni, this.grado, this.seccion, this.turno, this.foto);
  final int id;
  final String nombres, apellidos, dni, grado, seccion, turno;
  final Uint8List? foto;

  String get nombre => '$apellidos, $nombres'.trim();
  String get nombreNormal => '$nombres $apellidos'.trim();
  String get aula => '$grado $seccion'.trim();
}

class _Pendiente {
  _Pendiente(this.asistenciaId, this.nombre, this.dni, this.turno, this.entrada, this.limite);
  final int asistenciaId;
  final String nombre, dni, turno, entrada, limite;
}

class ManualScreen extends StatefulWidget {
  const ManualScreen({super.key, required this.user});
  final AuthUser user;
  @override
  State<ManualScreen> createState() => _ManualScreenState();
}

class _ManualScreenState extends State<ManualScreen> {
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static Color get green => P.ok;
  static Color get red => P.err;
  static Color get orange => P.warn;

  static const motivos = [
    'Carné olvidado',
    'Carné dañado o ilegible',
    'Cámara o lector sin funcionar',
    'Estudiante sin carné (nuevo ingreso)',
    'Corrección de un registro anterior',
    'Otros',
  ];

  final _searchCtrl = TextEditingController();
  final _otroCtrl = TextEditingController();

  List<_Alumno> _results = [];
  _Alumno? _student;
  Map<String, Object?>? _today; // registro del día del estudiante elegido
  _Modo _modo = _Modo.automatico;
  TimeOfDay _time = TimeOfDay.now();
  String? _motivo;
  bool _saving = false;

  String _pendingTurno = 'Ambos turnos';
  List<String> _turnos = ['Mañana', 'Tarde'];
  List<_Pendiente> _pending = [];
  bool _loadingPending = true;

  @override
  void initState() {
    super.initState();
    _loadPending();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _otroCtrl.dispose();
    super.dispose();
  }

  // ───────────────────────── Utilidades ─────────────────────────

  static String _two(int n) => n.toString().padLeft(2, '0');
  String _fecha(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';
  String _hhmm(TimeOfDay t) => '${_two(t.hour)}:${_two(t.minute)}';

  int _minutes(String hhmm, int fallback) {
    final p = hhmm.split(':');
    if (p.length < 2) return fallback;
    final h = int.tryParse(p[0]), m = int.tryParse(p[1]);
    return (h == null || m == null) ? fallback : h * 60 + m;
  }

  void _msg(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), backgroundColor: error ? red : Color(0xFF16805F)));
  }

  // ───────────────────────── Búsqueda ─────────────────────────

  Future<void> _search(String raw) async {
    final q = raw.trim();
    if (q.length < 2) {
      setState(() => _results = []);
      return;
    }
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final where = <String>[];
    final args = <Object?>[];
    for (final t in tokens) {
      where.add('(dni LIKE ? OR nombres LIKE ? OR apellidos LIKE ?)');
      args.addAll(['%$t%', '%$t%', '%$t%']);
    }
    final db = await AppDatabase.instance.database;
    final rows = await db.query('alumnos',
        where: 'activo=1 AND ${where.join(' AND ')}',
        whereArgs: args,
        orderBy: 'apellidos, nombres',
        limit: 8);
    if (!mounted || _searchCtrl.text.trim() != q) return; // llegó una búsqueda más reciente
    setState(() => _results = rows.map(_fromRow).toList());
  }

  _Alumno _fromRow(Map<String, Object?> r) => _Alumno(
        r['id'] as int,
        '${r['nombres'] ?? ''}',
        '${r['apellidos'] ?? ''}',
        '${r['dni'] ?? ''}',
        '${r['grado'] ?? ''}',
        '${r['seccion'] ?? ''}',
        '${r['turno'] ?? 'Mañana'}',
        r['foto'] as Uint8List?,
      );

  Future<void> _select(_Alumno a) async {
    _searchCtrl.clear();
    setState(() {
      _student = a;
      _results = [];
      _modo = _Modo.automatico;
      _motivo = null;
      _otroCtrl.clear();
      _time = TimeOfDay.now();
    });
    await _loadToday();
  }

  Future<void> _loadToday() async {
    final a = _student;
    if (a == null) return;
    final db = await AppDatabase.instance.database;
    final rows = await db.query('asistencias',
        where: 'alumno_id=? AND fecha=?', whereArgs: [a.id, _fecha(DateTime.now())], orderBy: 'id ASC', limit: 1);
    if (!mounted) return;
    setState(() => _today = rows.isEmpty ? null : rows.first);
  }

  void _cancel() => setState(() {
        _student = null;
        _today = null;
        _modo = _Modo.automatico;
        _motivo = null;
        _otroCtrl.clear();
      });

  // ───────────────────────── Lógica de estado ─────────────────────────

  /// Qué haría el modo Automático según lo que ya tiene el estudiante hoy.
  _Modo? get _autoResult {
    final t = _today;
    if (t == null) return _Modo.forzarEntrada;
    if (t['estado'] == 'FALTA') return null;
    if (t['hora_salida'] == null) return _Modo.forzarSalida;
    return null;
  }

  String get _todayStatusText {
    final t = _today;
    if (t == null) return 'Sin registros hoy. El siguiente registro será su entrada.';
    final hora = '${t['hora']}'.substring(0, 5);
    if (t['estado'] == 'FALTA') return 'Marcado como inasistencia hoy (entrada $hora). Usa "Forzar entrada" para corregirlo.';
    if (t['hora_salida'] == null) return 'Entrada a las $hora (${t['estado']}). El siguiente registro será su salida.';
    return 'Entrada $hora y salida ${'${t['hora_salida']}'.substring(0, 5)}. Día completo; solo puedes forzar un cambio.';
  }

  Future<String> _estadoEntrada(String turno, TimeOfDay t) =>
      AppDatabase.instance.estadoEntrada(turno, t.hour * 60 + t.minute);

  String get _autoHint {
    final r = _autoResult;
    if (r == _Modo.forzarEntrada) return 'Se registrará una entrada.';
    if (r == _Modo.forzarSalida) return 'Se registrará la salida.';
    return 'Nada que registrar en automático: elige Forzar entrada o Forzar salida.';
  }

  // ───────────────────────── Guardar ─────────────────────────

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text('Confirmar')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _save() async {
    final a = _student;
    if (a == null) return;
    if (_motivo == null) {
      _msg('Selecciona el motivo del registro manual.', error: true);
      return;
    }
    final otro = _otroCtrl.text.trim();
    if (_motivo == 'Otros' && otro.length < 3) {
      _msg('Escribe el motivo en el campo "Otros".', error: true);
      return;
    }
    final motivoFinal = _motivo == 'Otros' ? 'Otros: $otro' : _motivo!;

    // Resolver el modo real.
    var modo = _modo;
    if (modo == _Modo.automatico) {
      final r = _autoResult;
      if (r == null) {
        _msg('No hay nada que registrar en automático. Usa Forzar entrada o Forzar salida.', error: true);
        return;
      }
      modo = r;
    }

    setState(() => _saving = true);
    try {
      final db = await AppDatabase.instance.database;
      final hora = '${_hhmm(_time)}:00';
      final t = _today;

      if (modo == _Modo.forzarEntrada) {
        if (t != null) {
          final ok = await _confirm('Reemplazar entrada',
              'Ya existe un registro hoy. Se reemplazará la entrada y se borrará la salida. ¿Continuar?');
          if (!ok) return;
        }
        final estado = await _estadoEntrada(a.turno, _time);
        final values = {
          'hora': hora,
          'estado': estado,
          'tipo': 'MANUAL',
          'motivo': motivoFinal,
          'observacion': 'Entrada manual: $motivoFinal',
          'hora_salida': null,
          'salida_tipo': null,
          'usuario_id': widget.user.id,
        };
        if (t == null) {
          await db.insert('asistencias', {'alumno_id': a.id, 'fecha': _fecha(DateTime.now()), ...values});
        } else {
          await db.update('asistencias', values, where: 'id=?', whereArgs: [t['id']]);
        }
        _msg('Entrada registrada: ${a.nombreNormal} · $estado a las ${_hhmm(_time)}');
      } else {
        // Forzar salida
        if (t == null) {
          _msg('${a.nombreNormal} no tiene entrada hoy. Registra primero la entrada.', error: true);
          return;
        }
        if (t['estado'] == 'FALTA') {
          _msg('Está marcado como inasistencia. Corrígelo con "Forzar entrada".', error: true);
          return;
        }
        final entrada = _minutes('${t['hora']}', 0);
        if (_time.hour * 60 + _time.minute < entrada) {
          _msg('La salida no puede ser anterior a la entrada (${'${t['hora']}'.substring(0, 5)}).', error: true);
          return;
        }
        if (t['hora_salida'] != null) {
          final ok = await _confirm('Reemplazar salida', 'Ya tiene salida registrada hoy. ¿Reemplazarla por esta?');
          if (!ok) return;
        }
        await db.update(
            'asistencias',
            {
              'hora_salida': hora,
              'salida_tipo': 'MANUAL',
              'motivo': motivoFinal,
              'observacion': 'Salida manual: $motivoFinal',
              'usuario_id': widget.user.id,
            },
            where: 'id=?',
            whereArgs: [t['id']]);
        _msg('Salida registrada: ${a.nombreNormal} a las ${_hhmm(_time)}');
      }
      _cancel();
      await _loadPending();
    } catch (e) {
      _msg('No se pudo guardar: $e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ───────────────────────── Salidas pendientes ─────────────────────────

  Future<void> _loadPending() async {
    setState(() => _loadingPending = true);
    try {
      await AppDatabase.instance.marcarInasistenciasPendientes(); // días anteriores sin cerrar → FALTA
      final tn = await AppDatabase.instance.listaTurnos();
      if (mounted) setState(() => _turnos = tn);
      final db = await AppDatabase.instance.database;
      final rows = await db.rawQuery('''
        SELECT a.id, a.hora, al.nombres, al.apellidos, al.dni, al.turno, h.hora_salida AS limite
        FROM asistencias a
        JOIN alumnos al ON al.id=a.alumno_id
        LEFT JOIN horarios h ON h.turno=al.turno
        WHERE a.fecha=? AND a.hora_salida IS NULL AND a.estado IN ('TEMPRANO','PUNTUAL','TARDE') AND al.activo=1
        ${_pendingTurno == 'Ambos turnos' ? '' : 'AND al.turno=?'}
        ORDER BY al.apellidos, al.nombres
      ''', [_fecha(DateTime.now()), if (_pendingTurno != 'Ambos turnos') _pendingTurno]);
      final now = DateTime.now();
      final nowMin = now.hour * 60 + now.minute;
      final list = <_Pendiente>[];
      for (final r in rows) {
        final turno = '${r['turno'] ?? 'Mañana'}';
        final limite = (r['limite'] as String?) ?? (turno == 'Tarde' ? '19:00' : '13:00');
        if (nowMin < _minutes(limite, 24 * 60)) continue; // aún no pasa la hora oficial de salida
        list.add(_Pendiente(r['id'] as int, '${r['apellidos'] ?? ''}, ${r['nombres'] ?? ''}'.trim(),
            '${r['dni'] ?? ''}', turno, '${r['hora']}'.substring(0, 5), limite));
      }
      if (!mounted) return;
      setState(() {
        _pending = list;
        _loadingPending = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingPending = false);
      _msg('No se pudieron cargar las salidas pendientes: $e', error: true);
    }
  }

  Future<void> _closeExits(List<_Pendiente> items) async {
    if (items.isEmpty) return;
    final ok = await _confirm(
        items.length == 1 ? 'Cerrar salida' : 'Cerrar ${items.length} salidas',
        'Se registrará la salida a la hora oficial del turno, marcada como manual. ¿Continuar?');
    if (!ok) return;
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      for (final p in items) {
        await txn.update(
            'asistencias',
            {
              'hora_salida': '${p.limite}:00',
              'salida_tipo': 'MANUAL',
              'motivo': 'Cierre de salida pendiente',
              'observacion': 'Salida cerrada manualmente (hora oficial del turno)',
              'usuario_id': widget.user.id,
            },
            where: 'id=?',
            whereArgs: [p.asistenciaId]);
      }
    });
    _msg(items.length == 1 ? 'Salida cerrada.' : '${items.length} salidas cerradas.');
    await _loadPending();
    await _loadToday();
  }

  Future<void> _closeDay() async {
    final turno = _pendingTurno == 'Ambos turnos' ? null : _pendingTurno;
    final fecha = _fecha(DateTime.now());
    final c = await AppDatabase.instance.contarCierreDia(fecha, turno: turno);
    if (c.sinSalida == 0 && c.sinRegistro == 0) {
      _msg('No hay nada que cerrar: todos los estudiantes ya tienen su registro de hoy.');
      return;
    }
    final ok = await _confirm(
        'Cerrar día${turno == null ? '' : ' (turno $turno)'}',
        'Se registrarán como inasistencia (FALTA):\n'
        '• ${c.sinSalida} estudiante(s) con entrada y sin salida.\n'
        '• ${c.sinRegistro} estudiante(s) sin ningún registro hoy.\n\n'
        'Después podrás corregir un caso con "Forzar entrada" en el registro manual. ¿Cerrar el día?');
    if (!ok) return;
    try {
      await AppDatabase.instance.cerrarDia(fecha, turno: turno, usuarioId: widget.user.id);
      _msg('Día cerrado: ${c.sinSalida + c.sinRegistro} inasistencia(s) registradas.');
    } catch (e) {
      _msg('No se pudo cerrar el día: $e', error: true);
    }
    await _loadPending();
    await _loadToday();
  }

  Future<void> _markAbsent(_Pendiente p) async {
    final ok = await _confirm('Marcar inasistencia',
        '${p.nombre} tiene entrada pero no salida. Se registrará como inasistencia (FALTA). ¿Continuar?');
    if (!ok) return;
    final db = await AppDatabase.instance.database;
    await db.update(
        'asistencias',
        {
          'estado': 'FALTA',
          'motivo': 'Salida no cerrada',
          'observacion': 'Inasistencia: salida no cerrada',
          'usuario_id': widget.user.id,
        },
        where: 'id=?',
        whereArgs: [p.asistenciaId]);
    _msg('${p.nombre} marcado como inasistencia.');
    await _loadPending();
    await _loadToday();
  }

  // ───────────────────────── Interfaz ─────────────────────────

  BoxDecoration _panel() =>
      P.card(r: 16);

  InputDecoration _dec({String? label, String? hint, Widget? prefix}) => InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefix,
        filled: true,
        fillColor: P.field,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      backgroundColor: bg,
      body: Row(children: [
        AppSidebar(user: widget.user, selected: 'Registro manual'),
        FContent(
          child: SafeArea(
            child: Column(children: [
              Container(
                height: 66,
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  PageIcon(Icons.edit_note),
                  SizedBox(width: 12),
                  Text('Registro manual',
                      style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth > 900;
                  final left = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _searchPanel(),
                    if (_student != null) ...[SizedBox(height: 16), _registerPanel()],
                  ]);
                  final right = _pendingPanel();
                  return SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(18, 4, 18, 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      wide
                          ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Expanded(flex: 5, child: left),
                              SizedBox(width: 16),
                              Expanded(flex: 4, child: right),
                            ])
                          : Column(children: [left, SizedBox(height: 16), right]),
                    ]),
                  );
                }),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _searchPanel() => Container(
        padding: EdgeInsets.all(16),
        decoration: _panel(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.search, color: cyan, size: 26),
            SizedBox(width: 10),
            Text('Buscar estudiante', style: TextStyle(color: P.text, fontSize: 20, fontWeight: FontWeight.bold)),
          ]),
          SizedBox(height: 12),
          TextField(
            controller: _searchCtrl,
            onChanged: _search,
            decoration: _dec(hint: 'Nombres, apellidos o DNI (ej. 78…)', prefix: Icon(Icons.badge_outlined)),
          ),
          if (_searchCtrl.text.trim().length >= 2 && _results.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text('Sin coincidencias.', style: TextStyle(color: P.muted)),
            ),
          for (final a in _results)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _select(a),
                child: Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      border: Border.all(color: line), borderRadius: BorderRadius.circular(10), color: P.field),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(a.nombre,
                            style: TextStyle(color: P.text, fontWeight: FontWeight.bold, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('DNI ${a.dni} · ${a.aula.isEmpty ? '' : '${a.aula} · '}${a.turno}',
                            style: TextStyle(color: P.muted, fontSize: 12)),
                      ]),
                    ),
                    Icon(Icons.chevron_right, color: cyan),
                  ]),
                ),
              ),
            ),
        ]),
      );

  Widget _registerPanel() {
    final a = _student!;
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.how_to_reg, color: cyan, size: 26),
          SizedBox(width: 10),
          Text('Registrar asistencia', style: TextStyle(color: P.text, fontSize: 20, fontWeight: FontWeight.bold)),
        ]),
        SizedBox(height: 14),
        Row(children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: P.line,
            backgroundImage: a.foto == null ? null : MemoryImage(a.foto!),
            child: a.foto == null ? Icon(Icons.person, color: P.muted) : null,
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.nombreNormal, style: TextStyle(color: P.text, fontSize: 18, fontWeight: FontWeight.bold)),
              Text('DNI ${a.dni} · ${a.aula.isEmpty ? '' : '${a.aula} · '}Turno ${a.turno}',
                  style: TextStyle(color: P.muted, fontSize: 13)),
            ]),
          ),
        ]),
        SizedBox(height: 12),
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(color: P.panel2, borderRadius: BorderRadius.circular(8)),
          child: Text(_todayStatusText, style: TextStyle(color: P.text, fontSize: 13)),
        ),
        SizedBox(height: 14),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              DropdownButtonFormField<_Modo>(
                value: _modo,
                isExpanded: true,
                decoration: _dec(label: 'Tipo de registro'),
                items: const [
                  DropdownMenuItem(value: _Modo.automatico, child: Text('Automático (recomendado)')),
                  DropdownMenuItem(value: _Modo.forzarEntrada, child: Text('Forzar entrada')),
                  DropdownMenuItem(value: _Modo.forzarSalida, child: Text('Forzar salida')),
                ],
                onChanged: (v) => setState(() => _modo = v ?? _Modo.automatico),
              ),
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  switch (_modo) {
                    _Modo.automatico => _autoHint,
                    _Modo.forzarEntrada => 'Registra la entrada aunque ya exista una (la reemplaza).',
                    _Modo.forzarSalida => 'Registra la salida; el estudiante debe tener entrada hoy.',
                  },
                  style: TextStyle(color: P.muted2, fontSize: 12),
                ),
              ),
            ]),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              InkWell(
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
                child: InputDecorator(
                  decoration: _dec(label: 'Hora del registro', prefix: Icon(Icons.schedule)),
                  child: Text(_time.format(context), style: TextStyle(color: P.text, fontSize: 15)),
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text('Por defecto la hora actual. Ajústala si el estudiante llegó antes.',
                    style: TextStyle(color: P.muted2, fontSize: 12)),
              ),
            ]),
          ),
        ]),
        SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _motivo,
          isExpanded: true,
          decoration: _dec(label: 'Motivo del registro manual *'),
          hint: Text('— Selecciona un motivo —'),
          items: [for (final m in motivos) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: (v) => setState(() => _motivo = v),
        ),
        if (_motivo == 'Otros') ...[
          SizedBox(height: 10),
          TextField(
            controller: _otroCtrl,
            maxLength: 120,
            decoration: _dec(label: 'Describe el motivo *'),
          ),
        ],
        SizedBox(height: 14),
        Row(children: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: Icon(Icons.save),
            label: Text('Guardar registro'),
          ),
          SizedBox(width: 10),
          TextButton(onPressed: _saving ? null : _cancel, child: Text('Cancelar')),
        ]),
      ]),
    );
  }

  Widget _pendingPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.meeting_room, color: cyan, size: 26),
          SizedBox(width: 10),
          Expanded(
            child: Text('Salidas pendientes de hoy',
                style: TextStyle(color: P.text, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
        ]),
        SizedBox(height: 8),
        Text(
          'Estudiantes con entrada y sin salida, pasada ya la hora oficial de salida de su turno. '
          'Si se retiró y solo faltó escanear, cierra la salida. Si no se cierra, se considera inasistencia.',
          style: TextStyle(color: P.muted2, fontSize: 12.5),
        ),
        SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _pendingTurno,
              isExpanded: true,
              decoration: _dec(),
              items: [
                for (final t in ['Ambos turnos', ..._turnos]) DropdownMenuItem(value: t, child: Text(t)),
              ],
              onChanged: (v) {
                setState(() => _pendingTurno = v ?? 'Ambos turnos');
                _loadPending();
              },
            ),
          ),
          IconButton(tooltip: 'Actualizar', onPressed: _loadPending, icon: Icon(Icons.refresh, color: P.muted)),
        ]),
        SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _closeDay,
            icon: Icon(Icons.event_busy, size: 18, color: orange),
            label: Text('Cerrar día', style: TextStyle(color: P.text, fontWeight: FontWeight.bold)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: orange)),
          ),
        ),
        SizedBox(height: 12),
        if (_loadingPending)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
        else if (_pending.isEmpty)
          Padding(
            padding: EdgeInsets.all(12),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle, color: green, size: 20),
              SizedBox(width: 8),
              Text('No hay salidas pendientes en este momento.', style: TextStyle(color: P.muted)),
            ]),
          )
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () => _closeExits(List.of(_pending)),
              icon: Icon(Icons.done_all, size: 18),
              label: Text('Cerrar todas (${_pending.length})'),
            ),
          ),
          SizedBox(height: 8),
          for (final p in _pending)
            Container(
              margin: EdgeInsets.only(bottom: 8),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: P.field, border: Border.all(color: line), borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.nombre, style: TextStyle(color: P.text, fontWeight: FontWeight.bold)),
                    Text('DNI ${p.dni} · ${p.turno} · entró ${p.entrada} · salida oficial ${p.limite}',
                        style: TextStyle(color: P.muted, fontSize: 12)),
                  ]),
                ),
                IconButton(
                  tooltip: 'Cerrar salida',
                  onPressed: () => _closeExits([p]),
                  icon: Icon(Icons.logout, color: green),
                ),
                IconButton(
                  tooltip: 'Marcar inasistencia',
                  onPressed: () => _markAbsent(p),
                  icon: Icon(Icons.person_off, color: orange),
                ),
              ]),
            ),
        ],
      ]),
    );
  }
}
