import 'package:flutter/material.dart';

/// Cabecalho compacto do cadastro de vendedores (mesmo visual de clientes).
class VendedorCadastroHeader extends StatelessWidget {
  const VendedorCadastroHeader({
    super.key,
    required this.emEdicao,
    required this.vendedorId,
    required this.nome,
    required this.codigoInterno,
    required this.ativo,
    this.apelido = '',
    this.comissaoTexto,
  });

  final bool emEdicao;
  final int? vendedorId;
  final String nome;
  final String codigoInterno;
  final bool ativo;
  final String apelido;
  final String? comissaoTexto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = nome.trim().isEmpty
        ? (emEdicao ? 'Vendedor em edicao' : 'Novo vendedor')
        : nome.trim();
    final codigo = codigoInterno.trim().isNotEmpty
        ? codigoInterno.trim()
        : (vendedorId != null && vendedorId! > 0 ? '#$vendedorId' : 'Novo');

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.point_of_sale_outlined,
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
              if (apelido.trim().isNotEmpty)
                _ChipInfo(label: apelido.trim(), theme: theme),
              if (comissaoTexto != null && comissaoTexto!.trim().isNotEmpty)
                Text(
                  'Comissao: ${comissaoTexto!.trim()}%',
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
