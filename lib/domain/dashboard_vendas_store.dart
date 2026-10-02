import '../data/venda_repository.dart';
import '../model/usuario_sistema.dart';
import '../model/venda.dart';
import 'main_menu_dashboard_vendas.dart';

/// Par de KPIs de vendas (hoje e mês corrente) para o painel Início.
class DashboardVendasKpiPar {
  const DashboardVendasKpiPar({
    required this.hoje,
    required this.mes,
    required this.vendasHoje,
  });

  final MainMenuVendasResumo hoje;
  final MainMenuVendasResumo mes;
  final List<Venda> vendasHoje;
}

/// Carrega e reconcilia KPIs de vendas do dashboard (hoje + mês).
class DashboardVendasStore {
  DashboardVendasStore({
    required this.vendaRepository,
    required this.usuario,
  });

  final dynamic vendaRepository;
  final UsuarioSistema usuario;

  MainMenuVendasResumo vendasHojeResumo = const MainMenuVendasResumo.vazio();
  MainMenuVendasResumo vendasMesResumo = const MainMenuVendasResumo.vazio();
  List<Venda> vendasHojeLista = const [];

  /// Recarrega apenas o KPI do dia.
  void carregarVendasHoje([DateTime? agora]) {
    final ref = agora ?? DateTime.now();
    vendasHojeLista = MainMenuDashboardVendasKpi.listarVendasHojeNoRepositorio(
      vendaRepository: vendaRepository,
      agora: ref,
      usuario: usuario,
    );
    vendasHojeResumo = MainMenuDashboardVendasKpi.resumoDe(vendasHojeLista);
  }

  /// Recarrega o KPI do mês (usa [vendasHojeLista] se já carregada).
  void carregarVendasMes([DateTime? agora]) {
    final ref = agora ?? DateTime.now();
    vendasMesResumo = MainMenuDashboardVendasKpi.calcularResumoMesNoRepositorio(
      vendaRepository: vendaRepository,
      agora: ref,
      usuario: usuario,
      vendasHojeParaUniao: vendasHojeLista,
    );
    vendasMesResumo = MainMenuDashboardVendasKpi.garantirMesNaoMenorQueHoje(
      vendasMesResumo,
      vendasHojeResumo,
    );
  }

  /// Atualiza hoje e mês na ordem correta (refresh do painel).
  DashboardVendasKpiPar recarregarTudo([DateTime? agora]) {
    final ref = agora ?? DateTime.now();
    carregarVendasHoje(ref);
    carregarVendasMes(ref);
    return DashboardVendasKpiPar(
      hoje: vendasHojeResumo,
      mes: vendasMesResumo,
      vendasHoje: vendasHojeLista,
    );
  }

  /// Atalho estático sem manter estado (mesma regra do store).
  static DashboardVendasKpiPar recarregar({
    required dynamic vendaRepository,
    required UsuarioSistema usuario,
    DateTime? agora,
  }) {
    return DashboardVendasStore(
      vendaRepository: vendaRepository,
      usuario: usuario,
    ).recarregarTudo(agora);
  }
}
