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

  /// Primeiro dia do mês (00:00:00 local) até o fim do dia de [agora] (23:59:59.999).
  ///
  /// Alinha o filtro mensal ao KPI "hoje" para incluir todas as vendas finalizadas no dia.
  static ({DateTime inicioLocal, DateTime fimLocal}) intervaloMesCorrenteAteHoje(
    DateTime agora,
  ) {
    final inicioLocal = DateTime(agora.year, agora.month, 1);
    final fimDoDiaCorrente = DateTime(
      agora.year,
      agora.month,
      agora.day,
      23,
      59,
      59,
      999,
    );
    final fimLocal =
        agora.isAfter(fimDoDiaCorrente) ? agora : fimDoDiaCorrente;
    return (inicioLocal: inicioLocal, fimLocal: fimLocal);
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

  static MainMenuVendasResumo garantirMesNaoMenorQueHoje(
    MainMenuVendasResumo mes,
    MainMenuVendasResumo hoje,
  ) {
    if (mes.quantidade >= hoje.quantidade &&
        mes.faturamento >= hoje.faturamento - 0.0001) {
      return mes;
    }
    return MainMenuVendasResumo(
      quantidade:
          mes.quantidade < hoje.quantidade ? hoje.quantidade : mes.quantidade,
      faturamento: mes.faturamento < hoje.faturamento
          ? hoje.faturamento
          : mes.faturamento,
    );
  }

  /// Mesma fonte do card "Vendas hoje" no painel Início.
  static List<Venda> listarVendasHojeNoRepositorio({
    required dynamic vendaRepository,
    required DateTime agora,
    required UsuarioSistema usuario,
  }) {
    final verTotalLoja =
        UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(usuario);
    if (!verTotalLoja && usuario.vendedorId <= 0) {
      return const [];
    }
    final inicioDia = DateTime(agora.year, agora.month, agora.day);
    final fimDia =
        DateTime(agora.year, agora.month, agora.day, 23, 59, 59, 999);
    final filtro = FiltroListagemVendas(
      textoBusca: '',
      dataInicioUtc: inicioDia.toUtc(),
      dataFimUtc: fimDia.toUtc(),
      filtroCancelamento: 'ativas',
      canceladaPorFiltro: 'todos',
      formaPagamento: 'todos',
      tipoEntrega: 'todos',
      entregaPendente: 'todos',
      filtroFiscal: 'todos',
      vendedorId: verTotalLoja ? null : usuario.vendedorId,
    );
    final lista = List<Venda>.from(
      vendaRepository.listarListagemVendasCompleto(filtro),
    );
    _mesclarFinalizadasNoDiaLocal(
      lista,
      vendaRepository: vendaRepository,
      agora: agora,
      vendedorId: verTotalLoja ? null : usuario.vendedorId,
    );
    return lista;
  }

  static MainMenuVendasResumo carregarVendasHoje({
    required dynamic vendaRepository,
    required DateTime agora,
    required UsuarioSistema usuario,
  }) {
    return resumoDe(
      listarVendasHojeNoRepositorio(
        vendaRepository: vendaRepository,
        agora: agora,
        usuario: usuario,
      ),
    );
  }

  static List<Venda> listarVendasMesNoRepositorio({
    required dynamic vendaRepository,
    required DateTime agora,
    required UsuarioSistema usuario,
    List<Venda> vendasHojeParaUniao = const [],
  }) {
    if (!deveCarregarVendasMes(usuario)) {
      return const [];
    }
    final filtro = filtroVendasMesCorrente(
      agora: agora,
      vendedorId: vendedorIdParaFiltro(usuario),
    );
    final lista = List<Venda>.from(
      vendaRepository.listarListagemVendasCompleto(filtro),
    );
    _mesclarFinalizadasNoDiaLocal(
      lista,
      vendaRepository: vendaRepository,
      agora: agora,
      vendedorId: vendedorIdParaFiltro(usuario),
    );
    unirVendasPorId(lista, vendasHojeParaUniao);
    return lista;
  }

  static void unirVendasPorId(List<Venda> destino, Iterable<Venda> extras) {
    final ids = destino.map((v) => v.id).toSet();
    for (final v in extras) {
      if (ids.contains(v.id)) continue;
      destino.add(v);
      ids.add(v.id);
    }
  }

  static MainMenuVendasResumo calcularResumoMesNoRepositorio({
    required dynamic vendaRepository,
    required DateTime agora,
    required UsuarioSistema usuario,
    List<Venda> vendasHojeParaUniao = const [],
  }) {
    if (!deveCarregarVendasMes(usuario)) {
      return const MainMenuVendasResumo.vazio();
    }
    return resumoDe(
      listarVendasMesNoRepositorio(
        vendaRepository: vendaRepository,
        agora: agora,
        usuario: usuario,
        vendasHojeParaUniao: vendasHojeParaUniao,
      ),
    );
  }

  static MainMenuVendasResumo carregarVendasMes({
    required dynamic vendaRepository,
    required DateTime agora,
    required UsuarioSistema usuario,
    List<Venda> vendasHojeParaUniao = const [],
  }) {
    final mes = calcularResumoMesNoRepositorio(
      vendaRepository: vendaRepository,
      agora: agora,
      usuario: usuario,
      vendasHojeParaUniao: vendasHojeParaUniao,
    );
    final hoje = vendasHojeParaUniao.isEmpty
        ? carregarVendasHoje(
            vendaRepository: vendaRepository,
            agora: agora,
            usuario: usuario,
          )
        : resumoDe(vendasHojeParaUniao);
    return garantirMesNaoMenorQueHoje(mes, hoje);
  }

  static void _mesclarFinalizadasNoDiaLocal(
    List<Venda> lista, {
    required dynamic vendaRepository,
    required DateTime agora,
    required int? vendedorId,
  }) {
    if (vendaRepository is! VendaRepository) return;
    final extra = vendaRepository.listarVendasFinalizadasNoDiaLocal(agora);
    final ids = lista.map((v) => v.id).toSet();
    for (final v in extra) {
      if (ids.contains(v.id)) continue;
      if (vendedorId != null && v.vendedor.targetId != vendedorId) continue;
      lista.add(v);
      ids.add(v.id);
    }
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
