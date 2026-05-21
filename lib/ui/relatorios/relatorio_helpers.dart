import '../../data/venda_repository.dart';
import '../../model/venda.dart';
import 'relatorio_periodo.dart';

List<Venda> relatorioVendasFinalizadasPeriodo(
  VendaRepository repo,
  LimitesPeriodo limites,
) {
  final lista = repo.listarPorPeriodo(
    PeriodoFiltro(inicio: limites.$1, fim: limites.$2),
  );
  return lista
      .where((v) => v.status == 'finalizada' && !v.cancelada)
      .toList()
    ..sort((a, b) => b.data.compareTo(a.data));
}

PeriodoFiltro relatorioPeriodoFiltro(LimitesPeriodo limites) =>
    PeriodoFiltro(inicio: limites.$1, fim: limites.$2);

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
