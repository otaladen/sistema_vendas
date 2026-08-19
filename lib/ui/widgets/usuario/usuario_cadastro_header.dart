import 'package:flutter/material.dart';

/// Cabecalho compacto do cadastro de usuarios (mesmo visual de clientes).
class UsuarioCadastroHeader extends StatelessWidget {
  const UsuarioCadastroHeader({
    super.key,
    required this.emEdicao,
    required this.nome,
    required this.login,
    required this.ativo,
    required this.perfilRotulo,
    this.admin = false,
  });

  final bool emEdicao;
  final String nome;
  final String login;
  final bool ativo;
  final String perfilRotulo;
  final bool admin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = nome.trim().isEmpty
        ? (emEdicao ? 'Usuario em edicao' : 'Novo usuario')
        : nome.trim();
    final loginRotulo = login.trim().isEmpty ? '-' : login.trim();

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(
            Icons.manage_accounts_outlined,
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
              _ChipInfo(label: loginRotulo, theme: theme),
              _ChipInfo(
                label: ativo ? 'Ativo' : 'Inativo',
                theme: theme,
                destaque: ativo
                    ? theme.colorScheme.primaryContainer
                    : theme.colorScheme.errorContainer,
              ),
              if (admin) _ChipInfo(label: 'Admin', theme: theme),
              _ChipInfo(label: perfilRotulo, theme: theme),
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
