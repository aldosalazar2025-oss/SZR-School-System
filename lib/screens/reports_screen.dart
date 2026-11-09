import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'package:excel/excel.dart' as xl show Border, BorderStyle;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import '../carnet/carnet.dart';
import 'app_sidebar.dart';

Color get _bg => P.bg;
Color get _panel => P.panel;
Color get _line => P.line;
Color get _cyan => P.accent;
Color get _green => P.ok;
Color get _red => P.err;
Color get _orange => P.warn;
Color get _muted => P.muted;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _dmy(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _pct(double v) => v == v.roundToDouble() ? '${v.round()}%' : '${v.toStringAsFixed(1)}%';

/// Guarda los bytes del Excel en la ruta que elija el usuario (Windows).
Future<bool> _saveXlsx(BuildContext context, String fileName, List<int> bytes) async {
  try {
    var path = await FilePicker.platform.saveFile(
      dialogTitle: 'Exportar a Excel',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (path == null) return false;
    if (!path.toLowerCase().endsWith('.xlsx')) path = '$path.xlsx';
    await File(path).writeAsBytes(bytes, flush: true);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('No se pudo guardar el archivo: $e')));
    }
    return false;
  }
}

class _Day {
  _Day(this.fecha, this.entrada, this.salida, this.estado, this.tipo, this.registros);
  final String fecha;
  final String? entrada, salida;
  final String estado; // TEMPRANO, TARDE, FALTA
  final String tipo;
  final int registros;
}

class _StuStat {
  _StuStat(this.alumno);
  final Map<String, Object?> alumno;
  int esperados = 0, presentes = 0, ausentes = 0, puntuales = 0, tardanzas = 0, pendientes = 0, manuales = 0;
  final List<_Day> dias = [];
  double get pct => esperados == 0 ? 0 : presentes * 100 / esperados;
  String get nombre => '${alumno['apellidos']}, ${alumno['nombres']}'.trim();
  String get dni => '${alumno['dni'] ?? ''}';
  String get aula => '${alumno['grado'] ?? ''} "${alumno['seccion'] ?? ''}"';
  String get turno => '${alumno['turno'] ?? ''}';
}

/// Calcula las estadísticas. Día esperado = día lectivo (lunes a viernes) en el que hay
/// al menos un registro de asistencia en el turno del estudiante.
Future<List<_StuStat>> _compute(DateTime from, DateTime to, List<Map<String, Object?>> students) async {
  final db = await AppDatabase.instance.database;
  await AppDatabase.instance.marcarInasistenciasPendientes();
  final f = _ymd(from), t = _ymd(to);

  final dateRows = await db.rawQuery('''
    SELECT DISTINCT a.fecha AS fecha, al.turno AS turno
    FROM asistencias a JOIN alumnos al ON al.id = a.alumno_id
    WHERE a.fecha >= ? AND a.fecha <= ?
  ''', [f, t]);
  final byTurno = <String, List<String>>{};
  for (final r in dateRows) {
    final d = DateTime.tryParse('${r['fecha']}');
    if (d == null || d.weekday > 5) continue;
    byTurno.putIfAbsent('${r['turno']}', () => []).add('${r['fecha']}');
  }
  for (final l in byTurno.values) {
    l.sort();
  }

  final recs = await db.query('asistencias', where: 'fecha >= ? AND fecha <= ?', whereArgs: [f, t], orderBy: 'fecha, hora');
  final byStudent = <int, List<Map<String, Object?>>>{};
  for (final r in recs) {
    byStudent.putIfAbsent(r['alumno_id'] as int, () => []).add(r);
  }

  final out = <_StuStat>[];
  for (final a in students) {
    final s = _StuStat(a);
    final mine = byStudent[a['id'] as int] ?? const [];
    for (final fecha in byTurno['${a['turno']}'] ?? const <String>[]) {
      final day = mine.where((r) => r['fecha'] == fecha).toList();
      s.esperados++;
      final ok = day.where((r) => r['estado'] == 'TEMPRANO' || r['estado'] == 'PUNTUAL' || r['estado'] == 'TARDE').toList();
      if (ok.isEmpty) {
        s.ausentes++;
        s.dias.add(_Day(fecha, null, null, 'FALTA', day.isEmpty ? '' : '${day.first['tipo']}', day.length));
        continue;
      }
      final r = ok.first;
      s.presentes++;
      if (r['estado'] == 'TEMPRANO' || r['estado'] == 'PUNTUAL') s.puntuales++;
      if (r['estado'] == 'TARDE') s.tardanzas++;
      if (r['hora_salida'] == null) s.pendientes++;
      s.dias.add(_Day(fecha, '${r['hora']}', r['hora_salida'] as String?, '${r['estado']}', '${r['tipo']}', day.length));
    }
    s.manuales = mine.where((r) => r['tipo'] == 'MANUAL').length;
    out.add(s);
  }
  return out;
}

// ───────────── Exportación a Excel con el formato "CONTROL DE ASISTENCIA" ─────────────
// Replica la plantilla REG_DE_ASISTENCIA: una hoja por mes, con semanas, días L-M-M-J-V,
// símbolos de asistencia (1 = ✔, 0 = ✘, T = tardanza) y totales por alumno y por día.
// Los valores se guardan como 1 / 0 / "T" para que las fórmulas COUNTIF funcionen igual que en la plantilla.

const _mesesXlsx = ['ENERO', 'FEBRERO', 'MARZO', 'ABRIL', 'MAYO', 'JUNIO', 'JULIO', 'AGOSTO', 'SETIEMBRE', 'OCTUBRE', 'NOVIEMBRE', 'DICIEMBRE'];

const _xBlue = '4472C4', _xHead = 'BDD7EE', _xGreen = 'A9D18E', _xGreenLight = 'C5E0B4';
const _xRed = 'F2C2BC', _xYellow = 'FFE699', _xYellowDark = 'FFD966', _xTardy = 'FFFF00';
const _xSymbolFmt = '"✔";"";"✘"';

String _colName(int i) {
  var n = i + 1;
  var s = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = (n - 1) ~/ 26;
  }
  return s;
}

ExcelColor _hex(String rgb) => ExcelColor.fromHexString('FF$rgb');

xl.Border? _bd(String? k) => k == null
    ? null
    : xl.Border(borderStyle: k == 'm' ? xl.BorderStyle.Medium : xl.BorderStyle.Thin, borderColorHex: ExcelColor.black);

CellStyle _cs({
  String font = 'Calibri',
  int size = 11,
  bool bold = false,
  String? fill,
  String color = '000000',
  HorizontalAlign h = HorizontalAlign.Center,
  int rot = 0,
  bool wrap = false,
  String? l,
  String? r,
  String? t,
  String? b,
  String? fmt,
}) =>
    CellStyle(
      fontFamily: font,
      fontSize: size,
      bold: bold,
      fontColorHex: _hex(color),
      backgroundColorHex: fill == null ? ExcelColor.none : _hex(fill),
      horizontalAlign: h,
      verticalAlign: VerticalAlign.Center,
      rotation: rot,
      textWrapping: wrap ? TextWrapping.WrapText : null,
      leftBorder: _bd(l),
      rightBorder: _bd(r),
      topBorder: _bd(t),
      bottomBorder: _bd(b),
      numberFormat: fmt == null ? NumFormat.standard_0 : NumFormat.custom(formatCode: fmt),
    );

void _put(Sheet s, int c, int r, CellValue? v, CellStyle st) =>
    s.updateCell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r), v, cellStyle: st);

// Las combinaciones NO se hacen con Sheet.merge (el paquete descarta los estilos y bordes de las
// celdas no iniciales). Se registran aquí y se inyectan como <mergeCells> en el XML al final.
List<String> _curMerges = [];

/// Nombre de la institución (Personalización) que se escribe en el Excel; se carga antes de generar el libro.
String _xInstitucion = '';

void _merge(Sheet s, int c1, int r1, int c2, int r2) {
  if (c1 == c2 && r1 == r2) return;
  _curMerges.add('${_colName(c1)}${r1 + 1}:${_colName(c2)}${r2 + 1}');
}

/// Rango combinado con borde medio por fuera. [v] va en la celda superior izquierda.
void _xbox(Sheet s, int c1, int r1, int c2, int r2, CellValue? v,
    {String font = 'Calibri', int size = 11, bool bold = false, String? fill, String color = '000000', HorizontalAlign h = HorizontalAlign.Center, bool border = true, int rot = 0, bool wrap = false}) {
  for (var rr = r1; rr <= r2; rr++) {
    for (var cc = c1; cc <= c2; cc++) {
      _put(
        s,
        cc,
        rr,
        (cc == c1 && rr == r1) ? v : null,
        _cs(
          font: font, size: size, bold: bold, fill: fill, color: color, h: h, rot: rot, wrap: wrap,
          l: border && cc == c1 ? 'm' : null,
          r: border && cc == c2 ? 'm' : null,
          t: border && rr == r1 ? 'm' : null,
          b: border && rr == r2 ? 'm' : null,
        ),
      );
    }
  }
  _merge(s, c1, r1, c2, r2);
}

/// Rango combinado con bordes exteriores indicados en l/r/t/b (cada celda lleva solo los de su lado).
void _mbox(Sheet s, int c1, int r1, int c2, int r2, CellValue? v,
    {String font = 'Calibri', int size = 11, bool bold = true, String? fill, String color = '000000', int rot = 0, String? fmt, String? l, String? r, String? t, String? b}) {
  for (var rr = r1; rr <= r2; rr++) {
    for (var cc = c1; cc <= c2; cc++) {
      _put(
        s,
        cc,
        rr,
        (cc == c1 && rr == r1) ? v : null,
        _cs(
          font: font, size: size, bold: bold, fill: fill, color: color, rot: rot, fmt: fmt,
          l: cc == c1 ? l : null,
          r: cc == c2 ? r : null,
          t: rr == r1 ? t : null,
          b: rr == r2 ? b : null,
        ),
      );
    }
  }
  _merge(s, c1, r1, c2, r2);
}

/// Añade <mergeCells> a cada hoja del xlsx ya generado. Si algo falla, devuelve el archivo tal cual.
List<int> _injectMerges(List<int> bytes, Map<String, List<String>> merges) {
  try {
    final zip = ZipDecoder().decodeBytes(bytes);
    String text(String n) {
      final f = zip.findFile(n);
      return f == null ? '' : utf8.decode(f.content as List<int>);
    }

    String? attr(String tag, String name) => RegExp('(?:^|\\s)$name="([^"]*)"').firstMatch(tag)?.group(1);

    final rels = <String, String>{};
    for (final m in RegExp(r'<Relationship\b[^>]*>').allMatches(text('xl/_rels/workbook.xml.rels'))) {
      final id = attr(m.group(0)!, 'Id'), t = attr(m.group(0)!, 'Target');
      if (id != null && t != null) rels[id] = t;
    }
    final paths = <String, String>{};
    for (final m in RegExp(r'<sheet\b[^>]*>').allMatches(text('xl/workbook.xml'))) {
      final tag = m.group(0)!;
      final n = attr(tag, 'name'), id = attr(tag, 'r:id');
      var t = id == null ? null : rels[id];
      if (n == null || t == null) continue;
      t = t.startsWith('/') ? t.substring(1) : (t.startsWith('xl/') ? t : 'xl/$t');
      paths[t] = n;
    }

    final out = Archive();
    for (final f in zip.files) {
      if (!f.isFile) continue;
      var data = f.content as List<int>;
      final name = paths[f.name];
      final list = name == null ? null : merges[name];
      if (list != null && list.isNotEmpty) {
        var xml = utf8.decode(data);
        if (xml.contains('</sheetData>')) {
          final tag = '<mergeCells count="${list.length}">${list.map((r) => '<mergeCell ref="$r"/>').join()}</mergeCells>';
          xml = xml.replaceFirst('</sheetData>', '</sheetData>$tag');
          data = utf8.encode(xml);
        }
      }
      out.addFile(ArchiveFile(f.name, data.length, data));
    }
    return ZipEncoder().encode(out) ?? bytes;
  } catch (_) {
    return bytes;
  }
}

/// Construye el libro con una hoja por mes del periodo. Devuelve null si no hay días lectivos.
/// [extra] permite añadir hojas adicionales (por ejemplo el detalle del informe individual).
List<int>? _buildAsistenciaXlsx({
  required DateTime from,
  required DateTime to,
  required List<_StuStat> stats,
  required String grado,
  required String seccion,
  void Function(Excel x)? extra,
}) {
  final x = Excel.createExcel();
  final defaultName = x.getDefaultSheet()!;
  final merges = <String, List<String>>{};
  var first = true;
  var m = DateTime(from.year, from.month, 1);
  while (!m.isAfter(to)) {
    final next = DateTime(m.year, m.month + 1, 1);
    final a = m.isBefore(from) ? DateTime(from.year, from.month, from.day) : m;
    final monthEnd = next.subtract(Duration(days: 1));
    final b = monthEnd.isAfter(to) ? to : monthEnd;
    final days = <DateTime>[];
    for (var d = DateTime(a.year, a.month, a.day); !d.isAfter(b); d = DateTime(d.year, d.month, d.day + 1)) {
      if (d.weekday <= 5) days.add(d);
    }
    if (days.isNotEmpty) {
      final name = '${_mesesXlsx[m.month - 1][0]}${_mesesXlsx[m.month - 1].substring(1).toLowerCase()} ${m.year}';
      if (first) {
        x.rename(defaultName, name);
        first = false;
      }
      _curMerges = [];
      _fillMonthSheet(x[name], '${_mesesXlsx[m.month - 1]} ${m.year}', days, stats, grado, seccion);
      merges[name] = _curMerges;
    }
    m = next;
  }
  if (first) return null;
  extra?.call(x);
  final raw = x.encode();
  return raw == null ? null : _injectMerges(raw, merges);
}

void _fillMonthSheet(Sheet s, String title, List<DateTime> days, List<_StuStat> stats, String grado, String seccion) {
  const rMonth = 13, rWeek = 14, rLetter = 15, rNum = 16, r0 = 17; // filas (base 0) como la plantilla: 14, 15, 16, 17 y 18
  final n = days.length;
  final d0 = 2, dN = 2 + n - 1;
  final cX = dN + 1, cY = dN + 2, cZ = dN + 3, cAA = dN + 4;
  final count = stats.isEmpty ? 1 : stats.length;
  final rEnd = r0 + count - 1;
  final xr0 = r0 + 1, xrEnd = rEnd + 1; // filas base 1 para las fórmulas
  final legend = (cAA - 4) < 16 ? 16 : (cAA - 4); // deja una columna libre después de los datos generales
  final lastTop = (legend + 4) > cAA ? (legend + 4) : cAA;

  // Anchos y altos
  s.setColumnWidth(0, 4.44);
  s.setColumnWidth(1, 30);
  for (var c = d0; c <= dN; c++) {
    s.setColumnWidth(c, c == dN ? 6.1 : 4.55);
  }
  for (var c = cX; c <= cAA; c++) {
    s.setColumnWidth(c, 5.2);
  }
  s.setRowHeight(0, 28.8);
  for (final r in [3, 5, 7, 9, 11, 12]) {
    s.setRowHeight(r, 5.4);
  }
  for (var r = rMonth; r <= rNum; r++) {
    s.setRowHeight(r, 17.4);
  }

  // Título
  _xbox(s, 2, 0, lastTop, 0, TextCellValue('CONTROL DE ASISTENCIA'),
      font: 'Arial', size: 20, bold: true, color: 'FF0000', border: false);

  // Datos generales (los de institución, docente, curso y nivel se completan en Excel)
  void label(int row, String text) =>
      _put(s, 1, row, TextCellValue(text), _cs(font: 'Arial', bold: true, h: HorizontalAlign.Right));
  label(2, 'INSTITUCION EDUCATIVA:');
  _xbox(s, 2, 2, 14, 2, _xInstitucion.isEmpty ? null : TextCellValue(_xInstitucion), font: 'Arial', bold: true, h: HorizontalAlign.Left);
  label(4, 'DOCENTE:');
  _xbox(s, 2, 4, 14, 4, null);
  label(6, 'CURSO:');
  _xbox(s, 2, 6, 14, 6, null);
  label(8, 'NIVEL:');
  _xbox(s, 2, 8, 9, 8, null);
  label(10, 'GRADO:');
  _xbox(s, 2, 10, 4, 10, TextCellValue(grado));
  _xbox(s, 5, 10, 7, 10, TextCellValue('SECCION:'), font: 'Arial', bold: true, h: HorizontalAlign.Right, border: false);
  _xbox(s, 8, 10, 10, 10, TextCellValue(seccion));

  // Leyenda
  // Cada fila de la leyenda ocupa 2 filas de la hoja (una normal y una delgada) para que el cuadro quede continuo.
  _mbox(s, legend, 2, legend + 4, 3, TextCellValue('LEYENDA'), font: 'Arial', l: 'm', r: 'm', t: 'm', b: 't');
  void legendRow(int row, String text, CellValue code, CellValue sym, {String? fill, bool bold = false, bool last = false}) {
    final bot = last ? 'm' : 't';
    _mbox(s, legend, row, legend + 2, row + 1, TextCellValue(text), font: 'Arial', l: 'm', r: 't', t: 't', b: bot);
    _mbox(s, legend + 3, row, legend + 3, row + 1, code, bold: false, l: 't', r: 't', t: 't', b: bot);
    _mbox(s, legend + 4, row, legend + 4, row + 1, sym,
        bold: bold, fill: fill, fmt: sym is IntCellValue ? _xSymbolFmt : null,
        color: sym is IntCellValue ? (sym.value == 1 ? '00B050' : 'FF0000') : '000000', l: 't', r: 'm', t: 't', b: bot);
  }
  legendRow(4, 'ASISTENCIA', IntCellValue(1), IntCellValue(1));
  legendRow(6, 'FALTAS', IntCellValue(0), IntCellValue(0));
  legendRow(8, 'TARDANZAS', TextCellValue('T'), TextCellValue('T'), fill: _xTardy, bold: true, last: true);

  // Bordes: medio en el contorno y en las divisiones principales, fino en el resto
  String lb(int c) => (c == 0 || c == d0 || c == cX) ? 'm' : 't';
  String rb(int c) => (c == 1 || c == dN || c == cAA) ? 'm' : 't';

  // Cabecera
  _mbox(s, 0, rMonth, 0, rNum, TextCellValue('N° DE ORDEN'), size: 9, fill: _xHead, rot: 90, l: 'm', r: 't', t: 'm', b: 'm');
  _mbox(s, 1, rMonth, 1, rNum, TextCellValue('APELLIDOS Y NOMBRES'), fill: _xHead, l: 't', r: 'm', t: 'm', b: 'm');
  _mbox(s, d0, rMonth, dN, rMonth, TextCellValue(title), size: 14, fill: _xBlue, color: 'FFFFFF', l: 'm', r: 'm', t: 'm', b: 't');
  // Semanas (lunes a viernes)
  final weeks = <(int, int)>[];
  DateTime? lastKey;
  for (var j = 0; j < n; j++) {
    final d = days[j];
    final key = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    if (lastKey == null || key != lastKey) {
      weeks.add((d0 + j, d0 + j));
      lastKey = key;
    } else {
      weeks[weeks.length - 1] = (weeks.last.$1, d0 + j);
    }
  }
  for (var w = 0; w < weeks.length; w++) {
    final (c1, c2) = weeks[w];
    final num2 = (w + 1).toString().padLeft(2, '0');
    final wide = (c2 - c1 + 1) >= 3;
    _mbox(s, c1, rWeek, c2, rWeek, TextCellValue(wide ? 'SEMANA $num2' : 'SEM $num2'),
        size: wide ? 11 : 10, fill: _xHead, l: 'm', r: 'm', t: 'm', b: 't');
  }
  const letters = ['L', 'M', 'M', 'J', 'V'];
  for (var j = 0; j < n; j++) {
    final c = d0 + j;
    final isStart = weeks.any((w) => w.$1 == c);
    final isEnd = weeks.any((w) => w.$2 == c);
    _put(s, c, rLetter, TextCellValue(letters[days[j].weekday - 1]),
        _cs(bold: true, fill: _xHead, l: isStart ? 'm' : lb(c), r: isEnd ? 'm' : rb(c), t: 't', b: 't'));
    _put(s, c, rNum, IntCellValue(days[j].day),
        _cs(bold: true, fill: _xHead, l: isStart ? 'm' : lb(c), r: isEnd ? 'm' : rb(c), t: 't', b: 'm'));
  }
  final totals = [
    (cX, 'ASISTENCIA', _xGreen),
    (cY, '% DE ASISTENCIA', _xGreenLight),
    (cZ, 'FALTAS', _xRed),
    (cAA, 'TARDANZAS', _xYellow),
  ];
  for (final (c, text, fill) in totals) {
    _mbox(s, c, rMonth, c, rNum, TextCellValue(text), size: 9, fill: fill, rot: 90, l: lb(c), r: rb(c), t: 'm', b: 'm');
  }

  // Alumnos
  for (var i = 0; i < count; i++) {
    final r = r0 + i;
    final st = i < stats.length ? stats[i] : null;
    final top = i == 0 ? 'm' : 't', bottom = i == count - 1 ? 'm' : 't';
    _put(s, 0, r, st == null ? null : IntCellValue(i + 1), _cs(l: 'm', r: 't', t: top, b: bottom));
    _put(s, 1, r, st == null ? null : TextCellValue(st.nombre), _cs(h: HorizontalAlign.Left, l: 't', r: 'm', t: top, b: bottom));
    final estado = <String, String>{if (st != null) for (final d in st.dias) d.fecha: d.estado};
    for (var j = 0; j < n; j++) {
      final c = d0 + j;
      final e = estado[_ymd(days[j])];
      CellValue? v;
      CellStyle style;
      final isStart = weeks.any((w) => w.$1 == c), isEnd = weeks.any((w) => w.$2 == c);
      final l = isStart ? 'm' : lb(c), rr = isEnd ? 'm' : rb(c);
      if (e == 'TEMPRANO' || e == 'PUNTUAL') {
        v = IntCellValue(1);
        style = _cs(bold: true, color: '00B050', fmt: _xSymbolFmt, l: l, r: rr, t: top, b: bottom);
      } else if (e == 'TARDE') {
        v = TextCellValue('T');
        style = _cs(bold: true, fill: _xTardy, l: l, r: rr, t: top, b: bottom);
      } else if (e == 'FALTA') {
        v = IntCellValue(0);
        style = _cs(bold: true, color: 'FF0000', fmt: _xSymbolFmt, l: l, r: rr, t: top, b: bottom);
      } else {
        v = null;
        style = _cs(l: l, r: rr, t: top, b: bottom);
      }
      _put(s, c, r, v, style);
    }
    final rng = '${_colName(d0)}${r + 1}:${_colName(dN)}${r + 1}';
    _put(s, cX, r, FormulaCellValue('COUNTIF($rng,1)+COUNTIF($rng,"T")'), _cs(fill: _xGreen, l: 'm', r: 't', t: top, b: bottom));
    _put(s, cY, r, FormulaCellValue('IF(COUNTA($rng)=0,0,${_colName(cX)}${r + 1}/COUNTA($rng))'),
        _cs(size: 10, fill: _xGreenLight, fmt: '0%', l: 't', r: 't', t: top, b: bottom));
    _put(s, cZ, r, FormulaCellValue('COUNTIF($rng,0)'), _cs(fill: _xRed, l: 't', r: 't', t: top, b: bottom));
    _put(s, cAA, r, FormulaCellValue('COUNTIF($rng,"T")'), _cs(fill: _xYellow, l: 't', r: 'm', t: top, b: bottom));
  }

  // Totales por día
  final f0 = rEnd + 2; // deja una fila en blanco, como la plantilla
  final List<(String, String, int, String?)> foot = [
    ('ASISTENCIA', _xGreen, 11, null),
    ('% DE ASISTENCIA', _xGreenLight, 9, '0%'),
    ('FALTAS', _xRed, 11, null),
    ('TARDANZAS', _xYellowDark, 11, null),
  ];
  for (var k = 0; k < foot.length; k++) {
    final (text, fill, size, fmt) = foot[k];
    final r = f0 + k;
    final top = k == 0 ? 'm' : 't', bottom = k == foot.length - 1 ? 'm' : 't';
    _put(s, 1, r, TextCellValue(text), _cs(bold: true, fill: fill, h: HorizontalAlign.Left, l: 'm', r: 'm', t: top, b: bottom));
    for (var j = 0; j < n; j++) {
      final c = d0 + j;
      final col = _colName(c);
      final rg = '$col$xr0:$col$xrEnd';
      final String formula = switch (k) {
        0 => 'COUNTIF($rg,1)+COUNTIF($rg,"T")',
        1 => 'IF(COUNTA($rg)=0,0,$col${f0 + 1}/COUNTA($rg))',
        2 => 'COUNTIF($rg,0)',
        _ => 'COUNTIF($rg,"T")',
      };
      _put(s, c, r, FormulaCellValue(formula),
          _cs(size: size, fill: fill, fmt: fmt, l: c == d0 ? 'm' : 't', r: c == dN ? 'm' : 't', t: top, b: bottom));
    }
  }
}

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key, required this.user});
  final AuthUser user;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: FScaffold(
          backgroundColor: _bg,
          body: Row(children: [
            AppSidebar(user: user, selected: 'Reportes'),
            FContent(
              child: SafeArea(
                child: Column(children: [
                  Container(
                    height: 66,
                    padding: EdgeInsets.symmetric(horizontal: 22),
                    child: Row(children: [
                      PageIcon(Icons.assessment),
                      SizedBox(width: 12),
                      Text('Reportes', style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                    ]),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TabBar(
                      isScrollable: true,
                      indicatorColor: _cyan,
                      indicatorWeight: 3,
                      labelColor: P.text,
                      unselectedLabelColor: _muted,
                      tabs: [
                        Tab(icon: Icon(Icons.person, size: 18), text: 'Informe individual'),
                        Tab(icon: Icon(Icons.groups, size: 18), text: 'Reporte general'),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: _line),
                  Expanded(child: TabBarView(children: [_IndividualTab(), _GeneralTab()])),
                ]),
              ),
            ),
          ]),
        ),
      );
}

// ───────────────────────── Componentes comunes ─────────────────────────

InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      filled: true,
      fillColor: P.field,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );

Widget _box(String title, IconData icon, Widget child) => Container(
      padding: EdgeInsets.all(16),
      decoration: P.card(r: 13),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, color: _cyan, size: 22),
          SizedBox(width: 8),
          Text(title, style: TextStyle(color: P.text, fontSize: 17, fontWeight: FontWeight.bold)),
        ]),
        SizedBox(height: 14),
        child,
      ]),
    );

Widget _card(String value, String label, [Color? color]) => Container(
      width: 140,
      padding: EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: P.field, border: Border.all(color: _line), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(value, style: TextStyle(color: color ?? P.text, fontSize: 22, fontWeight: FontWeight.bold)),
        SizedBox(height: 4),
        Text(label, style: TextStyle(color: _muted, fontSize: 10, letterSpacing: .6)),
      ]),
    );

Widget _estadoChip(String estado) {
  final (txt, col) = switch (estado) {
    'TEMPRANO' || 'PUNTUAL' => ('PUNTUAL', _green),
    'TARDE' => ('TARDANZA', _orange),
    _ => ('AUSENTE', _red),
  };
  return Container(
    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(border: Border.all(color: col), borderRadius: BorderRadius.circular(20)),
    child: Text(txt, style: TextStyle(color: P.text, fontSize: 11, fontWeight: FontWeight.bold)),
  );
}

Widget _table(List<String> cols, List<List<Widget>> rows) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(P.head),
        headingTextStyle: TextStyle(color: P.text, fontWeight: FontWeight.bold, fontSize: 12),
        dataTextStyle: TextStyle(color: P.text, fontSize: 13),
        columns: [for (final c in cols) DataColumn(label: Text(c))],
        rows: [for (final r in rows) DataRow(cells: [for (final c in r) DataCell(c)])],
      ),
    );

class _DateField extends StatelessWidget {
  const _DateField({required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () async {
          final d = await showDatePicker(
              context: context, initialDate: value, firstDate: DateTime(2020), lastDate: DateTime(2100));
          if (d != null) onChanged(d);
        },
        child: InputDecorator(
          decoration: _dec(label),
          child: Row(children: [
            Expanded(child: Text(_dmy(value), style: TextStyle(color: P.text))),
            Icon(Icons.calendar_today, size: 16, color: _muted),
          ]),
        ),
      );
}

/// Buscador de estudiante por nombre, apellido o DNI (desde 2 caracteres).
class _StudentPicker extends StatefulWidget {
  const _StudentPicker({required this.label, required this.onPicked});
  final String label;
  final ValueChanged<Map<String, Object?>?> onPicked;
  @override
  State<_StudentPicker> createState() => _StudentPickerState();
}

class _StudentPickerState extends State<_StudentPicker> {
  final _ctrl = TextEditingController();
  List<Map<String, Object?>> _sugg = [];
  bool _picked = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    if (_picked) {
      _picked = false;
      widget.onPicked(null);
    }
    q = q.trim();
    if (q.length < 2) {
      setState(() => _sugg = []);
      return;
    }
    final db = await AppDatabase.instance.database;
    final like = '%$q%';
    final rows = await db.query('alumnos',
        where: "(nombres || ' ' || apellidos || ' ' || IFNULL(dni,'')) LIKE ? OR (apellidos || ' ' || nombres) LIKE ?",
        whereArgs: [like, like],
        orderBy: 'apellidos COLLATE NOCASE, nombres COLLATE NOCASE',
        limit: 6);
    if (mounted) setState(() => _sugg = rows);
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        TextField(
          controller: _ctrl,
          onChanged: _search,
          decoration: _dec(widget.label).copyWith(
            hintText: 'Nombre o DNI',
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: Icon(Icons.close, size: 18),
                    onPressed: () {
                      _ctrl.clear();
                      _picked = false;
                      widget.onPicked(null);
                      setState(() => _sugg = []);
                    }),
          ),
        ),
        if (_sugg.isNotEmpty)
          Container(
            margin: EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: P.field, border: Border.all(color: _line), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [
              for (final s in _sugg)
                ListTile(
                  dense: true,
                  title: Text('${s['apellidos']}, ${s['nombres']}', style: TextStyle(color: P.text)),
                  subtitle: Text('DNI ${s['dni'] ?? ''} · ${s['grado'] ?? ''} "${s['seccion'] ?? ''}" · ${s['turno']}',
                      style: TextStyle(color: _muted, fontSize: 11)),
                  onTap: () {
                    _ctrl.text = '${s['apellidos']}, ${s['nombres']}';
                    _picked = true;
                    setState(() => _sugg = []);
                    widget.onPicked(s);
                  },
                ),
            ]),
          ),
      ]);
}

void _toast(BuildContext c, String s) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(s)));

// ───────────────────────── Informe individual ─────────────────────────

class _IndividualTab extends StatefulWidget {
  const _IndividualTab();
  @override
  State<_IndividualTab> createState() => _IndividualTabState();
}

class _IndividualTabState extends State<_IndividualTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Map<String, Object?>? _student;
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  _StuStat? _stat;
  bool _busy = false;

  Future<void> _generate() async {
    if (_student == null) {
      _toast(context, 'Elige un estudiante de la lista de sugerencias.');
      return;
    }
    setState(() => _busy = true);
    final r = await _compute(_from, _to, [_student!]);
    if (mounted) {
      setState(() {
        _stat = r.first;
        _busy = false;
      });
    }
  }

  Future<void> _export() async {
    final s = _stat;
    if (s == null) return;
    _xInstitucion = (await CarnetConfig.load()).institucion.trim();
    final bytes = _buildAsistenciaXlsx(
      from: _from,
      to: _to,
      stats: [s],
      grado: '${s.alumno['grado'] ?? ''}',
      seccion: '${s.alumno['seccion'] ?? ''}',
      // Hoja extra con las horas de entrada y salida (la plantilla solo guarda 1 / 0 / T).
      extra: (x) {
        final det = x['Detalle'];
        det.appendRow(['Fecha', 'Entrada', 'Salida', 'Estado', 'Tipo de registro'].map((e) => TextCellValue(e)).toList());
        for (final d in s.dias) {
          det.appendRow([
            d.fecha,
            d.entrada ?? '',
            d.salida ?? (d.entrada == null ? '' : 'Pendiente'),
            (d.estado == 'TEMPRANO' || d.estado == 'PUNTUAL') ? 'Puntual' : d.estado == 'TARDE' ? 'Tardanza' : 'Ausente',
            d.tipo,
          ].map((e) => TextCellValue(e)).toList());
        }
      },
    );
    if (bytes == null) {
      if (mounted) _toast(context, 'No hay días lectivos (lunes a viernes) en el periodo elegido.');
      return;
    }
    final name = 'reporte_${s.dni.isEmpty ? 'estudiante' : s.dni}_${_ymd(_from)}_${_ymd(_to)}.xlsx';
    if (await _saveXlsx(context, name, bytes) && mounted) _toast(context, 'Excel exportado.');
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final s = _stat;
    return ListView(padding: EdgeInsets.all(18), children: [
      _box(
        'Elegir estudiante y periodo',
        Icons.search,
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          LayoutBuilder(builder: (context, c) {
            final picker = _StudentPicker(label: 'Estudiante', onPicked: (v) => setState(() {
                  _student = v;
                  _stat = null;
                }));
            final from = _DateField(label: 'Desde', value: _from, onChanged: (d) => setState(() => _from = d));
            final to = _DateField(label: 'Hasta', value: _to, onChanged: (d) => setState(() => _to = d));
            final btn = FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: Icon(Icons.play_arrow),
              label: Text('Generar'),
              style: FilledButton.styleFrom(minimumSize: Size(110, 46)),
            );
            if (c.maxWidth < 800) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                picker, SizedBox(height: 10), from, SizedBox(height: 10), to, SizedBox(height: 10), btn,
              ]);
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 4, child: picker),
              SizedBox(width: 10),
              Expanded(flex: 2, child: from),
              SizedBox(width: 10),
              Expanded(flex: 2, child: to),
              SizedBox(width: 10),
              btn,
            ]);
          }),
          if (_student != null)
            Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                  'Seleccionado: ${_student!['apellidos']}, ${_student!['nombres']} (${_student!['grado'] ?? ''} "${_student!['seccion'] ?? ''}", ${_student!['turno']})',
                  style: TextStyle(color: _muted)),
            ),
        ]),
      ),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
      if (s != null) ...[
        SizedBox(height: 16),
        _box(
          s.nombre,
          Icons.person,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('DNI ${s.dni} · ${s.aula} · Turno ${s.turno} · Periodo ${_ymd(_from)} → ${_ymd(_to)}',
                style: TextStyle(color: P.text)),
            SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _card('${s.esperados}', 'DÍAS ESPERADOS'),
              _card('${s.presentes}', 'DÍAS PRESENTES', _green),
              _card('${s.ausentes}', 'DÍAS AUSENTES', _red),
              _card('${s.puntuales}', 'PUNTUALES'),
              _card('${s.tardanzas}', 'TARDANZAS', _orange),
              _card(_pct(s.pct), '% ASISTENCIA', _cyan),
              _card('${s.pendientes}', 'SALIDAS PENDIENTES'),
            ]),
            SizedBox(height: 12),
            TextButton.icon(
              onPressed: _export,
              icon: Icon(Icons.table_view, color: _green),
              label: Text('Exportar a Excel', style: TextStyle(color: P.text)),
            ),
            if (s.dias.isEmpty)
              Padding(
                padding: EdgeInsets.all(12),
                child: Text('No hay días con registros en este periodo.', style: TextStyle(color: _muted)),
              )
            else
              _table(
                ['FECHA', 'ENTRADA', 'SALIDA', 'ESTADO', 'REGISTROS'],
                [
                  for (final d in s.dias)
                    [
                      Text(d.fecha),
                      Text(d.entrada ?? '—'),
                      Text(d.salida ?? '—'),
                      d.entrada != null && d.salida == null
                          ? Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                              decoration: BoxDecoration(border: Border.all(color: _orange), borderRadius: BorderRadius.circular(20)),
                              child: Text('SALIDA PENDIENTE', style: TextStyle(color: P.text, fontSize: 11, fontWeight: FontWeight.bold)),
                            )
                          : _estadoChip(d.estado),
                      Text('${d.registros}'),
                    ],
                ],
              ),
          ]),
        ),
      ],
    ]);
  }
}

// ───────────────────────── Reporte general ─────────────────────────

class _GeneralTab extends StatefulWidget {
  const _GeneralTab();
  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static const periods = ['Hoy', '7 días lectivos', 'Este mes', 'Rango personalizado'];
  String _period = 'Este mes', _turno = 'Todos', _grado = 'Todos', _seccion = 'Todos';
  DateTime _from = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _to = DateTime.now();
  Map<String, Object?>? _student;
  List<String> _grados = ['Todos'], _secciones = ['Todos'], _turnos = ['Todos', 'Mañana', 'Tarde'];
  List<_StuStat>? _stats;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('alumnos', columns: ['grado', 'seccion']);
    List<String> opts(String k) =>
        ['Todos', ...rows.map((r) => '${r[k] ?? ''}').where((s) => s.isNotEmpty).toSet().toList()..sort()];
    final tn = await AppDatabase.instance.listaTurnos();
    if (mounted) {
      setState(() {
        _turnos = ['Todos', ...tn];
        _grados = opts('grado');
        _secciones = opts('seccion');
      });
    }
  }

  void _setPeriod(String p) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    setState(() {
      _period = p;
      if (p == 'Hoy') {
        _from = today;
        _to = today;
      } else if (p == '7 días lectivos') {
        _to = today;
        _from = today.subtract(Duration(days: 8));
      } else if (p == 'Este mes') {
        _from = DateTime(n.year, n.month, 1);
        _to = today;
      }
    });
  }

  Future<void> _generate() async {
    setState(() => _busy = true);
    final db = await AppDatabase.instance.database;
    final where = <String>[], args = <Object?>[];
    if (_student != null) {
      where.add('id = ?');
      args.add(_student!['id']);
    }
    if (_turno != 'Todos') {
      where.add('turno = ?');
      args.add(_turno);
    }
    if (_grado != 'Todos') {
      where.add('grado = ?');
      args.add(_grado);
    }
    if (_seccion != 'Todos') {
      where.add('seccion = ?');
      args.add(_seccion);
    }
    final students = await db.query('alumnos',
        where: where.isEmpty ? null : where.join(' AND '),
        whereArgs: args,
        orderBy: 'apellidos COLLATE NOCASE, nombres COLLATE NOCASE');
    final r = await _compute(_from, _to, students);
    if (mounted) {
      setState(() {
        _stats = r;
        _busy = false;
      });
    }
  }

  int _sum(int Function(_StuStat) f) => (_stats ?? const <_StuStat>[]).fold(0, (a, s) => a + f(s));
  double get _totalPct {
    final e = _sum((s) => s.esperados);
    return e == 0 ? 0 : _sum((s) => s.presentes) * 100 / e;
  }

  Future<void> _export() async {
    final list = _stats;
    if (list == null) return;
    String pick(String filter, String key) {
      if (filter != 'Todos') return filter;
      if (_student != null) return '${_student![key] ?? ''}';
      return 'TODOS';
    }

    _xInstitucion = (await CarnetConfig.load()).institucion.trim();
    final bytes = _buildAsistenciaXlsx(
      from: _from,
      to: _to,
      stats: list,
      grado: pick(_grado, 'grado'),
      seccion: pick(_seccion, 'seccion'),
    );
    if (bytes == null) {
      if (mounted) _toast(context, 'No hay días lectivos (lunes a viernes) en el periodo elegido.');
      return;
    }
    if (await _saveXlsx(context, 'reporte_general_${_ymd(_from)}_${_ymd(_to)}.xlsx', bytes) && mounted) {
      _toast(context, 'Excel exportado.');
    }
  }

  Widget _drop(String label, String value, List<String> items, ValueChanged<String> onChanged) =>
      DropdownButtonFormField<String>(
        value: items.contains(value) ? value : items.first,
        isExpanded: true,
        decoration: _dec(label),
        items: [for (final i in items) DropdownMenuItem(value: i, child: Text(i))],
        onChanged: (v) => onChanged(v ?? value),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final list = _stats;
    final custom = _period == 'Rango personalizado';
    return ListView(padding: EdgeInsets.all(18), children: [
      _box(
        'Periodo y alcance',
        Icons.tune,
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 900 ? 4 : c.maxWidth > 560 ? 2 : 1;
          final w = (c.maxWidth - 12 * (cols - 1)) / cols;
          Widget cell(Widget child) => SizedBox(width: w, child: child);
          return Wrap(spacing: 12, runSpacing: 12, children: [
            cell(_drop('Periodo', _period, periods, _setPeriod)),
            cell(IgnorePointer(ignoring: !custom, child: Opacity(opacity: custom ? 1 : .5, child: _DateField(label: 'Desde', value: _from, onChanged: (d) => setState(() => _from = d))))),
            cell(IgnorePointer(ignoring: !custom, child: Opacity(opacity: custom ? 1 : .5, child: _DateField(label: 'Hasta', value: _to, onChanged: (d) => setState(() => _to = d))))),
            cell(_drop('Turno', _turno, _turnos, (v) => setState(() => _turno = v))),
            cell(_drop('Grado', _grado, _grados, (v) => setState(() => _grado = v))),
            cell(_drop('Sección', _seccion, _secciones, (v) => setState(() => _seccion = v))),
            cell(_StudentPicker(label: 'Estudiante (opcional)', onPicked: (v) => setState(() => _student = v))),
            cell(FilledButton.icon(
              onPressed: _busy ? null : _generate,
              icon: Icon(Icons.play_arrow),
              label: Text('Generar'),
              style: FilledButton.styleFrom(minimumSize: Size(110, 46)),
            )),
          ]);
        }),
      ),
      if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator(minHeight: 2)),
      if (list != null) ...[
        SizedBox(height: 16),
        _box(
          'Reporte general',
          Icons.groups,
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_ymd(_from)} → ${_ymd(_to)} · ${list.length} estudiantes', style: TextStyle(color: P.text)),
            SizedBox(height: 14),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _card('${_sum((s) => s.presentes)}', 'ASISTENCIAS', _green),
              _card('${_sum((s) => s.ausentes)}', 'AUSENCIAS', _red),
              _card('${_sum((s) => s.puntuales)}', 'PUNTUALES'),
              _card('${_sum((s) => s.tardanzas)}', 'TARDANZAS', _orange),
              _card('${_sum((s) => s.pendientes)}', 'SALIDAS PENDIENTES'),
              _card(_pct(_totalPct), '% ASISTENCIA', _cyan),
              _card('${_sum((s) => s.manuales)}', 'REGISTROS MANUALES'),
            ]),
            SizedBox(height: 12),
            TextButton.icon(
              onPressed: list.isEmpty ? null : _export,
              icon: Icon(Icons.table_view, color: _green),
              label: Text('Exportar a Excel', style: TextStyle(color: P.text)),
            ),
            if (list.isEmpty)
              Padding(padding: EdgeInsets.all(12), child: Text('No hay estudiantes con ese filtro.', style: TextStyle(color: _muted)))
            else
              _table(
                ['ESTUDIANTE', 'GRADO / SECCIÓN', 'TURNO', 'ESPERADOS', 'PRESENTES', 'AUSENTES', 'PUNTUALES', 'TARDANZAS', 'PENDIENTES', '% ASIST.'],
                [
                  for (final s in list)
                    [
                      Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.nombre, style: TextStyle(fontWeight: FontWeight.bold)),
                        Text(s.dni, style: TextStyle(color: _muted, fontSize: 11)),
                      ]),
                      Text(s.aula),
                      Text(s.turno),
                      Text('${s.esperados}'),
                      Text('${s.presentes}'),
                      Text('${s.ausentes}', style: TextStyle(color: s.ausentes > 0 ? _red : P.text)),
                      Text('${s.puntuales}'),
                      Text('${s.tardanzas}', style: TextStyle(color: s.tardanzas > 0 ? _orange : P.text)),
                      Text('${s.pendientes}'),
                      Text(_pct(s.pct)),
                    ],
                ],
              ),
          ]),
        ),
      ],
    ]);
  }
}
