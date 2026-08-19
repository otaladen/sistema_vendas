import 'package:flutter/material.dart';

/// Cabecalho compacto do cadastro de produtos (mesmo visual de clientes/motoristas).
class ProdutoCadastroHeader extends StatelessWidget {
  const ProdutoCadastroHeader({
    super.key,
    required this.emEdicao,
    required this.produtoId,
    required this.nome,
    required this.skuRotulo,
    required this.ativo,
    this.estoqueResumo,
    this.precoResumo,
    this.datasResumo,
  });

  final bool emEdicao;
  final int? produtoId;
  final String nome;
  final String skuRotulo;
  final bool ativo;
  final String? estoqueResumo;
  final String? precoResumo;
  final String? datasResumo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = nome.trim().isEmpty
        ? (emEdicao ? 'Produto em edicao' : 'Novo produto')
        : nome.trim();
    final sku = skuRotulo.trim().isNotEmpty ? skuRotulo.trim() : 'Sem SKU';

    final extras = <String>[
      if (precoResumo != null && precoResumo!.trim().isNotEmpty)
        precoResumo!.trim(),
      if (estoqueResumo != null && estoqueResumo!.trim().isNotEmpty)
        estoqueResumo!.trim(),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  titulo,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (datasResumo != null && datasResumo!.trim().isNotEmpty)
                  Text(
                    datasResumo!.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 0,
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _ChipInfo(label: sku, theme: theme),
                _ChipInfo(
                  label: ativo ? 'Ativo' : 'Inativo',
                  theme: theme,
                  destaque: ativo
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.errorContainer,
                ),
                if (emEdicao && produtoId != null && produtoId! > 0)
                  _ChipInfo(label: '#$produtoId', theme: theme),
                if (extras.isNotEmpty)
                  Text(
                    extras.join(' · '),
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                  ),
              ],
            ),
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
