import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'esc_pos_commands.dart';

/// Logo bitonal no topo do cupom/orcamento ESC/POS.
abstract final class EscPosLogoCabecalho {
  EscPosLogoCabecalho._();

  static void adicionar(
    BytesBuilder out,
    Uint8List? logoBytes,
    bool exibirLogo,
    EscPosLarguraBobina largura,
  ) {
    if (!exibirLogo || logoBytes == null || logoBytes.isEmpty) return;
    final cmd = EscPosImageRaster.comandosBitonal(
      logoBytes,
      maxWidthPx: EscPosImageRaster.larguraMaximaPx(largura),
    );
    if (cmd == null || cmd.isEmpty) return;
    out.add(EscPosCommands.alignCenter);
    out.add(cmd);
    out.add(EscPosCommands.feed(1));
  }
}

/// Raster bitonal (GS v 0) para impressoras ESC/POS Epson e compativeis.
abstract final class EscPosImageRaster {
  EscPosImageRaster._();

  static const headerGsV0 = 0x1D;
  static const cmdGsV0 = 0x76;

  /// Largura maxima em pixels conforme bobina (58 mm / 80 mm).
  static int larguraMaximaPx(EscPosLarguraBobina bobina) {
    return bobina == EscPosLarguraBobina.mm58 ? 384 : 576;
  }

  /// Converte JPEG/PNG em comandos ESC/POS (centralizado implicitamente via
  /// [EscPosCommands.alignCenter] antes de chamar).
  static Uint8List? comandosBitonal(
    Uint8List imageBytes, {
    required int maxWidthPx,
  }) {
    if (imageBytes.isEmpty || maxWidthPx < 8) return null;
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null) return null;

    final resized = _redimensionar(decoded, maxWidthPx);
    final raster = _montarRaster(resized);
    if (raster == null) return null;

    return EscPosCommands.rasterBitImage(
      widthPx: resized.width,
      heightPx: resized.height,
      rasterData: raster,
    );
  }

  static img.Image _redimensionar(img.Image source, int maxWidthPx) {
    if (source.width <= maxWidthPx) return source;
    final ratio = maxWidthPx / source.width;
    final h = (source.height * ratio).round().clamp(1, 4096);
    return img.copyResize(
      source,
      width: maxWidthPx,
      height: h,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Linhas empacotadas MSB-first; bit 1 = ponto preto.
  static Uint8List? _montarRaster(img.Image im) {
    final w = im.width;
    final h = im.height;
    if (w <= 0 || h <= 0) return null;
    final bytesPerRow = (w + 7) ~/ 8;
    final out = Uint8List(bytesPerRow * h);
    var o = 0;
    for (var y = 0; y < h; y++) {
      for (var xByte = 0; xByte < bytesPerRow; xByte++) {
        var b = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = xByte * 8 + bit;
          if (x >= w) continue;
          final p = im.getPixel(x, y);
          final lum = img.getLuminance(p);
          if (lum < 128) {
            b |= 0x80 >> bit;
          }
        }
        out[o++] = b;
      }
    }
    return out;
  }
}
