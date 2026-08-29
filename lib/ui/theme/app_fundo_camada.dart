import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_fundo_id.dart';
import 'app_fundo_scope.dart';

/// Camada atras do conteudo visivel (nao do menu/app bar).
class AppFundoCamada extends StatelessWidget {
  const AppFundoCamada({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fundo = AppFundoScope.maybeOf(context)?.fundoAtual ?? AppFundoId.liso;
    if (!fundo.pintaCamada) return child;

    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: CustomPaint(
            painter: AppFundoPainter(estilo: fundo, scheme: scheme),
            child: const SizedBox.expand(),
          ),
        ),
        child,
      ],
    );
  }
}

class AppFundoPainter extends CustomPainter {
  AppFundoPainter({required this.estilo, required this.scheme});

  final AppFundoId estilo;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final base = scheme.surface;
    canvas.drawRect(rect, Paint()..color = base);

    switch (estilo) {
      case AppFundoId.liso:
        return;
      case AppFundoId.degrade:
        _degrade(canvas, rect, size, base);
      case AppFundoId.malha:
        _malha(canvas, size);
      case AppFundoId.faixa:
        _faixa(canvas, size, base);
      case AppFundoId.vinheta:
        _vinheta(canvas, rect, size, base);
      case AppFundoId.linhas:
        _linhas(canvas, size);
    }
  }

  void _degrade(Canvas canvas, Rect rect, Size size, Color base) {
    final fundo = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color.alphaBlend(scheme.primary.withValues(alpha: 0.34), base),
          Color.alphaBlend(scheme.primary.withValues(alpha: 0.10), base),
          Color.alphaBlend(scheme.tertiary.withValues(alpha: 0.22), base),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, fundo);

    canvas.drawCircle(
      Offset(size.width * 0.86, size.height * 0.12),
      size.shortestSide * 0.42,
      Paint()..color = scheme.primary.withValues(alpha: 0.16),
    );
    canvas.drawCircle(
      Offset(size.width * 0.12, size.height * 0.88),
      size.shortestSide * 0.36,
      Paint()..color = scheme.tertiary.withValues(alpha: 0.18),
    );
  }

  void _malha(Canvas canvas, Size size) {
    const passo = 26.0;
    final linhas = Paint()
      ..color = scheme.primary.withValues(alpha: 0.14)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += passo) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linhas);
    }
    for (var y = 0.0; y <= size.height; y += passo) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linhas);
    }
    final ponto = Paint()..color = scheme.primary.withValues(alpha: 0.28);
    for (var y = 0.0; y <= size.height; y += passo) {
      for (var x = 0.0; x <= size.width; x += passo) {
        canvas.drawCircle(Offset(x, y), 2.3, ponto);
      }
    }
  }

  void _faixa(Canvas canvas, Size size, Color base) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.07),
          base,
        ),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 56),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primary.withValues(alpha: 0.38),
            scheme.primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 56)),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 0, 14, size.height),
      Paint()..color = scheme.primary,
    );
    canvas.drawRect(
      Rect.fromLTWH(14, 0, 70, size.height),
      Paint()
        ..shader = LinearGradient(
          colors: [
            scheme.primary.withValues(alpha: 0.28),
            scheme.primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromLTWH(14, 0, 70, size.height)),
    );
  }

  void _vinheta(Canvas canvas, Rect rect, Size size, Color base) {
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.center,
          radius: 0.78,
          colors: [
            base,
            Color.alphaBlend(scheme.primary.withValues(alpha: 0.16), base),
            Color.alphaBlend(scheme.primary.withValues(alpha: 0.40), base),
          ],
          stops: const [0.35, 0.72, 1],
        ).createShader(rect),
    );
    final canto = Paint()..color = scheme.primary.withValues(alpha: 0.22);
    final r = size.shortestSide * 0.28;
    canvas.drawCircle(Offset.zero, r, canto);
    canvas.drawCircle(Offset(size.width, 0), r, canto);
    canvas.drawCircle(Offset(0, size.height), r, canto);
    canvas.drawCircle(Offset(size.width, size.height), r, canto);
  }

  void _linhas(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = scheme.primary.withValues(alpha: 0.16)
      ..strokeWidth = 1.35;
    const passo = 18.0;
    final extra = size.width + size.height;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 7);
    canvas.translate(-size.width / 2, -size.height / 2);
    for (var x = -extra; x < extra; x += passo) {
      canvas.drawLine(Offset(x, -extra), Offset(x, extra), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AppFundoPainter oldDelegate) =>
      oldDelegate.estilo != estilo ||
      oldDelegate.scheme.primary != scheme.primary ||
      oldDelegate.scheme.surface != scheme.surface ||
      oldDelegate.scheme.tertiary != scheme.tertiary;
}
