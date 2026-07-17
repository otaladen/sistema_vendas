import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'operacao_feedback.dart';

/// Feedback exibido na tela do scanner apos cada leitura.
class PdvBarcodeScanFeedback {
  const PdvBarcodeScanFeedback({
    required this.sucesso,
    this.mensagem,
  });

  final bool sucesso;
  final String? mensagem;
}

/// Tela cheia de leitura de codigo de barras (PDV, cadastro, consulta).
class PdvBarcodeScannerPage extends StatefulWidget {
  const PdvBarcodeScannerPage({
    super.key,
    required this.onCodigoLido,
    this.titulo = 'Bipar produto',
    this.modoContinuoInicial = true,
    this.mostrarToggleContinuo = true,
    this.instrucaoContinuo =
        'Aponte para o codigo de barras. Cada bip adiciona ao orcamento.',
    this.instrucaoUnico =
        'Modo unico: fecha apos encontrar o produto.',
  });

  final Future<PdvBarcodeScanFeedback> Function(String codigo) onCodigoLido;
  final String titulo;
  final bool modoContinuoInicial;
  final bool mostrarToggleContinuo;
  final String instrucaoContinuo;
  final String instrucaoUnico;

  @override
  State<PdvBarcodeScannerPage> createState() => _PdvBarcodeScannerPageState();
}

class _PdvBarcodeScannerPageState extends State<PdvBarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
    ],
  );

  late bool _modoContinuo;
  bool _processando = false;
  String? _ultimoCodigo;
  DateTime? _ultimaLeituraEm;
  PdvBarcodeScanFeedback? _ultimoFeedback;
  int _totalLidos = 0;

  @override
  void initState() {
    super.initState();
    _modoContinuo = widget.modoContinuoInicial;
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  bool _deveIgnorarCodigo(String codigo) {
    final agora = DateTime.now();
    if (_ultimoCodigo == codigo &&
        _ultimaLeituraEm != null &&
        agora.difference(_ultimaLeituraEm!) < const Duration(milliseconds: 1400)) {
      return true;
    }
    return false;
  }

  Future<void> _aoDetectar(BarcodeCapture capture) async {
    if (_processando) return;
    final valor = capture.barcodes
        .map((b) => b.rawValue?.trim())
        .whereType<String>()
        .map((v) => v.replaceAll(RegExp(r'\s'), ''))
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (valor.isEmpty) return;
    if (_deveIgnorarCodigo(valor)) return;

    setState(() {
      _processando = true;
      _ultimoCodigo = valor;
      _ultimaLeituraEm = DateTime.now();
    });

    try {
      await _controller.stop();
    } catch (_) {}

    final feedback = await widget.onCodigoLido(valor);
    if (!mounted) return;

    setState(() {
      _processando = false;
      _ultimoFeedback = feedback;
      if (feedback.sucesso) _totalLidos++;
    });

    if (feedback.sucesso) {
      OperacaoFeedback.sucesso(
        context,
        feedback.mensagem?.trim().isNotEmpty == true
            ? feedback.mensagem!.trim()
            : 'Produto adicionado',
      );
    } else {
      OperacaoFeedback.erro(
        context,
        feedback.mensagem?.trim().isNotEmpty == true
            ? feedback.mensagem!.trim()
            : 'Produto nao encontrado',
      );
    }

    if (!_modoContinuo) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    try {
      await _controller.start();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final feedback = _ultimoFeedback;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(widget.titulo),
        actions: [
          IconButton(
            tooltip: _controller.torchEnabled ? 'Desligar lanterna' : 'Ligar lanterna',
            onPressed: () => _controller.toggleTorch(),
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, _) {
                return Icon(
                  state.torchState == TorchState.on
                      ? Icons.flash_on
                      : Icons.flash_off_outlined,
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'Trocar camera',
            onPressed: () => _controller.switchCamera(),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: (capture) => unawaited(_aoDetectar(capture)),
          ),
          IgnorePointer(
            child: Center(
              child: Container(
                width: MediaQuery.sizeOf(context).width * 0.78,
                height: MediaQuery.sizeOf(context).width * 0.42,
                decoration: BoxDecoration(
                  border: Border.all(color: scheme.primary, width: 2.5),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.62),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  _modoContinuo
                      ? widget.instrucaoContinuo
                      : widget.instrucaoUnico,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                      ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
          if (_processando)
            const ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.96),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.mostrarToggleContinuo
                                  ? 'Bipados nesta sessao: $_totalLidos'
                                  : (_ultimoCodigo ?? 'Aguardando leitura...'),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          if (widget.mostrarToggleContinuo)
                            FilterChip(
                              label: const Text('Bip continuo'),
                              selected: _modoContinuo,
                              onSelected: (v) =>
                                  setState(() => _modoContinuo = v),
                            ),
                        ],
                      ),
                      if (feedback != null) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              feedback.sucesso
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              color: feedback.sucesso
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                feedback.mensagem?.trim().isNotEmpty == true
                                    ? feedback.mensagem!.trim()
                                    : feedback.sucesso
                                        ? 'Produto adicionado'
                                        : 'Nao encontrado',
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.check),
                        label: const Text('Concluir'),
                      ),
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
