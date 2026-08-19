import 'package:flutter/material.dart';

/// Cabecalho compacto do cadastro de fornecedores (mesmo visual do de clientes).
class FornecedorCadastroHeader extends StatelessWidget {
  const FornecedorCadastroHeader({
    super.key,
    required this.emEdicao,
    required this.fornecedorId,
    required this.razaoSocial,
    required this.documento,
    required this.ativo,
  });

  final bool emEdicao;
  final int? fornecedorId;
  final String razaoSocial;
  final String documento;
  final bool ativo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = razaoSocial.trim().isEmpty
        ? (emEdicao ? 'Fornecedor em edicao' : 'Novo fornecedor')
        : razaoSocial.trim();
    final codigo = fornecedorId != null && fornecedorId! > 0
        ? '#$fornecedorId'
        : 'Novo';
    final doc = documento.trim().isEmpty ? '-' : documento.trim();
    final docRotulo = doc.replaceAll(RegExp(r'\D'), '').length <= 11
        ? 'CPF'
        : 'CNPJ';

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.local_shipping_outlined,
            size: 18,
            color: theme.colorScheme.primary,
          ),
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
