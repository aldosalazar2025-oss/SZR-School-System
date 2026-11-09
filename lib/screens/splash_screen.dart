import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/futuristic.dart';
import 'access_screen.dart';

/// Animación de bienvenida: logo, nombre del programa letra por letra y barra de carga.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  static const _title = 'SISTEMA ESCOLAR';
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Duration(milliseconds: 3600));
  bool _left = false;

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(_go);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _go() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pushReplacement(PageRouteBuilder<void>(
      transitionDuration: Duration(milliseconds: 800),
      pageBuilder: (_, __, ___) => const AccessScreen(),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
    ));
  }

  /// Progreso (0..1) de un tramo [a, b] de la animación total.
  double _t(double a, double b, [Curve curve = Curves.easeOutCubic]) =>
      Interval(a, b, curve: curve).transform(_c.value);

  String _boot() {
    const m = ['INICIANDO SISTEMA…', 'CARGANDO MÓDULOS…', 'CONECTANDO BASE DE DATOS…', 'SISTEMA LISTO'];
    return m[(_c.value * 4).floor().clamp(0, 3).toInt()];
  }

  Widget _glow(Color c, double size, double t) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
                colors: [c.withValues(alpha: (P.dark ? .26 : .34) * t), c.withValues(alpha: 0)]),
          ),
        ),
      );

  Widget _letter(String ch, int i) {
    final start = .22 + .30 * i / _title.length;
    final v = _t(start, start + .14);
    return Opacity(
      opacity: v.clamp(0.0, 1.0).toDouble(),
      child: Transform.translate(
        offset: Offset(0, (1 - v) * 16),
        child: Text(ch == ' ' ? '\u00A0' : ch,
            style: TextStyle(color: P.text, fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 4)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _go,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final logo = _t(0, .30, Curves.easeOutBack);
              final szr = _t(.55, .78, Curves.easeOutBack);
              final bar = _t(.70, .88);
              final sub = _t(.82, 1);
              final glow = _t(0, .5);
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [P.bg, P.tint]),
                ),
                child: Stack(children: [
                  Positioned(top: -140 + 40 * glow, left: -140, child: _glow(P.accent, 480, glow)),
                  Positioned(bottom: -160 + 40 * glow, right: -120, child: _glow(P.accent2, 520, glow)),
                  Positioned.fill(child: FuturisticBackground()),
                  Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Stack(alignment: Alignment.center, children: [
                        CustomPaint(
                          size: Size(250, 250),
                          painter: HudRingsPainter(rot: _c.value * math.pi * 6, strength: _t(0, .35)),
                        ),
                      Opacity(
                        opacity: _t(0, .2).clamp(0.0, 1.0).toDouble(),
                        child: Transform.scale(
                          scale: .55 + .45 * logo,
                          child: Container(
                            padding: EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                    color: P.accent.withValues(alpha: .35 * logo.clamp(0.0, 1.0)),
                                    blurRadius: 50,
                                    spreadRadius: 4),
                              ],
                            ),
                            child: Image.asset('assets/images/logo.png',
                                height: 150, filterQuality: FilterQuality.high),
                          ),
                        ),
                      ),
                      ]),
                      SizedBox(height: 22),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        for (int i = 0; i < _title.length; i++) _letter(_title[i], i),
                      ]),
                      SizedBox(height: 4),
                      Opacity(
                        opacity: szr.clamp(0.0, 1.0).toDouble(),
                        child: Transform.scale(
                          scale: .7 + .3 * szr,
                          child: ShaderMask(
                            shaderCallback: (r) =>
                                LinearGradient(colors: [P.accent, P.accent2]).createShader(r),
                            child: Text('SZR',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 64,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 14)),
                          ),
                        ),
                      ),
                      SizedBox(height: 10),
                      Container(
                        width: 200 * bar,
                        height: 4,
                        decoration: BoxDecoration(gradient: P.brand, borderRadius: BorderRadius.circular(4)),
                      ),
                      SizedBox(height: 16),
                      Opacity(
                        opacity: sub.clamp(0.0, 1.0).toDouble(),
                        child: Text('CONTROL DE ASISTENCIA',
                            style: TextStyle(
                                color: P.muted, fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 3)),
                      ),
                    ]),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 58,
                    child: Center(
                      child: Text(_boot(),
                          style: TextStyle(fontFamily: 'Consolas', color: P.subtle, fontSize: 11, letterSpacing: 3)),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 34,
                    child: Center(
                      child: SizedBox(
                        width: 220,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: math.min(1.0, _c.value), minHeight: 3),
                        ),
                      ),
                    ),
                  ),
                ]),
              );
            },
          ),
        ),
      );
}
