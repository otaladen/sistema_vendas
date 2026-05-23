import 'package:flutter/material.dart';

import 'entregas_montagem_callbacks.dart';
import 'logistica_entregas.dart';
import 'montagem_entrega_viagem.dart';
import 'romaneio_relatorios.dart';

/// Menu de impressao em lote na aba Montagem.
Future<void> showMontagemImpressaoLoteSheet({
  required BuildContext context,
  required EntregasMontagemCallbacks callbacks,
  required String motorista,
  required List<MontagemEntregaViagem> viagens,
  required MontagemEntregaViagem? viagemAtual,
}) {
  if (!motoristaLogisticaDefinido(motorista)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Defina o motorista antes de usar impressao em lote '
          '(relatorios por motorista).',
        ),
      ),
    );
    return Future.value();
  }
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Impressao em lote — $motorista',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
            if (viagemAtual != null) ...[
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: const Text('Separacao — viagem atual'),
                subtitle: Text(viagemAtual.rotulo),
                onTap: () async {
                  Navigator.pop(ctx);
                  await callbacks.emitirRelatorio(
                    tipo: RelatorioEntregaTipo.separacaoViagem,
                    viagem: viagemAtual.vendasOrdenadas,
                    salvarPdf: false,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Romaneio — viagem atual'),
                subtitle: Text(viagemAtual.rotulo),
                onTap: () async {
                  Navigator.pop(ctx);
                  await callbacks.emitirRelatorio(
                    tipo: RelatorioEntregaTipo.romaneioMotoristaDia,
                    motorista: motorista,
                    viagem: viagemAtual.vendasOrdenadas,
                    salvarPdf: false,
                  );
                },
              ),
            ],
            ListTile(
              leading: const Icon(Icons.view_agenda_outlined),
              title: const Text('Separacao — motorista no dia'),
              subtitle: Text('${viagens.length} viagem(ns) consolidadas'),
              onTap: () async {
                Navigator.pop(ctx);
                await callbacks.emitirRelatorio(
                  tipo: RelatorioEntregaTipo.separacaoMotoristaDia,
                  motorista: motorista,
                  salvarPdf: false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text('Romaneio — dia do motorista'),
              onTap: () async {
                Navigator.pop(ctx);
                await callbacks.emitirRelatorio(
                  tipo: RelatorioEntregaTipo.romaneioMotoristaDia,
                  motorista: motorista,
                  salvarPdf: false,
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.print_outlined),
              title: const Text('Separacao — cada viagem (sequencial)'),
              subtitle: const Text('Um PDF por viagem, na ordem da lista'),
              onTap: () async {
                Navigator.pop(ctx);
                for (final v in viagens) {
                  await callbacks.emitirRelatorio(
                    tipo: RelatorioEntregaTipo.separacaoViagem,
                    viagem: v.vendasOrdenadas,
                    salvarPdf: false,
                  );
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
