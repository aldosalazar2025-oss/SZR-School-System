import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import 'app_sidebar.dart';

/// Configuración de horarios por turno.
///
/// Cada turno tiene cuatro horas:
///  · Inicio del período de llegada temprana
///  · Inicio de puntualidad
///  · Hora límite de puntualidad (después de esta hora es TARDE)
///  · Horario de salida
/// El panel "Escanear asistencia" y el registro manual leen estos valores
/// para calcular si el estudiante llegó temprano, puntual o tarde.
class SchedulesScreen extends StatefulWidget {
  const SchedulesScreen({super.key, required this.user});
  final AuthUser user;
  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static Color get purple => P.accent;
  static Color get red => P.err;
  static Color get muted => P.muted;
  static Color get fieldBg => P.field;

  static const _fields = <(String, String)>[
    ('temprana', 'Inicio del período de llegada temprana'),
    ('puntual', 'Inicio de puntualidad'),
    ('limite', 'Hora límite de puntualidad'),
    ('salida', 'Horario de salida'),
  ];

  // turno -> {temprana, puntual, limite, salida} en formato HH:mm ('' = sin definir)
  final Map<String, Map<String, String>> _data = {};
  static const _base = ['Mañana', 'Tarde']; // turnos fijos: no se pueden eliminar
  bool _loading = true;
  final Set<String> _saving = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('horarios', orderBy: 'id');
    _data.clear();
    for (final r in rows) {
      _data['${r['turno']}'] = {
        'temprana': '${r['hora_temprana'] ?? ''}',
        'puntual': '${r['hora_puntual'] ?? ''}',
        'limite': '${r['hora_limite'] ?? ''}',
        'salida': '${r['hora_salida'] ?? ''}',
      };
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addTurno() async {
    final ctrl = TextEditingController();
    String? error;
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: panel,
          title: Text('Agregar turno'),
          content: SizedBox(
            width: 360,
            child: TextField(
              controller: ctrl,
              autofocus: true,
              maxLength: 30,
              decoration: InputDecoration(labelText: 'Nombre del turno (ej. Noche)', errorText: error),
              onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final v = ctrl.text.trim();
                if (v.isEmpty) {
                  setD(() => error = 'Escribe un nombre.');
                } else if (_data.keys.any((k) => k.toLowerCase() == v.toLowerCase())) {
                  setD(() => error = 'Ese turno ya existe.');
                } else {
                  Navigator.pop(ctx, v);
                }
              },
              child: Text('Agregar'),
            ),
          ],
        ),
      ),
    );
    if (name == null || name.isEmpty) return;
    final db = await AppDatabase.instance.database;
    await db.insert('horarios', {
      'turno': name,
      'hora_temprana': '07:50',
      'hora_puntual': '07:51',
      'hora_limite': '08:00',
      'hora_salida': '13:00',
    });
    await _load();
    if (mounted) _msg('Turno "$name" agregado. Ajusta sus horarios y pulsa Guardar.');
  }

  Future<void> _deleteTurno(String turno) async {
    final db = await AppDatabase.instance.database;
    final used = await db.rawQuery('SELECT COUNT(*) n FROM alumnos WHERE turno=?', [turno]);
    final n = (used.first['n'] as int?) ?? 0;
    if (n > 0) {
      _msg('No se puede eliminar: $n estudiante(s) pertenecen al turno "$turno". Cámbialos de turno primero.');
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminar turno'),
        content: Text('¿Eliminar el turno "$turno"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    await db.delete('horarios', where: 'turno=?', whereArgs: [turno]);
    await _load();
    if (mounted) _msg('Turno "$turno" eliminado.');
  }

  TimeOfDay? _parse(String s) {
    if (s.isEmpty) return null;
    final p = s.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 0, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  int _minutes(String s) {
    final t = _parse(s)!;
    return t.hour * 60 + t.minute;
  }

  Future<void> _pick(String turno, String key) async {
    final t = await showTimePicker(
      context: context,
      initialTime: _parse(_data[turno]![key]!) ?? (turno == 'Tarde' ? TimeOfDay(hour: 13, minute: 0) : TimeOfDay(hour: 7, minute: 0)),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t == null) return;
    setState(() => _data[turno]![key] = _fmt(t));
  }

  void _msg(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save(String turno) async {
    final d = _data[turno]!;
    if (d.values.any((v) => v.isEmpty)) {
      _msg('Turno ${turno.toLowerCase()}: completa las cuatro horas antes de guardar.');
      return;
    }
    final temprana = _minutes(d['temprana']!), puntual = _minutes(d['puntual']!);
    final limite = _minutes(d['limite']!), salida = _minutes(d['salida']!);
    if (temprana > puntual) {
      _msg('El inicio de llegada temprana no puede ser posterior al inicio de puntualidad.');
      return;
    }
    if (puntual > limite) {
      _msg('El inicio de puntualidad no puede ser posterior a la hora límite de puntualidad.');
      return;
    }
    if (salida <= limite) {
      _msg('El horario de salida debe ser posterior a la hora límite de puntualidad.');
      return;
    }
    setState(() => _saving.add(turno));
    try {
      final db = await AppDatabase.instance.database;
      await db.update(
        'horarios',
        {
          'hora_temprana': d['temprana'],
          'hora_puntual': d['puntual'],
          'hora_limite': d['limite'],
          'hora_salida': d['salida'],
        },
        where: 'turno = ?',
        whereArgs: [turno],
      );
      if (mounted) _msg('Turno ${turno.toLowerCase()} guardado.');
    } catch (_) {
      if (mounted) _msg('No se pudo guardar el turno ${turno.toLowerCase()}.');
    } finally {
      if (mounted) setState(() => _saving.remove(turno));
    }
  }

  Widget _timeField(String turno, String key, String label) {
    final value = _data[turno]![key]!;
    return Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: Column(children: [
        Text(label, textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 13.5, fontWeight: FontWeight.w600)),
        SizedBox(height: 8),
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _pick(turno, key),
          child: Container(
            height: 47,
            padding: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: fieldBg, border: Border.all(color: line), borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Expanded(
                child: Text(value.isEmpty ? '--:--' : value,
                    style: TextStyle(color: value.isEmpty ? muted : P.text, fontSize: 18, letterSpacing: value.isEmpty ? 1 : 0)),
              ),
              Icon(Icons.access_time, size: 19, color: P.text),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _turnoCard(String turno, IconData icon) {
    final busy = _saving.contains(turno);
    return Container(
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: line),
        boxShadow: P.shadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(height: 3, decoration: BoxDecoration(gradient: LinearGradient(colors: [P.accent2, purple]))),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              SizedBox(width: 40),
              Expanded(
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: cyan, size: 30),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text('Turno ${turno.toLowerCase()}',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: P.text, fontSize: 20, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              SizedBox(
                width: 40,
                child: _base.contains(turno)
                    ? null
                    : IconButton(
                        tooltip: 'Eliminar turno',
                        onPressed: () => _deleteTurno(turno),
                        icon: Icon(Icons.delete_outline, color: red),
                      ),
              ),
            ]),
            SizedBox(height: 18),
            for (final f in _fields) _timeField(turno, f.$1, f.$2),
            SizedBox(height: 6),
            Container(
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: P.brand,
                boxShadow: [BoxShadow(color: P.accent.withValues(alpha: .30), blurRadius: 14, offset: Offset(0, 5))],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: busy ? null : () => _save(turno),
                  child: Center(
                    child: busy
                        ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: P.onBrand))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.save, color: P.onBrand, size: 24),
                            SizedBox(width: 8),
                            Text('Guardar turno ${turno.toLowerCase()}',
                                style: TextStyle(color: P.onBrand, fontSize: 16, fontWeight: FontWeight.w800)),
                          ]),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) => FScaffold(
        backgroundColor: bg,
        body: Row(children: [
          AppSidebar(user: widget.user, selected: 'Horarios'),
          FContent(
            child: SafeArea(
              child: Column(children: [
                Container(
                  height: 66,
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Row(children: [
                    PageIcon(Icons.schedule),
                    SizedBox(width: 12),
                    Text('Horarios', style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]),
                ),
                Expanded(
                  child: _loading
                      ? Center(child: CircularProgressIndicator())
                      : LayoutBuilder(builder: (context, c) {
                          final cols = c.maxWidth < 800 ? 1 : 2;
                          const gap = 18.0;
                          final w = (c.maxWidth - 36 - gap * (cols - 1)) / cols;
                          IconData iconFor(String t) =>
                              t == 'Mañana' ? Icons.wb_sunny : (t == 'Tarde' ? Icons.wb_cloudy : Icons.schedule);
                          return SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(18, 4, 18, 24),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: OutlinedButton.icon(
                                  onPressed: _addTurno,
                                  icon: Icon(Icons.add, color: cyan),
                                  label: Text('Agregar turno', style: TextStyle(color: P.text, fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(side: BorderSide(color: cyan), minimumSize: Size(170, 44)),
                                ),
                              ),
                              SizedBox(height: 16),
                              Wrap(spacing: gap, runSpacing: gap, children: [
                                for (final t in _data.keys) SizedBox(width: w, child: _turnoCard(t, iconFor(t))),
                              ]),
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
