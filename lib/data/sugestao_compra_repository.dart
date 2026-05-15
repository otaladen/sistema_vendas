import 'dart:math' as math;

import '../model/produto.dart';
import 'objectbox.dart';

/// Linha do relatorio de sugestao de reposicao (somente leitura / exportacao).
class LinhaSugestaoCompra {
  const LinhaSugestaoCompra({
    required this.produto,
    required this.consumoNoPeriodoUnidades,
    required this.mediaUnidadesPorDia,
    this.diasCoberturaComEstoqueAtual,
    this.ultimaEntradaNfe,
    required this.quantidadeSugerida,
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
}

/// Cruza vendas finalizadas, estoque minimo e historico de entrada NF-e.
class SugestaoCompraRepository {
  SugestaoCompraRepository(this._db);

  final ObjectBox _db;

  /// [diasPeriodoConsumo]: janela para somar saidas (ex.: 60).
  /// [diasCoberturaAlvo]: meta de estoque em dias de venda (ex.: 30).
  /// [apenasComSugestaoOuRisco]: quando true, omite produtos sem alerta.
  List<LinhaSugestaoCompra> montarLinhas({
    required int diasPeriodoConsumo,
    required int diasCoberturaAlvo,
    bool apenasComSugestaoOuRisco = true,
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

    final produtos = _db.produtoBox.getAll();
    final linhas = <LinhaSugestaoCompra>[];

    for (final pr in produtos) {
      if (!pr.ativo) continue;

      final vendido = consumoPorProduto[pr.id] ?? 0;
      final media = vendido / dias;
      final livre = pr.estoqueLivreParaVenda;
      final minimo = pr.quantidadeMinima;

      final faltaMinimo = livre < minimo ? (minimo - livre) : 0;
      final metaGiro = (media * cobertura).ceil();
      final faltaGiro = livre < metaGiro ? (metaGiro - livre) : 0;
      final qtdSugerida = math.max(faltaMinimo, faltaGiro);

      double? diasCobertura;
      if (media > 1e-9) {
        diasCobertura = livre / media;
      }

      final ult = ultimaEntrada[pr.id];

      if (apenasComSugestaoOuRisco) {
        final abaixoMinimo = livre <= minimo;
        final giroBaixo = media > 1e-9 &&
            diasCobertura != null &&
            diasCobertura < cobertura;
        if (!abaixoMinimo && !giroBaixo && qtdSugerida <= 0) {
          continue;
        }
      }

      linhas.add(
        LinhaSugestaoCompra(
          produto: pr,
          consumoNoPeriodoUnidades: vendido,
          mediaUnidadesPorDia: media,
          diasCoberturaComEstoqueAtual: diasCobertura,
          ultimaEntradaNfe: ult,
          quantidadeSugerida: qtdSugerida,
        ),
      );
    }

    linhas.sort((a, b) {
      final c = b.quantidadeSugerida.compareTo(a.quantidadeSugerida);
      if (c != 0) return c;
      return a.produto.nome.compareTo(b.produto.nome);
    });
    return linhas;
  }
}
