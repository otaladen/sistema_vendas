import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/data/venda_repository.dart';
import 'package:sistema_vendas/domain/dashboard_vendas_store.dart';
import 'package:sistema_vendas/domain/main_menu_dashboard_vendas.dart';
import 'package:sistema_vendas/domain/perfil_usuario_preset.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';
import 'package:sistema_vendas/model/venda.dart';

void main() {
  group('DashboardVendasStore / KPI mês vs hoje', () {
    test('venda de hoje incrementa hoje e mês após recarregar', () {
      final agora = DateTime(2026, 10, 2, 14, 0);
      final vendaHoje = Venda(
        id: 100,
        data: DateTime(2026, 10, 2, 12, 0),
        total: 250,
        status: 'finalizada',
        finalizadaEm: DateTime(2026, 10, 2, 13, 30),
      );
      final repo = _RepoVendasDashboardStub(
        vendasHoje: [vendaHoje],
        vendasMes: const [],
      );
      final usuario = PerfilUsuarioPresetAplicador.aplicar(
        UsuarioSistema(
          id: 'v',
          nome: 'V',
          login: 'v',
          senha: 'x',
          vendedorId: 3,
        ),
        PerfilUsuarioPreset.vendedor,
      );

      final store = DashboardVendasStore(
        vendaRepository: repo,
        usuario: usuario,
      );
      store.carregarVendasHoje(agora);
      store.carregarVendasMes(agora);

      expect(store.vendasHojeResumo.quantidade, 1);
      expect(store.vendasHojeResumo.faturamento, 250);
      expect(store.vendasMesResumo.quantidade, 1);
      expect(store.vendasMesResumo.faturamento, 250);
    });

    test('nova venda no dia reflete em hoje e mês na mesma recarga', () {
      final agora = DateTime(2026, 10, 2, 10, 0);
      final repo = _RepoVendasDashboardStub(
        vendasHoje: const [],
        vendasMes: const [],
      );
      final usuario = UsuarioSistema(
        id: 'a',
        nome: 'A',
        login: 'a',
        senha: 'x',
        admin: true,
      );
      final store = DashboardVendasStore(
        vendaRepository: repo,
        usuario: usuario,
      );

      store.carregarVendasHoje(agora);
      store.carregarVendasMes(agora);
      expect(store.vendasHojeResumo.quantidade, 0);
      expect(store.vendasMesResumo.quantidade, 0);

      repo.vendasHoje = [
        Venda(id: 1, total: 80, status: 'finalizada'),
      ];
      repo.vendasMes = [Venda(id: 1, total: 80, status: 'finalizada')];

      store.carregarVendasHoje(agora);
      store.carregarVendasMes(agora);

      expect(store.vendasHojeResumo.quantidade, 1);
      expect(store.vendasMesResumo.quantidade, 1);
      expect(
        store.vendasMesResumo.faturamento,
        greaterThanOrEqualTo(store.vendasHojeResumo.faturamento),
      );
    });

    test('uniao com vendas de hoje garante mes >= hoje quando listagem mensal falha', () {
      final agora = DateTime(2026, 10, 2, 10, 0);
      final v1 = Venda(id: 1, total: 100, status: 'finalizada');
      final v2 = Venda(id: 2, total: 50, status: 'finalizada');
      final repo = _RepoVendasDashboardStub(
        vendasHoje: [v1, v2],
        vendasMes: [v1],
      );
      final usuario = UsuarioSistema(
        id: 'a',
        nome: 'A',
        login: 'a',
        senha: 'x',
        admin: true,
      );

      final par = DashboardVendasStore(
        vendaRepository: repo,
        usuario: usuario,
      ).recarregarTudo(agora);

      expect(par.hoje.quantidade, 2);
      expect(par.hoje.faturamento, 150);
      expect(par.mes.quantidade, greaterThanOrEqualTo(par.hoje.quantidade));
      expect(par.mes.faturamento, greaterThanOrEqualTo(par.hoje.faturamento));
    });

    test('garantirMesNaoMenorQueHoje corrige faturamento e quantidade', () {
      const hoje = MainMenuVendasResumo(quantidade: 3, faturamento: 900);
      const mes = MainMenuVendasResumo(quantidade: 2, faturamento: 500);
      final ajustado = MainMenuDashboardVendasKpi.garantirMesNaoMenorQueHoje(
        mes,
        hoje,
      );
      expect(ajustado.quantidade, 3);
      expect(ajustado.faturamento, 900);
    });
  });
}

class _RepoVendasDashboardStub {
  _RepoVendasDashboardStub({
    required List<Venda> vendasHoje,
    required List<Venda> vendasMes,
  })  : vendasHoje = List<Venda>.from(vendasHoje),
        vendasMes = List<Venda>.from(vendasMes);

  List<Venda> vendasHoje;
  List<Venda> vendasMes;

  List<Venda> listarListagemVendasCompleto(FiltroListagemVendas f) {
    final ini = f.dataInicioUtc?.toLocal();
    if (ini != null && ini.day == 1) {
      return List<Venda>.from(vendasMes);
    }
    return List<Venda>.from(vendasHoje);
  }
}
