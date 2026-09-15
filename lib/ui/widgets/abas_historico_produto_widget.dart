import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../data/api/produto_api_repository.dart';
import '../../domain/produto_embalagem.dart';
import '../../model/historico_entrada.dart';
import '../../model/produto.dart';
import '../shell/main_menu_deps.dart';
import '../theme/app_semantic_helper.dart';
import 'lan_api_feedback.dart';
import 'nfe_importada_detalhe_launcher.dart';

/// Aba com historico de compras (NF-e) do produto, mais recente primeiro.
class AbasHistoricoProdutoWidget extends StatefulWidget {
  const AbasHistoricoProdutoWidget({
    super.key,
    required this.produtoRepository,
    required this.produtoId,
    this.produto,
  });

  /// [ProdutoRepository] local ou API no terminal leve.
  final dynamic produtoRepository;
  final int? produtoId;

  /// Cadastro atual (unidade de estoque / embalagem para formatacao).
  final Produto? produto;

  @override
  State<AbasHistoricoProdutoWidget> createState() =>
      _AbasHistoricoProdutoWidgetState();
}

class _AbasHistoricoProdutoWidgetState extends State<AbasHistoricoProdutoWidget> {
  static final _nfData = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _nfMoeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  static final _nfQtd = NumberFormat('#,##0.###', 'pt_BR');

  List<HistoricoEntrada> _lista = const [];
  bool _carregando = true;

  Produto? get _produto {
    if (widget.produto != null) return widget.produto;
    final id = widget.produtoId;
    if (id == null || id <= 0) return null;
    try {
      return widget.produtoRepository.obterPorId(id) as Produto?;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  @override
  void didUpdateWidget(covariant AbasHistoricoProdutoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.produtoId != widget.produtoId ||
        oldWidget.produto?.id != widget.produto?.id) {
      _recarregar();
    }
  }

  void _recarregar() {
    final id = widget.produtoId;
    if (id == null || id == 0) {
      setState(() {
        _lista = const [];
        _carregando = false;
      });
      return;
    }
    setState(() => _carregando = true);
    final repo = widget.produtoRepository;
    if (repo is ProdutoApiRepository) {
      () async {
        try {
          final itens = await repo.listarHistoricoEntradaPorProdutoRemoto(id);
          if (!mounted) return;
          setState(() {
            _lista = itens;
            _carregando = false;
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _lista = const [];
            _carregando = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(LanApiFeedback.mensagem(e))),
          );
        }
      }();
      return;
    }
    List<HistoricoEntrada> itens = const [];
    try {
      final raw = repo.listarHistoricoEntradaPorProduto(id);
      if (raw is List<HistoricoEntrada>) {
        itens = raw;
      } else if (raw is List) {
        itens = raw.whereType<HistoricoEntrada>().toList();
      }
    } catch (_) {
      itens = const [];
    }
    setState(() {
      _lista = itens;
      _carregando = false;
    });
  }

  double? _variacaoPctCompraAnterior(int index) {
    if (index >= _lista.length - 1) return null;
    final atual = _lista[index];
    final anterior = _lista[index + 1];
    if (anterior.precoCustoUnitarioNota <= 0) return null;
    return (atual.precoCustoUnitarioNota - anterior.precoCustoUnitarioNota) /
        anterior.precoCustoUnitarioNota *
        100;
  }

  int _quantidadeEntradaNormalizada(HistoricoEntrada h) {
    final p = _produto;
    if (p == null) return h.quantidadeEntradaEstoque;
    return ProdutoEmbalagem.quantidadeEntradaHistoricoNormalizada(
      produto: p,
      quantidadeEntradaArmazenada: h.quantidadeEntradaEstoque,
      quantidadeFornecedor: h.quantidadeFornecedor,
      fatorConversaoUtilizado: h.fatorConversaoUtilizado,
      unidadeFornecedor: h.unidadeFornecedor,
    );
  }

  double _custoMedioPonderado() {
    var totalQtd = 0;
    var totalValor = 0.0;
    for (final h in _lista) {
      final qtd = _quantidadeEntradaNormalizada(h);
      if (qtd <= 0 || h.precoCustoUnitarioNota <= 0) {
        continue;
      }
      totalQtd += qtd;
      totalValor += qtd * h.precoCustoUnitarioNota;
    }
    if (totalQtd <= 0) return 0;
    return totalValor / totalQtd;
  }

  int _totalCompradoArmazenado() {
    var s = 0;
    for (final h in _lista) {
      s += _quantidadeEntradaNormalizada(h);
    }
    return s;
  }

  String _textoEstoqueEntrada(HistoricoEntrada h) {
    return ProdutoEmbalagem.formatarQuantidadeEntradaHistorico(
      produto: _produto,
      quantidadeEntradaArmazenada: h.quantidadeEntradaEstoque,
      quantidadeFornecedor: h.quantidadeFornecedor,
      fatorConversaoUtilizado: h.fatorConversaoUtilizado,
      unidadeFornecedor: h.unidadeFornecedor,
      comUnidade: true,
    );
  }

  String _textoTotalComprado() {
    final total = _totalCompradoArmazenado();
    final p = _produto;
    if (p != null) {
      return ProdutoEmbalagem.formatarEstoque(p, total, comUnidade: true);
    }
    return _nfQtd.format(total);
  }

  Future<void> _abrirNfeEntrada(HistoricoEntrada h) async {
    await NfeImportadaDetalheLauncher.abrirPorHistoricoEntrada(
      context,
      entrada: h,
      produtoRepository: widget.produtoRepository,
      nfeImportadaRepository:
          MainMenuDeps.maybeOf(context)?.nfeImportadaRepository,
      onImportacaoAlterada: _recarregar,
    );
  }

  void _copiarChaveNf(HistoricoEntrada h) {
    final chave = h.chaveAcesso.trim();
    if (chave.isEmpty) return;
    Clipboard.setData(ClipboardData(text: chave));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Chave da NF-e copiada'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.produtoId == null || widget.produtoId == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Salve o produto ou pesquise um cadastro existente para ver o historico de compras.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }

    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_lista.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: _HistoricoComprasEmptyState(),
        ),
      );
    }

    return SizedBox.expand(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PainelKpiCompras(
              ultimoCusto: _lista.first.precoCustoUnitarioNota,
              custoMedio: _custoMedioPonderado(),
              variacaoUltimaCompraPct: _variacaoPctCompraAnterior(0),
              totalComprado: _textoTotalComprado(),
              entradas: _lista.length,
            ),
            const SizedBox(height: 14),
            Expanded(
              child: _TabelaHistoricoCompras(
                lista: _lista,
                formatarData: (d) => _nfData.format(d.toLocal()),
                formatarMoeda: (v) => _nfMoeda.format(v),
                formatarQtdNota: (h) =>
                    '${_nfQtd.format(h.quantidadeFornecedor)} ${h.unidadeFornecedor}'
                        .trim(),
                formatarEstoqueEntrada: _textoEstoqueEntrada,
                variacaoPct: _variacaoPctCompraAnterior,
                onAbrirNfeEntrada: _abrirNfeEntrada,
                onCopiarChaveNf: _copiarChaveNf,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoricoComprasEmptyState extends StatelessWidget {
  const _HistoricoComprasEmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              size: 36,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Nenhuma compra registrada',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Entradas por NF-e de compra aparecem aqui com fornecedor, '
            'quantidade e custo unitario de cada aquisicao.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.35,
                ),
          ),
        ],
      ),
    );
  }
}

class _PainelKpiCompras extends StatelessWidget {
  const _PainelKpiCompras({
    required this.ultimoCusto,
    required this.custoMedio,
    required this.variacaoUltimaCompraPct,
    required this.totalComprado,
    required this.entradas,
  });

  final double ultimoCusto;
  final double custoMedio;
  final double? variacaoUltimaCompraPct;
  final String totalComprado;
  final int entradas;

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final scheme = Theme.of(context).colorScheme;

    String detalheVariacao = 'Primeira compra no historico';
    Color corVar = scheme.onSurfaceVariant;
    Color bgVar = scheme.surfaceContainerHighest;
    String valorVar = '—';
    if (variacaoUltimaCompraPct != null) {
      final pct = variacaoUltimaCompraPct!;
      valorVar =
          '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1).replaceAll('.', ',')}%';
      detalheVariacao = 'vs. compra anterior';
      if (pct > 0.5) {
        corVar = semantic.errorFg;
        bgVar = semantic.errorBg;
      } else if (pct < -0.5) {
        corVar = semantic.successFg;
        bgVar = semantic.successBg;
      } else {
        corVar = scheme.onSurfaceVariant;
        bgVar = scheme.surfaceContainerHighest;
      }
    }

    final cards = [
      _KpiCompraMini(
        icone: Icons.payments_outlined,
        rotulo: 'Ultimo custo pago',
        valor: _moeda.format(ultimoCusto),
        detalhe: 'Ultima NF-e no historico',
        cor: semantic.infoFg,
        bg: semantic.infoBg,
      ),
      _KpiCompraMini(
        icone: Icons.analytics_outlined,
        rotulo: 'Custo medio',
        valor: custoMedio > 0 ? _moeda.format(custoMedio) : '—',
        detalhe: 'Ponderado pelas entradas',
        cor: scheme.primary,
        bg: scheme.primaryContainer.withValues(alpha: 0.35),
      ),
      _KpiCompraMini(
        icone: Icons.trending_up_outlined,
        rotulo: 'Variacao recente',
        valor: valorVar,
        detalhe: detalheVariacao,
        cor: corVar,
        bg: bgVar,
        tag: variacaoUltimaCompraPct != null
            ? _VariacaoCustoBadge(pct: variacaoUltimaCompraPct!, compacto: true)
            : null,
      ),
      _KpiCompraMini(
        icone: Icons.inventory_2_outlined,
        rotulo: 'Total comprado',
        valor: totalComprado,
        detalhe: '$entradas entrada(s) por NF-e',
        cor: semantic.successFg,
        bg: semantic.successBg,
      ),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        if (w < 520) {
          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                cards[i],
              ],
            ],
          );
        }
        if (w < 900) {
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[0]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: 8),
                  Expanded(child: cards[3]),
                ],
              ),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }
}

class _KpiCompraMini extends StatelessWidget {
  const _KpiCompraMini({
    required this.icone,
    required this.rotulo,
    required this.valor,
    required this.detalhe,
    required this.cor,
    required this.bg,
    this.tag,
  });

  final IconData icone;
  final String rotulo;
  final String valor;
  final String detalhe;
  final Color cor;
  final Color bg;
  final Widget? tag;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, size: 18, color: cor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cor.withValues(alpha: 0.95),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?tag,
            ],
          ),
          const SizedBox(height: 8),
          Text(
            valor,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: cor,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            detalhe,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.25,
                ),
          ),
        ],
      ),
    );
  }
}

/// Larguras alinhadas entre cabecalho e linhas (sem padding horizontal extra).
abstract final class _HistoricoComprasTabelaLayout {
  static const larguraTotal = 920.0;
  static const emissao = 148.0;
  static const nf = 100.0;
  static const fornecedor = 200.0;
  static const qtdNf = 120.0;
  static const estoque = 120.0;
  static const custo = 120.0;
  static const variacao = 112.0;
}

class _TabelaHistoricoCompras extends StatelessWidget {
  const _TabelaHistoricoCompras({
    required this.lista,
    required this.formatarData,
    required this.formatarMoeda,
    required this.formatarQtdNota,
    required this.formatarEstoqueEntrada,
    required this.variacaoPct,
    required this.onAbrirNfeEntrada,
    required this.onCopiarChaveNf,
  });

  final List<HistoricoEntrada> lista;
  final String Function(DateTime) formatarData;
  final String Function(double) formatarMoeda;
  final String Function(HistoricoEntrada) formatarQtdNota;
  final String Function(HistoricoEntrada) formatarEstoqueEntrada;
  final double? Function(int index) variacaoPct;
  final Future<void> Function(HistoricoEntrada) onAbrirNfeEntrada;
  final void Function(HistoricoEntrada) onCopiarChaveNf;

  static const _minTableWidth = _HistoricoComprasTabelaLayout.larguraTotal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final border = BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65));

    return Card(
      elevation: 1.5,
      shadowColor: Colors.black26,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: border,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(
              children: [
                Icon(Icons.history, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Historico de aquisicoes',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const Spacer(),
                Text(
                  '${lista.length} registro(s)',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final alturaCorpo = constraints.hasBoundedHeight
                    ? constraints.maxHeight
                    : MediaQuery.sizeOf(context).height * 0.45;
                return Scrollbar(
                  thumbVisibility: lista.length > 6,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _minTableWidth,
                      height: alturaCorpo,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LinhaCabecalhoTabela(scheme: scheme),
                          Expanded(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              primary: false,
                              itemCount: lista.length,
                              itemBuilder: (context, i) {
                                return _LinhaDadosHistorico(
                                  entrada: lista[i],
                                  indice: i,
                                  zebrada: i.isOdd,
                                  formatarData: formatarData,
                                  formatarMoeda: formatarMoeda,
                                  formatarQtdNota: formatarQtdNota,
                                  formatarEstoqueEntrada: formatarEstoqueEntrada,
                                  variacaoPct: variacaoPct(i),
                                  onAbrirNfeEntrada: () =>
                                      onAbrirNfeEntrada(lista[i]),
                                  onCopiarChaveNf: () =>
                                      onCopiarChaveNf(lista[i]),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaCabecalhoTabela extends StatelessWidget {
  const _LinhaCabecalhoTabela({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
      child: Row(
        children: [
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.emissao,
            texto: 'Emissao',
          ),
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.nf,
            texto: 'NF',
          ),
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.fornecedor,
            texto: 'Fornecedor',
          ),
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.qtdNf,
            texto: 'Qtd NF',
          ),
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.estoque,
            texto: 'Estoque +',
          ),
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.custo,
            texto: 'Custo unit.',
            alinharFim: true,
          ),
          _CelulaCabecalho(
            largura: _HistoricoComprasTabelaLayout.variacao,
            texto: 'Variacao',
            alinharFim: true,
          ),
        ],
      ),
    );
  }
}

class _CelulaCabecalho extends StatelessWidget {
  const _CelulaCabecalho({
    required this.largura,
    required this.texto,
    this.alinharFim = false,
  });

  final double largura;
  final String texto;
  final bool alinharFim;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: largura,
      child: Text(
        texto,
        textAlign: alinharFim ? TextAlign.right : TextAlign.left,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _LinhaDadosHistorico extends StatefulWidget {
  const _LinhaDadosHistorico({
    required this.entrada,
    required this.indice,
    required this.zebrada,
    required this.formatarData,
    required this.formatarMoeda,
    required this.formatarQtdNota,
    required this.formatarEstoqueEntrada,
    required this.variacaoPct,
    required this.onAbrirNfeEntrada,
    required this.onCopiarChaveNf,
  });

  final HistoricoEntrada entrada;
  final int indice;
  final bool zebrada;
  final String Function(DateTime) formatarData;
  final String Function(double) formatarMoeda;
  final String Function(HistoricoEntrada) formatarQtdNota;
  final String Function(HistoricoEntrada) formatarEstoqueEntrada;
  final double? variacaoPct;
  final VoidCallback onAbrirNfeEntrada;
  final VoidCallback onCopiarChaveNf;

  @override
  State<_LinhaDadosHistorico> createState() => _LinhaDadosHistoricoState();
}

class _LinhaDadosHistoricoState extends State<_LinhaDadosHistorico> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final h = widget.entrada;
    final base = widget.zebrada
        ? scheme.surfaceContainerLowest.withValues(alpha: 0.55)
        : scheme.surface;
    final bg = _hover ? scheme.primaryContainer.withValues(alpha: 0.18) : base;

    return Material(
      color: bg,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: SizedBox(
          height: 48,
          width: _HistoricoComprasTabelaLayout.larguraTotal,
          child: Row(
            children: [
              SizedBox(
                width: _HistoricoComprasTabelaLayout.emissao,
                child: Text(
                  widget.formatarData(h.dataEmissao),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              SizedBox(
                width: _HistoricoComprasTabelaLayout.nf,
                child: Align(
                alignment: Alignment.centerLeft,
                child: h.numeroNota > 0
                    ? Tooltip(
                        message: 'Abrir NF-e importada\n'
                            'Segure para copiar a chave',
                        child: _ChipNumeroNf(
                          numero: h.numeroNota,
                          onTap: widget.onAbrirNfeEntrada,
                          onLongPress: h.chaveAcesso.isNotEmpty
                              ? widget.onCopiarChaveNf
                              : null,
                        ),
                      )
                    : Text(
                        '—',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                ),
              ),
              SizedBox(
                width: _HistoricoComprasTabelaLayout.fornecedor,
                child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
                    child: Icon(
                      Icons.business_outlined,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      h.nomeFornecedor.isNotEmpty ? h.nomeFornecedor : '—',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                ),
              ),
              SizedBox(
                width: _HistoricoComprasTabelaLayout.qtdNf,
                child: Text(
                  widget.formatarQtdNota(h),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              SizedBox(
                width: _HistoricoComprasTabelaLayout.estoque,
                child: Text(
                  '+${widget.formatarEstoqueEntrada(h)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.semanticColors.successFg,
                  ),
                ),
              ),
              SizedBox(
                width: _HistoricoComprasTabelaLayout.custo,
                child: Text(
                  widget.formatarMoeda(h.precoCustoUnitarioNota),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: _HistoricoComprasTabelaLayout.variacao,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: widget.variacaoPct != null
                      ? _VariacaoCustoBadge(pct: widget.variacaoPct!)
                      : Text(
                          '—',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipNumeroNf extends StatelessWidget {
  const _ChipNumeroNf({
    required this.numero,
    required this.onTap,
    this.onLongPress,
  });

  final int numero;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Text(
            '$numero',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class _VariacaoCustoBadge extends StatelessWidget {
  const _VariacaoCustoBadge({
    required this.pct,
    this.compacto = false,
  });

  final double pct;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;
    final scheme = Theme.of(context).colorScheme;

    late Color fg;
    late Color bg;
    late IconData icone;
    if (pct > 0.5) {
      fg = semantic.errorFg;
      bg = semantic.errorBg;
      icone = Icons.arrow_upward_rounded;
    } else if (pct < -0.5) {
      fg = semantic.successFg;
      bg = semantic.successBg;
      icone = Icons.arrow_downward_rounded;
    } else {
      fg = scheme.onSurfaceVariant;
      bg = scheme.surfaceContainerHighest;
      icone = Icons.remove_rounded;
    }

    final texto =
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1).replaceAll('.', ',')}%';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compacto ? 6 : 8,
        vertical: compacto ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: compacto ? 12 : 14, color: fg),
          const SizedBox(width: 2),
          Text(
            texto,
            style: TextStyle(
              fontSize: compacto ? 11 : 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
