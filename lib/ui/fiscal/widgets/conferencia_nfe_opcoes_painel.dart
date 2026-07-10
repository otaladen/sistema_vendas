import 'package:flutter/material.dart';

import '../../../domain/conferencia_nfe_opcoes.dart';

/// Checkboxes de lancamento (estilo Chacal) antes de confirmar a NF-e.
class ConferenciaNfeOpcoesPainel extends StatelessWidget {
  const ConferenciaNfeOpcoesPainel({
    super.key,
    required this.opcoes,
    required this.onChanged,
  });

  final ConferenciaNfeOpcoes opcoes;
  final ValueChanged<ConferenciaNfeOpcoes> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'Opcoes de lancamento',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Marque o que esta nota deve alterar ao confirmar (F10).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                _opcao(
                  context,
                  label: 'Lancar estoque',
                  value: opcoes.lancarEstoque,
                  onChanged: (v) => onChanged(opcoes.copyWith(lancarEstoque: v)),
                ),
                _opcao(
                  context,
                  label: 'Gerar contas a pagar',
                  value: opcoes.gerarContasPagar,
                  onChanged: (v) =>
                      onChanged(opcoes.copyWith(gerarContasPagar: v)),
                ),
                _opcao(
                  context,
                  label: 'Atualizar preco de custo',
                  value: opcoes.atualizarPrecoCusto,
                  onChanged: (v) =>
                      onChanged(opcoes.copyWith(atualizarPrecoCusto: v)),
                ),
                _opcao(
                  context,
                  label: 'Atualizar precos de venda',
                  value: opcoes.atualizarPrecosVenda,
                  enabled: opcoes.atualizarPrecoCusto,
                  onChanged: (v) =>
                      onChanged(opcoes.copyWith(atualizarPrecosVenda: v)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _opcao(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool enabled = true,
  }) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: enabled ? (v) => onChanged(v) : null,
      showCheckmark: true,
      labelStyle: TextStyle(
        fontWeight: value ? FontWeight.w700 : FontWeight.w500,
        fontSize: 12.5,
      ),
    );
  }
}
