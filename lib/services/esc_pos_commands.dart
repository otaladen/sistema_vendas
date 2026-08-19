import 'dart:convert';
import 'dart:typed_data';

/// Comandos ESC/POS basicos (Epson / Bematech / Elgin).
abstract final class EscPosCommands {
  EscPosCommands._();

  static final Uint8List init = Uint8List.fromList([0x1B, 0x40]);
  static final Uint8List alignLeft = Uint8List.fromList([0x1B, 0x61, 0]);
  static final Uint8List alignCenter = Uint8List.fromList([0x1B, 0x61, 1]);
  static final Uint8List alignRight = Uint8List.fromList([0x1B, 0x61, 2]);
  static final Uint8List boldOn = Uint8List.fromList([0x1B, 0x45, 1]);
  static final Uint8List boldOff = Uint8List.fromList([0x1B, 0x45, 0]);
  static final Uint8List doubleHeightOn =
      Uint8List.fromList([0x1D, 0x21, 0x01]);
  static final Uint8List normalSize = Uint8List.fromList([0x1D, 0x21, 0x00]);
  static final Uint8List underlineOn = Uint8List.fromList([0x1B, 0x2D, 1]);
  static final Uint8List underlineOff = Uint8List.fromList([0x1B, 0x2D, 0]);

  /// Codigo de pagina PC850 (acentos PT-BR comuns).
  static final Uint8List codePage850 =
      Uint8List.fromList([0x1B, 0x74, 2]);

  static Uint8List feed(int linhas) =>
      Uint8List.fromList([0x1B, 0x64, linhas.clamp(0, 10)]);

  /// Corte total (GS V 0).
  static final Uint8List cutFull = Uint8List.fromList([0x1D, 0x56, 0x00]);

  /// Corte parcial (GS V 1).
  static final Uint8List cutPartial = Uint8List.fromList([0x1D, 0x56, 0x01]);

  /// Pulso gaveta ESC p m t1 t2.
  static Uint8List drawerPulse({
    int pino = 0,
    int tempoOnMs = 50,
    int tempoOffMs = 250,
  }) {
    final m = pino.clamp(0, 1);
    final t1 = (tempoOnMs ~/ 2).clamp(1, 255);
    final t2 = (tempoOffMs ~/ 2).clamp(1, 255);
    return Uint8List.fromList([0x1B, 0x70, m, t1, t2]);
  }

  /// Texto em Latin-1 (ISO-8859-1), com fallback para ASCII.
  static Uint8List text(String s) {
    final normalized = _sanitizar(s);
    try {
      return Uint8List.fromList(latin1.encode(normalized));
    } catch (_) {
      return Uint8List.fromList(utf8.encode(normalized));
    }
  }

  static Uint8List line(String s) =>
      Uint8List.fromList([...text(s), 0x0A]);

  static Uint8List separator(int cols, [String ch = '-']) {
    final c = ch.isEmpty ? '-' : ch.substring(0, 1);
    return line(List.filled(cols.clamp(16, 64), c).join());
  }

  /// QR Code nativo Epson (GS ( k).
  static Uint8List qrCode(String payload, {int moduleSize = 5}) {
    final data = utf8.encode(payload);
    if (data.isEmpty) return Uint8List(0);
    final size = moduleSize.clamp(3, 8);
    final out = BytesBuilder(copy: false);
    // Model 2
    out.add([0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00]);
    // Module size
    out.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, size]);
    // Error correction level L
    out.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x30]);
    // Store data
    final storeLen = data.length + 3;
    out.add([
      0x1D,
      0x28,
      0x6B,
      storeLen & 0xFF,
      (storeLen >> 8) & 0xFF,
      0x31,
      0x50,
      0x30,
      ...data,
    ]);
    // Print
    out.add([0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]);
    return out.toBytes();
  }

  static String _sanitizar(String s) {
    return s
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('•', '-')
        .replaceAll('·', '-')
        .replaceAll('\u00A0', ' ')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
  }
}

/// Largura tipica da bobina em colunas de fonte normal.
enum EscPosLarguraBobina {
  mm58(32),
  mm80(48);

  const EscPosLarguraBobina(this.colunas);
  final int colunas;

  static EscPosLarguraBobina fromConfig(String raw) {
    final t = raw.trim().toLowerCase();
    if (t == '58' || t == 'mm58' || t == '58mm') return EscPosLarguraBobina.mm58;
    return EscPosLarguraBobina.mm80;
  }
}
