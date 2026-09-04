import 'package:flutter/material.dart';

import '../domain/produto_embalagem.dart';
import '../domain/produto_unidade_exibicao.dart';
import '../domain/promocao_info_vigente.dart';
import '../domain/pdv_consulta_insights_service.dart';
import '../domain/pdv_consulta_multi_deposito_util.dart';
import '../domain/quantidade_venda_util.dart';
import '../model/produto.dart';
import 'produto_detalhe_venda_page.dart';
import 'widgets/pdv_consulta_painel_insights.dart';
import 'widgets/pdv_estoque_resumo_panel.dart';
import 'widgets/pdv_sugestoes_carrinho_strip.dart';
import 'widgets/produto_foto_view.dart';
import 'widgets/promocao_badge.dart';
import 'widgets/quantidade_pdv_input_formatter.dart';

/// Painel lateral (ou compacto) com foto e resumo do item selecionado na consulta PDV.
///
/// Os precos das 3 tabelas ficam nas colunas da lista da consulta (nao neste painel).
class PdvConsultaPreviewPanel extends StatelessWidget {
  const PdvConsultaPreviewPanel({
    super.key,
    required this.produto,
    required this.formatarMoeda,
    required this.onDetalhes,
    this.compacto = false,
    this.mostrarDescricaoInline = false,
    this.tituloPainel = 'Selecionado',
    this.campanhaPromo,
    this.quantidadeNoOrcamento = 0,
    this.precoUnitarioLinha,
    this.precoUnitarioManual = false,
    this.onAlterarPreco,
    this.mostrarAdicionarAoOrcamento = false,
    this.onQuantidadeChanged,
    this.onAdicionar,
    this.controlesQuantidadeKey,
    this.insights,
    this.onSelecionarSimilar,
    this.onInserirKit,
    this.onAdicionarAgregado,
    this.rotulosDeposito = const PdvConsultaDepositoRotulos(),
    this.sugestoesCarrinho = const [],
    this.sugestoesOrigemNome = '',
    this.onFecharSugestoesCarrinho,
    this.onAdicionarSugestaoCarrinho,
    this.imagesDirectoryPath = '',
  });

  final Produto produto;
  final String Function(double) formatarMoeda;
  final VoidCallback onDetalhes;
  final bool compacto;
  final bool mostrarDescricaoInline;
  final String tituloPainel;
  final PromocaoInfoVigente? campanhaPromo;
  final num quantidadeNoOrcamento;
  final double? precoUnitarioLinha;
  final bool precoUnitarioManual;
  final VoidCallback? onAlterarPreco;
  final bool mostrarAdicionarAoOrcamento;
  final ValueChanged<double>? onQuantidadeChanged;
  final VoidCallback? onAdicionar;
  final GlobalKey<PdvConsultaControlesAdicionarState>? controlesQuantidadeKey;
  final PdvConsultaInsightsPacote? insights;
  final ValueChanged<int>? onSelecionarSimilar;
  final ValueChanged<PdvConsultaKitResumo>? onInserirKit;
  final ValueChanged<PdvConsultaAgregadoVenda>? onAdicionarAgregado;
  final PdvConsultaDepositoRotulos rotulosDeposito;
  final List<PdvConsultaAgregadoVenda> sugestoesCarrinho;
  final String sugestoesOrigemNome;
  final VoidCallback? onFecharSugestoesCarrinho;
  final ValueChanged<PdvConsultaAgregadoVenda>? onAdicionarSugestaoCarrinho;
  final String imagesDirectoryPath;

  bool get _temSugestoesCarrinho =>
      sugestoesCarrinho.isNotEmpty && onAdicionarSugestaoCarrinho != null;

  bool get _usarAbasInsights =>
      insights != null && insights!.temConteudo;

  EdgeInsets get _paddingScroll => EdgeInsets.fromLTRB(
        compacto ? 12 : 14,
        12,
        compacto ? 12 : 14,
        12,
      );

  Widget _scrollArea(List<Widget> children) {
    return SingleChildScrollView(
      padding: _paddingScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget? _buildRodapeAdicionar(BuildContext context) {
    if (!mostrarAdicionarAoOrcamento ||
        onAdicionar == null ||
        onQuantidadeChanged == null) {
      return null;
    }
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: scheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            compacto ? 12 : 14,
            8,
            compacto ? 12 : 14,
            8,
          ),
          child: PdvConsultaControlesAdicionar(
            key: controlesQuantidadeKey,
            produto: produto,
            onQuantidadeChanged: onQuantidadeChanged!,
            onAdicionar: onAdicionar!,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final conteudoVenda = _buildConteudoVenda(context, theme, scheme);
    final rodape = _buildRodapeAdicionar(context);

    final Widget corpoScroll;
    if (_usarAbasInsights) {
      corpoScroll = DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: scheme.surfaceContainerLow,
              child: TabBar(
                labelColor: scheme.primary,
                unselectedLabelColor: scheme.onSurfaceVariant,
                indicatorColor: scheme.primary,
                tabs: const [
                  Tab(text: 'Venda'),
                  Tab(text: 'Insights'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _scrollArea(conteudoVenda),
                  _scrollArea([
                    PdvConsultaPainelInsights(
                      insights: insights!,
                      formatarMoeda: formatarMoeda,
                      onSelecionarSimilar: onSelecionarSimilar,
                      onInserirKit: onInserirKit,
                      onAdicionarAgregado: onAdicionarAgregado,
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      corpoScroll = _scrollArea([
        ...conteudoVenda,
        if (insights != null && insights!.temConteudo) ...[
          const SizedBox(height: 12),
          PdvConsultaPainelInsights(
            insights: insights!,
            formatarMoeda: formatarMoeda,
            onSelecionarSimilar: onSelecionarSimilar,
            onInserirKit: onInserirKit,
            onAdicionarAgregado: onAdicionarAgregado,
          ),
        ],
      ]);
    }

    return Material(
      color: scheme.surfaceContainerLow,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            left: compacto
                ? BorderSide.none
                : BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  ),
            bottom: compacto
                ? BorderSide(
                    color: scheme.outlineVariant.withValues(alpha: 0.7),
                  )
                : BorderSide.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: corpoScroll),
            ?rodape,
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConteudoVenda(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
  ) {
    final alturaFoto = compacto ? 140.0 : 200.0;

    return [
      Text(
        tituloPainel,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
      ),
      const SizedBox(height: 8),
      _FotoPreview(
        key: ValueKey<String>('pdv-consulta-foto-${produto.id}'),
        fotoPath: produto.fotoPath,
        imagesDirectoryPath: imagesDirectoryPath,
        altura: alturaFoto,
      ),
      const SizedBox(height: 10),
      Text(
        produto.nome,
        maxLines: compacto ? 2 : 4,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
      ),
      const SizedBox(height: 6),
      if (produto.codigoInterno.trim().isNotEmpty)
        Text(
          'SKU: ${produto.codigoInterno}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      const SizedBox(height: 2),
      Text(
        'Unidade: ${rotuloUnidadeProdutoLista(produto)}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w700,
            ),
      ),
      if (produto.codigoBarras.trim().isNotEmpty) ...[
        const SizedBox(height: 2),
        Text(
          'EAN: ${produto.codigoBarras}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
      // Precos das 3 tabelas ficam nas colunas da lista da consulta.
      if (campanhaPromo != null) ...[
        const SizedBox(height: 10),
        _PainelPromocaoVendedor(campanha: campanhaPromo!),
      ],
      if (precoUnitarioLinha != null) ...[
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: precoUnitarioManual
                ? scheme.tertiaryContainer.withValues(alpha: 0.45)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: precoUnitarioManual
                  ? scheme.tertiary
                  : scheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                precoUnitarioManual
                    ? 'Preco negociado nesta venda'
                    : 'Preco na linha do carrinho',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                formatarMoeda(precoUnitarioLinha!),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: precoUnitarioManual
                      ? scheme.tertiary
                      : scheme.onSurface,
                ),
              ),
              if (onAlterarPreco != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: onAlterarPreco,
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Alterar preco (Ctrl+P)'),
                ),
              ],
            ],
          ),
        ),
      ],
      if (produto.rotuloConversaoEmbalagem.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(
          produto.rotuloConversaoEmbalagem,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ],
      const SizedBox(height: 4),
      Text(
        'Quantidade decimal liberada no PDV (ex.: 4,50)',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
      ),
      const SizedBox(height: 8),
      PdvEstoqueResumoPanel(
        produto: produto,
        compacto: compacto,
        quantidadeNoOrcamento: quantidadeNoOrcamento,
        rotulosDeposito: rotulosDeposito,
      ),
      if (_temSugestoesCarrinho) ...[
        const SizedBox(height: 12),
        PdvSugestoesCarrinhoStrip(
          sugestoes: sugestoesCarrinho,
          formatarMoeda: formatarMoeda,
          produtoOrigemNome: sugestoesOrigemNome,
          onAdicionar: onAdicionarSugestaoCarrinho!,
          onFechar: onFecharSugestoesCarrinho ?? () {},
        ),
      ],
      if (mostrarDescricaoInline) ...[
        const SizedBox(height: 10),
        ProdutoDescricaoTecnicaInline(
          produto: produto,
          alturaMaxima: compacto ? 96 : 150,
          compacto: compacto,
        ),
      ],
      const SizedBox(height: 12),
      if (!mostrarDescricaoInline)
        FilledButton.tonalIcon(
          onPressed: onDetalhes,
          icon: const Icon(Icons.info_outline, size: 20),
          label: const Text('Detalhes (Espaco / F9)'),
        )
      else
        TextButton.icon(
          onPressed: onDetalhes,
          icon: const Icon(Icons.open_in_full, size: 18),
          label: const Text('Ampliar (Espaco / F9)'),
        ),
    ];
  }
}

/// Quantidade e botao adicionar (estado local evita reset do scroll do painel).
class PdvConsultaControlesAdicionar extends StatefulWidget {
  const PdvConsultaControlesAdicionar({
    super.key,
    required this.produto,
    required this.onQuantidadeChanged,
    required this.onAdicionar,
  });

  final Produto produto;
  final ValueChanged<double> onQuantidadeChanged;
  final VoidCallback onAdicionar;

  @override
  State<PdvConsultaControlesAdicionar> createState() =>
      PdvConsultaControlesAdicionarState();
}

class PdvConsultaControlesAdicionarState
    extends State<PdvConsultaControlesAdicionar> {
  static const double _max = 99999;

  late double _quantidade;
  late final TextEditingController _qtdController;

  bool get _emUnidadeCompra => widget.produto.pdvPodeVenderEmUnidadeCompra;

  bool get _fracionada => true;

  double get _min => 0.001;

  double get _passoBotoes => _emUnidadeCompra ? 1 : 0.01;

  String get _rotuloUnidadeQuantidade {
    if (_emUnidadeCompra) {
      return ProdutoEmbalagem.normalizarUnidade(
        widget.produto.unidadeCompraEfetiva,
      );
    }
    return ProdutoEmbalagem.normalizarUnidade(widget.produto.unidade);
  }

  String? get _dicaConversao {
    if (!_emUnidadeCompra) return null;
    final conv = widget.produto.rotuloConversaoEmbalagem;
    if (conv.isEmpty) return null;
    final m2 = ProdutoEmbalagem.quantidadeComercialParaUnidadeVenda(
      produto: widget.produto,
      quantidadeComercial: _quantidade,
    );
    final uVenda = ProdutoEmbalagem.normalizarUnidade(widget.produto.unidade);
    final m2Txt = m2 == m2.roundToDouble()
        ? m2.toStringAsFixed(0)
        : m2.toStringAsFixed(2).replaceAll('.', ',');
    final qTxt = QuantidadeVendaUtil.formatarExibicao(
      _quantidade,
      fracionada: true,
    );
    return '$qTxt $_rotuloUnidadeQuantidade = $m2Txt $uVenda no orcamento';
  }

  @override
  void initState() {
    super.initState();
    _quantidade = 1;
    _qtdController = TextEditingController(text: '1');
    widget.onQuantidadeChanged(_quantidade);
  }

  @override
  void dispose() {
    _qtdController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(PdvConsultaControlesAdicionar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produto.id != widget.produto.id) {
      setState(() {
        _quantidade = 1;
        _qtdController.text = '1';
      });
      widget.onQuantidadeChanged(_quantidade);
    }
  }

  double? quantidadeConfirmada() {
    return QuantidadeVendaUtil.parseEntradaPdv(
          _qtdController.text,
          fracionada: _fracionada,
        ) ??
        (_quantidade > 0 ? _quantidade : null);
  }

  void aplicarDelta(int delta) {
    final atual = QuantidadeVendaUtil.parseEntradaPdv(
          _qtdController.text,
          fracionada: _fracionada,
        ) ??
        _quantidade;
    _aplicar(atual + delta);
  }

  void _aplicar(double nova) {
    final q = nova.clamp(_min, _max);
    setState(() => _quantidade = q);
    final txt = QuantidadeVendaUtil.formatarExibicao(q, fracionada: _fracionada);
    _qtdController.value = TextEditingValue(
      text: txt,
      selection: TextSelection.collapsed(offset: txt.length),
    );
    widget.onQuantidadeChanged(q);
  }

  void _delta(double delta) {
    final atual = QuantidadeVendaUtil.parseEntradaPdv(
          _qtdController.text,
          fracionada: _fracionada,
        ) ??
        _quantidade;
    _aplicar(atual + delta);
  }

  void _onTextoQtd(String texto) {
    final q = QuantidadeVendaUtil.parseEntradaPdv(
      texto,
      fracionada: _fracionada,
    );
    if (q == null) return;
    if ((q - _quantidade).abs() < 0.0000001) return;
    setState(() => _quantidade = q);
    widget.onQuantidadeChanged(q);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final qAtual = QuantidadeVendaUtil.parseEntradaPdv(
          _qtdController.text,
          fracionada: _fracionada,
        ) ??
        _quantidade;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _emUnidadeCompra
              ? 'Quantidade ($_rotuloUnidadeQuantidade) (+ / − no teclado)'
              : 'Quantidade ($_rotuloUnidadeQuantidade) — aceita 5,75',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (_dicaConversao != null) ...[
          const SizedBox(height: 4),
          Text(
            _dicaConversao!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 6),
        DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Diminuir quantidade',
                  onPressed: qAtual > _min ? () => _delta(-_passoBotoes) : null,
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: TextField(
                    controller: _qtdController,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: _fracionada ? '5,75' : '1',
                    ),
                    keyboardType: _fracionada
                        ? const TextInputType.numberWithOptions(decimal: true)
                        : TextInputType.number,
                    inputFormatters: [
                      QuantidadePdvInputFormatter(fracionada: _fracionada),
                    ],
                    onChanged: _onTextoQtd,
                    onSubmitted: (_) => widget.onAdicionar(),
                    onTap: () => _qtdController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: _qtdController.text.length,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Aumentar quantidade',
                  onPressed: qAtual < _max ? () => _delta(_passoBotoes) : null,
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: widget.onAdicionar,
          icon: const Icon(Icons.add_shopping_cart_outlined),
          label: const Text('Adicionar (Enter)'),
        ),
      ],
    );
  }
}

/// Resumo da campanha para o vendedor repassar ao cliente (painel lateral / carrinho).
class _PainelPromocaoVendedor extends StatelessWidget {
  const _PainelPromocaoVendedor({required this.campanha});

  final PromocaoInfoVigente campanha;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PromocaoBadge.corDe(context).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: PromocaoBadge.corDe(context).withValues(alpha: 0.45),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PromocaoBadge(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  campanha.nome.isNotEmpty ? campanha.nome : 'Promocao',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: PromocaoBadge.corDe(context),
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            campanha.rotuloTipoCampanha,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          Text(
            campanha.resumoRegra,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            campanha.textoPrecoParaVendedor,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: PromocaoBadge.corDe(context),
                  height: 1.35,
                ),
          ),
          if (campanha.textoPrecoComplementar != null) ...[
            const SizedBox(height: 4),
            Text(
              campanha.textoPrecoComplementar!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
          if (campanha.margemMinimaPercentual > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Margem minima: ${campanha.margemMinimaPercentual.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.error,
                  ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FotoPreview extends StatelessWidget {
  const _FotoPreview({
    super.key,
    required this.fotoPath,
    required this.imagesDirectoryPath,
    required this.altura,
  });

  final String fotoPath;
  final String imagesDirectoryPath;
  final double altura;

  @override
  Widget build(BuildContext context) {
    return ProdutoFotoView(
      fotoPath: fotoPath,
      imagesDirectoryPath: imagesDirectoryPath,
      height: altura,
      width: double.infinity,
      fit: BoxFit.contain,
      borderRadius: BorderRadius.circular(8),
      placeholderLabel: 'Sem foto',
      errorLabel: 'Foto indisponivel',
      // Decode reduzido: preview ~300px evita bitmap full-res na UI thread.
      cacheWidth: 300,
      cacheHeight: 300,
      filterQuality: FilterQuality.medium,
    );
  }
}
