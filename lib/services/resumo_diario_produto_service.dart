import 'package:objectbox/objectbox.dart';

import '../data/objectbox.dart';
import '../domain/estoque/tipo_movimento_estoque.dart';
import '../model/item_venda.dart';
import '../model/movimento_estoque.dart';
import '../model/resumo_diario_produto.dart';
import '../model/venda.dart';
import '../objectbox.g.dart';

/// Dia civil local gravado como meia-noite UTC, estável para [betweenDate].
abstract final class ResumoDiarioProdutoDia {
  static DateTime de(DateTime instante) {
    final local = instante.toLocal();
    return DateTime.utc(local.year, local.month, local.day);
  }

  static String chave(int produtoId, DateTime dia) {
    final d = dia.toUtc();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$produtoId|$y-$m-$day';
  }
}

/// Mantém [ResumoDiarioProduto] alinhado ao caixa e ao kardex.
///
/// A quantidade vendida entra só na finalização da venda. A saída física
/// (`cupomNaoFiscalVenda`, carreto, retirada) não soma de novo. Devolução e
/// entrada nascem do movimento de estoque. A tabela não entra no sync: cada
/// base cheia reconstrói o passado uma vez, quando ainda está vazia.
class ResumoDiarioProdutoService {
  ResumoDiarioProdutoService(this._db);

  final ObjectBox _db;

  Box<ResumoDiarioProduto> get _box => _db.resumoDiarioProdutoBox;

  /// Soma os itens no dia de [Venda.finalizadaEm] (ou [Venda.data]).
  ///
  /// [devolucaoJaNaLinha] vale só no backfill: a quantidade já devolvida na
  /// linha conta no dia da venda. No caixa ao vivo a devolução entra depois,
  /// pelo movimento [TipoMovimentoEstoque.devolucaoCliente].
  void registrarVendaFinalizada(
    Venda venda,
    List<ItemVenda> itens, {
    bool devolucaoJaNaLinha = false,
  }) {
    final quando = venda.finalizadaEm ?? venda.data;
    for (final item in itens) {
      final produtoId = item.produto.targetId;
      final qtd = item.quantidade;
      final devolvida = devolucaoJaNaLinha ? item.quantidadeDevolvida : 0;
      if (produtoId <= 0 || (qtd == 0 && devolvida == 0)) continue;
      _aplicar(
        produtoId: produtoId,
        quando: quando,
        quantidadeVendida: qtd,
        valorTotalVendido: item.quantidadeVendaEfetiva * item.precoUnitario,
        quantidadeDevolvida: devolvida,
      );
    }
  }

  /// Desfaz o que [registrarVendaFinalizada] somou, no mesmo dia da venda.
  void estornarVendaFinalizada(Venda venda, List<ItemVenda> itens) {
    final quando = venda.finalizadaEm ?? venda.data;
    for (final item in itens) {
      final produtoId = item.produto.targetId;
      if (produtoId <= 0 || item.quantidade == 0) continue;
      _aplicar(
        produtoId: produtoId,
        quando: quando,
        quantidadeVendida: -item.quantidade,
        valorTotalVendido: -(item.quantidadeVendaEfetiva * item.precoUnitario),
        quantidadeDevolvida: -item.quantidadeDevolvida,
      );
    }
  }

  /// Atualiza entrada ou devolução. Saída de venda é ignorada de propósito.
  void registrarMovimentoFisico({
    required int produtoId,
    required DateTime quando,
    required String tipoNome,
    required int deltaFisico,
  }) {
    if (produtoId <= 0 || deltaFisico == 0) return;
    if (tipoNome == TipoMovimentoEstoque.entradaNfeCompra.name ||
        tipoNome == TipoMovimentoEstoque.estornoEntradaNfeCompra.name) {
      _aplicar(
        produtoId: produtoId,
        quando: quando,
        quantidadeEntrada: deltaFisico,
      );
      return;
    }
    if (tipoNome == TipoMovimentoEstoque.ajusteManual.name && deltaFisico > 0) {
      _aplicar(
        produtoId: produtoId,
        quando: quando,
        quantidadeEntrada: deltaFisico,
      );
      return;
    }
    if (tipoNome == TipoMovimentoEstoque.devolucaoCliente.name) {
      _aplicar(
        produtoId: produtoId,
        quando: quando,
        quantidadeDevolvida: deltaFisico.abs(),
      );
    }
  }

  List<ResumoDiarioProduto> listarEntre(DateTime inicio, DateTime fim) {
    final de = ResumoDiarioProdutoDia.de(inicio);
    final ate = ResumoDiarioProdutoDia.de(fim);
    final q = _box
        .query(ResumoDiarioProduto_.data.betweenDate(de, ate))
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  /// Quantidade vendida menos devolvida no intervalo. Total <= 0 sai do mapa.
  Map<int, int> consumoLiquidoEntre(DateTime inicio, DateTime fim) {
    final mapa = <int, int>{};
    for (final linha in listarEntre(inicio, fim)) {
      final liquida = linha.quantidadeVendida - linha.quantidadeDevolvida;
      if (liquida == 0) continue;
      mapa.update(
        linha.produtoId,
        (atual) => atual + liquida,
        ifAbsent: () => liquida,
      );
    }
    mapa.removeWhere((_, total) => total <= 0);
    return mapa;
  }

  /// Quantidade vendida bruta, a mesma base da sugestão de compra.
  Map<int, int> consumoBrutoEntre(DateTime inicio, DateTime fim) {
    final mapa = <int, int>{};
    for (final linha in listarEntre(inicio, fim)) {
      if (linha.quantidadeVendida == 0) continue;
      mapa.update(
        linha.produtoId,
        (atual) => atual + linha.quantidadeVendida,
        ifAbsent: () => linha.quantidadeVendida,
      );
    }
    return mapa;
  }

  /// Reconstrói o passado só quando a tabela ainda não tem linha.
  ///
  /// Vendas finalizadas geram quantidade e valor; a devolução já gravada na
  /// linha fica no dia da venda. Movimentos repetem só entrada, estorno de
  /// entrada e ajuste positivo — a devolução do cliente não é relida, senão
  /// contaria duas vezes.
  int backfillSeVazio() {
    if (_box.count() > 0) return 0;
    return _db.store.runInTransaction(TxMode.write, () {
      if (_box.count() > 0) return 0;
      final vendas = _db.vendaBox
          .query(
            Venda_.status
                .equals('finalizada')
                .and(Venda_.cancelada.equals(false)),
          )
          .build();
      try {
        for (final venda in vendas.find()) {
          registrarVendaFinalizada(
            venda,
            venda.itens.toList(growable: false),
            devolucaoJaNaLinha: true,
          );
        }
      } finally {
        vendas.close();
      }

      final tiposEntrada = [
        TipoMovimentoEstoque.entradaNfeCompra.name,
        TipoMovimentoEstoque.estornoEntradaNfeCompra.name,
        TipoMovimentoEstoque.ajusteManual.name,
      ];
      final movimentos = _db.movimentoEstoqueBox
          .query(MovimentoEstoque_.tipoMovimento.oneOf(tiposEntrada))
          .build();
      try {
        for (final movimento in movimentos.find()) {
          registrarMovimentoFisico(
            produtoId: movimento.produto.targetId,
            quando: movimento.registradoEm,
            tipoNome: movimento.tipoMovimento,
            deltaFisico: movimento.deltaFisico,
          );
        }
      } finally {
        movimentos.close();
      }
      return _box.count();
    });
  }

  void _aplicar({
    required int produtoId,
    required DateTime quando,
    int quantidadeVendida = 0,
    double valorTotalVendido = 0,
    int quantidadeDevolvida = 0,
    int quantidadeEntrada = 0,
  }) {
    if (quantidadeVendida == 0 &&
        valorTotalVendido == 0 &&
        quantidadeDevolvida == 0 &&
        quantidadeEntrada == 0) {
      return;
    }
    final dia = ResumoDiarioProdutoDia.de(quando);
    final chave = ResumoDiarioProdutoDia.chave(produtoId, dia);
    final consulta = _box
        .query(ResumoDiarioProduto_.chaveDia.equals(chave))
        .build();
    ResumoDiarioProduto? atual;
    try {
      atual = consulta.findFirst();
    } finally {
      consulta.close();
    }
    final row =
        atual ??
        ResumoDiarioProduto(produtoId: produtoId, data: dia, chaveDia: chave);
    row.quantidadeVendida += quantidadeVendida;
    row.valorTotalVendido += valorTotalVendido;
    row.quantidadeDevolvida += quantidadeDevolvida;
    row.quantidadeEntrada += quantidadeEntrada;
    if (row.quantidadeVendida < 0) row.quantidadeVendida = 0;
    if (row.valorTotalVendido < 0) row.valorTotalVendido = 0;
    if (row.quantidadeDevolvida < 0) row.quantidadeDevolvida = 0;
    if (row.quantidadeEntrada < 0) row.quantidadeEntrada = 0;
    final vazio =
        row.quantidadeVendida == 0 &&
        row.valorTotalVendido.abs() < 0.000001 &&
        row.quantidadeDevolvida == 0 &&
        row.quantidadeEntrada == 0;
    if (vazio) {
      if (row.id > 0) _box.remove(row.id);
      return;
    }
    _box.put(row);
  }
}
