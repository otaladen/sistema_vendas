import 'package:barcode/barcode.dart';
import 'package:flutter/material.dart';

/// QR Code desenhado com o pacote [barcode] ja usado nos cupons.
class LanQrCodeView extends StatelessWidget {
  const LanQrCodeView({
    super.key,
    required this.data,
    this.size = 220,
  });

  final String data;
  final double size;

  @override
  Widget build(BuildContext context) {
    final payload = data.trim();
    if (payload.isEmpty) {
      return SizedBox(width: size, height: size);
    }
    final elementos = Barcode.qrCode()
        .make(payload, width: size, height: size, drawText: false)
        .toList(growable: false);
    return ColoredBox(
      color: Colors.white,
      child: CustomPaint(
        size: Size.square(size),
        painter: _LanQrPainter(elementos),
      ),
    );
  }
}

class _LanQrPainter extends CustomPainter {
  const _LanQrPainter(this.elementos);

  final List<BarcodeElement> elementos;

  @override
  void paint(Canvas canvas, Size size) {
    final tinta = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.fill;
    for (final e in elementos) {
      if (e is BarcodeBar && e.black) {
        canvas.drawRect(
          Rect.fromLTWH(e.left, e.top, e.width, e.height),
          tinta,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LanQrPainter oldDelegate) {
    return oldDelegate.elementos != elementos;
  }
}
