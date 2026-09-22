import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/main_menu_dashboard_vendas.dart';
import 'package:sistema_vendas/domain/perfil_usuario_preset.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  group('MainMenuDashboardVendasKpi.intervaloMesCorrenteAteHojeUtc', () {
    test('inicia no dia 1 do mes local e termina no instante atual', () {
      final agora = DateTime(2026, 9, 22, 15, 30, 45, 123, 456);
      final local = MainMenuDashboardVendasKpi.intervaloMesCorrenteAteHoje(agora);
      expect(local.inicioLocal, DateTime(2026, 9, 1));
      expect(local.fimLocal, agora);

      final utc = MainMenuDashboardVendasKpi.intervaloMesCorrenteAteHojeUtc(agora);
      expect(utc.inicioUtc, DateTime(2026, 9, 1).toUtc());
      expect(utc.fimUtc, agora.toUtc());
    });
  });

  group('MainMenuDashboardVendasKpi.filtroVendasMesCorrente', () {
    test('desconsidera canceladas e aplica vendedor quando informado', () {
      final agora = DateTime(2026, 3, 10, 9, 0);
      final filtro = MainMenuDashboardVendasKpi.filtroVendasMesCorrente(
        agora: agora,
        vendedorId: 42,
      );
      expect(filtro.filtroCancelamento, 'ativas');
      expect(filtro.vendedorId, 42);
      expect(filtro.dataInicioUtc, DateTime(2026, 3, 1).toUtc());
      expect(filtro.dataFimUtc, agora.toUtc());
    });
  });

  group('MainMenuDashboardVendasKpi.vendedorIdParaFiltro', () {
    test('gerente/admin ve loja inteira (sem filtro de vendedor)', () {
      final admin = UsuarioSistema(
        id: 'a',
        nome: 'A',
        login: 'a',
        senha: 'x',
        admin: true,
      );
      final gerente = PerfilUsuarioPresetAplicador.aplicar(
        UsuarioSistema(id: 'g', nome: 'G', login: 'g', senha: 'x'),
        PerfilUsuarioPreset.gerente,
      );
      expect(MainMenuDashboardVendasKpi.vendedorIdParaFiltro(admin), isNull);
      expect(MainMenuDashboardVendasKpi.vendedorIdParaFiltro(gerente), isNull);
    });

    test('vendedor vinculado filtra pelo vendedorId', () {
      final u = PerfilUsuarioPresetAplicador.aplicar(
        UsuarioSistema(
          id: 'v',
          nome: 'V',
          login: 'v',
          senha: 'x',
          vendedorId: 7,
        ),
        PerfilUsuarioPreset.vendedor,
      );
      expect(MainMenuDashboardVendasKpi.vendedorIdParaFiltro(u), 7);
    });

    test('operador sem vendedor nao carrega KPI mensal', () {
      final u = PerfilUsuarioPresetAplicador.aplicar(
        UsuarioSistema(id: 'c', nome: 'C', login: 'c', senha: 'x'),
        PerfilUsuarioPreset.caixa,
      );
      expect(MainMenuDashboardVendasKpi.deveCarregarVendasMes(u), isFalse);
      expect(MainMenuDashboardVendasKpi.vendedorIdParaFiltro(u), isNull);
    });
  });

  test('rotuloPeriodoMesDiscreto formata 01/MM a hoje', () {
    expect(
      MainMenuDashboardVendasKpi.rotuloPeriodoMesDiscreto(
        DateTime(2026, 9, 22),
      ),
      '01/09 a hoje',
    );
  });
}
