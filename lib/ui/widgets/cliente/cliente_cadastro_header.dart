import 'package:flutter/material.dart';

import '../../../domain/cliente_cadastro.dart';

/// Cabecalho fixo do cadastro de clientes com identidade e KPIs comerciais.
class ClienteCadastroHeader extends StatelessWidget {
  const ClienteCadastroHeader({
    super.key,
    required this.emEdicao,
    required this.clienteId,
    required this.nomeRazao,
    required this.tipoPessoa,
    required this.documento,
    required this.ativo,
    required this.segmento,
    required this.codigoInterno,
    this.totalGasto,
    this.ultimaCompraTexto,
    this.fiadoAberto,
    this.creditoDisponivel,
    this.limiteCredito,
  });

  final bool emEdicao;
  final int? clienteId;
  final String nomeRazao;
  final String tipoPessoa;
  final String documento;
  final bool ativo;
  final String segmento;
  final String codigoInterno;
  final String? totalGasto;
  final String? ultimaCompraTexto;
  final String? fiadoAberto;
  final String? creditoDisponivel;
  final double? limiteCredito;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = nomeRazao.trim().isEmpty
        ? (emEdicao ? 'Cliente em edicao' : 'Novo cliente')
        : nomeRazao.trim();
    final codigo = codigoInterno.trim().isNotEmpty
        ? codigoInterno.trim()
        : (clienteId != null ? '#$clienteId' : 'Novo');
    final docRotulo = tipoPessoa == 'juridica' ? 'CNPJ' : 'CPF';
    final doc = documento.trim().isEmpty ? '-' : documento.trim();
    final seg = segmento.trim().isEmpty
        ? null
        : ClienteCadastro.rotuloSegmento(segmento);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.badge_outlined, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _ChipInfo(label: codigo, theme: theme),
                        _ChipInfo(
                          label: tipoPessoa == 'juridica' ? 'PJ' : 'PF',
                          theme: theme,
                        ),
                        _ChipInfo(
                          label: ativo ? 'Ativo' : 'Inativo',
                          theme: theme,
                          destaque: ativo
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.errorContainer,
                        ),
                        if (seg != null) _ChipInfo(label: seg, theme: theme),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$docRotulo: $doc',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (emEdicao && clienteId != null && clienteId! > 0) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (totalGasto != null)
                  _KpiChip(
                    icon: Icons.shopping_cart_outlined,
                    rotulo: 'Gasto',
                    valor: totalGasto!,
                    theme: theme,
                  ),
                if (ultimaCompraTexto != null)
                  _KpiChip(
                    icon: Icons.schedule_outlined,
                    rotulo: 'Ultima compra',
                    valor: ultimaCompraTexto!,
                    theme: theme,
                  ),
                if (limiteCredito != null && limiteCredito! > 0) ...[
                  if (fiadoAberto != null)
                    _KpiChip(
                      icon: Icons.receipt_long_outlined,
                      rotulo: 'Fiado aberto',
                      valor: fiadoAberto!,
                      theme: theme,
                    ),
                  if (creditoDisponivel != null)
                    _KpiChip(
                      icon: Icons.account_balance_wallet_outlined,
                      rotulo: 'Disponivel',
                      valor: creditoDisponivel!,
                      theme: theme,
                      destaque: theme.colorScheme.primaryContainer,
                    ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipInfo extends StatelessWidget {
  const _ChipInfo({
    required this.label,
    required this.theme,
    this.destaque,
  });

  final String label;
  final ThemeData theme;
  final Color? destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: destaque ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _KpiChip extends StatelessWidget {
  const _KpiChip({
    required this.icon,
    required this.rotulo,
    required this.valor,
    required this.theme,
    this.destaque,
  });

  final IconData icon;
  final String rotulo;
  final String valor;
  final ThemeData theme;
  final Color? destaque;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: destaque ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            '$rotulo: ',
            style: theme.textTheme.labelSmall,
          ),
          Text(
            valor,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
