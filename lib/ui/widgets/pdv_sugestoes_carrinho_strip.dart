import 'package:flutter/material.dart';

import '../../domain/pdv_consulta_insights_service.dart';

/// Faixa discreta de sugestoes agregadas apos adicionar item ao carrinho (Fase 2).
class PdvSugestoesCarrinhoStrip extends StatelessWidget {
  const PdvSugestoesCarrinhoStrip({
    super.key,
    required this.produtoOrigemNome,
    required this.sugestoes,
    required this.formatarMoeda,
    required this.onAdicionar,
    required this.onFechar,
  });

  final String produtoOrigemNome;
  final List<PdvConsultaAgregadoVenda> sugestoes;
  final String Function(double) formatarMoeda;
  final ValueChanged<PdvConsultaAgregadoVenda> onAdicionar;
  final VoidCallback onFechar;

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
                    'Ofereca tambem — $produtoOrigemNome',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
    final detalhe = agregado.detalheLinha(formatarMoeda);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAdicionar,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
          child: Row(
            children: [
              Expanded(
                child: RichText(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    children: [
                      TextSpan(text: agregado.nome),
                      TextSpan(
                        text: ' · $detalhe',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: agregado.semEstoque
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Icon(
                Icons.add,
                size: 16,
                color: scheme.primary.withValues(alpha: 0.9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
