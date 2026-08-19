import 'package:flutter/material.dart';

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

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.badge_outlined, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              titulo,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Wrap(
            spacing: 4,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
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
              Text(
                '$docRotulo: $doc',
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
              ),
              if (emEdicao && clienteId != null && clienteId! > 0) ...[
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
                    rotulo: 'Ultima',
                    valor: ultimaCompraTexto!,
                    theme: theme,
                  ),
                if (limiteCredito != null &&
                    limiteCredito! > 0 &&
                    creditoDisponivel != null)
                  _KpiChip(
                    icon: Icons.account_balance_wallet_outlined,
                    rotulo: 'Disp.',
                    valor: creditoDisponivel!,
                    theme: theme,
                    destaque: theme.colorScheme.primaryContainer,
                  ),
              ],
            ],
          ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: destaque ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 10.5,
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: destaque ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: theme.colorScheme.primary),
          const SizedBox(width: 3),
          Text(
            '$rotulo: ',
            style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
          ),
          Text(
            valor,
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}
