import 'dart:async';

import '../../data/api/venda_api_repository.dart';
import '../../data/venda_repository.dart';
import '../../domain/relatorio_meta_comissao.dart';
import '../../domain/venda_relacao_safe.dart';
import '../../model/cliente.dart';
import '../../model/item_venda.dart';
import '../../model/venda.dart';
import '../../model/vendedor.dart';
import 'relatorio_periodo.dart';

export '../../domain/relatorio_meta_comissao.dart';

/// Nota do periodo com totais ja ajustados pelas devolucoes/trocas do intervalo.
class RelatorioVendaLinhaLiquida {
  const RelatorioVendaLinhaLiquida({
    required this.venda,
    required this.total,
    required this.lucro,
    required this.ajusteFaturamento,
    required this.ajusteLucro,
  });

  final Venda venda;
  final double total;
  final double lucro;
  final double ajusteFaturamento;
  final double ajusteLucro;

  bool get teveAjuste =>
      ajusteFaturamento.abs() >= 0.0001 || ajusteLucro.abs() >= 0.0001;
}

/// Vendas finalizadas do periodo com fat/lucro liquidos (impacto por nota).
List<RelatorioVendaLinhaLiquida> relatorioVendasPeriodoLiquidas(
  dynamic repo,
  LimitesPeriodo limites,
) {
  final vendas = relatorioVendasFinalizadasPeriodo(repo, limites);
  final imp = repo.calcularImpactosDevolucaoTrocaPeriodo(
    relatorioPeriodoFiltro(limites),
  ) as ImpactosDevolucaoTrocaPeriodo;
  return [
    for (final v in vendas)
      RelatorioVendaLinhaLiquida(
        venda: v,
        total: v.total + (imp.porVendaFaturamento[v.id] ?? 0),
        lucro: v.lucroTotal + (imp.porVendaLucro[v.id] ?? 0),
        ajusteFaturamento: imp.porVendaFaturamento[v.id] ?? 0,
        ajusteLucro: imp.porVendaLucro[v.id] ?? 0,
      ),
  ];
}

double relatorioMetaProporcional(double metaMensal, LimitesPeriodo limites) =>
    relatorioMetaProporcionalPeriodo(
      metaMensal: metaMensal,
      inicio: limites.$1,
      fim: limites.$2,
    );

/// [repo] aceita [VendaRepository] (servidor) ou VendaApiRepository (terminal).
List<Venda> relatorioVendasFinalizadasPeriodo(
  dynamic repo,
  LimitesPeriodo limites,
) {
  final lista = (repo.listarPorPeriodo(
        PeriodoFiltro(inicio: limites.$1, fim: limites.$2),
      ) as List)
      .cast<Venda>();
  return lista
      .where((v) => v.status == 'finalizada' && !v.cancelada)
      .toList()
    ..sort((a, b) => b.data.compareTo(a.data));
}

/// Itens sem depender de ToMany (quebrado no terminal leve / entidade detached).
List<ItemVenda> relatorioItensDaVenda(dynamic repo, Venda v) {
  try {
    final via = repo.listarItensPorVenda(v.id);
    if (via is List && via.isNotEmpty) {
      return List<ItemVenda>.from(via);
    }
  } catch (_) {}
  try {
    final locais = v.itens.toList();
    if (locais.isNotEmpty) return locais;
  } catch (_) {}
  return const [];
}

/// Cliente sem ToOne detached (terminal).
Cliente? relatorioClienteDaVenda(Venda v, {dynamic clienteRepository}) =>
    VendaRelacaoSafe.cliente(v, clienteRepository: clienteRepository);

/// Vendedor sem ToOne detached (terminal).
Vendedor? relatorioVendedorDaVenda(Venda v, {dynamic vendedorRepository}) =>
    VendaRelacaoSafe.vendedor(v, vendedorRepository: vendedorRepository);

String relatorioNomeCliente(
  Venda v, {
  dynamic clienteRepository,
  String fallback = 'Sem cliente',
}) =>
    VendaRelacaoSafe.nomeCliente(
      v,
      clienteRepository: clienteRepository,
      fallback: fallback,
    );

String relatorioNomeVendedor(
  Venda v, {
  dynamic vendedorRepository,
  String fallback = '-',
}) =>
    VendaRelacaoSafe.nomeVendedor(
      v,
      vendedorRepository: vendedorRepository,
      fallback: fallback,
    );

PeriodoFiltro relatorioPeriodoFiltro(LimitesPeriodo limites) =>
    PeriodoFiltro(inicio: limites.$1, fim: limites.$2);

/// Terminal leve: amplia a janela baixada se o periodo pedido sair do cache.
Future<void> relatorioHidratarPeriodoApi(
  dynamic repo,
  LimitesPeriodo limites,
) async {
  if (repo is! VendaApiRepository) return;
  try {
    await repo.garantirPeriodoRelatorioCarregado(limites.$1, limites.$2);
  } catch (_) {}
}

/// Lucro estimado da linha (quantidade liquida x margem unitaria).
double relatorioLucroItemVenda({
  required int quantidade,
  required int quantidadeDevolvida,
  required double precoUnitario,
  required double precoCustoUnitario,
}) {
  final q = quantidade - quantidadeDevolvida;
  if (q <= 0) return 0;
  return q * (precoUnitario - precoCustoUnitario);
}

String relatorioRotuloFormaPagamento(String forma) {
  switch (forma) {
    case 'pix':
      return 'PIX';
    case 'cartao_credito':
      return 'Credito';
    case 'cartao_debito':
      return 'Debito';
    case 'misto':
      return 'Misto';
    case 'dinheiro':
    default:
      return 'Dinheiro';
  }
}
