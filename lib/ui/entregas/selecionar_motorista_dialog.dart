import 'package:flutter/material.dart';

import '../../data/motorista_repository.dart';

/// Escolhe um motorista ativo (retorna nome ou null se cancelar).
Future<String?> showSelecionarMotoristaDialog(
  BuildContext context,
  MotoristaRepository motoristaRepository, {
  String titulo = 'Motorista',
  String? textoAuxiliar,
  String? motoristaSugerido,
  String rotuloConfirmar = 'Confirmar',
}) {
  final motoristas = motoristaRepository.listarAtivos();
  var escolhido = motoristaSugerido ??
      (motoristas.isNotEmpty ? motoristas.first.nome : null);

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setLocal) {
        return AlertDialog(
          title: Text(titulo),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (textoAuxiliar != null && textoAuxiliar.isNotEmpty) ...[
                Text(textoAuxiliar),
                const SizedBox(height: 12),
              ],
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
              child: Text(rotuloConfirmar),
            ),
          ],
        );
      },
    ),
  );
}
