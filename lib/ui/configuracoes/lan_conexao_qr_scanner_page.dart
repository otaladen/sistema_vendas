import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Leitura unica do QR de conexao (URL + token) no celular/tablet.
class LanConexaoQrScannerPage extends StatefulWidget {
  const LanConexaoQrScannerPage({super.key});

  @override
  State<LanConexaoQrScannerPage> createState() => _LanConexaoQrScannerPageState();
}

class _LanConexaoQrScannerPageState extends State<LanConexaoQrScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );

  bool _lido = false;

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _aoDetectar(BarcodeCapture capture) {
    if (_lido) return;
    final valor = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .whereType<String>()
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (valor.isEmpty) return;
    _lido = true;
    Navigator.of(context).pop(valor);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler QR Code de conexao')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _aoDetectar,
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Aponte para o QR gerado em Configuracoes > Rede e terminais '
                  'no PC servidor.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        shadows: const [
                          Shadow(blurRadius: 8, color: Colors.black),
                        ],
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
