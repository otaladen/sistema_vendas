import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/nfe_inutilizacao_store.dart';

Future<void> showNfeInutilizacaoHistoricoDialog(
  BuildContext context,
  NfeInutilizacaoStore store,
) {
  final fmt = DateFormat('dd/MM/yyyy HH:mm');
  final lista = store.listar();
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      title: const Text('Historico de inutilizacoes'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: lista.isEmpty
            ? const Center(
                child: Text('Nenhuma inutilizacao registrada neste computador.'),
              )
            : ListView.separated(
                itemCount: lista.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = lista[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      r.sucesso ? Icons.check_circle_outline : Icons.error_outline,
                      color: r.sucesso ? Colors.green.shade700 : Colors.red.shade700,
                    ),
                    title: Text(
                      'Serie ${r.serie}: ${r.numeroInicial} a ${r.numeroFinal}',
                    ),
                    subtitle: Text(
                      '${fmt.format(r.registradaEm.toLocal())}'
                      '${r.usuarioLogin.isNotEmpty ? ' · ${r.usuarioLogin}' : ''}'
                      '\n${r.justificativa}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    isThreeLine: true,
                    trailing: r.protocolo.isNotEmpty
                        ? Text('Prot.\n${r.protocolo}', textAlign: TextAlign.end)
                        : null,
                  );
                },
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
