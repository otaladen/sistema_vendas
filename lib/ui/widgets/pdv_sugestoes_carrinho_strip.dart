import 'package:flutter/material.dart';

import '../../domain/pdv_consulta_insights_service.dart';

/// Faixa discreta de sugestoes agregadas apos adicionar item ao carrinho (Fase 2).
class PdvSugestoesCarrinhoStrip extends StatelessWidget {
  const PdvSugestoesCarrinhoStrip({
    super.key,
    required this.sugestoes,
    required this.formatarMoeda,
    required this.onAdicionar,
    required this.onFechar,
    this.produtoOrigemNome,
  });

  final List<PdvConsultaAgregadoVenda> sugestoes;
  final String Function(double) formatarMoeda;
  final ValueChanged<PdvConsultaAgregadoVenda> onAdicionar;
  final VoidCallback onFechar;
  /// Produto que gerou as sugestoes (ex.: item recém-adicionado).
  final String? produtoOrigemNome;

  @override
  Widget build(BuildContext context) {
    if (sugestoes.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.22),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Ofereca tambem',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  onPressed: onFechar,
                  icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
            if (produtoOrigemNome != null &&
                produtoOrigemNome!.trim().isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                'Com: ${produtoOrigemNome!.trim()}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            for (var i = 0; i < sugestoes.length; i++) ...[
              if (i > 0) const SizedBox(height: 2),
              _LinhaSugestao(
                agregado: sugestoes[i],
                formatarMoeda: formatarMoeda,
                onAdicionar: () => onAdicionar(sugestoes[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaSugestao extends StatelessWidget {
  const _LinhaSugestao({
    required this.agregado,
    required this.formatarMoeda,
    required this.onAdicionar,
  });

  final PdvConsultaAgregadoVenda agregado;
  final String Function(double) formatarMoeda;
  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final badge = agregado.badgeFaixaCarrinho();
    final subtitulo = agregado.subtituloFaixaCarrinho(formatarMoeda);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAdicionar,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (badge != null) ...[
                          _BadgeOrigem(rotulo: badge),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            agregado.nome,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      subtitulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: agregado.semEstoque
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                        fontWeight:
                            agregado.semEstoque ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.add,
                size: 18,
                color: scheme.primary.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeOrigem extends StatelessWidget {
  const _BadgeOrigem({required this.rotulo});

  final String rotulo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        rotulo,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800,
          fontSize: 10,
        ),
      ),
    );
  }
}
