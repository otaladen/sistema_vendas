import 'package:flutter/material.dart';

import '../../domain/entrega_nao_entregue.dart';

class NaoEntregueFormResult {
  const NaoEntregueFormResult({
    required this.motivoCodigo,
    this.detalhe = '',
    this.retornouParaLoja = false,
  });

  final String motivoCodigo;
  final String detalhe;
  final bool retornouParaLoja;
}

Future<NaoEntregueFormResult?> showNaoEntregueDialog({
  required BuildContext context,
}) async {
  var motivo = EntregaNaoEntregueMotivo.ausente;
  var retornouParaLoja = false;
  final detalheCtrl = TextEditingController();

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          return AlertDialog(
            title: const Text('Nao entregue'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'A loja recebe o pedido de volta como reagendado, '
                      'com o motivo abaixo.',
                    ),
                    const SizedBox(height: 8),
                    for (final id in EntregaNaoEntregueMotivo.todos)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        selected: motivo == id,
                        title: Text(EntregaNaoEntregueMotivo.rotulo(id)),
                        leading: Icon(
                          motivo == id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                        ),
                        onTap: () => setLocal(() => motivo = id),
                      ),
                    TextField(
                      controller: detalheCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Detalhe (opcional)',
                        hintText: 'Ex.: ninguem atendeu, portao fechado',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Mercadoria',
                      style: Theme.of(ctx).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: !retornouParaLoja,
                      title: const Text('Permanece no caminhao'),
                      subtitle: const Text(
                        'Estoque continua baixado (carga em rota).',
                      ),
                      leading: Icon(
                        !retornouParaLoja
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: () => setLocal(() => retornouParaLoja = false),
                    ),
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      selected: retornouParaLoja,
                      title: const Text('Voltou para a loja'),
                      subtitle: const Text(
                        'Estorna a saida e libera o checklist Saiu.',
                      ),
                      leading: Icon(
                        retornouParaLoja
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                      ),
                      onTap: () => setLocal(() => retornouParaLoja = true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Registrar'),
              ),
            ],
          );
        },
      );
    },
  );

  final detalhe = detalheCtrl.text;
  detalheCtrl.dispose();
  if (ok != true) return null;
  return NaoEntregueFormResult(
    motivoCodigo: motivo,
    detalhe: detalhe,
    retornouParaLoja: retornouParaLoja,
  );
}
