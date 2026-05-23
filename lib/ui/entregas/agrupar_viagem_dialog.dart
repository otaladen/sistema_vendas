import 'package:flutter/material.dart';

import '../../data/motorista_repository.dart';

/// Dialogo para escolher motorista ao agrupar pedidos na mesma viagem.
Future<String?> showAgruparViagemMotoristaDialog(
  BuildContext context,
  MotoristaRepository motoristaRepository, {
  String? motoristaSugerido,
}) {
  final motoristas = motoristaRepository.listarAtivos();
  var escolhido = motoristaSugerido ??
      (motoristas.isNotEmpty ? motoristas.first.nome : null);

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setLocal) {
        return AlertDialog(
          title: const Text('Agrupar viagem (mesmo carro)'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Cada confirmacao = uma viagem (ex.: 1a saida do dia). '
                'Informe o motorista — na loja, cada motorista usa sempre o mesmo caminhao.',
              ),
              const SizedBox(height: 12),
              if (motoristas.isEmpty)
                const Text(
                  'Nenhum motorista ativo. Cadastre em Cadastros > Motoristas.',
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: escolhido,
                  decoration: const InputDecoration(
                    labelText: 'Motorista',
                  ),
                  items: motoristas
                      .map(
                        (m) => DropdownMenuItem(
                          value: m.nome,
                          child: Text(m.nome),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setLocal(() => escolhido = v),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: motoristas.isEmpty || escolhido == null
                  ? null
                  : () => Navigator.pop(ctx, escolhido),
              child: const Text('Confirmar agrupamento'),
            ),
          ],
        );
      },
    ),
  );
}
