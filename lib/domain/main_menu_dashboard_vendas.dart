import '../data/venda_repository.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import 'usuario_permissao_helper.dart';

/// KPIs de vendas do painel Início (hoje e mês corrente até agora).
class MainMenuVendasResumo {
  const MainMenuVendasResumo({
    required this.quantidade,
    required this.faturamento,
  });

  const MainMenuVendasResumo.vazio()
      : quantidade = 0,
        faturamento = 0;

  final int quantidade;
  final double faturamento;
}

class MainMenuDashboardVendasKpi {
  MainMenuDashboardVendasKpi._();

  /// Primeiro dia do mês (00:00 local) até o instante [agora] (local).
  static ({DateTime inicioLocal, DateTime fimLocal}) intervaloMesCorrenteAteHoje(
    DateTime agora,
  ) {
    return (
      inicioLocal: DateTime(agora.year, agora.month, 1),
      fimLocal: agora,
    );
  }

  /// UTC para [FiltroListagemVendas] — espelha o painel Início.
  static ({DateTime inicioUtc, DateTime fimUtc}) intervaloMesCorrenteAteHojeUtc(
    DateTime agora,
  ) {
    final local = intervaloMesCorrenteAteHoje(agora);
    return (
      inicioUtc: local.inicioLocal.toUtc(),
      fimUtc: local.fimLocal.toUtc(),
    );
  }

  /// `null` = loja inteira; ausência de filtro para vendedor sem vínculo.
  static int? vendedorIdParaFiltro(UsuarioSistema u) {
    if (UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u)) {
      return null;
    }
    if (u.vendedorId <= 0) return null;
    return u.vendedorId;
  }

  static bool deveCarregarVendasMes(UsuarioSistema u) {
    if (UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u)) return true;
    return u.vendedorId > 0;
  }

  static FiltroListagemVendas filtroVendasMesCorrente({
    required DateTime agora,
    int? vendedorId,
  }) {
    final utc = intervaloMesCorrenteAteHojeUtc(agora);
    return FiltroListagemVendas(
      textoBusca: '',
      dataInicioUtc: utc.inicioUtc,
      dataFimUtc: utc.fimUtc,
      filtroCancelamento: 'ativas',
      canceladaPorFiltro: 'todos',
      formaPagamento: 'todos',
      tipoEntrega: 'todos',
      entregaPendente: 'todos',
      filtroFiscal: 'todos',
      vendedorId: vendedorId,
    );
  }

  static MainMenuVendasResumo resumoDe(Iterable<Venda> vendas) {
    var total = 0.0;
    var qtd = 0;
    for (final v in vendas) {
      qtd++;
      total += v.total;
    }
    return MainMenuVendasResumo(quantidade: qtd, faturamento: total);
  }

  static MainMenuVendasResumo calcularResumoMesNoRepositorio({
    required dynamic vendaRepository,
    required DateTime agora,
    required UsuarioSistema usuario,
  }) {
    if (!deveCarregarVendasMes(usuario)) {
      return const MainMenuVendasResumo.vazio();
    }
    final filtro = filtroVendasMesCorrente(
      agora: agora,
      vendedorId: vendedorIdParaFiltro(usuario),
    );
    final lista = vendaRepository.listarListagemVendasCompleto(filtro);
    return resumoDe(List<Venda>.from(lista));
  }

  /// Ex.: `01/09 a hoje`.
  static String rotuloPeriodoMesDiscreto(DateTime agora) {
    final mm = agora.month.toString().padLeft(2, '0');
    return '01/$mm a hoje';
  }

  static String rotuloCardVendasMes(UsuarioSistema u) {
    if (UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u)) {
      return 'Vendas no mês';
    }
    return 'Minhas vendas no mês';
  }
}
