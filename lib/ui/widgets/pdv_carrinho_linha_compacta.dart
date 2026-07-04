import 'package:flutter/material.dart';

import 'pdv_botao_tabela_preco_item.dart';
import 'pdv_tipo_entrega_item.dart';
import 'promocao_badge.dart';

/// Linha compacta do carrinho do PDV (~52px).
class PdvCarrinhoLinhaCompacta extends StatelessWidget {
  const PdvCarrinhoLinhaCompacta({
    super.key,
    required this.nomeProduto,
    required this.rotuloPreco,
    required this.precoUnitarioFormatado,
    required this.subtotalFormatado,
    required this.quantidadeExibicao,
    required this.quantidadeArmazenada,
    required this.rotuloQuantidadeLinha,
    required this.tipoEntregaItem,
    required this.precoTipo,
    required this.selecionado,
    this.linhaImpar = false,
    required this.onTap,
    required this.onAlternarTipoEntrega,
    required this.onAlternarTabelaPreco,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onDividir,
    required this.onAlterarPreco,
    required this.onRemover,
    this.emPromocao = false,
    this.estoqueInsuficiente = false,
    this.precoManual = false,
    this.alvosTouchAmplos = false,
  });

  final String nomeProduto;
  final bool emPromocao;
  final bool estoqueInsuficiente;
  final bool precoManual;
  final String rotuloPreco;
  final String precoUnitarioFormatado;
  final String subtotalFormatado;
  final String quantidadeExibicao;
  final int quantidadeArmazenada;
  final String rotuloQuantidadeLinha;
  final String tipoEntregaItem;
  final String precoTipo;
  final bool selecionado;
  final bool linhaImpar;
  final VoidCallback onTap;
  final VoidCallback onAlternarTipoEntrega;
  final VoidCallback onAlternarTabelaPreco;
  final VoidCallback onDiminuir;
  final VoidCallback onAumentar;
  final VoidCallback onDividir;
  final VoidCallback onAlterarPreco;
  final VoidCallback onRemover;
  final bool alvosTouchAmplos;

  static const double alturaLinha = 52;
  static const double alturaLinhaTouch = 56;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = selecionado
        ? scheme.primaryContainer.withValues(alpha: 0.45)
        : (linhaImpar ? scheme.surfaceContainerLow : scheme.surface);
    final borda = selecionado
        ? scheme.primary.withValues(alpha: 0.4)
        : scheme.outlineVariant.withValues(alpha: 0.35);
    final minAcao = alvosTouchAmplos ? 44.0 : 40.0;
    final altura = alvosTouchAmplos ? alturaLinhaTouch : alturaLinha;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borda),
              left: selecionado
                  ? BorderSide(color: scheme.primary, width: 3)
                  : BorderSide.none,
            ),
          ),
          child: SizedBox(
            height: altura,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  PdvBotaoTipoEntregaItem(
                    compacto: true,
                    tipoEntregaItem: tipoEntregaItem,
                    onPressed: onAlternarTipoEntrega,
                  ),
                  PdvBotaoTabelaPrecoItem(
                    compacto: true,
                    precoTipo: precoTipo,
                    onPressed: onAlternarTabelaPreco,
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (emPromocao) ...[
                              const PromocaoBadge(compacto: true),
                              const SizedBox(width: 4),
                            ],
                            if (estoqueInsuficiente) ...[
                              Tooltip(
                                message: 'Quantidade no orcamento acima do estoque disponivel',
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  size: 16,
                                  color: scheme.error,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            if (precoManual) ...[
                              Tooltip(
                                message: 'Preco negociado manualmente',
                                child: Icon(
                                  Icons.price_change_outlined,
                                  size: 16,
                                  color: scheme.tertiary,
                                ),
                              ),
                              const SizedBox(width: 4),
                            ],
                            Expanded(
                              child: Text(
                                nomeProduto,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '$rotuloQuantidadeLinha · $precoUnitarioFormatado/$rotuloPreco',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: precoManual
                                ? scheme.tertiary
                                : scheme.onSurfaceVariant,
                            fontWeight:
                                precoManual ? FontWeight.w700 : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: onAlterarPreco,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 2,
                        ),
                        child: Text(
                          subtotalFormatado,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: precoManual ? scheme.tertiary : null,
                          ),
                        ),
                      ),
                    ),
                  ),
                  _AcaoIcone(
                    tooltip: 'Diminuir',
                    icon: Icons.remove,
                    onPressed: onDiminuir,
                    tamanhoMinimo: minAcao,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      quantidadeExibicao,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _AcaoIcone(
                    tooltip: 'Aumentar',
                    icon: Icons.add,
                    onPressed: onAumentar,
                    tamanhoMinimo: minAcao,
                  ),
                  _AcaoIcone(
                    tooltip: quantidadeArmazenada > 1
                        ? 'Dividir item (Ctrl+D)'
                        : 'Dividir item (min. 2 un.)',
                    icon: Icons.call_split,
                    onPressed: quantidadeArmazenada > 1 ? onDividir : null,
                    tamanhoMinimo: minAcao,
                  ),
                  _AcaoIcone(
                    tooltip: 'Remover item',
                    icon: Icons.delete_outline,
                    cor: scheme.error,
                    onPressed: onRemover,
                    tamanhoMinimo: minAcao,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

class _AcaoIcone extends StatelessWidget {
  const _AcaoIcone({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.cor,
    this.tamanhoMinimo = 40,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? cor;
  final double tamanhoMinimo;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints(
        minWidth: tamanhoMinimo,
        minHeight: tamanhoMinimo,
      ),
      icon: Icon(icon, size: tamanhoMinimo >= 40 ? 20 : 18, color: cor),
      onPressed: onPressed,
    );
  }
}
