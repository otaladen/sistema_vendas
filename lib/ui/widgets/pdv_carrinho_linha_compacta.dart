import 'package:flutter/material.dart';

import 'pdv_botao_tabela_preco_item.dart';
import 'pdv_carrinho_campo_quantidade.dart';
import 'pdv_carrinho_linha_colunas.dart';
import 'pdv_mobile_ui.dart';
import 'pdv_tipo_entrega_item.dart';
import 'promocao_badge.dart';

/// Linha compacta do carrinho do PDV (~34px no desktop; densa no celular).
class PdvCarrinhoLinhaCompacta extends StatelessWidget {
  const PdvCarrinhoLinhaCompacta({
    super.key,
    required this.nomeProduto,
    this.codigoProduto = '',
    this.unidadeMedida = '',
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
    required this.onEditarQuantidade,
    required this.onDividir,
    required this.onAlterarPreco,
    required this.onRemover,
    this.emPromocao = false,
    this.botaFora = false,
    this.precoManual = false,
    this.alvosTouchAmplos = false,
    this.editandoQuantidade = false,
    this.quantidadeFracionada = false,
    this.quantidadeController,
    this.quantidadeFocus,
    this.onConfirmarQuantidade,
    this.exibirColunaUnitario = false,
  });

  final String nomeProduto;
  final String codigoProduto;
  final String unidadeMedida;
  final bool emPromocao;
  final bool botaFora;
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
  final VoidCallback onEditarQuantidade;
  final VoidCallback onDividir;
  final VoidCallback onAlterarPreco;
  final VoidCallback onRemover;
  final bool alvosTouchAmplos;
  final bool editandoQuantidade;
  final bool quantidadeFracionada;
  final TextEditingController? quantidadeController;
  final FocusNode? quantidadeFocus;
  final VoidCallback? onConfirmarQuantidade;
  final bool exibirColunaUnitario;

  static const double alturaLinha = PdvTipografia.alturaLinhaLista;
  static const double alturaLinhaTouch = 40;

  /// Duas faixas densas: nome+total / controles (~8 itens na tela tipica).
  static const double alturaLinhaCelular = 58;

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
    final minAcao = celular ? 32.0 : (alvosTouchAmplos ? 36.0 : 32.0);
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
                horizontal: PdvCarrinhoLinhaColunas.paddingHorizontal,
                vertical: celular ? 3 : 4,
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

  String get _codigoExibicao => codigoProduto.trim();

  Widget _buildBotaoEntrega() {
    return PdvBotaoTipoEntregaItem(
      compacto: true,
      tipoEntregaItem: tipoEntregaItem,
      onPressed: onAlternarTipoEntrega,
    );
  }

  Widget _buildColunaCodigo(ThemeData theme, ColorScheme scheme) {
    final codigo = _codigoExibicao;
    if (codigo.isEmpty) return const SizedBox.shrink();

    return Text(
      '#$codigo',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w500,
        fontSize: PdvTipografia.listaMeta,
        height: 1.1,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.82),
      ),
    );
  }

  Widget _buildColunaUnidadeMedida(ThemeData theme, ColorScheme scheme) {
    final unidade = unidadeMedida.trim();
    if (unidade.isEmpty) return const SizedBox.shrink();

    return Text(
      unidade,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: theme.textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: PdvTipografia.listaMeta,
        height: 1.1,
        color: scheme.onSurfaceVariant.withValues(alpha: 0.88),
      ),
    );
  }

  Widget _buildNomeProduto(ThemeData theme, {required double fontSize}) {
    return Text(
      nomeProduto,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: fontSize,
        height: 1.1,
      ),
    );
  }

  /// [badges status] + [nome].
  Widget _buildLinhaIdentificacaoProduto(
    ThemeData theme,
    ColorScheme scheme, {
    required double fontSizeNome,
    bool incluirEntrega = false,
  }) {
    return Row(
      children: [
        if (incluirEntrega) _buildBotaoEntrega(),
        _buildBadges(scheme),
        Expanded(child: _buildNomeProduto(theme, fontSize: fontSizeNome)),
      ],
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
            _buildBotaoEntrega(),
            SizedBox(
              width: PdvCarrinhoLinhaColunas.larguraCodigo,
              child: Center(child: _buildColunaCodigo(theme, scheme)),
            ),
            SizedBox(
              width: PdvCarrinhoLinhaColunas.larguraUnidadeMedida,
              child: Center(child: _buildColunaUnidadeMedida(theme, scheme)),
            ),
            Expanded(
              child: _buildLinhaIdentificacaoProduto(
                theme,
                scheme,
                fontSizeNome: PdvTipografia.listaNome,
              ),
            ),
            const SizedBox(width: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: InkWell(
                onTap: onAlterarPreco,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 1, vertical: 1),
                  child: Text(
                    subtotalFormatado,
                    maxLines: 1,
                    softWrap: false,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: PdvTipografia.listaValor,
                      color: precoManual ? scheme.tertiary : null,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: Text(
                precoUnitarioFormatado,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      precoManual ? scheme.tertiary : scheme.onSurfaceVariant,
                  fontWeight: precoManual ? FontWeight.w700 : FontWeight.w500,
                  fontSize: PdvTipografia.listaSecundario,
                  height: 1.0,
                ),
              ),
            ),
            _AcaoIcone(
              tooltip: 'Diminuir',
              icon: Icons.remove,
              onPressed: editandoQuantidade ? null : onDiminuir,
              tamanhoMinimo: minAcao,
            ),
            SizedBox(
              width: PdvCarrinhoLinhaColunas.larguraCampoQuantidade,
              child: Center(
                child: PdvCarrinhoCampoQuantidade(
                  quantidadeExibicao: quantidadeExibicao,
                  editando: editandoQuantidade,
                  fracionada: quantidadeFracionada,
                  onTapEditar: onEditarQuantidade,
                  onConfirmar: onConfirmarQuantidade ?? onEditarQuantidade,
                  controller: quantidadeController,
                  focusNode: quantidadeFocus,
                  textStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: PdvTipografia.listaQuantidade,
                    height: 1.0,
                  ),
                ),
              ),
            ),
            _AcaoIcone(
              tooltip: 'Aumentar',
              icon: Icons.add,
              onPressed: editandoQuantidade ? null : onAumentar,
              tamanhoMinimo: minAcao,
            ),
            PdvBotaoTabelaPrecoItem(
              compacto: true,
              precoTipo: precoTipo,
              onPressed: onAlternarTabelaPreco,
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
    final minAcaoQtd = PdvCarrinhoLinhaColunas.minAcaoQuantidadeDe(
      alvosTouchAmplos: alvosTouchAmplos,
    );

    return PdvCarrinhoLinhaColunas.linha(
      entrega: _buildBotaoEntrega(),
      codigo: _buildColunaCodigo(theme, scheme),
      unidadeMedida: _buildColunaUnidadeMedida(theme, scheme),
      produto: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLinhaIdentificacaoProduto(
            theme,
            scheme,
            fontSizeNome: PdvTipografia.listaNome,
          ),
          if (!exibirColunaUnitario)
            Text(
              precoUnitarioFormatado,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: precoManual
                    ? scheme.tertiary
                    : scheme.onSurfaceVariant,
                fontWeight:
                    precoManual ? FontWeight.w700 : FontWeight.normal,
                fontSize: PdvTipografia.listaSecundario,
                height: 1.0,
              ),
            ),
        ],
      ),
      unitario: exibirColunaUnitario
          ? InkWell(
              onTap: onAlterarPreco,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
                child: Text(
                  precoUnitarioFormatado,
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: PdvTipografia.listaSecundario,
                    height: 1.0,
                    color: precoManual
                        ? scheme.tertiary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : null,
      subtotal: InkWell(
        onTap: onAlterarPreco,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 2),
          child: Text(
            subtotalFormatado,
            maxLines: 1,
            softWrap: false,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: PdvTipografia.listaValor,
              height: 1.0,
              color: precoManual ? scheme.tertiary : null,
            ),
          ),
        ),
      ),
      grupoQuantidade: PdvCarrinhoLinhaColunas.grupoQuantidadeDe(
        alvosTouchAmplos: alvosTouchAmplos,
        diminuir: _AcaoIcone(
          tooltip: 'Diminuir',
          icon: Icons.remove,
          onPressed: editandoQuantidade ? null : onDiminuir,
          tamanhoMinimo: minAcaoQtd,
        ),
        quantidade: PdvCarrinhoCampoQuantidade(
          quantidadeExibicao: quantidadeExibicao,
          editando: editandoQuantidade,
          fracionada: quantidadeFracionada,
          onTapEditar: onEditarQuantidade,
          onConfirmar: onConfirmarQuantidade ?? onEditarQuantidade,
          controller: quantidadeController,
          focusNode: quantidadeFocus,
          textStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: PdvTipografia.listaQuantidade,
            height: 1.0,
          ),
        ),
        aumentar: _AcaoIcone(
          tooltip: 'Aumentar',
          icon: Icons.add,
          onPressed: editandoQuantidade ? null : onAumentar,
          tamanhoMinimo: minAcaoQtd,
        ),
      ),
      tabelaPreco: PdvBotaoTabelaPrecoItem(
        compacto: true,
        precoTipo: precoTipo,
        onPressed: onAlternarTabelaPreco,
      ),
      acoes: PdvCarrinhoLinhaColunas.acoesDe(
        alvosTouchAmplos: alvosTouchAmplos,
        dividir: _AcaoIcone(
          tooltip: quantidadeArmazenada > 1
              ? 'Dividir item (Ctrl+D)'
              : 'Dividir item (min. 2 un.)',
          icon: Icons.call_split,
          onPressed: quantidadeArmazenada > 1 ? onDividir : null,
          tamanhoMinimo: minAcao,
        ),
        remover: _AcaoIcone(
          tooltip: 'Remover item',
          icon: Icons.delete_outline,
          cor: scheme.error,
          onPressed: onRemover,
          tamanhoMinimo: minAcao,
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
    this.tamanhoMinimo = 32,
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
      icon: Icon(icon, size: tamanhoMinimo >= 36 ? 18 : 16, color: cor),
      onPressed: onPressed,
    );
  }
}
