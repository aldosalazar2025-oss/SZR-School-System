import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

import '../auth/auth_repository.dart';
import '../database/app_database.dart';
import 'app_sidebar.dart';

/// Decodifica un QR a partir de los bytes de una foto (JPG/PNG).
/// Es una función de nivel superior para poder ejecutarse en un isolate con
/// `compute` y no congelar la interfaz mientras se analiza la imagen.
String? decodeQrFromImage(Uint8List bytes) {
  try {
    var image = img.decodeImage(bytes);
    if (image == null) return null;
    if (image.width > 960) image = img.copyResize(image, width: 960);
    final pixels = image
        .convert(numChannels: 4)
        .getBytes(order: img.ChannelOrder.abgr)
        .buffer
        .asInt32List();
    final source = RGBLuminanceSource(image.width, image.height, pixels);
    final bitmap = BinaryBitmap(HybridBinarizer(source));
    return QRCodeReader().decode(bitmap).text;
  } catch (_) {
    // NotFoundException u otros: no hay QR legible en este cuadro.
    return null;
  }
}

enum _Level { ok, warning, error }

class _ScanOutcome {
  _ScanOutcome(this.level, this.title, this.detail, {this.photo, this.record});
  final _Level level;
  final String title;
  final String detail;
  final Uint8List? photo;
  final _SessionRecord? record;
}

class _SessionRecord {
  _SessionRecord(this.name, this.time, this.type, this.status);
  final String name;
  final String time;
  final String type;
  final String status;
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.user});
  final AuthUser user;
  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> with SingleTickerProviderStateMixin {
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static Color get green => P.ok;
  static Color get red => P.err;
  static Color get orange => P.warn;
  static Color get blue => P.accent2;

  late final AnimationController _scanLine =
      AnimationController(vsync: this, duration: Duration(milliseconds: 2200))..repeat(reverse: true);
  final AudioPlayer _player = AudioPlayer();

  List<CameraDescription> _cameras = [];
  CameraDescription? _selected;
  CameraController? _controller;
  String? _cameraError;
  bool _loadingCamera = true;
  bool _sound = true;
  bool _disposed = false;

  String? _lastRaw;
  DateTime _lastRawAt = DateTime.fromMillisecondsSinceEpoch(0);
  _ScanOutcome? _outcome;
  final List<_SessionRecord> _session = [];

  @override
  void initState() {
    super.initState();
    _startCameras();
    _scanLoop();
  }

  @override
  void dispose() {
    _disposed = true;
    _scanLine.dispose();
    _player.dispose();
    final c = _controller;
    _controller = null;
    c?.dispose();
    super.dispose();
  }

  // ───────────────────────── Cámara ─────────────────────────

  Future<void> _startCameras() async {
    setState(() {
      _loadingCamera = true;
      _cameraError = null;
    });
    try {
      final list = await availableCameras();
      if (_disposed) return;
      if (list.isEmpty) {
        setState(() {
          _cameras = [];
          _loadingCamera = false;
          _cameraError = 'No se detectó ninguna cámara. Conecta una (webcam, USB o virtual) y pulsa Reintentar.';
        });
        return;
      }
      _cameras = list;
      await _openCamera(_selected != null && list.contains(_selected) ? _selected! : list.first);
    } catch (e) {
      if (_disposed) return;
      final missing = e is MissingPluginException || e.toString().contains('MissingPluginException');
      setState(() {
        _loadingCamera = false;
        _cameraError = missing
            ? 'El plugin de cámara no está cargado en esta compilación de Windows.\n'
                'Cierra la app y ejecuta: flutter clean, flutter pub get y flutter run -d windows '
                '(no uses hot reload).'
            : 'No se pudo acceder a la cámara: $e\n'
                'Revisa Configuración de Windows → Privacidad → Cámara y que ninguna otra app la esté usando.';
      });
    }
  }

  Future<void> _openCamera(CameraDescription description) async {
    if (_disposed) return;
    setState(() {
      _loadingCamera = true;
      _cameraError = null;
      _selected = description;
    });
    final old = _controller;
    _controller = null; // el bucle de escaneo se detiene mientras no haya controlador
    await old?.dispose();
    final controller = CameraController(description, ResolutionPreset.high, enableAudio: false);
    try {
      await controller.initialize();
      if (_disposed) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _loadingCamera = false;
      });
    } catch (e) {
      await controller.dispose();
      if (_disposed) return;
      setState(() {
        _loadingCamera = false;
        _cameraError = 'No se pudo iniciar "${description.name}": $e';
      });
    }
  }

  /// Toma fotos de la cámara de forma continua y busca un QR en cada una.
  /// (camera_windows no ofrece flujo de imágenes, por eso se usan capturas.)
  Future<void> _scanLoop() async {
    while (!_disposed) {
      final c = _controller;
      if (c == null || !c.value.isInitialized || c.value.isTakingPicture) {
        await Future<void>.delayed(Duration(milliseconds: 250));
        continue;
      }
      var pause = Duration(milliseconds: 120);
      try {
        final shot = await c.takePicture();
        final bytes = await shot.readAsBytes();
        try {
          await File(shot.path).delete();
        } catch (_) {}
        final code = await compute(decodeQrFromImage, bytes);
        if (code != null && !_disposed) await _onCode(code);
      } catch (_) {
        pause = Duration(milliseconds: 600);
      }
      await Future<void>.delayed(pause);
    }
  }

  // ───────────────────────── Registro ─────────────────────────

  Future<void> _onCode(String raw) async {
    final now = DateTime.now();
    // Evita repetir el mismo código mientras el estudiante sigue frente a la cámara.
    if (raw == _lastRaw && now.difference(_lastRawAt).inSeconds < 4) return;
    _lastRaw = raw;
    _lastRawAt = now;

    final outcome = await _register(raw.trim(), now);
    if (!mounted) return;
    setState(() {
      _outcome = outcome;
      if (outcome.record != null) {
        _session.insert(0, outcome.record!);
        if (_session.length > 50) _session.removeLast();
      }
    });
    _beep(outcome.level == _Level.ok);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  int _minutes(String hhmm, int fallback) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return fallback;
    final h = int.tryParse(parts[0]), m = int.tryParse(parts[1]);
    return (h == null || m == null) ? fallback : h * 60 + m;
  }

  Future<_ScanOutcome> _register(String raw, DateTime now) async {
    final match = RegExp(r'^ALUMNO:(\d+)\|DNI:(.*)$').firstMatch(raw);
    if (match == null) {
      return _ScanOutcome(_Level.error, 'Código no reconocido', 'Este QR no pertenece al sistema de asistencias.');
    }
    final id = int.parse(match.group(1)!);
    final db = await AppDatabase.instance.database;
    final rows = await db.query('alumnos', where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) {
      return _ScanOutcome(_Level.error, 'Estudiante no encontrado', 'El código no corresponde a ningún estudiante registrado.');
    }
    final s = rows.first;
    final storedQr = s['codigo_qr'] as String?;
    if (storedQr != null && storedQr.isNotEmpty && storedQr != raw) {
      return _ScanOutcome(_Level.error, 'Código inválido', 'El QR no coincide con el registrado para este estudiante.');
    }
    final name = '${s['nombres'] ?? ''} ${s['apellidos'] ?? ''}'.trim();
    final grade = '${s['grado'] ?? ''} ${s['seccion'] ?? ''}'.trim();
    final photo = s['foto'] as Uint8List?;
    if (s['activo'] != 1) {
      return _ScanOutcome(_Level.error, name, 'Estudiante deshabilitado. No se registró asistencia.', photo: photo);
    }

    final fecha = '${now.year.toString().padLeft(4, '0')}-${_two(now.month)}-${_two(now.day)}';
    final hora = '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';

    final previous = await db.query('asistencias',
        where: 'alumno_id=? AND fecha=?', whereArgs: [id, fecha], orderBy: 'id ASC', limit: 1);
    if (previous.isNotEmpty) {
      final p = previous.first;
      if (p['estado'] == 'FALTA') {
        return _ScanOutcome(_Level.warning, name,
            'Está marcado como inasistencia hoy. Corrígelo en Registro manual.', photo: photo);
      }
      if (p['hora_salida'] != null) {
        return _ScanOutcome(_Level.warning, name,
            'Entrada ${p['hora']} y salida ${p['hora_salida']} ya registradas hoy.', photo: photo);
      }
      // Segundo escaneo del día = salida (con 10 min mínimos para evitar dobles lecturas).
      final inParts = '${p['hora']}'.split(':');
      final inMin = (int.tryParse(inParts[0]) ?? 0) * 60 + (int.tryParse(inParts.length > 1 ? inParts[1] : '0') ?? 0);
      if (now.hour * 60 + now.minute - inMin < 10) {
        return _ScanOutcome(_Level.warning, name,
            'Ya registrado hoy a las ${p['hora']} (${p['estado']}).', photo: photo);
      }
      await db.update('asistencias',
          {'hora_salida': hora, 'salida_tipo': 'QR', 'usuario_id': widget.user.id},
          where: 'id=?', whereArgs: [p['id']]);
      final outTime = '${_two(now.hour)}:${_two(now.minute)}';
      return _ScanOutcome(_Level.ok, name, 'SALIDA registrada a las $outTime', photo: photo,
          record: _SessionRecord(name, outTime, 'QR', 'SALIDA'));
    }

    final turno = '${s['turno'] ?? 'Mañana'}';
    final status = await AppDatabase.instance.estadoEntrada(turno, now.hour * 60 + now.minute);

    await db.insert('asistencias', {
      'alumno_id': id,
      'fecha': fecha,
      'hora': hora,
      'estado': status,
      'tipo': 'QR',
      'usuario_id': widget.user.id,
    });

    final shortTime = '${_two(now.hour)}:${_two(now.minute)}';
    return _ScanOutcome(
      _Level.ok,
      name,
      '${grade.isEmpty ? turno : '$grade · $turno'} · $status a las $shortTime',
      photo: photo,
      record: _SessionRecord(name, shortTime, 'QR', status),
    );
  }

  Future<void> _beep(bool ok) async {
    if (!_sound) return;
    try {
      await _player.stop();
      await _player.play(AssetSource(ok ? 'sounds/ok.wav' : 'sounds/warn.wav'));
    } catch (_) {
      SystemSound.play(SystemSoundType.alert);
    }
  }

  // ───────────────────────── Interfaz ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      backgroundColor: bg,
      body: Row(children: [
        AppSidebar(user: widget.user, selected: 'Escanear QR'),
        FContent(
          child: SafeArea(
            child: Column(children: [
              Container(
                height: 66,
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(children: [
                  PageIcon(Icons.qr_code_scanner),
                  SizedBox(width: 12),
                  Text('Escanear asistencia',
                      style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                ]),
              ),
              Expanded(
                child: LayoutBuilder(builder: (context, c) {
                  final wide = c.maxWidth > 900;
                  final scanner = _scannerPanel();
                  final recent = _recentPanel();
                  if (wide) {
                    return Padding(
                      padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(flex: 5, child: SingleChildScrollView(child: scanner)),
                        SizedBox(width: 16),
                        Expanded(flex: 6, child: recent),
                      ]),
                    );
                  }
                  return ListView(
                    padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
                    children: [scanner, SizedBox(height: 16), SizedBox(height: 360, child: recent)],
                  );
                }),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  BoxDecoration _panel() =>
      P.card(r: 16);

  Widget _scannerPanel() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_cameras.length > 1)
          Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<CameraDescription>(
              value: _cameras.contains(_selected) ? _selected : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Cámara',
                prefixIcon: Icon(Icons.videocam),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: [
                for (final cam in _cameras)
                  DropdownMenuItem(value: cam, child: Text(cam.name, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (cam) {
                if (cam != null && cam != _selected) _openCamera(cam);
              },
            ),
          ),
        ClipRRect(borderRadius: BorderRadius.circular(10), child: _cameraView()),
        SizedBox(height: 10),
        Row(children: [
          Switch(value: _sound, onChanged: (v) => setState(() => _sound = v)),
          SizedBox(width: 6),
          Text('Sonido al escanear', style: TextStyle(color: P.text, fontSize: 15)),
          Spacer(),
          IconButton(
            tooltip: 'Reiniciar cámara',
            onPressed: _loadingCamera ? null : _startCameras,
            icon: Icon(Icons.refresh, color: cyan),
          ),
        ]),
        if (_outcome != null) ...[SizedBox(height: 8), _outcomeCard(_outcome!)],
      ]),
    );
  }

  Widget _cameraView() {
    final c = _controller;
    if (_loadingCamera) {
      return _CameraPlaceholder(child: CircularProgressIndicator());
    }
    if (_cameraError != null || c == null || !c.value.isInitialized) {
      return _CameraPlaceholder(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.videocam_off, color: P.text.withOpacity(.54), size: 44),
          SizedBox(height: 10),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Text(_cameraError ?? 'Cámara no disponible.',
                textAlign: TextAlign.center, style: TextStyle(color: P.muted)),
          ),
          SizedBox(height: 10),
          FilledButton.icon(onPressed: _startCameras, icon: Icon(Icons.refresh), label: Text('Reintentar')),
        ]),
      );
    }
    final ratio = c.value.aspectRatio > 0 ? c.value.aspectRatio : 4 / 3;
    return AspectRatio(
      aspectRatio: ratio,
      child: Stack(fit: StackFit.expand, children: [
        CameraPreview(c),
        AnimatedBuilder(
          animation: _scanLine,
          builder: (_, __) => CustomPaint(painter: _FramePainter(_scanLine.value, cyan)),
        ),
      ]),
    );
  }

  Widget _outcomeCard(_ScanOutcome o) {
    final color = switch (o.level) { _Level.ok => green, _Level.warning => orange, _Level.error => red };
    final icon = switch (o.level) {
      _Level.ok => Icons.check_circle,
      _Level.warning => Icons.info,
      _Level.error => Icons.cancel,
    };
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        border: Border.all(color: color.withOpacity(.7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        o.photo == null
            ? CircleAvatar(radius: 24, backgroundColor: color.withOpacity(.25), child: Icon(icon, color: color))
            : CircleAvatar(radius: 24, backgroundImage: MemoryImage(o.photo!)),
        SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(o.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: P.text, fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 2),
            Text(o.detail, style: TextStyle(color: P.muted, fontSize: 13)),
          ]),
        ),
        Icon(icon, color: color, size: 28),
      ]),
    );
  }

  Widget _recentPanel() {
    Widget cell(String t, int flex, {bool head = false, Widget? child}) => Expanded(
          flex: flex,
          child: Center(
            child: child ??
                Text(t,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: head ? P.text : P.text,
                      fontWeight: head ? FontWeight.bold : FontWeight.normal,
                      fontSize: head ? 12 : 13,
                    )),
          ),
        );

    Widget statusChip(String s) {
      final color = (s == 'TEMPRANO' || s == 'PUNTUAL') ? blue : (s == 'TARDE' ? orange : (s == 'SALIDA' ? green : red));
      return Container(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(color: color.withOpacity(.18), borderRadius: BorderRadius.circular(20)),
        child: Text(s, style: TextStyle(color: P.text, fontWeight: FontWeight.bold, fontSize: 11)),
      );
    }

    return Container(
      padding: EdgeInsets.all(16),
      decoration: _panel(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.format_list_bulleted, color: cyan, size: 28),
          SizedBox(width: 10),
          Expanded(
            child: Text('Últimos registrados en esta sesión',
                style: TextStyle(color: P.text, fontSize: 20, fontWeight: FontWeight.bold)),
          ),
          if (_session.isNotEmpty)
            Text('${_session.length}', style: TextStyle(color: P.text, fontSize: 18, fontWeight: FontWeight.bold)),
        ]),
        SizedBox(height: 14),
        Container(
          height: 42,
          color: P.head,
          child: Row(children: [
            cell('ESTUDIANTE', 4, head: true),
            cell('HORA', 2, head: true),
            cell('TIPO', 2, head: true),
            cell('ESTADO', 3, head: true),
          ]),
        ),
        Expanded(
          child: _session.isEmpty
              ? Center(
                  child: Text('Aún no hay registros en esta sesión', style: TextStyle(color: P.muted)))
              : ListView.separated(
                  itemCount: _session.length,
                  separatorBuilder: (_, __) => Divider(color: line, height: 1),
                  itemBuilder: (_, i) {
                    final r = _session[i];
                    return SizedBox(
                      height: 46,
                      child: Row(children: [
                        cell(r.name, 4),
                        cell(r.time, 2),
                        cell(r.type, 2),
                        cell('', 3, child: statusChip(r.status)),
                      ]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 4 / 3,
        child: Container(color: P.field, alignment: Alignment.center, child: child),
      );
}

/// Marco de enfoque con esquinas y una línea de barrido animada.
class _FramePainter extends CustomPainter {
  _FramePainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.shortestSide * 0.62;
    final rect = Rect.fromCenter(center: size.center(Offset.zero), width: side, height: side);
    final corner = side * 0.17;

    final p = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final path = Path()
      ..moveTo(rect.left, rect.top + corner)..lineTo(rect.left, rect.top)..lineTo(rect.left + corner, rect.top)
      ..moveTo(rect.right - corner, rect.top)..lineTo(rect.right, rect.top)..lineTo(rect.right, rect.top + corner)
      ..moveTo(rect.right, rect.bottom - corner)..lineTo(rect.right, rect.bottom)..lineTo(rect.right - corner, rect.bottom)
      ..moveTo(rect.left + corner, rect.bottom)..lineTo(rect.left, rect.bottom)..lineTo(rect.left, rect.bottom - corner);
    canvas.drawPath(path, p);

    final y = rect.top + rect.height * t;
    final glow = Paint()
      ..shader = LinearGradient(colors: [Colors.transparent, color, Colors.transparent])
          .createShader(Rect.fromLTWH(rect.left - 30, y - 1, rect.width + 60, 2))
      ..strokeWidth = 3;
    canvas.drawLine(Offset(rect.left - 30, y), Offset(rect.right + 30, y), glow);
  }

  @override
  bool shouldRepaint(_FramePainter old) => old.t != t || old.color != color;
}
