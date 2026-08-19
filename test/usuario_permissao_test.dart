import 'package:flutter_test/flutter_test.dart';
import 'package:sistema_vendas/domain/perfil_usuario_preset.dart';
import 'package:sistema_vendas/domain/permissao_usuario.dart';
import 'package:sistema_vendas/domain/main_menu_destino.dart';
import 'package:sistema_vendas/domain/usuario_permissao_helper.dart';
import 'package:sistema_vendas/domain/usuario_senha_codec.dart';
import 'package:sistema_vendas/model/usuario_sistema.dart';

void main() {
  test('vendedor: PDV sem cancelar, fiado nem reajuste', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '1', nome: 'V', login: 'v', senha: 'x'),
      PerfilUsuarioPreset.vendedor,
    );
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv), isTrue);
    expect(UsuarioPermissaoHelper.podeCancelarVendas(u), isFalse);
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.venderFiado), isFalse);
    expect(UsuarioPermissaoHelper.podeReajustePrecoLote(u), isFalse);
    expect(u.descontoMaximoPercentualPdv, 8);
  });

  test('motorista: so modo campo, sem modulo Entregas', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '2', nome: 'M', login: 'm', senha: 'x'),
      PerfilUsuarioPreset.motorista,
    );
    expect(UsuarioPermissaoHelper.podeVisualizarEntregas(u), isTrue);
    expect(UsuarioPermissaoHelper.podeGerenciarEntregas(u), isFalse);
    expect(UsuarioPermissaoHelper.ehMotoristaCampoSomente(u), isTrue);
    expect(UsuarioPermissaoHelper.podeAcessarModuloEntregas(u), isFalse);
    expect(UsuarioPermissaoHelper.podeUsarModoMotorista(u), isTrue);
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarPdv), isFalse);
    expect(MainMenuDestino.entregas.podeAcessar(u), isFalse);
    expect(MainMenuDestino.motorista.podeAcessar(u), isTrue);
    expect(MainMenuDestino.inicialAposLogin(u), MainMenuDestino.motorista);
  });

  test('gerente: reajuste e cancelar', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '3', nome: 'G', login: 'g', senha: 'x'),
      PerfilUsuarioPreset.gerente,
    );
    expect(UsuarioPermissaoHelper.podeReajustePrecoLote(u), isTrue);
    expect(UsuarioPermissaoHelper.podeCancelarVendas(u), isTrue);
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.venderFiado), isTrue);
  });

  test('caixa: so caixa basico sem listagem nem auditoria', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '4', nome: 'C', login: 'c', senha: 'x'),
      PerfilUsuarioPreset.caixa,
    );
    expect(UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarCaixa), isTrue);
    expect(
      UsuarioPermissaoHelper.tem(u, PermissaoUsuario.acessarListagemVendas),
      isFalse,
    );
    expect(UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u), isFalse);
    expect(UsuarioPermissaoHelper.podeVerMinhasVendasHoje(u), isFalse);
    expect(UsuarioPermissaoHelper.podeAcessarLojaAoVivo(u), isTrue);
    expect(UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u), isFalse);
    expect(UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(u), isFalse);
    expect(
      UsuarioPermissaoHelper.tem(u, PermissaoUsuario.leituraParcialCaixa),
      isFalse,
    );
    expect(
      UsuarioPermissaoHelper.tem(u, PermissaoUsuario.visualizarAuditoriaCaixa),
      isFalse,
    );
    expect(
      UsuarioPermissaoHelper.tem(u, PermissaoUsuario.manutencaoAuditoriaCaixa),
      isFalse,
    );
  });

  test('vendedor: minhas vendas sem total da loja', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(
        id: '5',
        nome: 'V',
        login: 'v2',
        senha: 'x',
        vendedorId: 12,
      ),
      PerfilUsuarioPreset.vendedor,
    );
    expect(UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u), isFalse);
    expect(UsuarioPermissaoHelper.podeVerMinhasVendasHoje(u), isTrue);
    expect(UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u), isTrue);
    expect(UsuarioPermissaoHelper.podeAcessarLojaAoVivo(u), isTrue);
    expect(UsuarioPermissaoHelper.podeVerMetasVendedoresLoja(u), isFalse);
  });

  test('separador: sem orcamentos nem faturamento', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '6', nome: 'S', login: 's', senha: 'x'),
      PerfilUsuarioPreset.separador,
    );
    expect(UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u), isFalse);
    expect(UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u), isFalse);
    expect(UsuarioPermissaoHelper.podeAcessarLojaAoVivo(u), isTrue);
  });

  test('gerente: visao gerencial completa no dashboard', () {
    final u = PerfilUsuarioPresetAplicador.aplicar(
      UsuarioSistema(id: '7', nome: 'G', login: 'g2', senha: 'x'),
      PerfilUsuarioPreset.gerente,
    );
    expect(UsuarioPermissaoHelper.podeVerFaturamentoTotalLoja(u), isTrue);
    expect(UsuarioPermissaoHelper.podeVerMetasVendedoresLoja(u), isTrue);
    expect(UsuarioPermissaoHelper.podeVerOrcamentosDashboard(u), isTrue);
    expect(UsuarioPermissaoHelper.podeVerBadgeFiscalDashboard(u), isTrue);
  });

  test('senha hash verifica e rejeita errada', () {
    final hash = UsuarioSenhaCodec.gerarHash('1234');
    expect(UsuarioSenhaCodec.verificar('1234', hash), isTrue);
    expect(UsuarioSenhaCodec.verificar('0000', hash), isFalse);
    expect(UsuarioSenhaCodec.isHashArmazenado(hash), isTrue);
  });
}
