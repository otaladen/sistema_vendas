import 'package:flutter/material.dart';

import '../../../domain/fiscal/fiscal_erro_dica_helper.dart';

/// Modal com motivo completo de rejeicao/erro fiscal.
abstract final class FiscalRejeicaoDetalheDialog {
  FiscalRejeicaoDetalheDialog._();

  static Future<void> show(
    BuildContext context, {
    required String titulo,
    required String numeroControle,
    required String statusFiscal,
    required String mensagemErro,
    String? dicaSolucao,
  }) {
    final dica = dicaSolucao ?? FiscalErroDicaHelper.dicaSolucao(mensagemErro);
    return showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        return AlertDialog(
          icon: Icon(Icons.error_outline, color: scheme.error, size: 32),
          title: Text(titulo),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _campo('Numero de controle / venda', numeroControle),
                  const SizedBox(height: 10),
                  _campo('Status fiscal atual', statusFiscal),
                  const SizedBox(height: 10),
                  Text(
                    'Mensagem de erro / rejeicao',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      mensagemErro.trim().isEmpty
                          ? 'Nenhuma mensagem detalhada registrada.'
                          : mensagemErro.trim(),
                    ),
                  ),
                  if (dica != null && dica.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Dica de solucao',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 18,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(dica)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  static Widget _campo(String rotulo, String valor) {
    return Builder(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rotulo,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(valor, style: theme.textTheme.bodyMedium),
          ],
        );
      },
    );
  }
}
