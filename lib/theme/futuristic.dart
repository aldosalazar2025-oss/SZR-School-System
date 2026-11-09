import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

class _Dot {
  _Dot(this.x0, this.y0, this.k, this.m, this.phase, this.size);
  final double x0, y0, phase, size;
  final int k, m;
}

List<_Dot> _makeDots() {
  final r = math.Random(11);
  return List.generate(
    46,
    (_) => _Dot(r.nextDouble(), r.nextDouble(), 1 + r.nextInt(3), 2 + r.nextInt(3), r.nextDouble(),
        1.2 + r.nextDouble() * 2.2),
  );
}

/// Fondo futurista animado: cuadrícula, haz de escaneo y partículas conectadas.
/// Úsalo como `Positioned.fill(child: FuturisticBackground())` o con `child`.
class FuturisticBackground extends StatefulWidget {
  const FuturisticBackground({super.key, this.child});
  final Widget? child;
  @override
  State<FuturisticBackground> createState() => _FuturisticBackgroundState();
}

class _FuturisticBackgroundState extends State<FuturisticBackground> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(seconds: 60))..repeat();
  final List<_Dot> _dots = _makeDots();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(fit: StackFit.expand, children: [
        IgnorePointer(
          child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(painter: _BgPainter(_c.value, _dots)),
            ),
          ),
        ),
        if (widget.child != null) widget.child!,
      ]);
}

class _BgPainter extends CustomPainter {
  _BgPainter(this.v, this.dots);
  final double v;
  final List<_Dot> dots;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = P.dark;
    final a = P.accent, b = P.accent2;
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;

    // Cuadrícula
    final gp = Paint()
      ..strokeWidth = 1
      ..color = a.withValues(alpha: dark ? .06 : .08);
    const step = 56.0;
    for (double x = 0; x < w; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, h), gp);
    }
    for (double y = 0; y < h; y += step) {
      canvas.drawLine(Offset(0, y), Offset(w, y), gp);
    }

    // Haz de escaneo
    final by = ((v * 3) % 1.0) * (h + 160) - 80;
    final rect = Rect.fromLTWH(0, by - 70, w, 140);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [b.withValues(alpha: 0), b.withValues(alpha: dark ? .10 : .13), b.withValues(alpha: 0)],
        ).createShader(rect),
    );

    // Partículas
    final pts = <Offset>[];
    for (int i = 0; i < dots.length; i++) {
      final d = dots[i];
      final y = (d.y0 - d.k * v) % 1.0;
      final x = d.x0 + .015 * math.sin(2 * math.pi * (d.m * v + d.phase));
      final p = Offset(x * w, y * h);
      pts.add(p);
      final tw = .5 + .5 * math.sin(2 * math.pi * (d.m * v + d.phase));
      final col = (i.isEven ? a : b);
      canvas.drawCircle(p, d.size * 3, Paint()..color = col.withValues(alpha: .10 + .10 * tw));
      canvas.drawCircle(p, d.size, Paint()..color = col.withValues(alpha: .35 + .45 * tw));
    }
    // Conexiones
    final lp = Paint()..strokeWidth = 1;
    for (int i = 0; i < pts.length; i++) {
      for (int j = i + 1; j < pts.length; j++) {
        final dist = (pts[i] - pts[j]).distance;
        if (dist < 130) {
          lp.color = a.withValues(alpha: (1 - dist / 130) * (dark ? .20 : .24));
          canvas.drawLine(pts[i], pts[j], lp);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BgPainter old) => true;
}

/// Anillos tipo HUD que giran (usados en la bienvenida).
class HudRingsPainter extends CustomPainter {
  HudRingsPainter({required this.rot, required this.strength});
  final double rot; // radianes
  final double strength; // 0..1
  @override
  void paint(Canvas canvas, Size size) {
    final s = strength.clamp(0.0, 1.0).toDouble();
    if (s <= 0) return;
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 4;
    final a = P.accent, b = P.accent2;

    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = b.withValues(alpha: .40 * s));

    // marcas
    final tick = Paint()
      ..strokeWidth = 1
      ..color = b.withValues(alpha: .35 * s);
    for (int i = 0; i < 60; i++) {
      final ang = rot * .3 + i * math.pi / 30;
      final len = i % 5 == 0 ? 9.0 : 5.0;
      canvas.drawLine(c + Offset(math.cos(ang), math.sin(ang)) * r,
          c + Offset(math.cos(ang), math.sin(ang)) * (r - len), tick);
    }

    // arcos exteriores
    final p2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round
      ..color = a.withValues(alpha: .90 * s);
    final r2 = r * .86;
    for (int i = 0; i < 6; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r2), rot + i * math.pi / 3, math.pi / 5, false, p2);
    }
    // arcos interiores (giran al revés)
    final p3 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = b.withValues(alpha: .85 * s);
    final r3 = r * .72;
    for (int i = 0; i < 3; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r3), -rot * 1.4 + i * 2 * math.pi / 3, math.pi / 2.6, false, p3);
    }
  }

  @override
  bool shouldRepaint(covariant HudRingsPainter old) => old.rot != rot || old.strength != strength;
}

/// Pantalla de bienvenida de ~2.6 s que se muestra al entrar al panel.
/// Colocar dentro de un Stack: `Positioned.fill(child: WelcomeOverlay(name: ...))`.
class WelcomeOverlay extends StatefulWidget {
  const WelcomeOverlay({super.key, required this.name});
  final String name;
  @override
  State<WelcomeOverlay> createState() => _WelcomeOverlayState();
}

class _WelcomeOverlayState extends State<WelcomeOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 2600));
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _t(double a, double b, [Curve cv = Curves.easeOutCubic]) => Interval(a, b, curve: cv).transform(_c.value);

  @override
  Widget build(BuildContext context) {
    if (_done) return SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _done = true),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final v = _c.value;
          final fade = v < .72 ? 1.0 : (1 - (v - .72) / .28).clamp(0.0, 1.0).toDouble();
          final ring = _t(0, .35);
          final title = _t(.18, .5);
          final user = _t(.4, .65);
          final scan = _t(0, .8, Curves.easeInOut);
          return Opacity(
            opacity: fade,
            child: Container(
              color: P.bg,
              child: Stack(fit: StackFit.expand, children: [
                FuturisticBackground(),
                Positioned(
                  left: 0,
                  right: 0,
                  top: scan * MediaQuery.of(context).size.height - 2,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [P.accent.withValues(alpha: 0), P.accent2, P.accent.withValues(alpha: 0)]),
                      boxShadow: [BoxShadow(color: P.accent2.withValues(alpha: .8), blurRadius: 24, spreadRadius: 2)],
                    ),
                  ),
                ),
                Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(
                      width: 240,
                      height: 240,
                      child: Stack(alignment: Alignment.center, children: [
                        CustomPaint(
                          size: Size(240, 240),
                          painter: HudRingsPainter(rot: v * math.pi * 5, strength: ring),
                        ),
                        Opacity(
                          opacity: title.clamp(0.0, 1.0).toDouble(),
                          child: Transform.scale(
                            scale: .6 + .4 * title,
                            child: Icon(Icons.verified_user_rounded, size: 84, color: P.accent2),
                          ),
                        ),
                      ]),
                    ),
                    SizedBox(height: 18),
                    Opacity(
                      opacity: title.clamp(0.0, 1.0).toDouble(),
                      child: Text('ACCESO CONCEDIDO',
                          style: TextStyle(
                              fontFamily: 'Consolas',
                              color: P.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 6 + 6 * (1 - title))),
                    ),
                    SizedBox(height: 10),
                    Opacity(
                      opacity: title.clamp(0.0, 1.0).toDouble(),
                      child: Transform.scale(
                        scale: .9 + .1 * title,
                        child: Text('BIENVENIDO',
                            style: TextStyle(
                                color: P.text,
                                fontSize: 52,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 8,
                                shadows: [Shadow(color: P.accent.withValues(alpha: .7), blurRadius: 28)])),
                      ),
                    ),
                    SizedBox(height: 6),
                    Opacity(
                      opacity: user.clamp(0.0, 1.0).toDouble(),
                      child: Transform.translate(
                        offset: Offset(0, (1 - user) * 12),
                        child: Text(widget.name.toUpperCase(),
                            style: TextStyle(color: P.muted, fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 5)),
                      ),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}

/// Animación de entrada: el contenido aparece con un fundido y un leve
/// deslizamiento hacia arriba. [delay] permite escalonar varias tarjetas.
class FEntrance extends StatefulWidget {
  const FEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 22,
  });
  final Widget child;
  final Duration delay;
  final double offset;
  @override
  State<FEntrance> createState() => _FEntranceState();
}

class _FEntranceState extends State<FEntrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Duration(milliseconds: 520));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _t;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      _t = Timer(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _a.value.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, (1 - _a.value) * widget.offset), child: child),
        ),
      );
}

/// Área de contenido junto a la barra lateral (equivale a `Expanded`) con
/// animación de entrada. La barra lateral queda fija, solo el contenido anima.
class FContent extends StatelessWidget {
  const FContent({super.key, required this.child, this.offset = 22});
  final Widget child;
  final double offset;
  @override
  Widget build(BuildContext context) => Expanded(child: FEntrance(offset: offset, child: child));
}

/// Scaffold con el fondo futurista animado detrás del contenido.
class FScaffold extends StatelessWidget {
  const FScaffold({super.key, this.backgroundColor, required this.body});
  final Color? backgroundColor;
  final Widget body;
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: backgroundColor,
        body: Stack(fit: StackFit.expand, children: [
          FuturisticBackground(),
          body,
        ]),
      );
}
