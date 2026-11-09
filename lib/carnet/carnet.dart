import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../database/app_database.dart';

/// Configuración de la plantilla de carnet (tamaño CR90 vertical, 58 × 90 mm).
class CarnetConfig {
  CarnetConfig({
    this.institucion = 'MI INSTITUCIÓN',
    this.nivel = 'Secundaria',
    this.tamano = 'CR90',
    List<int>? colores,
    this.logo,
    this.fotoEstudiante = true,
  }) : colores = colores ?? List.of(defaultColors);

  /// A fondo título · B color título · C fondo nivel · D fondo grado/sección · E color texto · F borde.
  static const defaultColors = <int>[0xFF6B0F1A, 0xFFF4C463, 0xFF9B1030, 0xFFFFF0D6, 0xFF5A0E18, 0xFF6C7CF2];
  static const labels = <String>[
    'A) Fondo título',
    'B) Color título',
    'C) Fondo nivel',
    'D) Fondo grado/sección',
    'E) Color de textos',
    'F) Borde carnet',
  ];

  String institucion, nivel;
  final String tamano;
  final List<int> colores;
  Uint8List? logo;
  bool fotoEstudiante;

  Color color(int i) => Color(colores[i]);

  CarnetConfig copy() => CarnetConfig(
        institucion: institucion,
        nivel: nivel,
        tamano: tamano,
        colores: List.of(colores),
        logo: logo,
        fotoEstudiante: fotoEstudiante,
      );

  Map<String, Object?> toJson() => {
        'institucion': institucion,
        'nivel': nivel,
        'tamano': tamano,
        'colores': colores,
        'logo': logo == null ? null : base64Encode(logo!),
        'foto': fotoEstudiante,
      };

  static CarnetConfig fromJson(Map<String, dynamic> j) {
    final c = (j['colores'] as List?)?.map((e) => (e as num).toInt()).toList();
    return CarnetConfig(
      institucion: '${j['institucion'] ?? 'MI INSTITUCIÓN'}',
      nivel: '${j['nivel'] ?? 'Secundaria'}',
      colores: (c != null && c.length == 6) ? c : null,
      logo: j['logo'] == null ? null : base64Decode('${j['logo']}'),
      fotoEstudiante: j['foto'] != false,
    );
  }

  static Future<CarnetConfig> load() async {
    try {
      final raw = await AppDatabase.instance.getConfig('carnet_config');
      if (raw != null) return fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {}
    return CarnetConfig();
  }

  Future<void> save() => AppDatabase.instance.setConfig('carnet_config', jsonEncode(toJson()));
}

/// Datos de un estudiante para dibujar su carnet.
class CarnetData {
  const CarnetData({
    required this.apellidos,
    required this.nombres,
    this.grado = '',
    this.seccion = '',
    this.dni = '',
    required this.qr,
    this.foto,
  });
  final String apellidos, nombres, grado, seccion, dni, qr;
  final Uint8List? foto;

  String get aula => '${grado.trim()}${seccion.trim()}';

  factory CarnetData.fromRow(Map<String, Object?> r) => CarnetData(
        apellidos: '${r['apellidos'] ?? ''}',
        nombres: '${r['nombres'] ?? ''}',
        grado: '${r['grado'] ?? ''}',
        seccion: '${r['seccion'] ?? ''}',
        dni: '${r['dni'] ?? ''}',
        qr: '${r['codigo_qr'] ?? ''}',
        foto: r['foto'] is Uint8List ? r['foto'] as Uint8List : null,
      );
}

Future<ui.Image?> carnetLoadImage(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  } catch (_) {
    return null;
  }
}

/// Dibuja el carnet en un espacio lógico de 580 × 900 (relación 58:90 = CR90 vertical).
class CarnetPainter extends CustomPainter {
  CarnetPainter(this.cfg, this.data, {this.logo, this.photo});
  final CarnetConfig cfg;
  final CarnetData data;
  final ui.Image? logo, photo;

  static const double W = 580, H = 900;

  TextPainter _tp(String text, TextStyle style, {double? maxWidth, double minSize = 18}) {
    var size = style.fontSize ?? 30;
    TextPainter make(double fs) => TextPainter(
          text: TextSpan(text: text, style: style.copyWith(fontSize: fs)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout();
    var tp = make(size);
    if (maxWidth != null) {
      while (tp.width > maxWidth && size > minSize) {
        size -= 1;
        tp = make(size);
      }
      if (tp.width > maxWidth) {
        tp = TextPainter(
          text: TextSpan(text: text, style: style.copyWith(fontSize: size)),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(maxWidth: maxWidth);
      }
    }
    return tp;
  }

  double _centered(Canvas c, TextPainter tp, double top) {
    tp.paint(c, Offset((W - tp.width) / 2, top));
    return tp.height;
  }

  void _pill(Canvas c, double top, double h, double w, Color fill) {
    final r = RRect.fromRectAndRadius(Rect.fromLTWH((W - w) / 2, top, w, h), Radius.circular(h / 2));
    c.drawRRect(r, Paint()..color = fill);
  }

  void _image(Canvas c, ui.Image img, Rect dst, BoxFit fit) {
    paintImage(canvas: c, rect: dst, image: img, fit: fit, filterQuality: FilterQuality.high);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / W, size.height / H);

    final fondo = cfg.color(0), titulo = cfg.color(1), nivelBg = cfg.color(2), gradoBg = cfg.color(3);
    final texto = cfg.color(4), borde = cfg.color(5);

    final card = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, W, H), const Radius.circular(40));
    canvas.drawRRect(card, Paint()..color = Colors.white);
    canvas.save();
    canvas.clipRRect(card);

    // Cabecera con arco
    final header = Path()
      ..moveTo(0, 0)
      ..lineTo(W, 0)
      ..lineTo(W, 320)
      ..quadraticBezierTo(W / 2, 190, 0, 320)
      ..close();
    canvas.drawPath(
      header,
      Paint()..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 320), [fondo, Color.lerp(fondo, Colors.black, .28)!]),
    );
    canvas.drawCircle(const Offset(W - 60, 50), 95, Paint()..color = Colors.white.withOpacity(.07));

    // Logo pequeño + nombre de la institución
    if (logo != null) {
      canvas.drawCircle(const Offset(W / 2, 58), 31, Paint()..color = Colors.white);
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: const Offset(W / 2, 58), radius: 27)));
      _image(canvas, logo!, Rect.fromCircle(center: const Offset(W / 2, 58), radius: 27), BoxFit.contain);
      canvas.restore();
    }
    final t = _tp(cfg.institucion.toUpperCase(), TextStyle(color: titulo, fontSize: 40, fontWeight: FontWeight.w800), maxWidth: W - 60, minSize: 20);
    _centered(canvas, t, logo != null ? 100 : 78);

    // Círculo central (foto del estudiante o logo)
    const cc = Offset(W / 2, 262);
    canvas.drawCircle(cc, 86, Paint()..color = Colors.black.withOpacity(.25)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    canvas.drawCircle(cc, 84, Paint()..color = Colors.white);
    final inner = Rect.fromCircle(center: cc, radius: 72);
    canvas.save();
    canvas.clipPath(Path()..addOval(inner));
    if (cfg.fotoEstudiante && photo != null) {
      _image(canvas, photo!, inner, BoxFit.cover);
    } else if (logo != null) {
      _image(canvas, logo!, inner.deflate(6), BoxFit.contain);
    } else {
      canvas.drawRect(inner, Paint()..color = fondo.withOpacity(.12));
      final ini = '${data.nombres.trim().isEmpty ? '' : data.nombres.trim()[0]}${data.apellidos.trim().isEmpty ? '' : data.apellidos.trim()[0]}'.toUpperCase();
      final it = _tp(ini, TextStyle(color: fondo, fontSize: 64, fontWeight: FontWeight.w800));
      it.paint(canvas, Offset(cc.dx - it.width / 2, cc.dy - it.height / 2));
    }
    canvas.restore();
    canvas.restore(); // fin clip tarjeta

    // Apellidos y nombres
    final ap = _tp(data.apellidos.toUpperCase(), TextStyle(color: texto, fontSize: 46, fontWeight: FontWeight.w800), maxWidth: W - 50, minSize: 24);
    _centered(canvas, ap, 358);
    final nm = _tp(data.nombres, TextStyle(color: texto.withOpacity(.65), fontSize: 34, fontWeight: FontWeight.w500), maxWidth: W - 50, minSize: 20);
    _centered(canvas, nm, 412);

    // Nivel y grado/sección
    if (cfg.nivel.trim().isNotEmpty) {
      final nv = _tp(cfg.nivel, const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w800), maxWidth: W - 140);
      _pill(canvas, 462, 48, nv.width + 64, nivelBg);
      nv.paint(canvas, Offset((W - nv.width) / 2, 462 + (48 - nv.height) / 2));
    }
    if (data.aula.isNotEmpty) {
      final gr = _tp(data.aula, TextStyle(color: texto, fontSize: 30, fontWeight: FontWeight.w800), maxWidth: W - 140);
      final gw = gr.width + 56 < 110 ? 110.0 : gr.width + 56;
      _pill(canvas, 520, 46, gw, gradoBg);
      gr.paint(canvas, Offset((W - gr.width) / 2, 520 + (46 - gr.height) / 2));
    }

    // QR
    const boxSize = 280.0, boxTop = 566.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH((W - boxSize) / 2, boxTop, boxSize, boxSize), const Radius.circular(14)),
      Paint()..color = Colors.white,
    );
    if (data.qr.isNotEmpty) {
      final qr = QrCode.fromData(data: data.qr, errorCorrectLevel: QrErrorCorrectLevel.M);
      final painter = QrPainter.withQr(
        qr: qr,
        eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
        dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
        gapless: true,
      );
      final mod = ((boxSize - 12) / qr.moduleCount).floorToDouble();
      final px = mod * qr.moduleCount;
      canvas.save();
      canvas.translate((W - px) / 2, boxTop + (boxSize - px) / 2);
      painter.paint(canvas, Size(px, px));
      canvas.restore();
    }
    final code = data.dni.isNotEmpty ? data.dni : '';
    if (code.isNotEmpty) {
      final ct = _tp('código  $code', const TextStyle(color: Color(0xFF8A94A6), fontSize: 22, letterSpacing: 2, fontWeight: FontWeight.w600));
      _centered(canvas, ct, 854);
    }

    // Borde
    canvas.drawRRect(card.deflate(6), Paint()..color = borde..style = PaintingStyle.stroke..strokeWidth = 12);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CarnetPainter old) => true;
}

/// Genera el PNG del carnet (escala 1.5 → 870 × 1350 px, ≈ 380 dpi a 58 × 90 mm).
Future<Uint8List> carnetRenderPng(CarnetConfig cfg, CarnetData d, {double scale = 1.5}) async {
  final logo = await carnetLoadImage(cfg.logo);
  final photo = await carnetLoadImage(d.foto);
  final w = (CarnetPainter.W * scale).round(), h = (CarnetPainter.H * scale).round();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  CarnetPainter(cfg, d, logo: logo, photo: photo).paint(canvas, Size(w.toDouble(), h.toDouble()));
  final img = await rec.endRecording().toImage(w, h);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}

/// Vista previa del carnet con el ancho indicado.
class CarnetView extends StatefulWidget {
  const CarnetView({super.key, required this.config, required this.data, this.width = 300});
  final CarnetConfig config;
  final CarnetData data;
  final double width;
  @override
  State<CarnetView> createState() => _CarnetViewState();
}

class _CarnetViewState extends State<CarnetView> {
  ui.Image? _logo, _photo;
  Uint8List? _logoSrc, _photoSrc;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant CarnetView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  Future<void> _sync() async {
    if (!identical(_logoSrc, widget.config.logo)) {
      _logoSrc = widget.config.logo;
      final img = await carnetLoadImage(_logoSrc);
      if (mounted) setState(() => _logo = img);
    }
    if (!identical(_photoSrc, widget.data.foto)) {
      _photoSrc = widget.data.foto;
      final img = await carnetLoadImage(_photoSrc);
      if (mounted) setState(() => _photo = img);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.width * CarnetPainter.H / CarnetPainter.W;
    return Container(
      width: widget.width,
      height: h,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.width * 40 / CarnetPainter.W),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(.45), blurRadius: 24, offset: const Offset(0, 10))],
      ),
      child: CustomPaint(painter: CarnetPainter(widget.config, widget.data, logo: _logo, photo: _photo)),
    );
  }
}


/// Genera un PNG cuadrado solo con el QR (fondo blanco y margen de silencio).
Future<Uint8List> qrRenderPng(String data, {int size = 800}) async {
  final qr = QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  final s = size.toDouble();
  canvas.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = Colors.white);
  final margin = s * 0.08;
  final mod = ((s - 2 * margin) / qr.moduleCount).floorToDouble();
  final px = mod * qr.moduleCount;
  canvas.translate((s - px) / 2, (s - px) / 2);
  QrPainter.withQr(
    qr: qr,
    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Color(0xFF000000)),
    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Color(0xFF000000)),
    gapless: true,
  ).paint(canvas, Size(px, px));
  final img = await rec.endRecording().toImage(size, size);
  final bd = await img.toByteData(format: ui.ImageByteFormat.png);
  return bd!.buffer.asUint8List();
}
