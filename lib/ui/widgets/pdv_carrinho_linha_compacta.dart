import 'package:flutter/material.dart';

import 'pdv_botao_tabela_preco_item.dart';
import 'pdv_mobile_ui.dart';
import 'pdv_tipo_entrega_item.dart';
import 'promocao_badge.dart';

/// Linha compacta do carrinho do PDV (~52px no desktop; densa no celular).
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
    required this.onTap,
    required this.onAlternarTipoEntrega,
    required this.onAlternarTabelaPreco,
    required this.onDiminuir,
    required this.onAumentar,
    required this.onDividir,
    required this.onAlterarPreco,
    required this.onRemover,
    this.emPromocao = false,
    this.botaFora = false,
    this.estoqueInsuficiente = false,
    this.precoManual = false,
    this.alvosTouchAmplos = false,
  });

  final String nomeProduto;
  final bool emPromocao;
  final bool botaFora;
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

  /// Duas faixas densas: nome+total / controles (~6 itens na tela tipica).
  static const double alturaLinhaCelular = 72;

  static double alturaParaLista({required bool alvosTouchAmplos}) {
    if (pdvPlataformaCelular) return alturaLinhaCelular;
    return alvosTouchAmplos ? alturaLinhaTouch : alturaLinha;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fundoTipo = PdvBotaoTipoEntregaItem.fundoPara(context, tipoEntregaItem);
    final bordaTipo = PdvBotaoTipoEntregaItem.bordaPara(context, tipoEntregaItem);
    final bg = selecionado
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.14),
            fundoTipo,
          )
        : fundoTipo;
    final borda = selecionado
        ? scheme.primary.withValues(alpha: 0.45)
        : bordaTipo.withValues(alpha: 0.85);
    final celular = pdvPlataformaCelular;
    final minAcao = celular ? 36.0 : (alvosTouchAmplos ? 44.0 : 40.0);
    final altura = alturaParaLista(alvosTouchAmplos: alvosTouchAmplos);

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: borda),
              left: BorderSide(
                color: selecionado ? scheme.primary : bordaTipo,
                width: selecionado ? 3 : 4,
              ),
            ),
          ),
          child: SizedBox(
            height: altura,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: celular ? 6 : 2,
                vertical: celular ? 4 : 0,
              ),
              child: celular
                  ? _buildLeiauteCelular(theme, scheme, minAcao)
                  : _buildLeiauteDesktop(theme, scheme, minAcao),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadges(ColorScheme scheme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (emPromocao) ...[
          const PromocaoBadge(compacto: true),
          const SizedBox(width: 4),
        ],
        if (botaFora) ...[
          Tooltip(
            message: 'Desconto automatico Bota-Fora (lote critico)',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Bota-fora',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
        if (estoqueInsuficiente) ...[
          Tooltip(
            message:
                'Quantidade no orcamento acima do estoque disponivel',
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
      ],
    );
  }

  /// Celular denso: nome+total em cima; entrega/qtd/acoes embaixo.
  Widget _buildLeiauteCelular(
    ThemeData theme,
    ColorScheme scheme,
    double minAcao,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _buildBadges(scheme),
            Expanded(
              child: Text(
                nomeProduto,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(width: 6),
            InkWell(
              onTap: onAlterarPreco,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Text(
                  subtotalFormatado,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: precoManual ? scheme.tertiary : null,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
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
              child: Text(
                '$rotuloQuantidadeLinha · $precoUnitarioFormatado/$rotuloPreco',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      precoManual ? scheme.tertiary : scheme.onSurfaceVariant,
                  fontWeight: precoManual ? FontWeight.w700 : FontWeight.w500,
                  height: 1.0,
                ),
              ),
            ),
            _AcaoIcone(
              tooltip: 'Diminuir',
              icon: Icons.remove,
              onPressed: onDiminuir,
              tamanhoMinimo: minAcao,
            ),
            Text(
              quantidadeExibicao,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            _AcaoIcone(
              tooltip: 'Aumentar',
              icon: Icons.add,
              onPressed: onAumentar,
              tamanhoMinimo: minAcao,
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais',
              padding: EdgeInsets.zero,
              constraints: BoxConstraints(
                minWidth: minAcao,
                minHeight: minAcao,
              ),
              onSelected: (v) {
                switch (v) {
                  case 'dividir':
                    onDividir();
                  case 'remover':
                    onRemover();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'dividir',
                  enabled: quantidadeArmazenada > 1,
                  child: Text(
                    quantidadeArmazenada > 1
                        ? 'Dividir item'
                        : 'Dividir (min. 2 un.)',
                  ),
                ),
                const PopupMenuItem(
                  value: 'remover',
                  child: Text('Remover item'),
                ),
              ],
              child: SizedBox(
                width: minAcao,
                height: minAcao,
                child: Icon(
                  Icons.more_vert,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLeiauteDesktop(
    ThemeData theme,
    ColorScheme scheme,
    double minAcao,
  ) {
    return Row(
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
                  _buildBadges(scheme),
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
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
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
