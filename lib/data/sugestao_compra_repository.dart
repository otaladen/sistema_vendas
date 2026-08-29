import 'dart:math' as math;

import '../domain/fornecedor_entrada_nfe_indice.dart';
import '../domain/produto_embalagem.dart';
import '../model/produto.dart';
import '../services/compras_preditivas_service.dart';
import 'objectbox.dart';
import 'sync/sync_entity_codec.dart';

/// Linha do relatorio de sugestao de reposicao (somente leitura / exportacao).
class LinhaSugestaoCompra {
  const LinhaSugestaoCompra({
    required this.produto,
    required this.consumoNoPeriodoUnidades,
    required this.mediaUnidadesPorDia,
    this.diasCoberturaComEstoqueAtual,
    this.ultimaEntradaNfe,
    required this.quantidadeSugerida,
    required this.pontoPedido,
    required this.estoqueCritico,
    required this.quantidadeSugeridaPorPp,
    this.alertaPorEstoqueSeguranca = false,
    this.fornecedorUltimaNfe = '',
    this.fornecedoresNfe = const [],
  });

  final Produto produto;
  final int consumoNoPeriodoUnidades;
  final double mediaUnidadesPorDia;

  /// Estoque livre / media diaria; null se nao houve venda no periodo.
  final double? diasCoberturaComEstoqueAtual;

  /// Maior [HistoricoEntrada.dataEmissao] ligada ao produto (entrada NF-e).
  final DateTime? ultimaEntradaNfe;

  /// max(falta para minimo, falta para cobrir giro alvo).
  final int quantidadeSugerida;

  /// PP = (vendaMediaDiaria * leadTimeDias) + estoqueSeguranca
  final double pontoPedido;

  /// [estoqueAtual] <= [pontoPedido] ou limiar de seguranca (produto novo).
  final bool estoqueCritico;

  /// Unidades para repor ate o PP (0 se acima do PP).
  final int quantidadeSugeridaPorPp;

  /// Produto sem giro confiavel: alerta prioriza estoque de seguranca.
  final bool alertaPorEstoqueSeguranca;

  /// Nome do fornecedor na NF-e de entrada mais recente deste SKU.
  final String fornecedorUltimaNfe;

  /// Todos os fornecedores com entrada de NF-e deste SKU.
  final List<String> fornecedoresNfe;

  static Map<String, dynamic> toApiMap(LinhaSugestaoCompra l) => {
        'produto': SyncEntityCodec.produtoParaMap(l.produto),
        'consumoNoPeriodoUnidades': l.consumoNoPeriodoUnidades,
        'mediaUnidadesPorDia': l.mediaUnidadesPorDia,
        'diasCoberturaComEstoqueAtual': l.diasCoberturaComEstoqueAtual,
        'ultimaEntradaNfe': l.ultimaEntradaNfe?.toUtc().toIso8601String(),
        'quantidadeSugerida': l.quantidadeSugerida,
        'pontoPedido': l.pontoPedido,
        'estoqueCritico': l.estoqueCritico,
        'quantidadeSugeridaPorPp': l.quantidadeSugeridaPorPp,
        'alertaPorEstoqueSeguranca': l.alertaPorEstoqueSeguranca,
        'fornecedorUltimaNfe': l.fornecedorUltimaNfe,
        'fornecedoresNfe': l.fornecedoresNfe,
      };

  static LinhaSugestaoCompra? fromApiMap(Map<String, dynamic> m) {
    final prodRaw = m['produto'];
    if (prodRaw is! Map) return null;
    final produto =
        SyncEntityCodec.produtoDeMap(Map<String, dynamic>.from(prodRaw));
    return LinhaSugestaoCompra(
      produto: produto,
      consumoNoPeriodoUnidades:
          (m['consumoNoPeriodoUnidades'] as num?)?.toInt() ?? 0,
      mediaUnidadesPorDia:
          (m['mediaUnidadesPorDia'] as num?)?.toDouble() ?? 0,
      diasCoberturaComEstoqueAtual:
          (m['diasCoberturaComEstoqueAtual'] as num?)?.toDouble(),
      ultimaEntradaNfe: DateTime.tryParse(
        (m['ultimaEntradaNfe'] ?? '').toString(),
      ),
      quantidadeSugerida: (m['quantidadeSugerida'] as num?)?.toInt() ?? 0,
      pontoPedido: (m['pontoPedido'] as num?)?.toDouble() ?? 0,
      estoqueCritico: m['estoqueCritico'] == true,
      quantidadeSugeridaPorPp:
          (m['quantidadeSugeridaPorPp'] as num?)?.toInt() ?? 0,
      alertaPorEstoqueSeguranca: m['alertaPorEstoqueSeguranca'] == true,
      fornecedorUltimaNfe: (m['fornecedorUltimaNfe'] ?? '').toString(),
      fornecedoresNfe: _stringsDeLista(m['fornecedoresNfe']),
    );
  }

  static List<String> _stringsDeLista(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
}

/// Cruza vendas finalizadas, estoque minimo, PP e historico de entrada NF-e.
class SugestaoCompraRepository {
  SugestaoCompraRepository(this._db);

  final ObjectBox _db;

  /// [diasPeriodoConsumo]: janela para somar saidas (ex.: 60).
  /// [diasCoberturaAlvo]: meta de estoque em dias de venda (ex.: 30).
  /// [apenasComSugestaoOuRisco]: quando true, omite produtos sem alerta.
  /// [fornecedorFiltro]: so SKUs com entrada NF-e desse fornecedor, abaixo do
  /// PP ou do estoque minimo.
  List<LinhaSugestaoCompra> montarLinhas({
    required int diasPeriodoConsumo,
    required int diasCoberturaAlvo,
    bool apenasComSugestaoOuRisco = true,
    String? fornecedorFiltro,
  }) {
    final dias = diasPeriodoConsumo <= 0 ? 1 : diasPeriodoConsumo;
    final cobertura = diasCoberturaAlvo <= 0 ? 30 : diasCoberturaAlvo;
    final fim = DateTime.now().toUtc();
    final inicio = fim.subtract(Duration(days: dias));

    final consumoPorProduto = <int, int>{};
    for (final iv in _db.itemVendaBox.getAll()) {
      final v = iv.venda.target;
      final p = iv.produto.target;
      if (v == null || p == null) continue;
      if (v.status != 'finalizada' || v.cancelada) continue;
      final vd = v.data.toUtc();
      if (vd.isBefore(inicio) || vd.isAfter(fim)) continue;
      consumoPorProduto.update(
        p.id,
        (x) => x + iv.quantidade,
        ifAbsent: () => iv.quantidade,
      );
    }

    final ultimaEntrada = <int, DateTime>{};
    for (final h in _db.historicoEntradaBox.getAll()) {
      final pid = h.produto.targetId;
      if (pid == 0) continue;
      final d = h.dataEmissao.toUtc();
      ultimaEntrada.update(
        pid,
        (prev) => d.isAfter(prev) ? d : prev,
        ifAbsent: () => d,
      );
    }

    final comprasSvc = ComprasPreditivasService(_db, diasHistoricoVendas: dias);
    final indiceForn = indiceFornecedoresNfe();
    final filtroForn = (fornecedorFiltro ?? '').trim();
    final produtos = _db.produtoBox.getAll();
    final linhas = <LinhaSugestaoCompra>[];

    for (final pr in produtos) {
      if (!pr.ativo) continue;

      final vendido = consumoPorProduto[pr.id] ?? 0;
      final vendidoExibicao =
          ProdutoEmbalagem.valorEstoqueExibicao(pr, vendido);
      final mediaHistorico = vendidoExibicao / dias;
      final mediaPersistida = pr.vendaMediaDiariaExibicao;
      final media = mediaPersistida > 0 ? mediaPersistida : mediaHistorico;
      final livre = pr.estoqueLivreExibicao;
      final estoqueAtual = pr.estoqueExibicao;
      final minimo = pr.quantidadeMinima.toDouble();

      final pp = comprasSvc.calcularPontoPedidoExibicao(
        pr,
        consumoNoPeriodo: vendido,
      );
      final criticoPp = comprasSvc.verificarEstoqueCritico(
        pr,
        consumoNoPeriodo: vendido,
      );
      final porSeguranca = !comprasSvc.temGiroVendaConfiavel(
        pr,
        consumoNoPeriodo: vendido,
      );
      final faltaPp = (pp - estoqueAtual).ceil();
      final qtdPorPp = faltaPp > 0 ? faltaPp : 0;

      final faltaMinimo = livre < minimo ? (minimo - livre).ceil() : 0;
      final metaGiro = (media * cobertura).ceil();
      final faltaGiro = livre < metaGiro ? (metaGiro - livre).ceil() : 0;
      final qtdSugerida = math.max(math.max(faltaMinimo, faltaGiro), qtdPorPp);

      double? diasCobertura;
      if (media > 1e-9) {
        diasCobertura = livre / media;
      }

      final ult = ultimaEntrada[pr.id];

      if (filtroForn.isNotEmpty) {
        if (!indiceForn.produtoDoFornecedor(pr.id, filtroForn)) continue;
        final abaixoMinimoForn = livre <= minimo;
        if (!criticoPp && !abaixoMinimoForn) continue;
      } else if (apenasComSugestaoOuRisco) {
        final abaixoMinimo = livre <= minimo;
        final giroBaixo = media > 1e-9 &&
            diasCobertura != null &&
            diasCobertura < cobertura;
        if (!abaixoMinimo && !giroBaixo && !criticoPp && qtdSugerida <= 0) {
          continue;
        }
      }

      // Atualiza media persistida (escala raw) se ainda zerada e houve venda.
      if (pr.vendaMediaDiaria <= 0 && vendido > 0) {
        comprasSvc.atualizarVendaMediaDiaria(pr);
        _db.produtoBox.put(pr);
      }

      linhas.add(
        LinhaSugestaoCompra(
          produto: pr,
          consumoNoPeriodoUnidades: vendido,
          mediaUnidadesPorDia: media,
          diasCoberturaComEstoqueAtual: diasCobertura,
          ultimaEntradaNfe: ult,
          quantidadeSugerida: qtdSugerida,
          pontoPedido: pp,
          estoqueCritico: criticoPp,
          quantidadeSugeridaPorPp: qtdPorPp,
          alertaPorEstoqueSeguranca: porSeguranca && criticoPp,
          fornecedorUltimaNfe: indiceForn.ultimoFornecedorDe(pr.id) ?? '',
          fornecedoresNfe: indiceForn.fornecedoresDoProduto(pr.id),
        ),
      );
    }

    linhas.sort((a, b) {
      if (a.estoqueCritico != b.estoqueCritico) {
        return a.estoqueCritico ? -1 : 1;
      }
      final c = b.quantidadeSugerida.compareTo(a.quantidadeSugerida);
      if (c != 0) return c;
      return a.produto.nome.compareTo(b.produto.nome);
    });
    return linhas;
  }

  FornecedorEntradaNfeIndice indiceFornecedoresNfe() {
    final lancamentos = <FornecedorEntradaNfeLancamento>[];
    for (final h in _db.historicoEntradaBox.getAll()) {
      final pid = h.produto.targetId;
      final nome = h.nomeFornecedor.trim();
      if (pid <= 0 || nome.isEmpty) continue;
      lancamentos.add(
        FornecedorEntradaNfeLancamento(
          produtoId: pid,
          nomeFornecedor: nome,
          data: h.dataEmissao,
        ),
      );
    }
    for (final v in _db.vinculoFornecedorProdutoBox.getAll()) {
      final pid = v.produto.targetId;
      if (pid <= 0) continue;
      final f = v.fornecedor.target;
      if (f == null) continue;
      final nome = f.nomeExibicao.trim();
      if (nome.isEmpty) continue;
      lancamentos.add(
        FornecedorEntradaNfeLancamento(
          produtoId: pid,
          nomeFornecedor: nome,
          data: f.atualizadoEm,
        ),
      );
    }
    return FornecedorEntradaNfeIndice.deLancamentos(lancamentos);
  }
}
