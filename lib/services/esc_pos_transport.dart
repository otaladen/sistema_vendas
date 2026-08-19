import 'dart:io';
import 'dart:typed_data';

import 'gaveta_raw_io.dart';

/// Destino fisico dos bytes ESC/POS.
enum EscPosDestinoTipo {
  /// Fila Windows (USB/driver) via WritePrinter RAW.
  windows,

  /// Socket TCP (porta 9100 tipica).
  rede,

  /// Porta serial COMx no Windows.
  com,
}

class EscPosDestino {
  const EscPosDestino.windows(this.nomeImpressora)
      : tipo = EscPosDestinoTipo.windows,
        host = '',
        portaTcp = 9100,
        portaCom = '';

  const EscPosDestino.rede(this.host, {this.portaTcp = 9100})
      : tipo = EscPosDestinoTipo.rede,
        nomeImpressora = '',
        portaCom = '';

  const EscPosDestino.com(this.portaCom)
      : tipo = EscPosDestinoTipo.com,
        nomeImpressora = '',
        host = '',
        portaTcp = 9100;

  final EscPosDestinoTipo tipo;
  final String nomeImpressora;
  final String host;
  final int portaTcp;
  final String portaCom;

  static EscPosDestino fromConfig({
    required String tipo,
    required String impressoraWindows,
    required String host,
    required int portaTcp,
    required String portaCom,
  }) {
    switch (tipo.trim().toLowerCase()) {
      case 'rede':
      case 'tcp':
      case 'ip':
        return EscPosDestino.rede(
          host.trim(),
          portaTcp: portaTcp.clamp(1, 65535),
        );
      case 'com':
      case 'serial':
        return EscPosDestino.com(portaCom.trim());
      case 'windows':
      case 'usb':
      default:
        return EscPosDestino.windows(impressoraWindows.trim());
    }
  }
}

/// Envia bytes RAW para impressora termica.
abstract final class EscPosTransport {
  EscPosTransport._();

  static Future<void> enviar(EscPosDestino destino, Uint8List bytes) async {
    if (bytes.isEmpty) return;
    switch (destino.tipo) {
      case EscPosDestinoTipo.windows:
        if (!Platform.isWindows) {
          throw StateError('Impressao RAW Windows so no app desktop Windows.');
        }
        final nome = destino.nomeImpressora.trim();
        if (nome.isEmpty) {
          throw StateError(
            'Configure o nome da impressora termica (fila do Windows).',
          );
        }
        await enviarRawParaImpressora(nome, bytes);
      case EscPosDestinoTipo.rede:
        await _enviarTcp(destino.host, destino.portaTcp, bytes);
      case EscPosDestinoTipo.com:
        await _enviarCom(destino.portaCom, bytes);
    }
  }

  static Future<void> _enviarTcp(String host, int porta, Uint8List bytes) async {
    final h = host.trim();
    if (h.isEmpty) {
      throw StateError('Informe o IP da impressora termica.');
    }
    Socket? socket;
    try {
      socket = await Socket.connect(
        h,
        porta,
        timeout: const Duration(seconds: 8),
      );
      socket.add(bytes);
      await socket.flush();
    } finally {
      await socket?.close();
    }
  }

  static Future<void> _enviarCom(String portaCom, Uint8List bytes) async {
    if (!Platform.isWindows) {
      throw StateError('Porta COM disponivel apenas no Windows.');
    }
    var p = portaCom.trim().toUpperCase();
    if (p.isEmpty) {
      throw StateError('Informe a porta COM (ex.: COM3).');
    }
    if (!p.startsWith('COM')) {
      p = 'COM$p';
    }
    final path = '\\\\.\\$p';
    final file = File(path);
    final raf = await file.open(mode: FileMode.write);
    try {
      await raf.writeFrom(bytes);
      await raf.flush();
    } finally {
      await raf.close();
    }
  }
}
