import 'package:flutter/material.dart';

import '../../../domain/main_menu_destino.dart';
import '../../theme/app_modulo_cores.dart';
import '../../theme/app_semantic_helper.dart';

/// Resumo somente leitura do funcionario selecionado (estilo cadastro de produtos).
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
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;
    final titulo = nome.trim().isEmpty ? 'Novo funcionario' : nome.trim();
    final codigoRotulo =
        codigo.trim().isEmpty ? 'Sem codigo' : 'Codigo ${codigo.trim()}';

    final chips = <Widget>[
      Chip(
        visualDensity: VisualDensity.compact,
        label: Text(codigoRotulo),
      ),
      Chip(
        visualDensity: VisualDensity.compact,
        label: Text(ativo ? 'Ativo' : 'Inativo'),
        backgroundColor: ativo
            ? scheme.primaryContainer.withValues(alpha: 0.55)
            : scheme.errorContainer.withValues(alpha: 0.4),
      ),
      if (tempoCasa.isNotEmpty)
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text(tempoCasa),
        ),
      if (emEdicaoId != null)
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text('#$emEdicaoId'),
        ),
      if (tambemVendedorPdv)
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text(
            vendedorVinculadoId > 0
                ? 'PDV #$vendedorVinculadoId'
                : 'Vendedor PDV',
          ),
        ),
      if (tambemMotoristaEntrega)
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text(
            motoristaVinculadoId > 0
                ? 'Motorista #$motoristaVinculadoId'
                : 'Motorista',
          ),
          backgroundColor: MainMenuDestino.entregas
              .cor(context)
              .withValues(alpha: 0.18),
        ),
      if (temUsuarioSistema)
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text(
            usuarioLogin != null && usuarioLogin!.isNotEmpty
                ? 'Login $usuarioLogin'
                : 'Usuario ERP',
          ),
        ),
      if (cnhVencida)
        Chip(
          visualDensity: VisualDensity.compact,
          label: const Text('CNH vencida'),
          backgroundColor: semantic.errorBg.withValues(alpha: 0.55),
        ),
      if (asoVencido)
        Chip(
          visualDensity: VisualDensity.compact,
          label: const Text('ASO vencido'),
          backgroundColor: semantic.errorBg.withValues(alpha: 0.55),
        ),
      if (!ativo && dataDemissaoFormatada != null)
        Chip(
          visualDensity: VisualDensity.compact,
          label: Text('Demissao $dataDemissaoFormatada'),
          backgroundColor: semantic.errorBg.withValues(alpha: 0.45),
        ),
    ];

    final identidade = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          maxLines: compact ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: (compact
                  ? theme.textTheme.titleMedium
                  : theme.textTheme.titleLarge)
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          resumoRh.isEmpty ? 'Defina setor e funcao na aba Dados' : resumoRh,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: chips,
        ),
      ],
    );

    final metricas = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Liquido ref.',
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        Text(
          liquidoFormatado,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: scheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Prox. pag.: $proximoPagamentoFormatado',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );

    return Container(
      margin: EdgeInsets.only(bottom: compact ? 4 : 6),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final empilhar = constraints.maxWidth < 640;
          if (empilhar) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identidade,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerLeft, child: metricas),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: identidade),
              const SizedBox(width: 16),
              metricas,
            ],
          );
        },
      ),
    );
  }
}
