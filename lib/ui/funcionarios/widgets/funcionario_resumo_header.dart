import 'package:flutter/material.dart';

/// Faixa resumo do funcionario em edicao (estilo hub financeiro).
class FuncionarioResumoHeader extends StatelessWidget {
  const FuncionarioResumoHeader({
    super.key,
    required this.codigoController,
    required this.nomeController,
    required this.nomeFocus,
    required this.resumoRh,
    required this.tempoCasa,
    required this.liquidoFormatado,
    required this.proximoPagamentoFormatado,
    required this.ativo,
    required this.onAtivoChanged,
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
    this.larguraCodigo = 132,
    this.compact = false,
  });

  final TextEditingController codigoController;
  final TextEditingController nomeController;
  final FocusNode nomeFocus;
  final String resumoRh;
  final String tempoCasa;
  final String liquidoFormatado;
  final String proximoPagamentoFormatado;
  final bool ativo;
  final ValueChanged<bool> onAtivoChanged;
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
  final double larguraCodigo;
  final bool compact;

  double get _gap8 => compact ? 6 : 8;
  double get _gap12 => compact ? 8 : 12;
  double get _gap16 => compact ? 10 : 16;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nomeExibicao = nomeController.text.trim();
    final titulo = nomeExibicao.isEmpty ? 'Novo funcionario' : nomeExibicao;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.35),
            scheme.surfaceContainerHighest.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(compact ? 10 : 14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(_gap16, _gap12, _gap16, _gap12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        maxLines: compact ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: (compact
                                ? theme.textTheme.titleMedium
                                : theme.textTheme.titleLarge)
                            ?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 4),
                        Text(
                          resumoRh.isEmpty ? 'Defina setor e funcao' : resumoRh,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      SizedBox(height: compact ? 4 : 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _BadgeStatus(
                            rotulo: ativo ? 'Ativo' : 'Inativo',
                            cor: ativo ? scheme.primary : scheme.error,
                            bg: ativo
                                ? scheme.primaryContainer.withValues(alpha: 0.5)
                                : scheme.errorContainer.withValues(alpha: 0.4),
                          ),
                          _BadgeStatus(
                            rotulo: tempoCasa,
                            cor: scheme.onSurfaceVariant,
                            bg: scheme.surfaceContainerHighest,
                          ),
                          if (emEdicaoId != null)
                            _BadgeStatus(
                              rotulo: 'Registro #$emEdicaoId',
                              cor: scheme.secondary,
                              bg: scheme.secondaryContainer.withValues(alpha: 0.45),
                            ),
                          if (tambemVendedorPdv)
                            _BadgeStatus(
                              rotulo: vendedorVinculadoId > 0
                                  ? 'PDV #$vendedorVinculadoId'
                                  : 'Vendedor PDV',
                              cor: scheme.tertiary,
                              bg: scheme.tertiaryContainer.withValues(alpha: 0.45),
                            ),
                          if (tambemMotoristaEntrega)
                            _BadgeStatus(
                              rotulo: motoristaVinculadoId > 0
                                  ? 'Motorista #$motoristaVinculadoId'
                                  : 'Motorista',
                              cor: const Color(0xFF0277BD),
                              bg: const Color(0xFFE1F5FE),
                            ),
                          if (temUsuarioSistema)
                            _BadgeStatus(
                              rotulo: usuarioLogin != null && usuarioLogin!.isNotEmpty
                                  ? 'Login ${usuarioLogin!}'
                                  : 'Usuario ERP',
                              cor: scheme.secondary,
                              bg: scheme.secondaryContainer.withValues(alpha: 0.45),
                            ),
                          if (cnhVencida)
                            _BadgeStatus(
                              rotulo: 'CNH vencida',
                              cor: scheme.error,
                              bg: scheme.errorContainer.withValues(alpha: 0.35),
                            ),
                          if (asoVencido)
                            _BadgeStatus(
                              rotulo: 'ASO vencido',
                              cor: scheme.error,
                              bg: scheme.errorContainer.withValues(alpha: 0.35),
                            ),
                          if (!ativo && dataDemissaoFormatada != null)
                            _BadgeStatus(
                              rotulo: 'Demissao $dataDemissaoFormatada',
                              cor: scheme.error,
                              bg: scheme.errorContainer.withValues(alpha: 0.35),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: ativo,
                  onChanged: onAtivoChanged,
                ),
              ],
            ),
            SizedBox(height: _gap12),
            LayoutBuilder(
              builder: (context, constraints) {
                final empilhar = constraints.maxWidth < (compact ? 520 : 720);
                final codigoW = compact ? 112.0 : larguraCodigo;
                final campoCodigo = SizedBox(
                  width: codigoW,
                  child: TextField(
                    controller: codigoController,
                    decoration: const InputDecoration(
                      labelText: 'Codigo interno',
                      hintText: 'Ex.: 01',
                      isDense: true,
                      filled: true,
                    ),
                  ),
                );
                final campoNome = TextField(
                  focusNode: nomeFocus,
                  controller: nomeController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nome completo',
                    isDense: true,
                    filled: true,
                  ),
                );
                if (empilhar) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      campoCodigo,
                      SizedBox(height: _gap8),
                      campoNome,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    campoCodigo,
                    SizedBox(width: _gap16),
                    Expanded(child: campoNome),
                  ],
                );
              },
            ),
            SizedBox(height: _gap12),
            LayoutBuilder(
              builder: (context, c) {
                final coluna = c.maxWidth < (compact ? 480 : 560);
                final metricas = [
                  _MetricaResumo(
                    icone: Icons.account_balance_wallet_outlined,
                    rotulo: 'Liquido ref.',
                    valor: liquidoFormatado,
                    cor: const Color(0xFF1565C0),
                    compact: compact,
                  ),
                  _MetricaResumo(
                    icone: Icons.event_outlined,
                    rotulo: 'Prox. pagamento',
                    valor: proximoPagamentoFormatado,
                    cor: const Color(0xFF2E7D32),
                    compact: compact,
                  ),
                ];
                if (coluna) {
                  return Column(
                    children: [
                      metricas[0],
                      SizedBox(height: _gap8),
                      metricas[1],
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: metricas[0]),
                    const SizedBox(width: 10),
                    Expanded(child: metricas[1]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgeStatus extends StatelessWidget {
  const _BadgeStatus({
    required this.rotulo,
    required this.cor,
    required this.bg,
  });

  final String rotulo;
  final Color cor;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        rotulo,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cor,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _MetricaResumo extends StatelessWidget {
  const _MetricaResumo({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.cor,
    this.compact = false,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final Color cor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 7 : 10,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(compact ? 8 : 10),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: [
          Icon(icone, size: compact ? 18 : 20, color: cor),
          SizedBox(width: compact ? 8 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rotulo,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: compact ? 10 : null,
                  ),
                ),
                Text(
                  valor,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cor,
                    fontSize: compact ? 13 : null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
