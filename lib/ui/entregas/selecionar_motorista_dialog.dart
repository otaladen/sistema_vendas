import 'package:flutter/material.dart';

import '../../domain/motorista_lista_safe.dart';

/// Escolhe um motorista ativo (retorna nome, '' se limpar, ou null se cancelar).
Future<String?> showSelecionarMotoristaDialog(
  BuildContext context,
  dynamic motoristaRepository, {
  String titulo = 'Motorista',
  String? textoAuxiliar,
  String? motoristaSugerido,
  String rotuloConfirmar = 'Confirmar',
  bool permitirLimpar = false,
}) {
  final opcoes = MotoristaListaSafe.opcoesDropdown(
    motoristaRepository: motoristaRepository,
    atual: motoristaSugerido,
  );
  var escolhido = MotoristaListaSafe.valorInicialDropdown(
    opcoes: opcoes,
    preferido: motoristaSugerido,
  );

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
              if (opcoes.isEmpty)
                const Text(
                  'Nenhum motorista ativo. Cadastre em Cadastros > Motoristas.',
                )
              else
                DropdownButtonFormField<String>(
                  key: ValueKey('mot_${opcoes.join('|')}'),
                  initialValue: escolhido,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Motorista',
                  ),
                  items: opcoes
                      .map(
                        (nome) => DropdownMenuItem(
                          value: nome,
                          child: Text(nome),
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
            if (permitirLimpar)
              TextButton(
                onPressed: () => Navigator.pop(ctx, ''),
                child: const Text('Limpar'),
              ),
            ElevatedButton(
              onPressed: opcoes.isEmpty || escolhido == null
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
