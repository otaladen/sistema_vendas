import 'dart:convert' show utf8;
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

  /// Texto para termica: ASCII + acentos PT-BR em CP850 (Epson TM-T20).
  ///
  /// Nao usa Latin-1 cru: com `ESC t 2` (CP850) isso gera "Sao"→"Soo" etc.
  static Uint8List text(String s) {
    final normalized = _sanitizar(s);
    return Uint8List.fromList(_encodeCp850(normalized));
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

  /// Mapa minimo PT-BR → byte CP850. Demais chars ASCII ou '?'.
  static const Map<int, int> _cp850Extras = {
    0x00C7: 0x80, // Ç
    0x00FC: 0x81, // ü
    0x00E9: 0x82, // é
    0x00E2: 0x83, // â
    0x00E4: 0x84, // ä
    0x00E0: 0x85, // à
    0x00E7: 0x87, // ç
    0x00EA: 0x88, // ê
    0x00EB: 0x89, // ë
    0x00E8: 0x8A, // è
    0x00EF: 0x8B, // ï
    0x00EE: 0x8C, // î
    0x00EC: 0x8D, // ì
    0x00C9: 0x90, // É
    0x00F4: 0x93, // ô
    0x00F6: 0x94, // ö
    0x00F2: 0x95, // ò
    0x00FB: 0x96, // û
    0x00F9: 0x97, // ù
    0x00D6: 0x99, // Ö
    0x00DC: 0x9A, // Ü
    0x00E1: 0xA0, // á
    0x00ED: 0xA1, // í
    0x00F3: 0xA2, // ó
    0x00FA: 0xA3, // ú
    0x00F1: 0xA4, // ñ
    0x00D1: 0xA5, // Ñ
    0x00C1: 0xB5, // Á
    0x00C2: 0xB6, // Â
    0x00C0: 0xB7, // À
    0x00E3: 0xC6, // ã
    0x00C3: 0xC7, // Ã
    0x00CA: 0xD2, // Ê
    0x00CB: 0xD3, // Ë
    0x00C8: 0xD4, // È
    0x00CD: 0xD6, // Í
    0x00CE: 0xD7, // Î
    0x00CF: 0xD8, // Ï
    0x00D3: 0xE0, // Ó
    0x00D4: 0xE2, // Ô
    0x00D2: 0xE3, // Ò
    0x00F5: 0xE4, // õ
    0x00D5: 0xE5, // Õ
    0x00DA: 0xE9, // Ú
    0x00DB: 0xEA, // Û
    0x00D9: 0xEB, // Ù
  };

  static List<int> _encodeCp850(String s) {
    final out = <int>[];
    for (final r in s.runes) {
      if (r >= 0x20 && r <= 0x7E) {
        out.add(r);
        continue;
      }
      if (r == 0x09) {
        out.add(0x20);
        continue;
      }
      final mapped = _cp850Extras[r];
      if (mapped != null) {
        out.add(mapped);
        continue;
      }
      // Fallback: remove acento generico / substitui.
      out.add(0x3F); // ?
    }
    return out;
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
