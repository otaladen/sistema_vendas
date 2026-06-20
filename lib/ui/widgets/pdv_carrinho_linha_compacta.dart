import 'package:flutter/material.dart';

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
    required this.quantidade,
    this.detalheQuantidade,
    this.rotuloUnidade,
    required this.tipoEntregaItem,
    required this.selecionado,
    this.linhaImpar = false,
    required this.onTap,
    required this.onAlternarTipoEntrega,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onDividir,
    required this.onAlterarPreco,
    required this.onRemover,
    this.emPromocao = false,
    this.estoqueInsuficiente = false,
    this.precoManual = false,
  });

  final String nomeProduto;
  final bool emPromocao;
  final bool estoqueInsuficiente;
  final bool precoManual;
  final String rotuloPreco;
  final String precoUnitarioFormatado;
  final String subtotalFormatado;
  final int quantidade;
  final String? detalheQuantidade;
  final String? rotuloUnidade;
  final String tipoEntregaItem;
  final bool selecionado;
  final bool linhaImpar;
  final VoidCallback onTap;
  final VoidCallback onAlternarTipoEntrega;
  final VoidCallback onDiminuir;
  final VoidCallback onAumentar;
  final VoidCallback onDividir;
  final VoidCallback onAlterarPreco;
  final VoidCallback onRemover;

  static const double alturaLinha = 52;

  String _linhaQuantidadeUnidade() {
    final un = rotuloUnidade?.trim();
    if (un != null && un.isNotEmpty) {
      return '$quantidade $un × $precoUnitarioFormatado';
    }
    return '$quantidade × $precoUnitarioFormatado';
  }

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
            height: alturaLinha,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                children: [
                  PdvBotaoTipoEntregaItem(
                    compacto: true,
                    tipoEntregaItem: tipoEntregaItem,
                    onPressed: onAlternarTipoEntrega,
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
                          detalheQuantidade != null
                              ? '$detalheQuantidade · $precoUnitarioFormatado/$rotuloPreco'
                              : '${_linhaQuantidadeUnidade()} · $rotuloPreco',
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
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Text(
                      '$quantidade',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _AcaoIcone(
                    tooltip: 'Aumentar',
                    icon: Icons.add,
                    onPressed: onAumentar,
                  ),
                  _AcaoIcone(
                    tooltip: quantidade > 1
                        ? 'Dividir item (Ctrl+D)'
                        : 'Dividir item (min. 2 un.)',
                    icon: Icons.call_split,
                    onPressed: quantidade > 1 ? onDividir : null,
                  ),
                  _AcaoIcone(
                    tooltip: 'Remover item',
                    icon: Icons.delete_outline,
                    cor: scheme.error,
                    onPressed: onRemover,
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
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? cor;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
      icon: Icon(icon, size: 18, color: cor),
      onPressed: onPressed,
    );
  }
}
