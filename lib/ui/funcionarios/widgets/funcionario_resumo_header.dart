import 'dart:io';

import 'package:flutter/material.dart';

import '../../../domain/main_menu_destino.dart';
import '../../theme/app_modulo_cores.dart';
import '../../theme/app_semantic_helper.dart';

/// Cabecalho compacto do cadastro de funcionarios (mesmo visual de clientes).
class FuncionarioResumoHeader extends StatelessWidget {
  const FuncionarioResumoHeader({
    super.key,
    required this.nome,
    required this.codigo,
    required this.resumoRh,
    required this.tempoCasa,
    required this.liquidoFormatado,
    required this.proximoPagamentoFormatado,
    required this.ativo,
    this.emEdicaoId,
    this.tambemVendedorPdv = false,
    this.vendedorVinculadoId = 0,
    this.tambemMotoristaEntrega = false,
    this.motoristaVinculadoId = 0,
    this.temUsuarioSistema = false,
    this.usuarioLogin,
    this.cnhVencida = false,
    this.asoVencido = false,
    this.dataDemissaoFormatada,
    this.fotoPath,
    this.compact = false,
  });

  final String nome;
  final String codigo;
  final String resumoRh;
  final String tempoCasa;
  final String liquidoFormatado;
  final String proximoPagamentoFormatado;
  final bool ativo;
  final int? emEdicaoId;
  final bool tambemVendedorPdv;
  final int vendedorVinculadoId;
  final bool tambemMotoristaEntrega;
  final int motoristaVinculadoId;
  final bool temUsuarioSistema;
  final String? usuarioLogin;
  final bool cnhVencida;
  final bool asoVencido;
  final String? dataDemissaoFormatada;
  final String? fotoPath;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final titulo = nome.trim().isEmpty
        ? (emEdicaoId != null ? 'Funcionario em edicao' : 'Novo funcionario')
        : nome.trim();
    final codigoRotulo = codigo.trim().isNotEmpty
        ? codigo.trim()
        : (emEdicaoId != null ? '#$emEdicaoId' : 'Novo');

    return Container(
      padding: EdgeInsets.fromLTRB(4, compact ? 3 : 4, 8, compact ? 3 : 4),
      color: scheme.surfaceContainerHighest,
      child: Row(
        children: [
          _buildAvatar(scheme),
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
                if (resumoRh.trim().isNotEmpty)
                  Text(
                    resumoRh,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.end,
              children: [
                _ChipInfo(label: codigoRotulo, theme: theme),
                _ChipInfo(
                  label: ativo ? 'Ativo' : 'Inativo',
                  theme: theme,
                  destaque: ativo
                      ? scheme.primaryContainer
                      : scheme.errorContainer,
                ),
                if (tempoCasa.isNotEmpty)
                  _ChipInfo(label: tempoCasa, theme: theme),
                if (tambemVendedorPdv)
                  _ChipInfo(
                    label: vendedorVinculadoId > 0
                        ? 'PDV #$vendedorVinculadoId'
                        : 'Vendedor PDV',
                    theme: theme,
                  ),
                if (tambemMotoristaEntrega)
                  _ChipInfo(
                    label: motoristaVinculadoId > 0
                        ? 'Motorista #$motoristaVinculadoId'
                        : 'Motorista',
                    theme: theme,
                    destaque: MainMenuDestino.entregas
                        .cor(context)
                        .withValues(alpha: 0.18),
                  ),
                if (temUsuarioSistema)
                  _ChipInfo(
                    label: usuarioLogin != null && usuarioLogin!.isNotEmpty
                        ? 'Login $usuarioLogin'
                        : 'Usuario ERP',
                    theme: theme,
                  ),
                if (cnhVencida)
                  _ChipInfo(
                    label: 'CNH vencida',
                    theme: theme,
                    destaque: semantic.errorBg,
                  ),
                if (asoVencido)
                  _ChipInfo(
                    label: 'ASO vencido',
                    theme: theme,
                    destaque: semantic.errorBg,
                  ),
                if (!ativo && dataDemissaoFormatada != null)
                  _ChipInfo(
                    label: 'Demissao $dataDemissaoFormatada',
                    theme: theme,
                    destaque: semantic.errorBg,
                  ),
                Text(
                  'Liq. $liquidoFormatado',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                Text(
                  'Pag. $proximoPagamentoFormatado',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(ColorScheme scheme) {
    final path = fotoPath?.trim() ?? '';
    final file = path.isNotEmpty ? File(path) : null;
    final temFoto = file != null && file.existsSync();
    final tamanho = compact ? 28.0 : 32.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: tamanho,
        height: tamanho,
        child: temFoto
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                child: Icon(
                  Icons.badge_outlined,
                  color: scheme.primary,
                  size: compact ? 16 : 18,
                ),
              ),
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
