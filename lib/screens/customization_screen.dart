import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/futuristic.dart';
import 'package:flutter/services.dart';

import '../auth/auth_repository.dart';
import '../carnet/carnet.dart';
import 'app_sidebar.dart';

/// Personalización de la plantilla de carnet (CR90) que reemplaza al QR suelto.
class CustomizationScreen extends StatefulWidget {
  const CustomizationScreen({super.key, required this.user});
  final AuthUser user;
  @override
  State<CustomizationScreen> createState() => _CustomizationScreenState();
}

class _CustomizationScreenState extends State<CustomizationScreen> {
  static Color get bg => P.bg;
  static Color get panel => P.panel;
  static Color get line => P.line;
  static Color get cyan => P.accent;
  static Color get muted => P.muted;
  static Color get fieldBg => P.field;

  CarnetConfig _cfg = CarnetConfig();
  bool _loading = true, _saving = false, _dirty = false;
  final _inst = TextEditingController(), _nivel = TextEditingController();

  static const _sample = CarnetData(
    apellidos: 'Zuñiga Rojas',
    nombres: 'Axel Fransue',
    grado: '4',
    seccion: 'D',
    dni: '62810457',
    qr: 'ALUMNO:0|DNI:62810457',
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _inst.dispose();
    _nivel.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final c = await CarnetConfig.load();
    _inst.text = c.institucion;
    _nivel.text = c.nivel;
    if (mounted) {
      setState(() {
        _cfg = c;
        _loading = false;
      });
    }
  }

  void _msg(String t) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));

  void _touch(VoidCallback f) => setState(() {
        f();
        _dirty = true;
      });

  Future<void> _pickLogo() async {
    final f = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = f?.files.single.bytes;
    if (bytes == null) return;
    _touch(() => _cfg.logo = bytes);
  }

  Future<void> _pickColor(int i) async {
    final c = await showCarnetColorPicker(context, _cfg.color(i), CarnetConfig.labels[i]);
    if (c != null) _touch(() => _cfg.colores[i] = c.value);
  }

  Future<void> _save() async {
    if (_inst.text.trim().isEmpty) {
      _msg('Escribe el nombre de la institución.');
      return;
    }
    setState(() => _saving = true);
    try {
      _cfg
        ..institucion = _inst.text.trim()
        ..nivel = _nivel.text.trim();
      await _cfg.save();
      if (mounted) {
        setState(() => _dirty = false);
        _msg('Plantilla de carnet guardada. Se usará al generar los carnets de los estudiantes.');
      }
    } catch (e) {
      if (mounted) _msg('No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: muted, fontSize: 12),
        filled: true,
        fillColor: fieldBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: line)),
      );

  Widget _swatch(int i) => SizedBox(
        width: 150,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(CarnetConfig.labels[i], style: TextStyle(color: muted, fontSize: 11, fontWeight: FontWeight.bold)),
          SizedBox(height: 6),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => _pickColor(i),
            child: Container(
              height: 40,
              padding: EdgeInsets.all(6),
              decoration: BoxDecoration(color: fieldBg, border: Border.all(color: line), borderRadius: BorderRadius.circular(10)),
              child: Container(decoration: BoxDecoration(color: _cfg.color(i), borderRadius: BorderRadius.circular(6))),
            ),
          ),
        ]),
      );

  Widget _controls() => Container(
        padding: EdgeInsets.all(18),
        decoration: P.card(r: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _inst,
            style: TextStyle(color: P.text),
            decoration: _dec('NOMBRE DE LA INSTITUCIÓN / EMPRESA'),
            onChanged: (v) => _touch(() => _cfg.institucion = v),
          ),
          SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nivel,
                style: TextStyle(color: P.text),
                decoration: _dec('NIVEL (etiqueta, ej. Secundaria)'),
                onChanged: (v) => _touch(() => _cfg.nivel = v),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: InputDecorator(
                decoration: _dec('TAMAÑO DE CARNET'),
                child: Text('CR90 · 58 × 90 mm (vertical)', style: TextStyle(color: P.text)),
              ),
            ),
          ]),
          SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickLogo,
              icon: Icon(Icons.image, color: cyan),
              label: Text(_cfg.logo == null ? 'Elegir logo / imagen' : 'Cambiar logo', style: TextStyle(color: P.text)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: cyan), minimumSize: Size(0, 44)),
            ),
            SizedBox(width: 10),
            if (_cfg.logo != null)
              TextButton(onPressed: () => _touch(() => _cfg.logo = null), child: Text('Quitar', style: TextStyle(color: P.err))),
            SizedBox(width: 6),
            Text(_cfg.logo == null ? 'Sin imagen' : 'Imagen lista', style: TextStyle(color: muted, fontSize: 12)),
          ]),
          SizedBox(height: 6),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _cfg.fotoEstudiante,
            onChanged: (v) => _touch(() => _cfg.fotoEstudiante = v),
            title: Text('Mostrar la foto del estudiante en el círculo', style: TextStyle(color: P.text, fontSize: 13)),
            subtitle: Text('Si el estudiante no tiene foto, se usa el logo.', style: TextStyle(color: muted, fontSize: 11)),
          ),
          SizedBox(height: 8),
          Wrap(spacing: 14, runSpacing: 14, children: [for (var i = 0; i < 6; i++) _swatch(i)]),
          SizedBox(height: 20),
          Row(children: [
            OutlinedButton.icon(
              onPressed: () => _touch(() {
                for (var i = 0; i < 6; i++) {
                  _cfg.colores[i] = CarnetConfig.defaultColors[i];
                }
              }),
              icon: Icon(Icons.restart_alt, color: muted),
              label: Text('Restablecer colores', style: TextStyle(color: muted)),
              style: OutlinedButton.styleFrom(side: BorderSide(color: line), minimumSize: Size(0, 46)),
            ),
            Spacer(),
            FilledButton.icon(
              onPressed: _saving || !_dirty ? null : _save,
              icon: _saving
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.save),
              label: Text('Guardar'),
              style: FilledButton.styleFrom(minimumSize: Size(150, 46)),
            ),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) => FScaffold(
        backgroundColor: bg,
        body: Row(children: [
          AppSidebar(user: widget.user, selected: 'Personalización'),
          FContent(
            child: SafeArea(
              child: Column(children: [
                Container(
                  height: 66,
                  padding: EdgeInsets.symmetric(horizontal: 22),
                  child: Row(children: [
                    PageIcon(Icons.palette),
                    SizedBox(width: 12),
                    Text('Personalizar carnet', style: TextStyle(color: P.text, fontSize: 22, fontWeight: FontWeight.bold)),
                  ]),
                ),
                Expanded(
                  child: _loading
                      ? Center(child: CircularProgressIndicator())
                      : LayoutBuilder(builder: (context, c) {
                          final wide = c.maxWidth > 900;
                          final preview = Center(child: CarnetView(config: _cfg, data: _sample, width: wide ? 310 : 280));
                          return SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(18, 4, 18, 24),
                            child: wide
                                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    SizedBox(width: 360, child: Padding(padding: EdgeInsets.only(top: 8), child: preview)),
                                    SizedBox(width: 18),
                                    Expanded(child: _controls()),
                                  ])
                                : Column(children: [preview, SizedBox(height: 18), _controls()]),
                          );
                        }),
                ),
              ]),
            ),
          ),
        ]),
      );
}

/// Selector de color con sliders RGB, código hexadecimal y colores rápidos.
Future<Color?> showCarnetColorPicker(BuildContext context, Color initial, String title) {
  return showDialog<Color>(
    context: context,
    builder: (ctx) {
      var r = initial.red, g = initial.green, b = initial.blue;
      final hex = TextEditingController(text: _hex(initial));
      return StatefulBuilder(builder: (ctx, setD) {
        final color = Color.fromARGB(255, r, g, b);
        void sync() => hex.text = _hex(color);
        Widget slider(String label, int v, Color active, ValueChanged<int> on) => Row(children: [
              SizedBox(width: 18, child: Text(label, style: TextStyle(fontWeight: FontWeight.bold))),
              Expanded(
                child: Slider(
                  value: v.toDouble(),
                  min: 0,
                  max: 255,
                  activeColor: active,
                  onChanged: (x) => setD(() {
                    on(x.round());
                    sync();
                  }),
                ),
              ),
              SizedBox(width: 34, child: Text('$v', textAlign: TextAlign.end)),
            ]);
        const presets = <int>[
          0xFF6B0F1A, 0xFF9B1030, 0xFFF4C463, 0xFFFFF0D6, 0xFF1E3A8A, 0xFF2563EB, 0xFF0F766E, 0xFF16A34A,
          0xFF7C3AED, 0xFF6C7CF2, 0xFFEA580C, 0xFFDC2626, 0xFF111827, 0xFF6B7280, 0xFFFFFFFF, 0xFFFACC15,
        ];
        return AlertDialog(
          backgroundColor: P.panel,
          title: Text(title),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                height: 54,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10), border: Border.all(color: P.text.withOpacity(.24))),
              ),
              SizedBox(height: 10),
              slider('R', r, P.err, (v) => r = v),
              slider('G', g, P.ok, (v) => g = v),
              slider('B', b, Colors.lightBlueAccent, (v) => b = v),
              TextField(
                controller: hex,
                decoration: InputDecoration(labelText: 'Hexadecimal (#RRGGBB)'),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')), LengthLimitingTextInputFormatter(7)],
                onChanged: (v) {
                  final p = _parseHex(v);
                  if (p != null) setD(() {
                        r = p.red;
                        g = p.green;
                        b = p.blue;
                      });
                },
              ),
              SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in presets)
                  InkWell(
                    onTap: () => setD(() {
                      final c = Color(p);
                      r = c.red;
                      g = c.green;
                      b = c.blue;
                      sync();
                    }),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(color: Color(p), borderRadius: BorderRadius.circular(6), border: Border.all(color: P.text.withOpacity(.24))),
                    ),
                  ),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, color), child: Text('Aceptar')),
          ],
        );
      });
    },
  );
}

String _hex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}${c.green.toRadixString(16).padLeft(2, '0')}${c.blue.toRadixString(16).padLeft(2, '0')}'.toUpperCase();

Color? _parseHex(String v) {
  var s = v.trim().replaceFirst('#', '');
  if (s.length != 6) return null;
  final n = int.tryParse(s, radix: 16);
  return n == null ? null : Color(0xFF000000 | n);
}
