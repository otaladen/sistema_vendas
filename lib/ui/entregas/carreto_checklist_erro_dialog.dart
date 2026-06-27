import 'package:flutter/material.dart';

import '../../domain/entregas/carreto_checklist_estoque_helper.dart';
import '../../domain/venda_documento_rotulo_helper.dart';
import '../../model/movimento_estoque.dart';
import '../../model/venda.dart';

Future<void> mostrarDialogoErroChecklistSaiu({
  required BuildContext context,
  required Venda venda,
  required Object erro,
  required List<MovimentoEstoque> Function(int produtoId) listarMovimentos,
}) async {
  final kardex = CarretoChecklistEstoqueHelper.resumirKardexPedido(
    venda: venda,
    listarMovimentos: listarMovimentos,
  );
  final controle = VendaDocumentoRotuloHelper.rotuloControleInterno(venda);

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: Text(CarretoChecklistEstoqueHelper.tituloDialogoErroSaiu()),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  CarretoChecklistEstoqueHelper.mensagemResumida(erro),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(CarretoChecklistEstoqueHelper.orientacaoCorrecao()),
                const SizedBox(height: 12),
                Text(
                  'Kardex — $controle',
                  style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 6),
                ...kardex.map(
                  (linha) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      linha,
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            height: 1.35,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendi'),
          ),
        ],
      );
    },
  );
}
