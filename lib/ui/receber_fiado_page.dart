import 'package:flutter/material.dart';

import '../data/cliente_repository.dart';
import '../data/venda_repository.dart';
import 'widgets/receber_fiado_panel.dart';

/// Página legada de recebimento de fiado (preferir o fluxo no Caixa).
class ReceberFiadoPage extends StatelessWidget {
  const ReceberFiadoPage({
    super.key,
    required this.vendaRepository,
    required this.clienteRepository,
  });

  final VendaRepository vendaRepository;
  final ClienteRepository clienteRepository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receber fiado'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: ReceberFiadoPanel(
          vendaRepository: vendaRepository,
          clienteRepository: clienteRepository,
        ),
      ),
    );
  }
}
